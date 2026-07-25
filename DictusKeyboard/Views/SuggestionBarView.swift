// DictusKeyboard/Views/SuggestionBarView.swift
// Displays up to 3 word/accent suggestions in a horizontal row within the toolbar.
import SwiftUI
import DictusCore

/// A 3-slot suggestion bar that appears in the toolbar while the user is typing.
///
/// WHY a separate view:
/// The suggestion bar has its own layout logic (equal-width slots, dividers,
/// bold center slot) that would clutter ToolbarView. Extracting it keeps
/// both views focused on a single responsibility.
///
/// WHY .frame(maxWidth: .infinity) per slot:
/// This ensures all slots take equal width regardless of text length,
/// matching Apple's native keyboard suggestion bar layout.
///
/// Visual states per mode:
/// - completions: bold best completion in slot 1, others regular.
/// - corrections: quoted original in slot 0, bold correction in slot 1.
/// - predictions: all slots equal weight.
/// - undoAvailable: slot 0 is the "undo chip" — accent-tinted with an
///   undo arrow icon. It pulses briefly when a correction is applied (#224):
///   autocorrect fires no haptic, so this pulse is the correction feedback.
///   It says both "we corrected this" and "tap here to revert".
struct SuggestionBarView: View {
    let suggestions: [String]
    let mode: SuggestionMode
    let onTap: (Int) -> Void

    /// True during the brief flash of the undo chip right after a correction.
    /// The chip rises to a stronger tint + slight scale, then eases back to
    /// its resting tint (which persists while undo is available).
    @State private var undoPulseActive = false

    var body: some View {
        if suggestions.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    if index > 0 {
                        // Thin vertical divider between slots (Apple keyboard style)
                        Rectangle()
                            .fill(Color(.systemGray3))
                            .frame(width: 0.5)
                            .padding(.vertical, 8)
                    }

                    Button {
                        onTap(index)
                    } label: {
                        slotLabel(suggestion, at: index)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: suggestions)
            // The bar leaves the hierarchy between correction and undoAvailable
            // (suggestions are cleared, then repopulated async), so entry into
            // undo mode is usually a fresh onAppear. onChange covers in-place
            // transitions (e.g. predictions -> undoAvailable without emptying).
            .onAppear {
                if mode == .undoAvailable { triggerUndoPulse() }
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .undoAvailable { triggerUndoPulse() }
            }
        }
    }

    // MARK: - Slot rendering

    /// Renders one suggestion slot. The undo chip (slot 0 in undo mode) gets
    /// dedicated styling; all other slots are plain text.
    @ViewBuilder
    private func slotLabel(_ suggestion: String, at index: Int) -> some View {
        if mode == .undoAvailable && index == 0 {
            undoChip(word: suggestion)
        } else {
            // In correction mode:
            //   index 0 = original word in quotes (tapping keeps it as-is)
            //   index 1 = bold correction (auto-applied on space)
            //   index 2 = alternative correction
            // In completion mode:
            //   index 1 = bold (best completion)
            //   others = regular weight
            // In prediction mode:
            //   All equal weight -- no "auto-applied" word, all are suggestions
            // This matches standard iOS keyboard suggestion bar behavior.
            Text(displayText(suggestion, at: index))
                .font(.system(size: 15))
                .fontWeight(fontWeight(at: index))
                .foregroundColor(Color(.label))
        }
    }

    /// The undo chip: original word + undo arrow on an accent-tinted capsule.
    ///
    /// WHY a tinted chip instead of plain text (#224):
    /// Autocorrect no longer fires a haptic, so the bar is the only surface
    /// that signals "a word was just corrected". The persistent accent tint
    /// keeps the revert action discoverable for as long as undo is available;
    /// the entry pulse marks the moment of correction itself.
    private func undoChip(word: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 12, weight: .semibold))
            Text(word)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(.dictusAccent)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.dictusAccent.opacity(undoPulseActive ? 0.35 : 0.12))
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
        )
        .scaleEffect(undoPulseActive ? 1.05 : 1.0)
    }

    /// Flashes the undo chip: instant rise (reads as an event, not a fade-in),
    /// then a ~0.45s ease back to the resting tint.
    ///
    /// WHY withTransaction for the rise:
    /// The enclosing bar animates on `suggestions` changes; disabling animations
    /// for the rise guarantees the flash starts at full strength immediately.
    private func triggerUndoPulse() {
        var rise = Transaction()
        rise.disablesAnimations = true
        withTransaction(rise) { undoPulseActive = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.45)) {
                undoPulseActive = false
            }
        }
    }

    /// In correction mode, the original word (index 0) is shown in quotes
    /// to indicate it's the "as-typed" option. Matches iOS native behavior
    /// where the unquoted bold center word is the one that gets auto-applied.
    private func fontWeight(at index: Int) -> Font.Weight {
        switch mode {
        case .predictions:
            return .regular
        case .undoAvailable:
            return index == 0 ? .semibold : .regular
        default:
            return index == 1 ? .semibold : .regular
        }
    }

    private func displayText(_ suggestion: String, at index: Int) -> String {
        if mode == .corrections && index == 0 {
            return "\u{201C}\(suggestion)\u{201D}"
        }
        return suggestion
    }
}
