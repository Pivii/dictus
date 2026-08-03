# Headless Simulator

How an agent gets DictusApp running on an iOS Simulator and produces a screenshot, without opening a window.

Every command below was executed on this machine (Xcode 26.4.1, iOS 26.5 runtime, iPhone 17). The outputs shown are the ones they produced.

**`open -a Simulator` is forbidden.** Pierre works on this machine and any window steals his focus. `xcrun simctl` drives a booted device without a UI; that is the whole toolkit. If a command opens a window anyway, stop and record it here.

## 1. Choose and boot a device

Check for a booted device before booting another:

```bash
xcrun simctl list devices booted
```

```
== Devices ==
-- iOS 26.5 --
    iPhone 17 (231991C2-5F6E-4A2B-8BC3-0C729DFD2B2A) (Booted)
```

Reuse it. If nothing is booted, pick a UDID from the available list:

```bash
xcrun simctl list devices available
```

```
-- iOS 26.5 --
    iPhone 17 Pro (1720B34A-F21A-4E22-9F44-A7BB663D8004) (Shutdown)
    iPhone 17 (231991C2-5F6E-4A2B-8BC3-0C729DFD2B2A) (Booted)
    iPhone 13 (D80C795A-6FB6-421B-98F7-18E878A14E7D) (Shutdown)
```

```bash
xcrun simctl boot <udid>
xcrun simctl bootstatus <udid>
```

`bootstatus` blocks until the device is usable. Its last lines look like a failure and are not:

```
[2026-08-03 11:39:37 +0000] Status=4294967295, isTerminal=YES, Elapsed=00:04.
	Finished
```

On an already-booted device it prints `Device already booted, nothing to do.`

## 2. Build for that simulator

A fresh worktree resolves its packages from zero, so all three steps are needed the first time:

```bash
xcodebuild -resolvePackageDependencies \
  -project Dictus.xcodeproj -scheme DictusApp \
  -derivedDataPath build/DerivedData

./scripts/patch-fluidaudio-swift5.sh build/DerivedData

xcodebuild build \
  -project Dictus.xcodeproj -scheme DictusApp -configuration Debug \
  -destination 'platform=iOS Simulator,id=<udid>' \
  -derivedDataPath build/DerivedData
```

