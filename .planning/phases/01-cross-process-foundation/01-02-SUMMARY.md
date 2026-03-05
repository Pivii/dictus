# Summary: Plan 1.2 — Cross-Process Signaling

**Completed:** 2026-03-05
**Status:** Done
**Tasks:** 6/6

---

## What Was Built

Plan 1.2 implements the full cross-process dictation round-trip between DictusKeyboard and DictusApp, using stub transcription to prove the architecture before real audio is added in Phase 2.

### Files Created
- `DictusApp/DictationCoordinator.swift` — Dictation state machine (ObservableObject). Handles `dictus://dictate` URL, simulates recording (1.5s) and transcription (1s), writes stub result + timestamps to App Group, posts Darwin notifications on every status transition.
- `DictusApp/DictationView.swift` — `DictationStatusView` component. Shows icon + label for each `DictationStatus` state with appropriate SF Symbol and color coding.
- `DictusKeyboard/KeyboardState.swift` — Cross-process observer (ObservableObject). Listens for Darwin notifications, reads `DictationStatus` and `lastTranscription` from App Group UserDefaults. Includes 100ms retry guard for UserDefaults propagation race condition. Cleans up observers in `deinit`.
- `DictusKeyboard/Views/MicButtonDisabled.swift` — Disabled mic button for when Full Access is off. Tapping shows a popover with Full Access instructions and a Settings deep link (`app-settings:`).

### Files Modified
- `DictusApp/Info.plist` — Added `CFBundleURLTypes` entry registering `dictus://` URL scheme with identifier `com.pivi.dictus`.
- `DictusApp/DictusApp.swift` — Added `@StateObject coordinator`, `.onOpenURL` handler routing `dictus://dictate` to `DictationCoordinator.startDictation()`, environment injection.
- `DictusApp/ContentView.swift` — Added `@EnvironmentObject coordinator`, shows `DictationStatusView` when status != `.idle`, displays last transcription result below status.
- `DictusKeyboard/KeyboardViewController.swift` — Added `viewDidDisappear` and `textDidChange` lifecycle overrides; removed inline `#available` guard noise; `KeyboardState` lifecycle is tied to `KeyboardRootView`'s `@StateObject`.

---

## Architecture Decisions

### No `dictus://return`
Per 01-RESEARCH.md, there is no App Store-safe API to programmatically return to a previous app on iOS 16–18. The plan intentionally omits it. iOS shows a `< [Previous App]` status bar chevron automatically when DictusApp is opened via URL scheme — no code needed.

### `KeyboardState` owned by `KeyboardRootView`, not `KeyboardViewController`
`@StateObject` in `KeyboardRootView` ties `KeyboardState`'s lifetime to the SwiftUI view. When the hosting controller is deallocated, `KeyboardState.deinit` runs and removes Darwin observers — preventing leaks across keyboard show/hide cycles.

### 100ms UserDefaults retry in `KeyboardState`
Darwin notifications are posted immediately after `defaults.synchronize()`, but on-device UserDefaults propagation across App Group boundaries can lag. A 100ms deferred read guards against receiving the notification before the value is visible.

### `@available(iOS 14.0, *)` on all `DictusLogger` calls
The logger already uses this availability guard internally. Call sites in DictusApp and DictusKeyboard must wrap usages to avoid compiler warnings on the iOS 16.0 deployment target.

---

## Commits

1. `feat(1.2.1)` — Register dictus:// URL scheme in DictusApp Info.plist
2. `feat(1.2.2)` — Create DictationCoordinator in DictusApp
3. `feat(1.2.3)` — Handle dictus:// URL in DictusApp and add DictationStatusView
4. `feat(1.2.4)` — Create KeyboardState for cross-process updates in keyboard extension
5. `feat(1.2.5)` — Create MicButtonDisabled reusable component
6. `feat(1.2.6)` — Integrate KeyboardState lifecycle into KeyboardViewController

---

## Verification Status

Manual verification on physical device pending (requires Xcode build + deploy):
- [ ] Opening `dictus://dictate` in Safari launches DictusApp and triggers dictation stub
- [ ] DictusApp console shows "Dictation started via URL scheme" + status transitions
- [ ] DictusApp UI shows recording -> transcribing -> ready state sequence
- [ ] `KeyboardState` receives Darwin notification and reads transcription from App Group
- [ ] iOS shows `< [Previous App]` back chevron in status bar
- [ ] Cancelling mid-dictation (new trigger) resets cleanly
- [ ] Round-trip works on physical iPhone

Note: Full keyboard integration (mic button wired to URL, status bar display) is verified in Plan 1.3.
