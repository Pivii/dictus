#if os(iOS)
// DictusCore/Sources/DictusCore/Design/AnimatedMicButton.swift
// Animated microphone button with visual states for idle, recording, transcribing, and success.
import SwiftUI

/// Animated mic button with 4 visual states matching dictation lifecycle.
///
/// WHY separate from keyboard ToolbarView mic button:
/// ToolbarView's mic is a compact icon in the keyboard toolbar. This AnimatedMicButton
/// is a larger, more prominent button for the main app's HomeView -- different visual
/// treatment, same functional purpose.
///
/// State machine:
/// - idle/ready: soft blue glow pulsing at 2s interval
/// - recording: red pulse ring scaling 1.0-1.3 at 0.8s interval
/// - transcribing/processing: blue shimmer sweep moving left-to-right at 1.5s
///   (this button is the main app's; the two stages are told apart in the keyboard
///   overlay and the Dynamic Island, which is where the user waits -- see #267)
/// - failed: same as idle (reset to inviting state)
/// - Transition from either post-recording stage to ready: brief green flash (0.3s fade)
public struct AnimatedMicButton: View {
    public let status: DictationStatus
    public let isPill: Bool

    /// The armed Smart Mode's mark, drawn on the button's corner, or nil when there
    /// is nothing armed. A glyph for Notes, the target's code for Translate — see
    /// `SmartModeBadge` for why the two are not the same thing.
    ///
    /// A parameter since #79, and a badge rather than a colour. The obvious signal
    /// was to recolour the pill, and it was built twice and refused on sight both
    /// times: the resting pill is *already* the accent blue, so any second colour on
    /// it reads as a foreign element pasted onto the product rather than as a state
    /// of it. The badge changes the button's silhouette instead, which is the axis
    /// the design had left free — it costs zero width in the most contested 32 pt of
    /// the UI, it survives every status the button can be in, and it names *which*
    /// mode instead of merely saying that one exists.
    ///
    /// It never replaces anything the status owns. Recording stays red and the two
    /// post-recording stages stay in their washed accent, because those describe what
    /// the phone is doing right now and outrank a setting — a red mic must mean
    /// recording on every screen of this product.
    public let badge: SmartModeBadge?

    public let onTap: () -> Void

    public init(status: DictationStatus,
                isPill: Bool = false,
                badge: SmartModeBadge? = nil,
                onTap: @escaping () -> Void) {
        self.status = status
        self.isPill = isPill
        self.badge = badge
        self.onTap = onTap
    }

    // MARK: - Animation State

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var showSuccessFlash: Bool = false
    @State private var previousStatus: DictationStatus = .idle

    /// Circle mode: 72pt diameter. Pill mode: 56x36 capsule for keyboard toolbar.
    private var buttonWidth: CGFloat { isPill ? 56 : 72 }
    private var buttonHeight: CGFloat { isPill ? 36 : 72 }
    private var ringWidth: CGFloat { isPill ? 66 : 92 }
    private var ringHeight: CGFloat { isPill ? 46 : 92 }

    /// Returns Capsule or Circle based on isPill.
    /// WHY AnyShape: @ViewBuilder wraps conditionals in _ConditionalContent which
    /// doesn't conform to Shape. AnyShape (available since iOS 16) erases the
    /// concrete type so both branches return the same Shape-conforming type.
    private func mainShape() -> AnyShape {
        if isPill {
            return AnyShape(Capsule())
        } else {
            return AnyShape(Circle())
        }
    }

    /// Whether the button is tappable in the current status.
    /// Only idle, ready, and failed allow new dictation starts.
    private var isTappable: Bool {
        status == .idle || status == .ready || status == .failed
    }

