---
phase: 1
plan: "1.3"
title: "Keyboard Shell"
wave: 3
depends_on: ["1.1", "1.2"]
requirements: ["KBD-01", "KBD-02", "KBD-04"]
files_modified:
  - DictusKeyboard/KeyboardRootView.swift
  - DictusKeyboard/Views/KeyboardView.swift
  - DictusKeyboard/Views/KeyRow.swift
  - DictusKeyboard/Views/KeyButton.swift
  - DictusKeyboard/Views/SpecialKeyButton.swift
  - DictusKeyboard/Views/FullAccessBanner.swift
  - DictusKeyboard/Views/StatusBar.swift
  - DictusKeyboard/Models/KeyboardLayout.swift
  - DictusKeyboard/Models/KeyboardLayer.swift
  - DictusKeyboard/Models/KeyDefinition.swift
  - DictusKeyboard/InputView.swift
autonomous: true
---

# Plan 1.3: Keyboard Shell

## Objective
Build a fully functional AZERTY keyboard with letters, numbers/symbols layers, shift, delete, space, return, globe, and a mic button placeholder. The keyboard matches native iOS appearance (key shapes, colors, dark/light mode), includes key tap preview popups, and degrades gracefully when Full Access is off (typing works, mic disabled, persistent banner shown). This is the user-facing shell that all future keyboard features build on.

**Early delivery note:** This plan delivers KBD-02 ("Full AZERTY keyboard layout") which is assigned to Phase 3 in REQUIREMENTS. Phase 3 will polish it further (long-press accented characters, haptic feedback refinements).

**Deferred to Phase 3:** Long-press accented characters (e.g. e -> é, è, ê; a -> à, â; c -> ç) as described in CONTEXT.md. The popup infrastructure is built here (key preview), but the long-press character picker requires additional gesture handling and is explicitly deferred.

## must_haves
- [ ] All 10 AZERTY letter keys per row render correctly in standard French layout
- [ ] Typing any letter inserts the correct character via `textDocumentProxy.insertText()`
- [ ] Shift key toggles between lowercase and uppercase; double-tap enables caps lock
- [ ] Delete key calls `textDocumentProxy.deleteBackward()`
- [ ] Space bar inserts a space, Return key inserts a newline
- [ ] Globe key calls `advanceToNextInputMode()` to switch keyboards
- [ ] 123 key toggles to numbers/symbols layer; ABC key returns to letters
- [ ] Keyboard adapts to light and dark mode automatically
- [ ] Key tap shows popup preview above the pressed key (matching native iOS)
- [ ] Without Full Access: mic button dimmed, persistent banner visible, all typing still works
- [ ] With Full Access: mic button is a blue `Link` to `dictus://dictate`
- [ ] Keyboard appears within ~300ms without blank flash

<tasks>

<task id="1.3.1" title="Define keyboard layout data model" estimated_effort="M">
**What:** Create the data structures that describe the AZERTY keyboard layout — key definitions, rows, and layers (letters, numbers/symbols, shifted symbols).
**Why:** Separating layout data from rendering keeps the code clean and makes it easy to add QWERTY in Phase 3. Each key is defined once with its character, width, and type.
**How:**
1. Create `DictusKeyboard/Models/KeyDefinition.swift`:

```swift
// DictusKeyboard/Models/KeyDefinition.swift
import Foundation

/// A single key on the keyboard.
enum KeyType {
    case character   // Regular letter or symbol
    case shift       // Shift / caps lock
    case delete      // Backspace
    case space       // Space bar
    case returnKey   // Return / Enter
    case globe       // Switch keyboard
    case layerSwitch // 123 / ABC toggle
    case mic         // Dictation trigger
    case symbolToggle // #+= toggle on number layer
}

struct KeyDefinition: Identifiable {
    let id = UUID()
    let label: String          // Display label
    let output: String?        // Character to insert (nil for special keys)
    let type: KeyType
    let widthMultiplier: CGFloat  // 1.0 = standard letter key width

    init(
        _ label: String,
        output: String? = nil,
        type: KeyType = .character,
        width: CGFloat = 1.0
    ) {
        self.label = label
        self.output = output ?? label
        self.type = type
        self.widthMultiplier = width
    }
}
```

