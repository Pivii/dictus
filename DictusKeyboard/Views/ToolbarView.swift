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
///
/// The bar has two presentations (#241) and keeps its 52 pt in both, so opening
/// the panel is a content swap and not a resize. In an area that has produced four
/// layout regressions (#166 and family), that property matters more than anything
/// else in the design:
///
///     closed:  [☰]  ← centre slot →  [🎤 pill]
///     open:    [✕]                   [Dictus Pro] [⚙]
///
/// There is deliberately no mic while the panel is open: the panel is not a
/// surface anyone dictates from, and the mic's absence is what makes the state
/// unambiguous.
struct ToolbarView: View {
    let hasFullAccess: Bool
    let dictationStatus: DictationStatus
    var onMicTap: () -> Void

    // Suggestion bar integration parameters (default to idle/empty)
    var statusMessage: String?
    var suggestions: [String] = []
    var suggestionMode: SuggestionMode = .idle
    var onSuggestionTap: ((Int) -> Void)?

    /// Whether the hamburger panel currently fills the keyboard area (#241).
    /// Drives which of the two presentations above the bar renders.
    var isPanelOpen: Bool = false

    /// Opens the panel from the hamburger, closes it from the ✕. Same callback:
    /// both are the same control in the same 32 pt slot, just labelled by state.
    var onPanelToggle: (() -> Void)?

    /// Gear, panel presentation only. Opens DictusApp.
    var onSettingsTap: (() -> Void)?

    /// Hides the Pro entry. Read once when the panel opens rather than observed:
    /// a subscription cannot change while the keyboard is the frontmost surface.
    var isProActive: Bool = false

    /// Pro entry, panel presentation only. Non-subscribers only.
    var onProTap: (() -> Void)?

    var body: some View {
        // WHY ZStack: ensures the banner text is centered horizontally across the
        // full toolbar width, independent of the mic pill position on the right.
        // Both layers are vertically centered by the ZStack's default alignment.
        ZStack {
            if !hasFullAccess {
                fullAccessBar
            } else if isPanelOpen {
                panelBar
            } else {
                dictationBar
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

    // MARK: - Presentations

    /// The dictation cockpit: hamburger left (when idle), suggestion bar (when
    /// typing), mic right.
    ///
    /// WHY the hamburger yields to suggestions:
    /// The suggestion bar needs horizontal space to display 3 slots legibly. The
    /// hamburger inherits that arbitration from the language switcher it replaced,
    /// at the same 32 pt cost. Accepted consequence (#241): the keyboard language
    /// cannot be changed mid-word.
    private var dictationBar: some View {
        HStack {
            if let message = statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            } else if suggestions.isEmpty {
                hamburgerButton

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
    }

    /// The panel header: close left, gear anchored right, Pro entry inserted to
    /// the gear's left for non-subscribers.
    ///
    /// The gear is last in the stack in both subscription states, so it never
    /// moves — a subscriber must not have to look for it somewhere a
    /// non-subscriber does not.
    private var panelBar: some View {
        HStack(spacing: 8) {
            closeButton

            Spacer()

            if !isProActive {
                proEntry
            }

            settingsButton
        }
    }

    /// No Full Access: centered banner text + disabled mic on the right.
    private var fullAccessBar: some View {
        ZStack {
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

                AnimatedMicButton(status: .idle, isPill: true, onTap: {})
                    .disabled(true)
                    .opacity(0.4)
            }
        }
    }

    // MARK: - Controls

    /// Bare hamburger, no language code on it (#241): the keyboard already
    /// announces its language through the spacebar label and the key positions,
    /// and a variable-width label jitters the most contested 32 pt of the UI.
    private var hamburgerButton: some View {
        panelToggleButton(
            systemName: "line.3.horizontal",
            label: Text("Keyboard menu")
        )
    }

    private var closeButton: some View {
        panelToggleButton(
            systemName: "xmark",
            label: Text("Close menu")
        )
    }

    /// Both states of the left slot, at the identical 32 pt frame the language
    /// label used, so ☰ becomes ✕ in place with no geometry change.
    private func panelToggleButton(systemName: String, label: Text) -> some View {
        Button {
            HapticFeedback.keyTapped()
            onPanelToggle?()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color(.label))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private var settingsButton: some View {
        Button {
            HapticFeedback.keyTapped()
            onSettingsTap?()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(Color(.label))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Open Dictus"))
    }

    /// White pill, gradient text, in both light and dark appearances (#241).
    ///
    /// Chosen over a gradient-filled pill and over gradient text alone: it carries
    /// the paywall's own gradient, so the Pro signal reads identically across
    /// surfaces, while staying legible against either keyboard background.
    ///
    /// Known and accepted: on the light keyboard a white rounded pill with a
    /// shadow resembles a key. If it reads as a key on device, the recorded
    /// fallback is a gradient-filled pill in light appearance only.
    private var proEntry: some View {
        Button {
            HapticFeedback.keyTapped()
            onProTap?()
        } label: {
            Text(verbatim: "Dictus Pro")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.dictusGradientStart, .dictusGradientEnd],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Capsule().fill(Color.white)
                )
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
        }
        .accessibilityLabel(Text(verbatim: "Dictus Pro"))
    }
}
