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

    /// The colour of the button's **ring**, when the status has not claimed it.
    ///
    /// A parameter since #79: the keyboard's pill signals the armed Smart Mode by
    /// turning `.dictusSmartMode` purple, which costs zero width in the most
    /// contested 32 pt of the UI and stays visible while the user is typing.
    ///
    /// ### Why the ring and not the fill
    ///
    /// It was the fill, and that is what a device session found wrong (2026-08-24).
    /// The armed pill was 2,016 pt² of full-saturation purple, permanently, because
    /// the mode is sticky — while every other purple in the feature is already quiet:
    /// a 0.22 capsule behind a fan row, a 0.14 capsule behind the overlay badge, 13 pt
    /// of label text. One surface out of four was shouting, and it read as foreign in
    /// an app whose identity is grey, blue and white.
    ///
    /// A 3 pt stroke around the 66 × 46 ring is roughly 300 pt² — the same token and
    /// the same meaning at about a seventh of the ink. It also puts the signal on the
    /// **edge**, which is where `SmartModeFanView` already argues the signal has to
    /// be: the thumb that armed the mode is sitting on the pill.
    ///
    /// Removing purple altogether was considered and rejected. `#8B5CF6` measures
    /// 4.23:1 against white — better than `#3D7EFF`'s 3.73:1 — so it is not a
    /// contrast problem, and the brand kit names this colour "Smart mode". The dose
    /// was the problem.
    ///
    /// The status always outranks it: recording keeps its red ring, because a red mic
    /// must mean recording on every screen of this product.
    public let ringTint: Color

    public let onTap: () -> Void

    public init(status: DictationStatus,
                isPill: Bool = false,
                ringTint: Color = .dictusAccent,
                onTap: @escaping () -> Void) {
        self.status = status
        self.isPill = isPill
        self.ringTint = ringTint
        self.onTap = onTap
    }

    /// Whether the ring is carrying a signal of its own rather than the default glow.
    ///
    /// Drives the two things that separate an armed ring from an idle one: it is
    /// opaque and a notch thicker, and it does **not** breathe. The pulse says "tap
    /// me", which is about the button; armed is a statement about a setting, and
    /// settings do not breathe. That second channel is what keeps the two states
    /// distinguishable without relying on colour alone.
    private var ringCarriesSignal: Bool { ringTint != .dictusAccent }

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

    // MARK: - Ring Effects

    @ViewBuilder
    private var ringEffect: some View {
        switch status {
        case .idle, .ready, .failed:
            // Glass ring with soft glow pulsing 0.3-0.6 opacity over 2s — unless the
            // ring is carrying a signal, in which case it is opaque, 3 pt and still.
            //
            // Opaque is not a taste call: at the 0.3 end of the breath, `#8B5CF6`
            // composited over a light keyboard measures 1.35:1, which is invisible.
            // At full opacity it is 2.83:1 against that backdrop and 4.23:1 against
            // white. A breathing purple ring would have been a signal that vanishes
            // for half of every two seconds.
            mainShape()
                .fill(Color.clear)
                .frame(width: ringWidth, height: ringHeight)
                .dictusGlass(in: isPill ? AnyShape(Capsule()) : AnyShape(Circle()))
                .overlay(
                    mainShape()
                        .stroke(
                            ringTint.opacity(ringCarriesSignal ? 1 : glowOpacity),
                            lineWidth: ringCarriesSignal ? 3 : 2
                        )
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
            // Static glass ring during transcription and the LLM stage. The armed
            // mode stays named here too: this is the longest wait in the product,
            // and it is when the user most wants to be sure of what they armed.
            mainShape()
                .fill(Color.clear)
                .frame(width: ringWidth, height: ringHeight)
                .dictusGlass(in: isPill ? AnyShape(Capsule()) : AnyShape(Circle()))
                .overlay(
                    mainShape()
                        .stroke(
                            ringTint.opacity(ringCarriesSignal ? 0.8 : 0.4),
                            lineWidth: 2
                        )
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
            // Always the accent. The armed Smart Mode used to replace this and no
            // longer does — see `ringTint`. Blue at rest is the reference point the
            // rest of the toolbar's deliberately-50% icons are calibrated against
            // (`DictusColors.dictusPillIconSecondary`), and Dictus already renders a
            // faded mic to mean "you cannot dictate": desaturating the resting state
            // would put the default one step from the disabled one.
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
        AnimatedMicButton(status: .recording, isPill: true) {}
        AnimatedMicButton(status: .transcribing, isPill: true) {}
    }
    .padding()
    .background(Color(hex: 0x0A1628))
}
#endif