2. Create `DictusKeyboard/Models/KeyboardLayer.swift`:

```swift
// DictusKeyboard/Models/KeyboardLayer.swift
import Foundation

/// Represents a full keyboard layer (letters, numbers, symbols).
enum KeyboardLayerType {
    case letters
    case numbers
    case symbols
}

struct KeyboardLayer {
    let type: KeyboardLayerType
    let rows: [[KeyDefinition]]
}
```

3. Create `DictusKeyboard/Models/KeyboardLayout.swift` with the full AZERTY definition:

```swift
// DictusKeyboard/Models/KeyboardLayout.swift
import Foundation

/// Defines the complete AZERTY keyboard layout matching iOS native French keyboard.
enum KeyboardLayout {

    // MARK: - Letters layer (lowercase shown; shift applies uppercasing)

    static let lettersRows: [[KeyDefinition]] = [
        // Row 1: top letter row
        ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"].map {
            KeyDefinition($0, output: $0.lowercased())
        },
        // Row 2: home row
        ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"].map {
            KeyDefinition($0, output: $0.lowercased())
        },
        // Row 3: bottom letter row with shift and delete
        [
            KeyDefinition("shift", type: .shift, width: 1.5),
            KeyDefinition("W", output: "w"),
            KeyDefinition("X", output: "x"),
            KeyDefinition("C", output: "c"),
            KeyDefinition("V", output: "v"),
            KeyDefinition("B", output: "b"),
            KeyDefinition("N", output: "n"),
            KeyDefinition("delete", type: .delete, width: 1.5),
        ],
        // Row 4: bottom function row
        [
            KeyDefinition("globe", type: .globe, width: 1.2),
            KeyDefinition("123", type: .layerSwitch, width: 1.2),
            KeyDefinition("mic", type: .mic, width: 1.0),
            KeyDefinition("space", output: " ", type: .space, width: 3.5),
            KeyDefinition("return", type: .returnKey, width: 1.8),
        ],
    ]

    // MARK: - Numbers layer
    // Note: Mic key is intentionally absent from numbers/symbols layers,
    // matching native iOS behavior where the mic is letters-layer only.

    static let numbersRows: [[KeyDefinition]] = [
        // Row 1: numbers
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].map {
            KeyDefinition($0)
        },
        // Row 2: common symbols
        ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""].map {
            KeyDefinition($0)
        },
        // Row 3: more symbols + toggle + delete
        [
            KeyDefinition("#+=", type: .symbolToggle, width: 1.5),
            KeyDefinition(".", output: "."),
            KeyDefinition(",", output: ","),
            KeyDefinition("?", output: "?"),
            KeyDefinition("!", output: "!"),
            KeyDefinition("'", output: "'"),
            KeyDefinition("delete", type: .delete, width: 1.5),
        ],
        // Row 4: back to letters + space + return (no mic — letters only)
        [
            KeyDefinition("ABC", type: .layerSwitch, width: 1.2),
            KeyDefinition("globe", type: .globe, width: 1.2),
            KeyDefinition("space", output: " ", type: .space, width: 4.7),
            KeyDefinition("return", type: .returnKey, width: 1.8),
        ],
    ]

    // MARK: - Symbols layer (accessed via #+= on numbers layer)

    static let symbolsRows: [[KeyDefinition]] = [
        // Row 1: brackets and math
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map {
            KeyDefinition($0)
        },
        // Row 2: special characters
        ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "·"].map {
            KeyDefinition($0)
        },
        // Row 3: toggle back + more + delete
        [
            KeyDefinition("123", type: .symbolToggle, width: 1.5),
            KeyDefinition(".", output: "."),
            KeyDefinition(",", output: ","),
            KeyDefinition("?", output: "?"),
            KeyDefinition("!", output: "!"),
            KeyDefinition("'", output: "'"),
            KeyDefinition("delete", type: .delete, width: 1.5),
        ],
        // Row 4: same as numbers
        [
            KeyDefinition("ABC", type: .layerSwitch, width: 1.2),
            KeyDefinition("globe", type: .globe, width: 1.2),
            KeyDefinition("space", output: " ", type: .space, width: 4.7),
            KeyDefinition("return", type: .returnKey, width: 1.8),
        ],
    ]
}
```

