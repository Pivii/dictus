# Headless Simulator

How an agent gets DictusApp running on an iOS Simulator and produces a screenshot, without opening a window.

Every command below was executed on this machine (Xcode 26.4.1, iOS 26.5 runtime, iPhone 17). The outputs shown are the ones they produced.

**Never bring a Simulator window to the front.** Pierre works on this machine and a foregrounded window steals his focus. `open -a Simulator` is therefore forbidden — but `open -g -a Simulator` is not, and section 5 needs it: `-g` starts the app without foregrounding it. Verified 2026-08-22 by reading the frontmost process before and after; it did not change. If a command foregrounds a window anyway, stop and record it here.

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

With that build, `AppGroup.containerURL` comes back nil on the device, so `dictus_debug.log` is never written and nothing crossing the App Group can be observed. Built without those flags, the app is ad-hoc signed and the container resolves. Drop the flags.

Do not read a mechanism into that. The ad-hoc signed build carries an *empty* entitlements dictionary — no `application-groups` key — and its container resolves anyway, so the simulator is not gating on the entitlement the way a device does. Signed-versus-unsigned is what was observed to matter here, not why.

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

## 5. Drive the UI

`simctl` has no touch injection. **`axe` does** — it is installed on this machine (`/opt/homebrew/bin/axe`, v1.8.0, `brew install cameroncooke/axe/axe`) and it taps, swipes, types and dumps the accessibility tree.

**The catch, and it is the whole section:** every point-based command needs Simulator.app to be running *with the target device attached*. Simulator.app merely being alive is not enough — a device booted after it started is not attached to it. The order matters and so does the wait:

```bash
xcrun simctl boot <udid>
xcrun simctl bootstatus <udid>     # blocks until the device is usable — do not skip
open -g -a Simulator               # -g starts it without foregrounding it
```

Then poll rather than assume. Attachment takes a few seconds, and firing `open -g` before `bootstatus` returns leaves the device unattached — that failure was reproduced here twice before the order was pinned down:

```bash
for i in 1 2 3 4 5 6; do
  sleep 5
  axe describe-ui --udid <udid> >/dev/null 2>&1 && break
done
```

**Do not quit Simulator.app to reset the attachment.** Quitting it shuts down every device it owns — observed here, a booted device went straight to `Shutdown`. Re-run `open -g -a Simulator` instead.

Without the attachment, every point-based command fails with a message that misattributes its own cause:

```
Error: No translation object returned for simulator. This means you have likely
specified a point onscreen that is invalid or invisible due to a fullscreen dialog
```

There is no dialog. The point-translation bridge is simply not connected. Measured 2026-08-22 on Xcode 26.4.1 / iOS 26.5, on a clean Home screen, by label and by coordinates, with `--tap-style simulator` and `physical` alike. Run `open -g -a Simulator` and the same command succeeds.

| Needs Simulator.app attached | Works with `simctl` alone |
| --- | --- |
| `tap`, `touch`, `swipe`, `drag`, `describe-ui`, `slider` | `button`, `key`, `key-sequence`, `type`, `gesture`, `screenshot`, `record-video` |

Read the screen before you tap it. `describe-ui` returns the full accessibility tree as JSON, with an `AXFrame` per element in **points** (402×874 on an iPhone 17, not the 1206×2622 pixels a screenshot has):

```bash
axe describe-ui --udid <udid>
```

Tap by accessibility label rather than by coordinate wherever the label is stable — it survives layout changes:

```bash
axe tap --label "Commencer" --udid <udid>
```

```
✓ Tap at resolved tap point at (201.0, 716.0) completed successfully
```

When two elements share a label and neither exposes an `AXUniqueId`, `axe` refuses rather than guessing:

```
Warning: Multiple (2) accessibility elements matched --label 'Continuer', and none of
the matches expose AXUniqueId on this screen. Use coordinates for this step … No tap performed.
```

That is the right behaviour, and it is a nudge: give controls an agent is expected to drive an `.accessibilityIdentifier("…")` and target them with `--id`. Coordinates still work when there is no usable label, and the tab bar is the usual case:

