// DictusKeyboard/Views/ToolbarView.swift
import SwiftUI
import DictusCore

/// Toolbar displayed above the keyboard with app shortcut and AnimatedMicButton.
/// Inspired by Wispr Flow -- the mic button is the primary dictation trigger.
///
/// WHY AnimatedMicButton replaces inline micIcon:
/// AnimatedMicButton provides 4 visual states (idle glow, recording pulse,
/// transcribing shimmer, success flash) that give the user clear feedback
/// about the dictation lifecycle. The inline micIcon only had basic color changes.
struct ToolbarView: View {
    let hasFullAccess: Bool
    let dictationStatus: DictationStatus
    var onMicTap: () -> Void

    // Suggestion bar integration parameters (default to idle/empty)
    var suggestions: [String] = []
    var suggestionMode: SuggestionMode = .idle
    var onSuggestionTap: ((Int) -> Void)? = nil

    /// Icon size scales with Dynamic Type.
    @ScaledMetric private var gearIconSize: CGFloat = 16

    var body: some View {
        // WHY ZStack: ensures the banner text is centered horizontally across the
        // full toolbar width, independent of the mic pill position on the right.
        // Both layers are vertically centered by the ZStack's default alignment.
        ZStack {
            if hasFullAccess {
                // Normal mode: gear left (when idle), suggestion bar (when typing), mic right.
                // WHY hide gear when suggestions showing:
                // The suggestion bar needs horizontal space to display 3 slots legibly.
                // The gear icon is rarely needed during active typing, and users can
                // access settings between typing sessions when the bar reverts to idle.
                HStack {
                    if suggestions.isEmpty {
                        Link(destination: URL(string: "dictus://")!) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: gearIconSize, weight: .medium))
                                .foregroundColor(Color(.systemGray))
                                .frame(width: 32, height: 32)
                        }

                        Spacer()
                    } else {
                        SuggestionBarView(
                            suggestions: suggestions,
                            mode: suggestionMode,
                            onTap: { index in onSuggestionTap?(index) }
                        )
                    }

                    AnimatedMicButton(status: dictationStatus, isPill: true, onTap: onMicTap)
                }
            } else {
                // No Full Access: centered banner text + disabled mic on the right
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Acces complet requis")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()

                    AnimatedMicButton(status: .idle, isPill: true, onTap: {})
                        .disabled(true)
                        .opacity(0.4)
                }
            }
        }
        .padding(.horizontal, 12)
        // WHY 48pt instead of 44pt: The AnimatedMicButton pill (36pt tall) has glow/shadow
        // effects that extend slightly above. 44pt clipped the top of the mic pill.
        // 48pt provides 6pt breathing room above and below the pill.
        .frame(height: 48)
    }
}
