// DictusApp/Views/KeyboardModePicker.swift
// Reusable default layer picker with segmented control and miniature previews.
import SwiftUI
import DictusCore

/// Segmented picker for selecting the default keyboard layer with a miniature preview.
///
/// WHY reusable component:
/// This picker used to appear in both SettingsView and onboarding; the
/// onboarding layer-choice step was removed in #213 and the picker now lives
/// in SettingsView only, where it stays fully functional.
///
/// WHY @AppStorage instead of @Binding:
/// When used inside onboarding (which has .id(currentPage) + transitions),
/// a @Binding from the parent's @AppStorage doesn't propagate updates reliably.
/// Owning the @AppStorage directly ensures the picker always reads/writes
/// the correct value and triggers view updates on selection change.
struct DefaultLayerPicker: View {

    @AppStorage(SharedKeys.defaultKeyboardLayer, store: UserDefaults(suiteName: AppGroup.identifier))
    var selectedLayer: String = "letters"

    var body: some View {
        VStack(spacing: 16) {
            // WHY explicit tags instead of ForEach:
            // SwiftUI's Picker with segmented style can have tag-matching issues
            // when tags come from ForEach with dynamic content. Explicit Text/tag
            // pairs guarantee the correct String value is written to the binding.
            Picker("Default page", selection: $selectedLayer) {
                Text("ABC").tag("letters")
                Text("123").tag("numbers")
            }
            .pickerStyle(.segmented)

            // Non-interactive miniature preview of the selected layer.
            // WHY .id(selectedLayer): Forces SwiftUI to recreate the preview
            // when the selection changes, instead of trying to diff two very
            // different view hierarchies. Without this, the segmented picker
            // updates visually but the preview can stay stale.
            previewForLayer
                .id(selectedLayer)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.dictusAccent.opacity(0.15), lineWidth: 1)
                )
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.2), value: selectedLayer)
        }
    }

    // MARK: - Preview Router

    @ViewBuilder
    private var previewForLayer: some View {
        if selectedLayer == DefaultKeyboardLayer.numbers.rawValue {
            numbersModePreview
        } else {
            lettersModePreview
        }
    }

    // MARK: - Shared Toolbar Preview

    /// Miniature toolbar matching the real ToolbarView layout:
    /// gear icon on the left, mic pill on the right.
    private var toolbarPreview: some View {
        HStack {
            // Gear icon (settings shortcut) — left side
            Image(systemName: "gearshape.fill")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(Color(.systemGray))

            Spacer()

            // Mic pill — right side, matching AnimatedMicButton shape
            Capsule()
                .fill(Color.dictusAccent)
                .frame(width: 36, height: 18)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                )
        }
        .frame(height: 22)
    }

    // MARK: - Letters Preview (AZERTY)

    /// Four rows with actual AZERTY letters to be immediately recognizable.
    private var lettersModePreview: some View {
        VStack(spacing: 3) {
            toolbarPreview

            // AZERTY rows with actual letters
            let rows = [
                ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"],
                ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"],
                ["W", "X", "C", "V", "B", "N"],
                ["123", "espace"]
            ]

            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 2) {
                    if rowIndex == 3 {
                        // Bottom row: 123 key + space bar
                        miniKey("123", width: 32, isSpecial: true)
                        miniKey("espace", isSpace: true)
                    } else {
                        ForEach(rows[rowIndex], id: \.self) { letter in
                            miniKey(letter)
                        }
                    }
                }
            }
        }
        .padding(10)
    }

    // MARK: - Numbers Preview (123 + symbols)

    /// Number row + symbol rows to clearly distinguish from letters.
    private var numbersModePreview: some View {
        VStack(spacing: 3) {
            toolbarPreview

            // Number row
            HStack(spacing: 2) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], id: \.self) { num in
                    miniKey(num, isHighlighted: true)
                }
            }

            // Symbol rows
            let symbolRows = [
                ["-", "/", ":", ";", "(", ")", "€", "&", "@"],
                [".", ",", "?", "!", "'"]
            ]

            ForEach(0..<symbolRows.count, id: \.self) { rowIndex in
                HStack(spacing: 2) {
                    ForEach(symbolRows[rowIndex], id: \.self) { sym in
                        miniKey(sym)
                    }
                }
            }

            // Bottom row: ABC key + space bar
            HStack(spacing: 2) {
                miniKey("ABC", width: 32, isSpecial: true)
                miniKey("espace", isSpace: true)
            }
        }
        .padding(10)
    }

    // MARK: - Mini Key Helper

    /// A tiny key cell for the miniature keyboard previews.
    /// All keys use maxWidth: .infinity so they fill the available row width evenly,
    /// just like the real keyboard. Special keys (123, ABC) get a fixed width instead.
    private func miniKey(
        _ label: String,
        width: CGFloat? = nil,
        isSpace: Bool = false,
        isSpecial: Bool = false,
        isHighlighted: Bool = false
    ) -> some View {
        // Adaptive colors: work on both light and dark backgrounds
        let bg: Color = isSpecial
            ? Color(.systemGray4)
            : isHighlighted
                ? Color.dictusAccent.opacity(0.2)
                : Color(.systemGray5)

        let maxW: CGFloat = width ?? .infinity

        return Text(label)
            .font(.system(size: isSpace ? 6 : 7, weight: .medium))
            .foregroundStyle(isHighlighted ? Color.dictusAccent : .primary)
            .frame(maxWidth: maxW, minHeight: 16)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(bg)
            )
    }
}