**Files:**
- `DictusKeyboard/Models/KeyDefinition.swift` — Key data model
- `DictusKeyboard/Models/KeyboardLayer.swift` — Layer type enum
- `DictusKeyboard/Models/KeyboardLayout.swift` — Full AZERTY layout data

**Done when:**
- All three layers (letters, numbers, symbols) are defined with correct key positions
- Layout data matches iOS native French AZERTY structure
</task>

<task id="1.3.2" title="Build KeyButton and key popup preview" estimated_effort="M">
**What:** Create the reusable `KeyButton` SwiftUI view for standard character keys — matching native iOS appearance with rounded rect shape, appropriate colors for light/dark mode, and a popup preview above the key on press.
**Why:** The keyboard must feel native (CONTEXT.md decision). Key tap preview popups are one of the most recognizable iOS keyboard behaviors and provide essential visual feedback for accurate typing.
**How:**
1. Create `DictusKeyboard/Views/KeyButton.swift`:

```swift
// DictusKeyboard/Views/KeyButton.swift
import SwiftUI

/// A standard keyboard key that inserts a character on tap.
/// Shows a popup preview above the key during the press gesture.
struct KeyButton: View {
    let key: KeyDefinition
    let isShifted: Bool
    let onTap: (String) -> Void

    @State private var isPressed = false

    private var displayLabel: String {
        isShifted ? key.label.uppercased() : key.label.lowercased()
    }

    private var outputChar: String {
        guard let output = key.output else { return "" }
        return isShifted ? output.uppercased() : output
    }

    var body: some View {
        // Using a plain gesture to get press/release states
        Text(displayLabel)
            .font(.system(size: 22, weight: .regular))
            .frame(maxWidth: .infinity)
            .frame(height: KeyMetrics.keyHeight)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
            )
            .overlay(
                // Popup preview shown above key on press
                Group {
                    if isPressed {
                        KeyPopup(label: displayLabel)
                            .offset(y: -(KeyMetrics.keyHeight + 8))
                    }
                },
                alignment: .top
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onTap(outputChar)
                    }
            )
    }
}

/// The popup preview bubble shown above a pressed key.
struct KeyPopup: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 32, weight: .regular))
            .frame(width: 50, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            )
    }
}

/// Shared key dimension constants.
enum KeyMetrics {
    static let keyHeight: CGFloat = 42
    static let rowSpacing: CGFloat = 6
    static let keySpacing: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 3
}
```

**Files:**
- `DictusKeyboard/Views/KeyButton.swift` — Character key view with popup preview

**Done when:**
- Key renders with rounded rect, shadow, correct font size
- Press-and-hold shows popup preview above key
- Release inserts the character
- Dark/light mode automatically switches colors
</task>

<task id="1.3.3" title="Build special key views (shift, delete, globe, space, return)" estimated_effort="M">
**What:** Create views for all non-character keys: shift (with caps lock on double-tap), delete (with repeat-on-hold), globe, space bar, return, and layer switch (123/ABC).
**Why:** Each special key has unique behavior beyond simple character insertion. Shift must track state (off/on/locked), delete needs repeat-on-hold for fast deletion, and globe must call the UIKit `advanceToNextInputMode()` method.
**How:**
1. Create `DictusKeyboard/Views/SpecialKeyButton.swift`:

