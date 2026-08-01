// DictusKeyboard/Views/RecordingOverlay.swift
import SwiftUI
import DictusCore

/// Full-screen recording overlay that replaces the keyboard during active recording.
/// Shows different visual states based on DictationStatus:
/// - .requested: flat waveform bars, "Démarrage..." text, cancel-only button
/// - .recording: live waveform, elapsed timer, cancel + stop buttons
/// - .transcribing: shimmer waveform, "Transcription..." text
///
/// WHY this replaces the keyboard:
/// Wispr Flow-inspired design -- when recording, the keyboard area transforms into
/// an immersive recording UI. This prevents accidental key presses during dictation
/// and provides clear visual feedback that the mic is active.
///
/// WHY dedicated keyboard waveform driver:
/// The shared BrandWaveform uses TimelineView, which proved fragile inside the keyboard
/// extension after suspension/resume. The keyboard now owns a single explicit animation
/// driver that starts and stops with the overlay lifecycle, while this view stays a thin
/// container around rendering and controls.
struct RecordingOverlay: View {
    let dictationStatus: DictationStatus
    let waveformEnergy: [Float]
    let elapsedSeconds: Double
    @ObservedObject var waveformDriver: KeyboardWaveformDriver
    let onCancel: () -> Void
    let onStop: () -> Void
    @State private var instanceID = String(UUID().uuidString.prefix(8))

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

    /// Shared with `ToolbarView`'s pill icons so the two bars stay one system
    /// (#241). Same values as the local definition it replaces.
    private var secondaryForeground: Color { .dictusPillIconSecondary }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: varies by state but has consistent height
            topBar

            // Waveform area fills remaining space between topBar and footer.
            // WHY no GeometryReader: On the first frame, the hosting view may still be
            // at toolbar height (52pt) before expanding to full keyboard height.
            // GeometryReader would measure the old frame, rendering the waveform
            // compressed at the top for ~1 frame before re-measuring. Using a fixed
            // maxHeight + Spacers ensures the waveform is centered from the first frame.
            VStack(spacing: 8) {
                Spacer(minLength: 0)

                KeyboardWaveformView(
                    maxHeight: 120,
                    driver: waveformDriver
                )
                .padding(.horizontal, 2)

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)

            // Footer: varies by state
            footer
        }
        .background(Color.clear)
        .onAppear {
            PersistentLog.log(.diagnosticProbe(
                component: "RecordingOverlay",
                instanceID: instanceID,
                action: "onAppear",
                details: "status=\(dictationStatus.rawValue) energyCount=\(waveformEnergy.count)"
            ))
            PersistentLog.log(.overlayBodyEvaluated(
                status: dictationStatus.rawValue,
                showsOverlay: true,
                energyCount: waveformEnergy.count
            ))
        }
        .onDisappear {
            PersistentLog.log(.diagnosticProbe(
                component: "RecordingOverlay",
                instanceID: instanceID,
                action: "onDisappear",
                details: "status=\(dictationStatus.rawValue)"
            ))
        }
        .onChange(of: dictationStatus) { _, newStatus in
            PersistentLog.log(.diagnosticProbe(
                component: "RecordingOverlay",
                instanceID: instanceID,
                action: "statusChanged",
                details: "newStatus=\(newStatus.rawValue) energyCount=\(waveformEnergy.count)"
            ))
        }
    }

    // MARK: - Top bar (varies by state)

    /// Top bar with recording control buttons.
    ///
    /// WHY @ViewBuilder: Each state shows different buttons but reserves the same
    /// vertical space (10pt + 36pt pill + 6pt = 52pt total), so the BrandWaveform
    /// below never shifts vertically during state transitions.
    ///
    /// WHY 10pt on top and not 6 (#241 device feedback): this bar replaces
    /// `ToolbarView`, which is 52pt tall with 4pt of top padding and centres its
    /// pills — putting their top edge at y=10. At 6pt these pills sat 4pt higher,
    /// so starting a recording made both of them visibly jump up a notch. The
    /// asymmetric padding is what makes the two bars interchangeable.
    ///
    /// Horizontal alignment was already correct: the 17pt trailing inset offsets
    /// the mic's 66pt ring around its 56pt pill, so the right-hand pill keeps the
    /// same edge in both bars.
    @ViewBuilder
    private var topBar: some View {
        switch dictationStatus {
        case .requested:
            // Cancel only (no stop button -- nothing to stop yet)
            HStack {
                PillButton(icon: "xmark", color: secondaryForeground) {
                    HapticFeedback.recordingStopped()
                    onCancel()
                }
                Spacer()
            }
            .padding(.leading, 12)
            .padding(.trailing, 17)
            .padding(.top, 10)
            .padding(.bottom, 6)

        case .transcribing:
            // Reserve same height as button row so waveform doesn't shift
            Color.clear
                .frame(height: 36)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

        default:
            // Cancel (left) and validate (right) -- pill-shaped Liquid Glass buttons
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
            .padding(.leading, 12)
            .padding(.trailing, 17)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Footer (varies by state)

    /// Footer with status text and optional timer.
    /// WHY matching heights: Each state reserves the same total footer height
    /// (timer line + caption line + padding) so the BrandWaveform above never
    /// shifts vertically during state transitions.
    @ViewBuilder
    private var footer: some View {
        switch dictationStatus {
        case .requested:
            // Reserve timer height (invisible) so waveform doesn't shift
            Color.clear
                .frame(height: timerFontSize)
                .padding(.bottom, 4)

            Text("Starting...")
                .font(.dictusCaption)
                .foregroundColor(secondaryForeground)
                .padding(.bottom, 8)

        case .transcribing:
            // Reserve timer height (invisible) so waveform doesn't shift
            Color.clear
                .frame(height: timerFontSize)
                .padding(.bottom, 4)

            Text("Transcribing...")
                .font(.dictusCaption)
                .foregroundColor(secondaryForeground)
                .padding(.bottom, 8)

        default:
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
                    .frame(width: 56, height: 36)
                    .contentShape(Rectangle())
                    .dictusGlass(in: Capsule())
            }
            .buttonStyle(GlassPressStyle())
        }
    }
}
