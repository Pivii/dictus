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
    let onWordDelete: () -> Void
    let onGlobe: () -> Void
    let onEmoji: () -> Void
    let onLayerSwitch: () -> Void
    let onSymbolToggle: () -> Void
    let onSpace: () -> Void
    let onReturn: () -> Void
    let onAccentAdaptive: (String) -> Void
    let onCursorMove: (Int) -> Void
    let onTrackpadStateChange: (Bool) -> Void
    let lastTypedChar: String?
    let hasFullAccess: Bool

    /// Calculate the width of a 1x key based on row content.
    ///
    /// WHY zero-spacing: With HStack(spacing: 0), each key's touch area
    /// covers the full allocated width including what was previously gap space.
    /// Visual gaps are created by inset backgrounds (padding on RoundedRectangle).
    /// This eliminates dead zones AND fixes edge key touch issues (UIView overlay
    /// bounds now extend to the keyboard edge with no clipping gap).
    private var unitKeyWidth: CGFloat {
        let totalMultiplier = keys.reduce(0) { $0 + $1.widthMultiplier }
        return rowWidth / totalMultiplier
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(keys) { key in
                keyView(for: key)
            }
        }
        .frame(height: KeyMetrics.keyHeight + KeyMetrics.rowSpacing)
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
            DeleteKey(width: keyWidth, onDelete: onDelete, onWordDelete: onWordDelete)

        case .space:
            SpaceKey(
                width: keyWidth,
                onTap: onSpace,
                onCursorMove: onCursorMove,
                onTrackpadStateChange: onTrackpadStateChange
            )

        case .returnKey:
            ReturnKey(width: keyWidth, onTap: onReturn)

        case .globe:
            GlobeKey(width: keyWidth, onTap: onGlobe)

        case .layerSwitch:
            LayerSwitchKey(label: key.label, width: keyWidth, onTap: onLayerSwitch)

        case .mic:
            // Mic keys are filtered out before reaching KeyRow (Plan 03-02).
            // The mic button now lives in ToolbarView above the keyboard.
            // This case is kept for exhaustive switch — should never execute.
            EmptyView()

        case .symbolToggle:
            LayerSwitchKey(label: key.label, width: keyWidth, onTap: onSymbolToggle)

        case .emoji:
            EmojiKey(width: keyWidth, onTap: onEmoji)

        case .accentAdaptive:
            AdaptiveAccentKey(
                width: keyWidth,
                isShifted: isShifted,
                lastTypedChar: lastTypedChar,
                onTap: onAccentAdaptive
            )
        }
    }
}