The patch step is not optional and the path is not optional (#285): a build passing `-derivedDataPath` resolves its own FluidAudio checkout, and patching Xcode's shared one says nothing about it.

```
Patched: /Users/…/298/build/DerivedData/SourcePackages/checkouts/FluidAudio/Package.swift
FluidAudio checkout patched for the build using: /Users/…/298/build/DerivedData
```

Building `DictusApp` builds the embedded keyboard, widgets and core. The product lands at:

```
build/DerivedData/Build/Products/Debug-iphonesimulator/DictusApp.app
build/DerivedData/Build/Products/Debug-iphonesimulator/DictusApp.app/PlugIns/DictusKeyboard.appex
build/DerivedData/Build/Products/Debug-iphonesimulator/DictusApp.app/PlugIns/DictusWidgets.appex
```

**Do not copy CI's signing flags into a build you intend to run.** `.github/workflows/ci.yml` passes `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGNING_IDENTITY=""`, which is right for a compile-only check and wrong here. That build is unsigned:

```bash
codesign -d --entitlements - build/DerivedData/Build/Products/Debug-iphonesimulator/DictusApp.app
```

```
Executable=/Users/…/DictusApp.app/DictusApp
```

and it gets no App Group container on the device, so `dictus_debug.log` is never written and nothing that crosses the App Group behaves as it does on device. The same build without those flags is ad-hoc signed and does get the container. Drop the flags.

## 3. Install and launch

```bash
xcrun simctl install <udid> build/DerivedData/Build/Products/Debug-iphonesimulator/DictusApp.app
xcrun simctl launch <udid> com.pivi.dictus
```

```
com.pivi.dictus: 84714
```

Bundle identifiers: app `com.pivi.dictus`, keyboard `com.pivi.dictus.keyboard`, widgets `com.pivi.dictus.widgets`.

**A launch failure** exits non-zero and names the domain:

```bash
xcrun simctl launch <udid> com.pivi.nope
```

```
An error was encountered processing the command (domain=FBSOpenApplicationServiceErrorDomain, code=4):
Simulator device failed to launch com.pivi.nope.
```

**A crash after launch** looks like a success: `launch` exits 0 and prints a pid, because the process did start. Check the pid:

```bash
ps -p <pid> -o pid,comm
```

Nothing but the header means the process is gone. The reason is in the device log:

```bash
xcrun simctl spawn <udid> log show --last 10m --style compact \
  --predicate 'process == "SpringBoard" AND eventMessage CONTAINS "Process exited"' \
  | grep pivi.dictus
```

```
… [app<com.pivi.dictus>:24394] … status:<RBSProcessExitStatus| domain:frontboard(10) code:force-quit(0xfbfbfbfb)>
… [app<com.pivi.dictus>:31271] … status:<RBSProcessExitStatus| domain:signal(2) code:SIGSEGV(11)>
```

`force-quit` is `simctl terminate`; a signal is a crash. Do not wait for a `.ips`: a SIGSEGV killed here produced no crash report under `~/Library/Logs/DiagnosticReports/`.

Container paths, when you need the app's own state:

```bash
xcrun simctl get_app_container <udid> com.pivi.dictus groups
```

```
group.solutions.pivi.dictus	/Users/…/Devices/<udid>/data/Containers/Shared/AppGroup/3B7549C4-…
```

`dictus_debug.log` sits at the root of that directory.

## 4. Capture

```bash
xcrun simctl io <udid> screenshot /path/outside/the/repo/shot.png
```

```
Wrote screenshot to: /…/shot.png
```

**Screenshots do not belong in the repository.** Write them to a scratch directory and report the absolute paths.

`simctl launch` returns as soon as the process spawns, not when the UI is on screen. A screenshot taken immediately captures the launch animation or a black frame. Let the UI settle, then shoot; repeating the screenshot a few times and keeping the last one is enough.

Video recording works headlessly. It runs until SIGINT:

```bash
xcrun simctl io <udid> recordVideo --codec=h264 --force /path/outside/the/repo/demo.mp4
```

```
Recording started
Recording completed. Writing to disk.
Wrote video to: /…/demo.mp4
```

## 5. Control the frame

This project ships a dark-first design in French and English, so all three of these matter.

**Appearance** — read, then set:

```bash
xcrun simctl ui <udid> appearance         # light
xcrun simctl ui <udid> appearance dark
```

**Status bar** — a fixed status bar keeps screenshots comparable:

```bash
xcrun simctl status_bar <udid> override \
  --time "09:41" --batteryState charged --batteryLevel 100 --cellularBars 4
```

**App language, per launch** — the cheapest way to shoot both locales:

```bash
xcrun simctl launch <udid> com.pivi.dictus -AppleLanguages '(en)' -AppleLocale en_US
```

Verified: the same screen renders `Commencer` without it and `Get started` with it. This changes the app only; the system UI stays in the device language.

**Device language, system-wide** — needed when the system UI or date formats are part of what you are looking at. Shut the device down, edit its global preferences, boot again:

```bash
xcrun simctl shutdown <udid>
python3 - "$HOME/Library/Developer/CoreSimulator/Devices/<udid>/data/Library/Preferences/.GlobalPreferences.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
d['AppleLanguages'] = ['en-US']
d['AppleLocale'] = 'en_US'
plistlib.dump(d, open(sys.argv[1], 'wb'))
PY
xcrun simctl boot <udid>
```

Two traps here, both observed while writing this file. `defaults write` from the host against a plist inside a device's data directory silently does not stick — the host `cfprefsd` owns the write and it never reaches the file. `plutil -replace` fails on a key the file does not have yet. Editing the plist with `plistlib` while the device is shut down is what works.

Put the device back the way you found it. This one is `fr_FR` with `AppleLanguages = (fr-FR, en-GB)`.

## 6. Clean up

```bash
xcrun simctl status_bar <udid> clear
xcrun simctl ui <udid> appearance light
xcrun simctl uninstall <udid> com.pivi.dictus
```

`uninstall` also deletes the App Group container, so `dictus_debug.log` and every persisted preference go with it. Read what you need first.

Revert any `defaults write` you made on the device — those survive uninstall.

Leaving a device booted between runs is fine and is the cheaper default; boot is the slow part. Shut down only a device you booted yourself:

```bash
xcrun simctl shutdown <udid>
```

## 7. What the simulator cannot show

**There is no way to tap or type.** `simctl` has no touch injection: no tap, no swipe, no text entry. Everything reachable is reachable by launching, by a preference written before launch, or not at all. Driving the UI needs a UI test target, which this repo does not have.

**The Dictus keyboard cannot be enabled.** This was established by experiment, not assumed. The extension does register with the plug-in system on install:

```bash
xcrun simctl spawn <udid> pluginkit -m -v -p com.apple.keyboard-service
```

```
     com.pivi.dictus.keyboard(1.8.0)	657D5A4D-…	/Users/…/DictusApp.app/PlugIns/DictusKeyboard.appex
```

Registering is not enabling. Four attempts, all failed:

| Attempt | Result |
| --- | --- |
| `defaults write com.apple.Preferences AppleKeyboards -array … "com.pivi.dictus.keyboard"`, then reboot the device | The value persists and reads back, but `UITextInputMode.activeInputModes` never contains the keyboard |
| `pluginkit -e use -i com.pivi.dictus.keyboard` | Exits 0, flips the pluginkit flag to `+`, changes nothing for the app, and the flag is lost on the next boot |
| Settings deep link `prefs:root=General&path=Keyboard/KEYBOARDS` | `LSApplicationWorkspaceErrorDomain error 115`. `App-prefs:` opens Settings at its root only |
| Toggling it in Settings by hand | Needs a tap |

The verification was DictusApp's own check on the onboarding keyboard page, reached by writing `dictus.onboardingCurrentPage = 2` into the App Group preferences before launch. With both writes applied and the device rebooted, `dictus_debug.log` says:

```
[…] DEBUG   [lifecycle] <APP> onboardingKeyboardCheckStarted modeCount=3
[…] DEBUG   [lifecycle] <APP> onboardingKeyboardNotFound modeCount=3
```

**Anything behind the keyboard is therefore off the table in a simulator** — layout, dead zones, the height constraint, the globe key, keyboard memory, keyboard-to-app handoff. Most of this repo's open bugs are keyboard bugs, and they still need a device.

**Custom-scheme URLs prompt.** `simctl openurl` cannot stand in for a tap:

```bash
xcrun simctl openurl <udid> "dictus://dictate?source=keyboard"
```

exits 0 and raises an `Ouvrir dans « Dictus » ?` confirmation alert, which needs a tap. It behaves the same whether Dictus is frontmost or the device is on the Home screen.

**Microphone and dictation were not exercised, and the reason is structural.** The audio session does configure:

```
[…] INFO    [audio] <APP> audioSessionConfigured category=playAndRecord
[…] WARNING [audio] <APP> engineWarmUpFailed context=didBecomeActive error=modelReady=false
```

No transcription model is installed, and installing one means the Models tab — a tap — plus a download. Recording never starts, so nothing was proven about capture. `xcrun simctl privacy <udid> grant microphone com.pivi.dictus` exits 0, but it was never put to use.

Two things to know before trying: the simulator captures the **Mac's** input device, so a recording started here records the room Pierre is sitting in; and transcription runs on Mac silicon, so any timing measured in a simulator says nothing about the phone.

**StoreKit is inert.** The paywall and subscription state cannot be exercised without a StoreKit configuration:

```
[…] ERROR   [lifecycle] <APP> subscriptionError action=loadProducts error=empty result (StoreKit configuration missing or product ID unknown)
```

**What does work**, beyond plain screens: the App Group container and `dictus_debug.log` (with a signed build), and Live Activities — one started and rendered in the Dynamic Island during this run.
