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

    /// Whether the mic should present its not-ready state because a model load
    /// is in flight (issue #250). Presentation only — the authoritative refusal
    /// still lives in `KeyboardState.startRecording()`.
    var micAvailability: MicAvailability = .available

    // Suggestion bar integration parameters (default to idle/empty)
    var statusMessage: KeyboardStatusMessage?
    var suggestions: [String] = []
    var suggestionMode: SuggestionMode = .idle
    var onSuggestionTap: ((Int) -> Void)?

    /// Callback when the user cycles the language via the toolbar switcher.
    var onLanguageChanged: ((SupportedLanguage) -> Void)?

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
                    if let message = statusMessage {
                        Text(message.text)
                            .font(.caption)
                            // Only real failures are red. A model still loading
                            // is a normal transient wait (issue #250).
                            .foregroundColor(message.isError ? .red : .secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    } else if suggestions.isEmpty {
                        LanguageSwitcherView(onLanguageChanged: onLanguageChanged)

                        Spacer()
                    } else {
                        SuggestionBarView(
                            suggestions: suggestions,
                            mode: suggestionMode,
                            onTap: { index in onSuggestionTap?(index) }
                        )
                    }

                    if micAvailability == .modelLoading && dictationStatus.isMicRestingState {
                        // Model load in flight: same dimmed treatment as the
                        // no-Full-Access case, but still tappable so the tap
                        // explains the wait instead of doing nothing.
                        unavailableMic(isTappable: true, onTap: onMicTap)
                            .accessibilityLabel(Text("Microphone unavailable, the model is loading"))
                    } else {
                        AnimatedMicButton(status: dictationStatus, isPill: true, onTap: onMicTap)
                    }
                }
            } else {
                // No Full Access: centered banner text + disabled mic on the right
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Full access required")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()

                    unavailableMic(isTappable: false, onTap: {})
                }
            }
        }
        .padding(.horizontal, 12)
        // Push content down so the mic ring/glow doesn't get clipped by the
        // iOS keyboard container's native top border (~2pt separator).
        .padding(.top, 4)
        // WHY 52pt: The AnimatedMicButton pill (36pt tall) has ring/glow effects
        // extending to 46pt. With 4pt top padding, 52pt total provides enough
        // breathing room above and below the pill without clipping.
        .frame(height: 52)
    }

    /// The single "mic not available" presentation, shared by every reason the
    /// mic can be unavailable (issue #250).
    ///
    /// WHY one builder: the no-Full-Access case already had a dimmed mic. A
    /// second, divergent disabled style for model loading would teach the user
    /// two different visual vocabularies for the same idea. The two cases
    /// differ only in whether the tap does something — Full Access has nothing
    /// useful to say here (the toolbar already carries its own banner), while a
    /// load in flight explains itself through the toolbar message.
    @ViewBuilder
    private func unavailableMic(isTappable: Bool, onTap: @escaping () -> Void) -> some View {
        AnimatedMicButton(status: .idle, isPill: true, onTap: onTap)
            .disabled(!isTappable)
            .opacity(0.4)
    }
}

private extension DictationStatus {
    /// Whether the mic button is currently sitting idle, i.e. the toolbar mic is
    /// the "start a dictation" affordance rather than live lifecycle feedback.
    ///
    /// The not-ready presentation must never mask recording/transcribing
    /// states: those own the button while they last, and a load cannot be in
    /// flight for them anyway.
    var isMicRestingState: Bool {
        self == .idle || self == .ready || self == .failed
    }
}
