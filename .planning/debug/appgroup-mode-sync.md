---
status: resolved
trigger: "App Group sync issue — KeyboardMode picker in Settings doesn't propagate to keyboard extension"
created: 2026-03-10T00:00:00Z
updated: 2026-03-10T00:00:00Z
---

## Current Focus

hypothesis: Keyboard extension reads KeyboardMode.active only in .onAppear which fires once per @StateObject lifetime, not per keyboard show
test: Read KeyboardRootView lifecycle code
expecting: .onAppear only fires on first insertion into view hierarchy, not on subsequent keyboard opens
next_action: Confirm root cause and document fix

## Symptoms

expected: Changing keyboard mode in DictusApp Settings immediately reflects in keyboard extension next time it opens
actual: Keyboard extension keeps old mode until app is rebuilt (extension process killed and restarted)
errors: None — silent stale read
reproduction: 1) Open Settings, change mode from Full to Micro. 2) Switch to any app, open keyboard. 3) Keyboard still shows Full mode.
started: Since Phase 09 keyboard modes were implemented

## Eliminated

(none needed — root cause found on first investigation)

## Evidence

- timestamp: 2026-03-10
  checked: KeyboardMode.swift — .active computed property
  found: Reads AppGroup.defaults.string(forKey:) each call — no caching at this level. This is correct.
  implication: The read mechanism itself is fine.

- timestamp: 2026-03-10
  checked: SettingsView.swift — how mode is written
  found: Uses @AppStorage(SharedKeys.keyboardMode, store: UserDefaults(suiteName: AppGroup.identifier)) — writes correctly to App Group shared defaults
  implication: The write mechanism is correct.

- timestamp: 2026-03-10
  checked: KeyboardRootView.swift — when mode is read
  found: Line 25: `@State private var currentMode: KeyboardMode = .full` — initialized to .full. Line 139: `currentMode = KeyboardMode.active` inside .onAppear.
  implication: ROOT CAUSE — @State + .onAppear in keyboard extension is the problem. See resolution.

## Resolution

root_cause: |
  KeyboardRootView uses `@State private var currentMode: KeyboardMode = .full` (line 25) and only
  updates it in `.onAppear` (line 139). The problem is that `.onAppear` in a keyboard extension does
  NOT fire every time the keyboard is shown to the user.

  iOS keyboard extensions work differently from regular views:
  1. The UIInputViewController (and its hosted SwiftUI view) is created ONCE per extension process.
  2. `.onAppear` fires when the SwiftUI view is first inserted into the view hierarchy.
  3. When the user dismisses and re-opens the keyboard, iOS often REUSES the same extension process
     and view hierarchy — `.onAppear` does NOT fire again.
  4. The extension process only dies when iOS kills it for memory pressure or when the app is rebuilt.

  So `currentMode` gets set to `KeyboardMode.active` once on first keyboard open, then stays stale
  for the entire lifetime of the extension process.

fix: |
  The keyboard extension's UIInputViewController has a lifecycle method `viewWillAppear(_:)` that
  IS called every time the keyboard appears (unlike SwiftUI's .onAppear). Two approaches:

  **Option A (Recommended): Use viewWillAppear in the UIInputViewController**
  In KeyboardViewController (the UIInputViewController subclass), override `viewWillAppear` to post
  a notification or update an @Published property that KeyboardRootView observes. This is the most
  reliable approach because viewWillAppear is guaranteed by UIKit on every keyboard show.

  **Option B: Use scenePhase or NotificationCenter**
  Listen for UIApplication.keyboardDidShowNotification or similar, but keyboard extensions have
  limited access to UIApplication notifications.

  **Option C (Simplest): Make currentMode a computed property**
  Instead of @State, read KeyboardMode.active directly in the body. But this loses the benefit of
  SwiftUI's diffing (would re-read on every body evaluation). Acceptable given it's just a UserDefaults read.

  **Concrete fix (Option A):**
  1. In KeyboardViewController, add an @Published or ObservableObject property for the current mode
  2. Override viewWillAppear to re-read KeyboardMode.active
  3. Pass this observable to KeyboardRootView instead of using internal @State

verification: Pending implementation
files_changed: []
