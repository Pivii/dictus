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
        context.coordinator.previousRowCount = rows.count
        context.coordinator.previousFirstRowCount = rows.first?.count ?? 0
        context.coordinator.previousShiftState = shiftState
        context.coordinator.previousLastTypedChar = lastTypedChar

        return container
    }

    func updateUIView(_ container: KeyboardContainerView, context: Context) {
        let coordinator = context.coordinator

        // Detect if rows changed (different count or different first-row count means layer switch)
        let rowCountChanged = rows.count != coordinator.previousRowCount
        let firstRowCountChanged = (rows.first?.count ?? 0) != coordinator.previousFirstRowCount

        if rowCountChanged || firstRowCountChanged {
            // Full rebuild for layer switch (letters <-> numbers <-> symbols)
            container.buildKeys(rows: rows, actions: actions)
            coordinator.previousRowCount = rows.count
            coordinator.previousFirstRowCount = rows.first?.count ?? 0
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
    }

    /// Coordinator stores previous state to avoid unnecessary rebuilds.
    ///
    /// WHY not Equatable on rows:
    /// KeyDefinition uses UUID identifiers, so array equality checks would always fail.
    /// Comparing counts is sufficient: same row count + same first-row count means same layer.
    class Coordinator {
        var previousRowCount: Int = 0
        var previousFirstRowCount: Int = 0
        var previousShiftState: ShiftState = .off
        var previousLastTypedChar: String?
    }
}