```swift
// DictusKeyboard/Views/SpecialKeyButton.swift
import SwiftUI

/// Shift key with three states: off, shift (single character), caps lock.
struct ShiftKey: View {
    @Binding var shiftState: ShiftState
    let width: CGFloat

    var body: some View {
        Button {
            switch shiftState {
            case .off:
                shiftState = .shifted
            case .shifted:
                shiftState = .off
            case .capsLocked:
                shiftState = .off
            }
        } label: {
            Image(systemName: shiftIconName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(shiftState != .off
                              ? Color(.label)
                              : Color(.systemGray3))
                )
                .foregroundColor(shiftState != .off
                                 ? Color(.systemBackground)
                                 : Color(.label))
        }
        // Double-tap for caps lock
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                shiftState = .capsLocked
            }
        )
    }

    private var shiftIconName: String {
        switch shiftState {
        case .off: return "shift"
        case .shifted: return "shift.fill"
        case .capsLocked: return "capslock.fill"
        }
    }
}

enum ShiftState {
    case off
    case shifted
    case capsLocked
}

/// Delete key with repeat-on-hold behavior.
/// Uses Task + Task.sleep instead of Timer.scheduledTimer, which is
/// unreliable in keyboard extensions (RunLoop may not be active).
/// Includes ~400ms initial delay before repeat begins (native iOS feel).
struct DeleteKey: View {
    let width: CGFloat
    let onDelete: () -> Void

    @State private var isHolding = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: "delete.left.fill")
            .font(.system(size: 16, weight: .medium))
            .frame(width: width)
            .frame(height: KeyMetrics.keyHeight)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray3))
            )
            .foregroundColor(Color(.label))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHolding {
                            isHolding = true
                            onDelete() // Immediate first delete
                            repeatTask = Task { @MainActor in
                                // Initial delay before repeat begins (~400ms,
                                // matching native iOS delete key behavior)
                                try? await Task.sleep(nanoseconds: 400_000_000)
                                // Repeat at ~100ms intervals while held
                                while !Task.isCancelled {
                                    onDelete()
                                    try? await Task.sleep(nanoseconds: 100_000_000)
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        isHolding = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
    }
}

/// Space bar key.
struct SpaceKey: View {
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("espace")
                .font(.system(size: 15))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 1)
                )
        }
        .foregroundColor(Color(.label))
    }
}

/// Return key.
struct ReturnKey: View {
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("retour")
                .font(.system(size: 15, weight: .medium))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemGray3))
                )
        }
        .foregroundColor(Color(.label))
    }
}

/// Globe key (switch keyboards).
struct GlobeKey: View {
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemGray3))
                )
        }
        .foregroundColor(Color(.label))
    }
}

/// Layer switch key (123 / ABC).
struct LayerSwitchKey: View {
    let label: String
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemGray3))
                )
        }
        .foregroundColor(Color(.label))
    }
}
```

**Files:**
- `DictusKeyboard/Views/SpecialKeyButton.swift` — All special key views

**Done when:**
- Shift toggles between off/shifted/capsLocked with correct icons
- Double-tap shift activates caps lock
- Delete fires once on tap, waits ~400ms, then repeats on hold (~100ms intervals)
- Space inserts " ", Return inserts "\n"
- Globe calls `advanceToNextInputMode()`
- All keys match system gray/white color scheme in both light and dark mode
</task>

<task id="1.3.4" title="Build the main KeyboardView composing all rows and layers" estimated_effort="L">
**What:** Create the main `KeyboardView` that renders all four rows of the current layer, manages shift state, handles layer switching, and computes dynamic key widths based on screen size.
**Why:** This is the central composition view that brings all key components together into a functional keyboard. It manages the mutable state (current layer, shift) and routes key taps to `textDocumentProxy`.
**How:**
1. Create `DictusKeyboard/Views/KeyRow.swift`:

```swift
// DictusKeyboard/Views/KeyRow.swift
import SwiftUI

/// Renders a single row of keys with appropriate spacing.
struct KeyRow: View {
    let keys: [KeyDefinition]
    let rowWidth: CGFloat
    let isShifted: Bool
    let shiftState: Binding<ShiftState>
    let onCharacter: (String) -> Void
    let onDelete: () -> Void
    let onGlobe: () -> Void
    let onLayerSwitch: () -> Void
    let onSymbolToggle: () -> Void
    let onSpace: () -> Void
    let onReturn: () -> Void
    let hasFullAccess: Bool

    /// Calculate the width of a 1x key based on row content.
    private var unitKeyWidth: CGFloat {
        let totalMultiplier = keys.reduce(0) { $0 + $1.widthMultiplier }
        let totalSpacing = CGFloat(keys.count - 1) * KeyMetrics.keySpacing
        let availableWidth = rowWidth - (KeyMetrics.rowHorizontalPadding * 2) - totalSpacing
        return availableWidth / totalMultiplier
    }

    var body: some View {
        HStack(spacing: KeyMetrics.keySpacing) {
            ForEach(keys) { key in
                keyView(for: key)
            }
        }
        .padding(.horizontal, KeyMetrics.rowHorizontalPadding)
    }

    @ViewBuilder
    private func keyView(for key: KeyDefinition) -> some View {
        let keyWidth = unitKeyWidth * key.widthMultiplier

        switch key.type {
        case .character:
            KeyButton(key: key, isShifted: isShifted, onTap: onCharacter)

        case .shift:
            ShiftKey(shiftState: shiftState, width: keyWidth)

        case .delete:
            DeleteKey(width: keyWidth, onDelete: onDelete)

        case .space:
            SpaceKey(width: keyWidth, onTap: onSpace)

        case .returnKey:
            ReturnKey(width: keyWidth, onTap: onReturn)

        case .globe:
            GlobeKey(width: keyWidth, onTap: onGlobe)

        case .layerSwitch:
            LayerSwitchKey(label: key.label, width: keyWidth, onTap: onLayerSwitch)

        case .mic:
            MicKey(width: keyWidth, hasFullAccess: hasFullAccess)

        case .symbolToggle:
            LayerSwitchKey(label: key.label, width: keyWidth, onTap: onSymbolToggle)
        }
    }
}
```

2. Create `DictusKeyboard/Views/KeyboardView.swift`:

```swift
// DictusKeyboard/Views/KeyboardView.swift
import SwiftUI
import DictusCore

/// The main keyboard view composing all rows and managing layer/shift state.
struct KeyboardView: View {
    let controller: UIInputViewController
    let hasFullAccess: Bool

    @State private var currentLayer: KeyboardLayerType = .letters
    @State private var shiftState: ShiftState = .off

    private var isShifted: Bool {
        shiftState == .shifted || shiftState == .capsLocked
    }

    private var currentRows: [[KeyDefinition]] {
        switch currentLayer {
        case .letters: return KeyboardLayout.lettersRows
        case .numbers: return KeyboardLayout.numbersRows
        case .symbols: return KeyboardLayout.symbolsRows
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: KeyMetrics.rowSpacing) {
                ForEach(Array(currentRows.enumerated()), id: \.offset) { _, row in
                    KeyRow(
                        keys: row,
                        rowWidth: geometry.size.width,
                        isShifted: isShifted,
                        shiftState: $shiftState,
                        onCharacter: { char in
                            insertCharacter(char)
                        },
                        onDelete: {
                            controller.textDocumentProxy.deleteBackward()
                        },
                        onGlobe: {
                            controller.advanceToNextInputMode()
                        },
                        onLayerSwitch: {
                            toggleLettersNumbers()
                        },
                        onSymbolToggle: {
                            toggleNumbersSymbols()
                        },
                        onSpace: {
                            controller.textDocumentProxy.insertText(" ")
                        },
                        onReturn: {
                            controller.textDocumentProxy.insertText("\n")
                        },
                        hasFullAccess: hasFullAccess
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: keyboardHeight)
    }

    private var keyboardHeight: CGFloat {
        let rows = CGFloat(currentRows.count)
        return (rows * KeyMetrics.keyHeight)
            + ((rows - 1) * KeyMetrics.rowSpacing)
            + 8  // vertical padding
    }

    private func insertCharacter(_ char: String) {
        controller.textDocumentProxy.insertText(char)

        // Auto-unshift after one character (unless caps locked)
        if shiftState == .shifted {
            shiftState = .off
        }
    }

    private func toggleLettersNumbers() {
        if currentLayer == .letters {
            currentLayer = .numbers
        } else {
            currentLayer = .letters
            shiftState = .off
        }
    }

    private func toggleNumbersSymbols() {
        if currentLayer == .numbers {
            currentLayer = .symbols
        } else {
            currentLayer = .numbers
        }
    }
}

/// Mic key — shows Link when Full Access is on, disabled button otherwise.
struct MicKey: View {
    let width: CGFloat
    let hasFullAccess: Bool

    var body: some View {
        if hasFullAccess {
            Link(destination: URL(string: "dictus://dictate")!) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: width)
                    .frame(height: KeyMetrics.keyHeight)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.blue)
                    )
            }
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 18, weight: .medium))
                .frame(width: width)
                .frame(height: KeyMetrics.keyHeight)
                .foregroundColor(Color(.systemGray2))
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(.systemGray4))
                )
        }
    }
}
```