```bash
axe tap -x 201 -y 815 --udid <udid>    # Models tab
```

Verified end to end on 2026-08-22: installing DictusApp, tapping through the onboarding pages by label, and reaching the Models and Settings tabs by coordinate. The frontmost application stayed the terminal throughout.

**A long press needs one HID session, which means `batch`.** A held press is what opens iOS's own menus — the globe key's keyboard picker above all — and `axe` holds the press only inside a single batch:

```bash
axe batch --udid <udid> \
  --step "touch -x 42 -y 840 --down" \
  --step "sleep 1.8" \
  --step "touch -x 42 -y 840 --up"
```

Those coordinates are this device's globe key. Read the real one from `describe-ui` rather than trusting them: the globe is labelled `Clavier suivant`, and its `AXFrame` gives the centre to press.

A menu opened that way **stays open after the release**, so there is no race — read it, then tap the row by label:

```bash
axe describe-ui --udid <udid>
axe tap --label "Dictus, français" --udid <udid>
```

**Never tap the globe to change keyboard.** A tap cycles through the enabled keyboards and skips the third-party ones, so it never lands on Dictus. That single mistake is what produced the wrong conclusion this file carried until 2026-08-23 (section 8).

**A control missing from the accessibility tree needs `--tap-style physical`.** With the default `automatic` style, `axe` falls back to a simulator tap and such a control does not react. Measured 2026-08-23 on the Full Access switch, which `describe-ui` does not report at all (section 8); expect the same wherever a control you can see in a screenshot has no element in the tree.

Xcode 27 replaces this attachment dance with Device Hub and drops the Simulator.app requirement, per AXe's own compatibility notes. Until this machine moves to it, `open -g -a Simulator` is the price of a tap.

## 6. Control the frame

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

**`plutil -extract` rewrites the file it reads.** Reading one key out of a plist looks like a read and is not: `plutil -extract <keypath> json <file>` writes the extracted value back over `<file>` unless `-o -` sends it to stdout instead. Observed 2026-08-23, on a built `Info.plist` it destroyed; the keys that then appeared to be missing looked like a build bug and were not. Whatever you are inspecting, pass `-o -`:

```bash
plutil -extract <keypath> json -o - <file>
```

Put the device back the way you found it. This one is `fr_FR` with `AppleLanguages = (fr-FR, en-GB)`.

## 7. Clean up

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

## 8. What the simulator cannot show

**Tapping and typing are no longer on this list.** They were, until 2026-08-22, on the grounds that `simctl` has no touch injection. That is still true of `simctl` and was never true of the machine: see section 5. Do not re-derive the old limit from the `simctl` man page.

**The Dictus keyboard renders in a simulator, takes Full Access, and drives the whole dictation chain.** This file said the rendering was unresolved until 2026-08-23. It was wrong, and the reason was in how the keyboard was being reached: the globe key was being *tapped*, and a tap cycles past the third-party keyboards. Long-press it and pick Dictus from the menu — section 5 has the sequence, `axe batch` included.

Measured end to end on 2026-08-23. The keyboard draws its own AZERTY layout, with the `espace` bar, the hamburger panel button and the mic button.

**Registering.** The extension registers on install, which was never the question:

```bash
xcrun simctl spawn <udid> pluginkit -m -v -p com.apple.keyboard-service
```

```
     com.pivi.dictus.keyboard(1.8.0)	657D5A4D-…	/Users/…/DictusApp.app/PlugIns/DictusKeyboard.appex
```

`pkd` logs `Created plugin` for `com.pivi.dictus.keyboard(1.8.0)`, and SpringBoard lists it under `com.apple.keyboard-service`.

**Enabling, without tapping through Settings.** The device's keyboard list is `AppleKeyboards` in its `.GlobalPreferences.plist`, and a third-party keyboard is a bare bundle identifier there, not the `locale@sw=` shape the built-ins use. Write it with `plistlib` while the device is shut down — section 6's technique:

