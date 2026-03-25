// DictusKeyboard/Views/UIKit/KeyboardUIView.swift
// UIViewRepresentable wrapper embedding the UIKit keyboard in SwiftUI.
import SwiftUI
import DictusCore

/// Bridges the UIKit keyboard container into the SwiftUI view hierarchy.
///
/// WHY UIViewRepresentable:
/// The UIKit keyboard buttons (LetterKeyButton, SpecialKeyButtons) need to live in UIKit
/// for `point(inside:with:)` hit region expansion. UIViewRepresentable embeds the UIKit
/// view tree into SwiftUI, allowing the keyboard to coexist with SwiftUI toolbar, overlays,
/// and popup previews.
///
/// WHY Coordinator for change detection:
/// SwiftUI calls updateUIView on every state change (shift, lastTypedChar, etc.).
/// Without change detection, every keystroke would rebuild all buttons. The Coordinator
/// tracks previous state so we only rebuild when the layout actually changes (layer switch),
/// and do lightweight updates for shift/accent changes.
struct KeyboardUIView: UIViewRepresentable {

    let rows: [[KeyDefinition]]
    let currentLayer: KeyboardLayerType
    let isShifted: Bool
    let shiftState: ShiftState
    let lastTypedChar: String?
    @ObservedObject var touchState: KeyboardTouchState
    let actions: KeyboardActions

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> KeyboardContainerView {
        let container = KeyboardContainerView()
        container.touchState = touchState
        container.buildKeys(rows: rows, actions: actions)

        // Store initial state in coordinator
        context.coordinator.previousLayer = currentLayer
        context.coordinator.previousShiftState = shiftState
        context.coordinator.previousLastTypedChar = lastTypedChar

        return container
    }

    func updateUIView(_ container: KeyboardContainerView, context: Context) {
        let coordinator = context.coordinator

        // Detect layer switch by comparing the actual layer type.
        // WHY not row counts: All 4 layouts (AZERTY, QWERTY, numbers, symbols) have
        // identical dimensions (4 rows, 10 first-row keys), so row count comparison
        // never triggers a rebuild. Direct layer comparison catches every switch.
        if currentLayer != coordinator.previousLayer {
            // Full rebuild for layer switch (letters <-> numbers <-> symbols)
            container.buildKeys(rows: rows, actions: actions)
            coordinator.previousLayer = currentLayer
        }

        // Shift change: lightweight update (no rebuild)
        if shiftState != coordinator.previousShiftState {
            container.updateShift(isShifted)
            container.updateShiftIcon(shiftState)
            coordinator.previousShiftState = shiftState
        }

        // Accent state change: lightweight update
        if lastTypedChar != coordinator.previousLastTypedChar {
            container.updateAccentState(lastTypedChar: lastTypedChar, isShifted: isShifted)
            coordinator.previousLastTypedChar = lastTypedChar
        }

        // Update return key label from text field context (cheap -- just reads proxy value)
        container.updateReturnKeyType()
    }

    /// Coordinator stores previous state to avoid unnecessary rebuilds.
    ///
    /// WHY previousLayer instead of row counts:
    /// All keyboard layouts have identical row dimensions (4 rows, 10 first-row keys),
    /// so comparing counts never detects a layer switch. Direct layer comparison is reliable.
    class Coordinator {
        var previousLayer: KeyboardLayerType = .letters
        var previousShiftState: ShiftState = .off
        var previousLastTypedChar: String?
    }
}
