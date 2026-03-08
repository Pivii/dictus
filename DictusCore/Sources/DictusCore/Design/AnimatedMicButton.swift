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
/// - transcribing: blue shimmer sweep moving left-to-right at 1.5s
/// - failed: same as idle (reset to inviting state)
/// - Transition from transcribing to ready: brief green flash (0.3s fade)
public struct AnimatedMicButton: View {
    public let status: DictationStatus
    public let onTap: () -> Void

    public init(status: DictationStatus, onTap: @escaping () -> Void) {
        self.status = status
        self.onTap = onTap
    }

    // MARK: - Animation State

    @State private var pulseScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var showSuccessFlash: Bool = false
    @State private var previousStatus: DictationStatus = .idle

    private let buttonSize: CGFloat = 72

    public var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background ring effects
                ringEffect

                // Main button circle
                Circle()
                    .fill(buttonFillColor)
                    .frame(width: buttonSize, height: buttonSize)

                // Shimmer overlay for transcribing state
                if status == .transcribing {
                    shimmerOverlay
                }

                // Success flash overlay
                if showSuccessFlash {
                    Circle()
                        .fill(Color.dictusSuccess.opacity(0.6))
                        .frame(width: buttonSize, height: buttonSize)
                }

                // Mic icon
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .scaleEffect(status == .recording ? pulseScale * 0.9 + 0.1 : 1.0)
            }
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.88))
        .disabled(status == .recording || status == .transcribing)
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
            // Glass ring with soft glow pulsing 0.3-0.6 opacity over 2s
            Circle()
                .fill(Color.clear)
                .frame(width: buttonSize + 20, height: buttonSize + 20)
                .dictusGlass(in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.dictusAccent.opacity(glowOpacity), lineWidth: 2)
                        .frame(width: buttonSize + 20, height: buttonSize + 20)
                )

        case .recording:
            // Red pulse ring scaling 1.0-1.3 over 0.8s
            Circle()
                .fill(Color.clear)
                .frame(width: buttonSize + 20, height: buttonSize + 20)
                .dictusGlass(in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.dictusRecording.opacity(0.5), lineWidth: 3)
                        .frame(width: buttonSize + 20, height: buttonSize + 20)
                )
                .scaleEffect(pulseScale)

        case .transcribing, .requested:
            // Static glass ring during transcription
            Circle()
                .fill(Color.clear)
                .frame(width: buttonSize + 20, height: buttonSize + 20)
                .dictusGlass(in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.dictusAccent.opacity(0.4), lineWidth: 2)
                        .frame(width: buttonSize + 20, height: buttonSize + 20)
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
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0),
                    ],
                    startPoint: UnitPoint(x: shimmerOffset - 0.3, y: 0.5),
                    endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                )
            )
            .frame(width: buttonSize, height: buttonSize)
    }

    // MARK: - Helpers

    private var buttonFillColor: Color {
        switch status {
        case .recording:
            return .dictusRecording
        case .transcribing:
            return .dictusAccent
        default:
            return .dictusAccent
        }
    }

    // MARK: - Animation Control

    private func handleStatusChange(from oldStatus: DictationStatus, to newStatus: DictationStatus) {
        // Success flash when transitioning from transcribing to ready
        if oldStatus == .transcribing && newStatus == .ready {
            showSuccessFlash = true
            withAnimation(.easeOut(duration: 0.3)) {
                // Flash will fade
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showSuccessFlash = false
            }
        }

        switch newStatus {
        case .idle, .ready, .failed:
            startIdleAnimation()
        case .recording:
            startRecordingAnimation()
        case .transcribing:
            startTranscribingAnimation()
        case .requested:
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

#Preview {
    VStack(spacing: 40) {
        AnimatedMicButton(status: .idle) {}
        AnimatedMicButton(status: .recording) {}
        AnimatedMicButton(status: .transcribing) {}
    }
    .padding()
    .background(Color(hex: 0x0A1628))
}
