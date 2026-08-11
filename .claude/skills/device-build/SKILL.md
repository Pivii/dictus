---
name: device-build
description: Build Dictus and install it on Pierre's physical iPhone over Wi-Fi, from any commit, without him touching the Mac. Use when he asks for a build on his phone ("build ça sur mon téléphone", "installe la PR sur l'iPhone", "je veux tester X sur device") — including when he is away from the computer.
---

# Build onto the iPhone, remotely

Pierre is usually not at the Mac. He tests on his phone and talks to you from it. This skill puts a named commit on that phone and proves which commit it is.

**The whole point is the proof.** He validates PRs by reading `rev` on line 2 of an exported log. A build that installs but reports the wrong commit is worse than no build: it produces a validation of code that was never tested. One mechanism in this repo still makes that failure easy, and it has bitten already (see Traps).

## What must be true before you start

Check, don't assume — each of these has its own error and its own fix.

```bash
xcrun devicectl list devices
```

The iPhone must be listed `available (paired)`. Then:

```bash
xcrun devicectl device info details --device <id> \
  | grep -E "tunnelState|developerModeStatus|osVersionNumber"
```

Wanted: `tunnelState: connected`, `developerModeStatus: enabled`.

- **Not listed, or `unavailable`** — the Mac is asleep, off Wi-Fi, or the phone left the network. Pierre has to wake something; say which.
- **Xcode older than the phone's iOS** is fine and expected. It blocks installing *from Xcode's UI*, which is why this skill exists. `devicectl` does not care.

Device id as of 2026-08-09: `B05E304C-D238-5A94-B0D9-F4BF366A7FC6` ("Iphone de Bob", iPhone 15 Pro Max). Re-read it from `devicectl list devices` rather than trusting this line.

## Build from the dedicated worktree, never the main clone

```
/Users/pierreviviere/dev/dictus-wt/device
```

Its `HEAD` is yours. The main clone's is not: Xcode is open on this project and other sessions share the machine, and a checkout there has been observed moving back under an agent **twelve seconds** after it was made. That produced a signed, installable build of the wrong branch.

The worktree also keeps its own `build/DerivedData`, so package resolution survives between runs.

```bash
git -C /Users/pierreviviere/dev/dictus-wt/device fetch -q origin
git -C /Users/pierreviviere/dev/dictus-wt/device checkout --detach <sha-or-ref> -q
git -C /Users/pierreviviere/dev/dictus-wt/device rev-parse --short HEAD
```

Create it if missing: `git worktree add --detach ../dictus-wt/device <sha>`, then resolve once (below). Leave it in place afterwards — it is not per-issue, it is the build machine.

**First use of a fresh worktree only** — packages resolve from zero and FluidAudio needs its Swift 5 patch or the build fails (#285):

```bash
cd /Users/pierreviviere/dev/dictus-wt/device
xcodebuild -resolvePackageDependencies -project Dictus.xcodeproj -scheme DictusApp \
  -derivedDataPath build/DerivedData
./scripts/patch-fluidaudio-swift5.sh build/DerivedData
```

## Build, then verify, then install

An incremental build is fine since #344. Add `clean` only when you have a reason of your own; it is no longer needed to make the revision correct.

```bash
cd /Users/pierreviviere/dev/dictus-wt/device
xcodebuild build -project Dictus.xcodeproj -scheme DictusApp -configuration Debug \
  -destination 'id=<device-id>' -derivedDataPath build/DerivedData -allowProvisioningUpdates
```

Signing needs nothing from Pierre: `-allowProvisioningUpdates` renews the team profile itself.

**Verify before installing anyway.** The build no longer drops the revision on its own, but the wrong *checkout* still stamps the wrong sha, and that failure is invisible until he has already tested. Check both bundles — the app and the keyboard extension are separate binaries and the keyboard is what he is usually testing:

```bash
APP=build/DerivedData/Build/Products/Debug-iphoneos/DictusApp.app
plutil -p "$APP/DictusBuildInfo.plist"
plutil -p "$APP/PlugIns/DictusKeyboard.appex/DictusBuildInfo.plist"
```

Both must print the sha you checked out. **Anything else — a different sha, or the file absent — stop and do not install.** Re-read `git rev-parse --short HEAD` in the worktree: if it moved, something else is driving this checkout and Pierre needs to know before he tests anything.

The build log carries the same line if you would rather grep it:

```
note: build info f31f7da@fix/344-git-sha-injection -> …/DictusApp.app/DictusBuildInfo.plist
```

```bash
xcrun devicectl device install app --device <device-id> "$APP"
xcrun devicectl device process launch --device <device-id> com.pivi.dictus
```

## Report

Give him three things, always:

- the sha now on the phone, and that `rev <sha>@HEAD` is what line 2 of the log must say
- what the build was *for* — the issue or PR in his terms, not the diff
- that installing resets the app's container: learned dictionary, settings and any stored dictation state are gone

That last one is not a detail. A dev install has already invalidated a test run (learned words) and produced a bogus Live Activity issue (#294).

## Traps

**The revision no longer needs `clean` — but do not assume the old advice is gone from elsewhere.** Until #344 the `Inject Git SHA into Info.plist` phase wrote into the built `Info.plist`, which `ProcessInfoPlistFile` also produces. Nothing ordered the two, and an incremental build ran them the other way round, so a no-op rebuild four seconds after a good build left the key **absent** from both plists. The phase now writes its own `DictusBuildInfo.plist`, which nothing else produces, so no ordering can exist to get wrong. Any note you find telling you to `clean build` for the sha, or to `plutil` the `Info.plist`, predates that.

**`git rev-parse` reads the worktree you are standing in.** The injection script runs `cd "$SRCROOT"`, so building the main clone stamps the main clone's HEAD no matter which sha you meant. This is the failure the worktree removes.

**A green build is not an install.** `devicectl install` can fail after `BUILD SUCCEEDED` on a locked device or a dropped tunnel. Read its output; it prints `App installed:` and a bundle path on success.

## When he asks for "the current develop"

Fetch first, then build `origin/develop`'s tip by sha, not by branch name — a detached sha is what you can quote back to him and what he can check against the log.