    public var body: some View {
        Button {
            // Belt-and-suspenders guard: .disabled should prevent this,
            // but log if somehow reached during a non-tappable state.
            guard isTappable else {
                PersistentLog.log(.rapidTapRejected)
                return
            }
            onTap()
        } label: {
            ZStack {
                // Background ring effects
                ringEffect

                // Main button shape (circle or pill)
                mainShape()
                    .fill(buttonFillColor)
                    .frame(width: buttonWidth, height: buttonHeight)

                // Shimmer overlay for the two post-recording stages
                if status == .transcribing || status == .processing {
                    shimmerOverlay
                }

                // Success flash overlay
                if showSuccessFlash {
                    mainShape()
                        .fill(Color.dictusSuccess.opacity(0.6))
                        .frame(width: buttonWidth, height: buttonHeight)
                }

                // Mic icon
                Image(systemName: "mic.fill")
                    .font(.system(size: isPill ? 14 : 16, weight: .medium))
                    .foregroundColor(.white)
                    .scaleEffect(status == .recording ? pulseScale * 0.9 + 0.1 : 1.0)

                // Armed Smart Mode, last so nothing draws over it
                armedBadge
            }
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.88))
        .disabled(!isTappable)
        .onChange(of: status) { newStatus in
            handleStatusChange(from: previousStatus, to: newStatus)
            previousStatus = newStatus
        }
        .onAppear {
            startIdleAnimation()
        }
    }

    // MARK: - Armed Smart Mode Badge

    /// The mode's glyph on a white disc, straddling the button's lower-right edge.
    ///
    /// White and not a tint of the button: the disc has to survive every fill the
    /// status can put behind it — accent blue at rest, red while recording, a washed
    /// highlight while transcribing — and white is the only value that reads on all
    /// three without becoming a fourth colour in the product.
    ///
    /// It straddles the edge rather than sitting inside it so the silhouette itself
    /// changes. That is the whole point of the badge: the signal has to survive being
    /// seen out of the corner of the eye, at which distance a glyph *inside* a 56×36
    /// pill is just texture.
    @ViewBuilder
    private var armedBadge: some View {
        if let badge {
            badgeContent(badge)
                .foregroundColor(.dictusAccent)
                .frame(width: badgeDiameter, height: badgeDiameter)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                .offset(x: badgeOffset.width, y: badgeOffset.height)
        }
    }

    /// Text rides smaller than a glyph, and rounded.
    ///
    /// A two-letter code set at the symbol's size overflows the disc — SF Symbols are
    /// drawn to fit their point size, two characters are not. Rounded because the disc
    /// is one, and `.monospaced`-style digits are not wanted: these are letters.
    @ViewBuilder
    private func badgeContent(_ badge: SmartModeBadge) -> some View {
        switch badge {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: badgeDiameter * 0.52, weight: .semibold))
        case .text(let value):
            Text(value)
                .font(.system(size: badgeDiameter * 0.44, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var badgeDiameter: CGFloat { isPill ? 18 : 24 }

    /// Placed against the corner of the *button*, not of the ring: the ring is a glow
    /// and has no edge the eye reads as the button's own.
    private var badgeOffset: CGSize {
        isPill ? CGSize(width: 24, height: 13) : CGSize(width: 25, height: 25)
    }

    // MARK: - Ring Effects

    @ViewBuilder
    private var ringEffect: some View {
        switch status {
        case .idle, .ready, .failed:
            // Glass ring with soft glow pulsing 0.3-0.6 opacity over 2s
            mainShape()
                .fill(Color.clear)
                .frame(width: ringWidth, height: ringHeight)
                .dictusGlass(in: isPill ? AnyShape(Capsule()) : AnyShape(Circle()))
                .overlay(
                    mainShape()
                        .stroke(Color.dictusAccent.opacity(glowOpacity), lineWidth: 2)
                        .frame(width: ringWidth, height: ringHeight)
                )

        case .recording:
            // Red pulse ring scaling 1.0-1.3 over 0.8s
            mainShape()
                .fill(Color.clear)
                .frame(width: ringWidth, height: ringHeight)
                .dictusGlass(in: isPill ? AnyShape(Capsule()) : AnyShape(Circle()))
                .overlay(
                    mainShape()
                        .stroke(Color.dictusRecording.opacity(0.5), lineWidth: 3)
                        .frame(width: ringWidth, height: ringHeight)
                )
                .scaleEffect(pulseScale)

        case .transcribing, .processing, .requested:
            // Static glass ring during transcription and the LLM stage
            mainShape()
                .fill(Color.clear)
                .frame(width: ringWidth, height: ringHeight)
                .dictusGlass(in: isPill ? AnyShape(Capsule()) : AnyShape(Circle()))
                .overlay(
                    mainShape()
                        .stroke(Color.dictusAccent.opacity(0.4), lineWidth: 2)
                        .frame(width: ringWidth, height: ringHeight)
                )
        }
    }

    // MARK: - Shimmer Overlay

    /// Left-to-right shimmer sweep for transcribing state.
    ///
    /// WHY a gradient mask approach:
    /// A moving gradient overlay creates the "shimmer" effect without custom drawing.
    /// The offset animation moves the bright spot across the button surface.
    private var shimmerOverlay: some View {
        mainShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0)
                    ],
                    startPoint: UnitPoint(x: shimmerOffset - 0.3, y: 0.5),
                    endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                )
            )
            .frame(width: buttonWidth, height: buttonHeight)
    }

    // MARK: - Helpers

    private var buttonFillColor: Color {
        switch status {
        case .recording:
            return .dictusRecording
        case .transcribing, .processing:
            return .dictusAccentHighlight.opacity(0.5)
        default:
            return .dictusAccent
        }
    }

    // MARK: - Animation Control

    /// WHY there is no log line here any more (#255): this view is instantiated
    /// once per live keyboard root view, and iOS keeps ~9 of those alive at a time,
    /// so `statusChanged source=micButton` reported a single transition ~9 times —
    /// 44 lines for 5 dictations in the measured session. The transition itself is
    /// already logged exactly once by whoever owns the status: `KeyboardState`
    /// (`source=keyboardState`) in the extension, `DictationCoordinator`
    /// (`source=coordinator`) in the app. Nothing is lost.
    ///
    /// The animation reset below is deliberately NOT gated: it must keep running on
    /// every instance, including the app's own visible recording UI.
    private func handleStatusChange(from oldStatus: DictationStatus, to newStatus: DictationStatus) {
        // Reset ALL animation state to concrete values WITHOUT animation first.
        // WHY: This cancels any existing repeating animations that could stack
        // with the new ones, causing jitter or incorrect visual state.
        pulseScale = 1.0
        glowOpacity = 0.3
        shimmerOffset = -1.0

        // Success flash when transitioning from transcribing to ready.
        // WHY withAnimation instead of asyncAfter: SwiftUI animates the transition
        // from true to false over 0.3s, eliminating the timer race condition.
        if (oldStatus == .transcribing || oldStatus == .processing) && newStatus == .ready {
            showSuccessFlash = true
            withAnimation(.easeOut(duration: 0.3)) {
                showSuccessFlash = false
            }
        }

        switch newStatus {
        case .idle, .ready, .failed:
            startIdleAnimation()
        case .recording:
            startRecordingAnimation()
        case .transcribing, .processing:
            startTranscribingAnimation()
        case .requested:
            // Static state -- no animations. Button is disabled via isTappable.
            // Visual: standard accent color, no pulse, no glow animation.
            break
        }
    }

    private func startIdleAnimation() {
        pulseScale = 1.0
        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            glowOpacity = 0.6
        }
    }

    private func startRecordingAnimation() {
        glowOpacity = 0.5
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.3
        }
    }

    private func startTranscribingAnimation() {
        pulseScale = 1.0
        glowOpacity = 0.4
        shimmerOffset = -1.0
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            shimmerOffset = 2.0
        }
    }
}

#Preview("Circle") {
    VStack(spacing: 40) {
        AnimatedMicButton(status: .idle) {}
        AnimatedMicButton(status: .recording) {}
        AnimatedMicButton(status: .transcribing) {}
    }
    .padding()
    .background(Color(hex: 0x0A1628))
}

#Preview("Pill") {
    VStack(spacing: 40) {
        AnimatedMicButton(status: .idle, isPill: true) {}
        AnimatedMicButton(status: .idle, isPill: true, badge: .symbol("list.bullet")) {}
        AnimatedMicButton(status: .idle, isPill: true, badge: .text("EN")) {}
        AnimatedMicButton(status: .recording, isPill: true, badge: .text("ES")) {}
        AnimatedMicButton(status: .transcribing, isPill: true) {}
    }
    .padding()
    .background(Color(hex: 0x0A1628))
}
#endif