```python
d['AppleKeyboards'] = [
    'fr_FR@sw=AZERTY-French;hw=Automatic',
    'en_US@sw=QWERTY;hw=Automatic',
    'emoji@sw=Emoji',
    'com.pivi.dictus.keyboard',
]
```

Then boot, attach Simulator.app (section 5), install, and open any text field. Tapping through Settings → Général → Clavier → Claviers → Ajouter un clavier → Dictus reaches the same state and also works. `defaults write` from the host does not land, and neither does the `com.apple.Preferences` domain — `AppleKeyboards` does not live there; the version of this file before #378 made both mistakes at once and concluded from them that the keyboard could not be enabled at all.

**Full Access.** Granted by tap, in Réglages → Général → Clavier → Claviers → Dictus. The switch is not in the accessibility tree, so `axe`'s default `automatic` style falls back to a simulator tap and the toggle does not move; `--tap-style physical` moves it:

```bash
axe tap -x 337 -y 161 --tap-style physical --udid <udid>   # the Full Access switch
axe tap --label "Autoriser" --udid <udid>                  # the confirmation alert
```

The log then carries `fullAccess=true`.

**What the extension then gives you.** It runs, and it writes: `<KBD> diagnosticProbe` lines carrying `inputBounds`, `keyboardFrame`, `hostingConst`, `heightConst`, `memMB`, `status`, `mode` and `coldStart`. Tapping the mic fires the whole keyboard → app dictation chain, which on a device with no model installed ends where it should:

```
dictationFailed error=No model downloaded
statusChanged from=idle to=failed
dictationMessageCleared reason=appError-timeout
```

That is most of the keyboard surface this repo debugs, reachable without a device.

**The software keyboard appears, and `Connect Hardware Keyboard` did not stop it.** A widely repeated claim says a connected hardware keyboard suppresses the on-screen one and that this is why keyboard testing fails in simulators. Measured here with `ConnectHardwareKeyboard = 1`: tapping Safari's address bar brought up the full AZERTY keyboard, globe key included. The setting is real and headless-controllable —

```bash
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
```

— but on Xcode 26.4.1 / iOS 26.5 it is not what stands between an agent and a software keyboard. Check section 5's attachment first.

**The keyboard renders and still does not give you the numbers.** Memory and timing are device figures. `memMB=50` was observed for the extension in this run; simulator memory is not device memory and no verdict belongs in that number. Dead zones, the declared height constraint and the keyboard-to-app handoff still need a physical iPhone.

**Custom-scheme URLs prompt.** `simctl openurl` raises a confirmation the user must accept — though section 5 can now accept it:

```bash
xcrun simctl openurl <udid> "dictus://dictate?source=keyboard"
```

exits 0 and raises an `Ouvrir dans « Dictus » ?` confirmation alert, which needs a tap. It behaves the same whether Dictus is frontmost or the device is on the Home screen.

**The dictation chain runs; the capture at the end of it does not.** Tapping the keyboard's mic reaches DictusApp and comes back with the `No model downloaded` failure quoted in the keyboard entry above. Past that point nothing was exercised, and the reason is structural. The audio session does configure:

```
[…] INFO    [audio] <APP> audioSessionConfigured category=playAndRecord
[…] WARNING [audio] <APP> engineWarmUpFailed context=didBecomeActive error=modelReady=false
```

No transcription model is installed, and installing one means the Models tab — a tap — plus a download. Recording never starts, so nothing is proven about capture. `xcrun simctl privacy <udid> grant microphone com.pivi.dictus` exits 0, but it was never put to use.

Two things to know before trying: the simulator captures the **Mac's** input device, so a recording started here records the room Pierre is sitting in; and transcription runs on Mac silicon, so any timing measured in a simulator says nothing about the phone.

**StoreKit is inert.** The paywall and subscription state cannot be exercised without a StoreKit configuration:

```
[…] ERROR   [lifecycle] <APP> subscriptionError action=loadProducts error=empty result (StoreKit configuration missing or product ID unknown)
```

**What does work**, beyond plain screens: the App Group container and `dictus_debug.log` (with a signed build), and Live Activities — one started and rendered in the Dynamic Island during this run.