**Files:**
- `DictusKeyboard/Views/KeyRow.swift` — Single row renderer
- `DictusKeyboard/Views/KeyboardView.swift` — Main keyboard composition

**Done when:**
- All four rows render with correct key positions matching iOS AZERTY
- Layer switching between letters/numbers/symbols works
- Shift/caps lock affects letter output
- Keys dynamically fill screen width
- Keyboard height is stable and matches ~216pt standard
</task>

<task id="1.3.5" title="Build FullAccessBanner for graceful degradation" estimated_effort="S">
**What:** Create a persistent, non-dismissible banner shown above the keyboard when Full Access is not enabled. The banner explains why Full Access is needed and deep-links to iOS Settings.
**Why:** CONTEXT.md and KBD-04 require that the keyboard degrades gracefully without Full Access. The banner is the primary mechanism to guide users toward enabling Full Access so dictation works.
**How:**
1. Create `DictusKeyboard/Views/FullAccessBanner.swift`:

```swift
// DictusKeyboard/Views/FullAccessBanner.swift
import SwiftUI

/// Non-dismissible banner shown when Full Access is disabled.
/// Guides the user to Settings to enable Full Access for dictation.
struct FullAccessBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)

            Text("Dictée désactivée.")
                .font(.caption2)
                .foregroundColor(.primary)

            Spacer()

            // Deep-link to Settings
            // "app-settings:" opens the app's settings page in iOS Settings
            Link(destination: URL(string: "app-settings:")!) {
                Text("Activer")
                    .font(.caption2.bold())
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
    }
}
```

**Files:**
- `DictusKeyboard/Views/FullAccessBanner.swift` — Full Access banner with Settings deep-link

