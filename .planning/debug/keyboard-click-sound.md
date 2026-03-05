---
status: diagnosed
trigger: "System keyboard click sound does not work in DictusKeyboard extension"
created: 2026-03-05T00:00:00Z
updated: 2026-03-05T00:00:00Z
---

## Current Focus

hypothesis: KeyboardInputView is added as a regular subview, but Apple requires it to BE the inputView — the view returned by the controller's `inputView` property
test: Code review of KeyboardViewController.viewDidLoad() vs Apple documentation requirements
expecting: The `inputView` property of UIInputViewController must return the UIInputViewAudioFeedback-conforming view
next_action: Confirm root cause and recommend fix

## Symptoms

expected: With Full Access enabled and keyboard clicks on in iOS Settings, tapping keys produces the native iOS click sound
actual: No click sound when tapping any key
errors: None (silent failure — playInputClick() is a no-op when requirements not met)
reproduction: Tap any character key on DictusKeyboard with Full Access enabled
started: Since initial implementation

## Eliminated

(none — root cause found on first hypothesis)

## Evidence

- timestamp: 2026-03-05
  checked: InputView.swift — KeyboardInputView class
  found: Class correctly conforms to UIInputViewAudioFeedback with enableInputClicksWhenVisible returning true
  implication: Protocol conformance is correct — not the issue

- timestamp: 2026-03-05
  checked: KeyboardViewController.viewDidLoad() — how KeyboardInputView is used
  found: KeyboardInputView is created and added as a subview via `view.addSubview(inputView)`. It is NOT assigned to the controller's `inputView` property.
  implication: THIS IS THE ROOT CAUSE. Apple docs state playInputClick() "plays an input click in an enabled input view". The view adopting UIInputViewAudioFeedback must be the actual input view (the view returned by the `inputView` property), not just any subview in the hierarchy.

- timestamp: 2026-03-05
  checked: Apple documentation for playInputClick() and UIInputViewAudioFeedback
  found: Apple docs say "To play a standard keyboard input click, use the playInputClick method of UIDevice in a custom input view or keyboard accessory view that adopts UIInputViewAudioFeedback." The UIInputViewController has an `inputView` property (inherited from UIViewController / UIResponder) that represents THE input view. For keyboard extensions, this is the primary view.
  implication: The UIInputViewAudioFeedback-conforming view needs to be discoverable by the system as an "input view" — not just a random subview

- timestamp: 2026-03-05
  checked: KeyboardView.swift — where playInputClick() is called
  found: Line 76 calls `UIDevice.current.playInputClick()` inside `insertCharacter()`, gated on `hasFullAccess`. This is correct placement.
  implication: The call site is fine — the problem is the view hierarchy setup, not the call

- timestamp: 2026-03-05
  checked: Special keys (space, return, delete, shift) — whether they also call playInputClick()
  found: Only `insertCharacter()` calls playInputClick(). Space, return, delete, shift, globe, and layer switch keys do NOT play the click sound.
  implication: Secondary issue — even after fixing the root cause, only character keys will click. Special keys should also play the click sound for native-feeling feedback.

- timestamp: 2026-03-05
  checked: Apple Developer Forums thread 84252 and multiple developer resources
  found: Multiple developers confirm that for keyboard extensions, the UIInputViewAudioFeedback protocol must be on the view that the system recognizes as the input view. In keyboard extensions, `UIInputViewController.inputView` is the primary view that the system manages.
  implication: The fix should make the controller's `inputView` be (or contain at the root) the UIInputViewAudioFeedback-conforming view

## Resolution

root_cause: |
  KeyboardInputView (which correctly conforms to UIInputViewAudioFeedback) is added as a
  zero-frame subview of the controller's view, but this is NOT sufficient. Apple's
  playInputClick() only works when the UIInputViewAudioFeedback-conforming view is the
  actual "input view" that the system recognizes — i.e., the view returned by the
  UIInputViewController's `inputView` property.

  In the current code (KeyboardViewController.swift line 28):
    view.addSubview(inputView)
  This just sticks it as a child subview. The system does not walk the subview tree looking
  for UIInputViewAudioFeedback conformance — it checks the inputView itself.

  Secondary issue: only character keys call playInputClick(). Space, return, and delete
  keys should also produce click sounds for a native feel.

fix: |
  PRIMARY FIX (two possible approaches):

  Approach A — Override the inputView property:
  In KeyboardViewController, override the `inputView` property to return a
  KeyboardInputView instance. Then add the hosting controller's view as a subview
  of that KeyboardInputView (instead of self.view). This makes the entire keyboard
  be inside the UIInputViewAudioFeedback-conforming view.

  Approach B — Make the controller's existing view conform:
  Create a custom UIInputView subclass that conforms to UIInputViewAudioFeedback,
  and use it as the controller's inputView. UIInputViewController already has a
  settable `inputView` property of type UIInputView.

  SECONDARY FIX:
  Add playInputClick() calls to space, return, and delete key handlers in
  KeyboardView.swift (onSpace, onReturn, onDelete closures).

verification: (not yet applied — research-only mode)
files_changed: []
