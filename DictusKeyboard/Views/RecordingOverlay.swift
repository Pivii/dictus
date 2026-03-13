// DictusKeyboard/Views/RecordingOverlay.swift
import SwiftUI
import DictusCore

/// Full-screen recording overlay that replaces the keyboard during active recording.
/// Shows different visual states based on DictationStatus:
/// - .requested: flat waveform bars, "D\u{00E9}marrage..." text, cancel-only button
/// - .recording: live waveform, elapsed timer, cancel + stop buttons
/// - .transcribing: shimmer waveform, "Transcription..." text
///
/// WHY this replaces the keyboard:
/// Wispr Flow-inspired design -- when recording, the keyboard area transforms into
/// an immersive recording UI. This prevents accidental key presses during dictation
/// and provides clear visual feedback that the mic is active.
struct RecordingOverlay: View {
    let dictationStatus: DictationStatus
    let waveformEnergy: [Float]
    let elapsedSeconds: Double
    let onCancel: () -> Void
    let onStop: () -> Void

    /// Adaptive foreground color -- dark on light keyboard, light on dark keyboard.
    @Environment(\.colorScheme) private var colorScheme

    /// Timer font size scales with Dynamic Type.
    ///
    /// WHY @ScaledMetric:
    /// Keyboard extensions should respect Dynamic Type. Using @ScaledMetric makes
    /// the timer font size scale proportionally with the user's text size setting,
    /// while keeping monospaced design for proper digit alignment.
    @ScaledMetric private var timerFontSize: CGFloat = 20

    private var foregroundColor: Color {
        colorScheme == .dark ? .white : Color(white: 0.15)
    }

    private var secondaryForeground: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : Color(white: 0.15).opacity(0.5)
    }

    var body: some View {
        ZStack {
            // Transparent background -- the native iOS keyboard chrome shows through.
            // No dark rectangle, the overlay blends seamlessly with the keyboard.
            Color.clear

            switch dictationStatus {
            case .requested:
                requestedContent
            case .transcribing:
                transcribingContent
            default:
                recordingContent
            }
        }
        .onAppear {
            // Diagnostic logging for waveform disappearance bug investigation.
            // Logs once on overlay appear to capture initial state.
            PersistentLog.log("[Waveform] Overlay appeared — status=\(dictationStatus), energyCount=\(waveformEnergy.count)")
        }
        .onChange(of: waveformEnergy.count) { newCount in
            // Log significant changes in waveform energy count to diagnose
            // intermittent waveform disappearance. Only logs transitions to/from 0
            // to avoid flooding the log on every audio frame.
            if newCount == 0 || waveformEnergy.count == 0 {
                PersistentLog.log("[Waveform] Energy count changed — status=\(dictationStatus), count=\(newCount)")
            }
        }
    }

    // MARK: - Requested state (waiting for app to start recording)

    /// Shows flat waveform bars and "D\u{00E9}marrage..." text with cancel-only button.
    ///
    /// WHY a distinct visual for .requested:
    /// The overlay appears immediately on mic tap (before the app starts recording).
    /// Flat bars + "D\u{00E9}marrage..." gives the user instant visual feedback that their
    /// tap was registered, while clearly indicating recording hasn't started yet.
    private var requestedContent: some View {
        VStack(spacing: 0) {
            // Top bar: cancel only (no stop button -- nothing to stop yet)
            HStack {
                PillButton(icon: "xmark", color: secondaryForeground) {
                    HapticFeedback.recordingStopped()
                    onCancel()
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Flat waveform bars -- empty energy array produces flat bars in BrandWaveform
            GeometryReader { geo in
                VStack(spacing: 8) {
                    Spacer(minLength: 0)

                    BrandWaveform(
                        energyLevels: [],
                        maxHeight: geo.size.height * 0.7
                    )
                    .padding(.horizontal, 2)

                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            // Footer: "D\u{00E9}marrage..." status text
            Text("D\u{00E9}marrage...")
                .font(.dictusCaption)
                .foregroundColor(secondaryForeground)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Recording state

    private var recordingContent: some View {
        VStack(spacing: 0) {
            // Top bar: cancel (left) and validate (right) -- pill-shaped Liquid Glass buttons
            HStack {
                PillButton(icon: "xmark", color: secondaryForeground) {
                    HapticFeedback.recordingStopped()
                    onCancel()
                }

                Spacer()

                PillButton(icon: "checkmark", color: .dictusSuccess) {
                    HapticFeedback.recordingStopped()
                    onStop()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Waveform fills all remaining vertical space between buttons and footer.
            // WHY GeometryReader: The waveform must adapt to whatever space is
            // available rather than using a fixed maxHeight that can overflow.
            GeometryReader { geo in
                VStack(spacing: 8) {
                    Spacer(minLength: 0)

                    BrandWaveform(
                        energyLevels: waveformEnergy,
                        maxHeight: geo.size.height * 0.7
                    )
                    .padding(.horizontal, 2)

                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            // Footer: timer + status -- fixed height
            Text(formattedTime)
                .font(.system(size: timerFontSize, weight: .medium, design: .monospaced))
                .foregroundColor(foregroundColor)
                .padding(.bottom, 4)

            Text("Listening...")
                .font(.dictusCaption)
                .foregroundColor(secondaryForeground)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Transcribing state

    private var transcribingContent: some View {
        VStack(spacing: 16) {
            Spacer()

            // WHY BrandWaveform instead of ProcessingAnimation:
            // ProcessingAnimation showed 3 logo-based pulsing bars. BrandWaveform with
            // isProcessing: true produces a sinusoidal traveling wave that visually
            // continues from the recording waveform, signaling "processing audio data".
            BrandWaveform(maxHeight: 60, isProcessing: true)
                .padding(.horizontal, 16)

            Text("Transcription...")
                .font(.dictusCaption)
                .foregroundColor(secondaryForeground)

            Spacer()
        }
    }

    // MARK: - Helpers

    private var formattedTime: String {
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Pill Button

    /// Pill-shaped recording control button with Liquid Glass styling.
    ///
    /// WHY pill shape instead of SF Symbol circles:
    /// The old xmark.circle.fill / checkmark.circle.fill were small and hard to tap.
    /// Pill buttons (56x36) match the toolbar mic button shape, create visual consistency
    /// across the recording UI, and provide a larger hit target.
    private struct PillButton: View {
        let icon: String
        let color: Color
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 56, height: 44)
                    .contentShape(Rectangle())
                    .dictusGlass(in: Capsule())
            }
            .buttonStyle(GlassPressStyle())
        }
    }
}