**Done when:**
- Banner renders above keyboard when `hasFullAccess == false`
- "Activer" link opens Dictus settings page (user navigates to keyboard settings from there — `app-settings:` opens the app's own settings page, not the keyboard-specific page directly)
- Banner does not appear when Full Access is on
- Banner is non-dismissible — always visible without Full Access
</task>

<task id="1.3.6" title="Enable system keyboard click sound" estimated_effort="S">
**What:** Implement `UIInputViewAudioFeedback` protocol to enable system keyboard click sounds on key taps, but only when Full Access is enabled.
**Why:** CONTEXT.md decision: "Key taps include system click sound matching native iOS keyboard behavior." Without the audio feedback protocol, `playInputClick()` either does nothing or hangs. The click sound only works with Full Access.
**How:**
1. Create `DictusKeyboard/InputView.swift`:

```swift
// DictusKeyboard/InputView.swift
import UIKit

/// Custom UIView that enables the system keyboard click sound.
/// UIInputViewAudioFeedback protocol must be adopted by a UIView subclass,
/// not by a SwiftUI view. We set this as the inputView of
/// UIInputViewController to enable UIDevice.current.playInputClick().
class KeyboardInputView: UIView, UIInputViewAudioFeedback {
    /// Return true to enable keyboard click sounds via playInputClick().
    var enableInputClicksWhenVisible: Bool { true }
}
```

2. In `KeyboardViewController.viewDidLoad()`, set the custom input view:

```swift
// In KeyboardViewController, add to viewDidLoad():
let inputView = KeyboardInputView(
    frame: CGRect(x: 0, y: 0, width: 0, height: 0)
)
inputView.translatesAutoresizingMaskIntoConstraints = false
view.addSubview(inputView)
```

3. Add a click helper to the key button tap handler (only when Full Access is on):

```swift
// Add to the onCharacter closure in KeyboardView:
if hasFullAccess {
    UIDevice.current.playInputClick()
}
```

**Files:**
- `DictusKeyboard/InputView.swift` — UIInputViewAudioFeedback conformance

**Done when:**
- Key taps produce the system click sound when Full Access is enabled
- No click sound (and no hang) when Full Access is off
</task>

<task id="1.3.7" title="Integrate KeyboardView into KeyboardRootView" estimated_effort="M">
**What:** Replace the placeholder `KeyboardRootView` with the full composition: FullAccessBanner (conditional) + StatusBar + TranscriptionStub + KeyboardView. Wire up `KeyboardState` (from Plan 1.2) for cross-process updates. This task owns `KeyboardRootView.swift` — Plan 1.2 does not touch this file.
**Why:** This is the integration step that brings all keyboard components together into the final view hierarchy. The root view decides what to show based on Full Access status and dictation state. Using a fixed total height prevents layout jumps when the banner or status bar appears/disappears.
**How:**
1. Update `DictusKeyboard/KeyboardRootView.swift`:

```swift
// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import DictusCore

/// Root SwiftUI view for the keyboard extension.
/// Composes: FullAccessBanner + StatusBar + KeyboardView.
struct KeyboardRootView: View {
    let controller: UIInputViewController
    @StateObject private var state = KeyboardState()

    var body: some View {
        VStack(spacing: 0) {
            // Full Access banner — persistent when disabled
            if !controller.hasFullAccess {
                FullAccessBanner()
            }

            // Status bar — shows during active dictation round-trip
            if let message = state.statusMessage {
                StatusBar(message: message)
            }

            // Transcription result stub (Phase 1 only — replaced in Phase 3)
            if let transcription = state.lastTranscription,
               state.dictationStatus == .ready {
                TranscriptionStub(text: transcription, controller: controller)
            }

            // Main keyboard
            KeyboardView(
                controller: controller,
                hasFullAccess: controller.hasFullAccess
            )
        }
        .background(Color(.secondarySystemBackground))
    }
}

/// Status bar shown during dictation round-trip.
struct StatusBar: View {
    let message: String

    var body: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
    }
}

/// Temporary view to show received transcription in Phase 1.
/// Phase 3 replaces this with TranscriptionPreviewBar.
struct TranscriptionStub: View {
    let text: String
    let controller: UIInputViewController

    var body: some View {
        HStack {
            Text(text)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button("Insérer") {
                controller.textDocumentProxy.insertText(text)
            }
            .font(.caption.bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
    }
}
```

2. Update `KeyboardViewController.swift` to ensure the hosting controller uses clear background and proper constraints.

**Files:**
- `DictusKeyboard/KeyboardRootView.swift` — Complete root view integration

**Done when:**
- Keyboard shows FullAccessBanner when Full Access is off, hides it when on
- StatusBar appears during dictation round-trip
- AZERTY keyboard renders below with full typing functionality
- Background color adapts to light/dark mode
- Keyboard does not flash blank on first appearance (renders within ~300ms)
</task>

</tasks>

## Verification
- [ ] Switch to Dictus keyboard via Globe key — keyboard appears without blank flash
- [ ] Type "azerty" — correct letters appear in text field
- [ ] Type "AZERTY" using shift — uppercase letters appear
- [ ] Double-tap shift — caps lock icon shown, all subsequent letters uppercase until toggled off
- [ ] Delete key removes characters; hold delete waits ~400ms then rapidly removes multiple characters
- [ ] Space bar inserts space, Return inserts newline
- [ ] Globe key switches to next keyboard
- [ ] Tap 123 — numbers/symbols layer appears; tap ABC — returns to letters
- [ ] Tap #+= on numbers layer — additional symbols appear; tap 123 returns to numbers
- [ ] Mic button is blue when Full Access on, dimmed gray when off
- [ ] Mic button (blue) opens DictusApp when tapped
- [ ] FullAccessBanner visible when Full Access off, hidden when on
- [ ] FullAccessBanner "Activer" link opens Dictus settings page (user navigates to keyboard settings from there)
- [ ] Keyboard renders correctly in dark mode
- [ ] Key taps produce system click sound (with Full Access)
- [ ] All typing works in any app (Notes, Messages, Safari, etc.)
