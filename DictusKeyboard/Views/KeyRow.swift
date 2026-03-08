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
            // Mic keys are filtered out before reaching KeyRow (Plan 03-02).
            // The mic button now lives in ToolbarView above the keyboard.
            // This case is kept for exhaustive switch — should never execute.
            EmptyView()

        case .symbolToggle:
            LayerSwitchKey(label: key.label, width: keyWidth, onTap: onSymbolToggle)

        case .emoji:
            // Placeholder — full implementation in Task 2
            EmojiKey(width: keyWidth, onTap: onGlobe)

        case .accentAdaptive:
            // Placeholder — full implementation in Task 2
            EmptyView()
        }
    }
}
