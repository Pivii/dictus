// DictusCore/Sources/DictusCore/Design/BrandWaveform.swift
// Multi-bar waveform with brand-inspired colors (blue gradient center, white opacity sides).
import SwiftUI

/// Multi-bar audio waveform styled with Dictus brand colors.
///
/// WHY multi-bar instead of 3-bar logo:
/// 3 bars felt static and logo-like, not like a real audio visualizer.
/// This uses 30 bars for fluid audio feedback, but keeps brand identity through
/// the color scheme: center bars use the blue gradient, outer bars use white at
/// decreasing opacity -- echoing the logo's asymmetric bar styling.
///
/// WHY GeometryReader for bar width:
/// Bar width adapts automatically to fit available space in each context.
/// The waveform fills the space whether it appears in the recording overlay
/// (full keyboard width), the HomeView card (narrower), or RecordingView (full screen).
public struct BrandWaveform: View {
    /// Array of energy levels (0.0-1.0) for each bar. Count determines bar count.
    public let energyLevels: [Float]

    /// Fixed height of the waveform container. Bars grow within this space.
    public var maxHeight: CGFloat = 80

    /// When true, generates a synthetic sinusoidal wave pattern instead of using energyLevels.
    /// WHY: During transcription processing, the audio engine is idle but we want continuous
    /// visual feedback. A traveling sine wave maintains waveform continuity from the recording
    /// state while indicating "processing" rather than "recording".
    public var isProcessing: Bool = false

    public init(energyLevels: [Float] = [], maxHeight: CGFloat = 80, isProcessing: Bool = false) {
        self.energyLevels = energyLevels
        self.maxHeight = maxHeight
        self.isProcessing = isProcessing
    }

    /// WHY @Environment colorScheme:
    /// Outer bars use white in dark mode (original) and gray in light mode.
    /// Without this, white bars on a light background are invisible.
    @Environment(\.colorScheme) private var colorScheme

    /// Smoothed display levels for fluid animation.
    /// WHY @State instead of using energyLevels directly:
    /// energyLevels arrive at ~60Hz (app) or ~5Hz (keyboard). Direct rendering causes
    /// either micro-jitter (60Hz) or visible jumps (5Hz). displayLevels lerps toward
    /// energyLevels every frame, producing smooth motion regardless of input rate.
    @State private var displayLevels: [Float] = Array(repeating: 0, count: 30)

    /// Number of bars to display.
    private let barCount = 30

    /// Consistent spacing between bars.
    private let barSpacing: CGFloat = 2

    /// Smoothing factor for lerp interpolation (0 = no change, 1 = instant snap).
    /// WHY 0.3: Balances responsiveness (voice feels reactive) with smoothness
    /// (no jitter between frames). Lower values feel sluggish, higher values
    /// reintroduce the jitter we're trying to fix.
    private let smoothingFactor: Float = 0.3

    /// Exponential decay factor for bars returning to zero when energy drops.
    /// WHY separate from smoothingFactor: We want bars to rise quickly (responsive)
    /// but fall slowly (visually pleasing decay). 0.85 = bars take ~10 frames to
    /// fully settle, creating a smooth "fade out" instead of a harsh snap to zero.
    private let decayFactor: Float = 0.85

    public var body: some View {
        // WHY TimelineView for both recording AND processing:
        // Recording mode needs continuous frame updates to lerp displayLevels toward
        // energyLevels. Without TimelineView, SwiftUI only rerenders when energyLevels
        // changes — which means 5Hz keyboard updates produce 5fps animation.
        // TimelineView gives us a 60fps render loop for smooth interpolation in both modes.
        TimelineView(.animation) { timeline in
            let phase = isProcessing
                ? timeline.date.timeIntervalSinceReferenceDate / 2.0
                : 0
            waveformContent(processingPhase: phase)
                .onChange(of: timeline.date) { _ in
                    if !isProcessing {
                        updateDisplayLevels()
                    }
                }
        }
    }

    /// Canvas-based rendering for 60fps waveform.
    ///
    /// WHY Canvas instead of ForEach + RoundedRectangle:
    /// ForEach creates 30 separate SwiftUI views, each with its own layout pass.
    /// Canvas renders all 30 bars in a single GPU draw call, which is significantly
    /// more efficient and eliminates frame drops during rapid energy level updates.
    ///
    /// WHY zero minHeight in non-processing mode:
    /// The old minHeight of 4pt caused visible micro-movements at zero energy,
    /// making the waveform appear "alive" even when silent. Setting minHeight = 0
    /// means bars completely disappear at zero energy -- perfectly still.
    private func waveformContent(processingPhase: Double) -> some View {
        Canvas { context, size in
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let barWidth = max((size.width - totalSpacing) / CGFloat(barCount), 2)

            for index in 0..<barCount {
                let energy: Float
                if isProcessing {
                    energy = processingEnergy(at: index, phase: processingPhase)
                } else {
                    energy = index < displayLevels.count ? displayLevels[index] : 0
                }

                // Minimum bar height so the waveform baseline is always visible,
                // even in complete silence. 2pt = thin line, enough to see the
                // colored bar pattern (blue center, gray edges) without looking "active".
                let minHeight: CGFloat = isProcessing ? 4 : 2
                let height = max(minHeight + CGFloat(energy) * (maxHeight - minHeight), minHeight)

                let x = CGFloat(index) * (barWidth + barSpacing)
                let y = (size.height - height) / 2
                let rect = CGRect(x: x, y: y, width: barWidth, height: max(height, 0))
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                context.fill(path, with: .color(resolvedBarColor(at: index)))
            }
        }
        .frame(height: maxHeight)
    }

    /// Update displayLevels toward target energyLevels using lerp + exponential decay.
    ///
    /// Called every frame by TimelineView. Each bar interpolates independently:
    /// - If target > current: lerp UP (responsive to voice)
    /// - If target < current: decay DOWN (smooth fade-out)
    ///
    /// WHY lerp for rise, decay for fall:
    /// Rising bars should feel snappy (voice → immediate visual response).
    /// Falling bars should feel natural (voice stops → gradual settle, not a snap).
    private func updateDisplayLevels() {
        let targets = targetLevels()

        var updated = displayLevels
        for i in 0..<barCount {
            let target = i < targets.count ? targets[i] : Float(0)
            let current = updated[i]

            if target > current {
                // Rising: lerp toward target
                updated[i] = current + (target - current) * smoothingFactor
            } else {
                // Falling: exponential decay toward target
                updated[i] = target + (current - target) * decayFactor
            }

            // Snap to zero below perceptual threshold to avoid infinite decay
            if updated[i] < 0.005 {
                updated[i] = 0
            }
        }

        displayLevels = updated
    }

    /// Map energyLevels (variable count) to exactly barCount target values.
    /// Applies silence thresholding to eliminate ambient mic noise.
    private func targetLevels() -> [Float] {
        guard !energyLevels.isEmpty else {
            return Array(repeating: Float(0), count: barCount)
        }

        var result = [Float]()
        for index in 0..<barCount {
            let position = Float(index) / Float(max(barCount - 1, 1))
            let arrayIndex = position * Float(energyLevels.count - 1)
            let lower = Int(arrayIndex)
            let upper = min(lower + 1, energyLevels.count - 1)
            let fraction = arrayIndex - Float(lower)
            let value = energyLevels[lower] * (1 - fraction) + energyLevels[upper] * fraction
            // Silence threshold: ambient mic noise produces small non-zero energy (0.01-0.05).
            // Treat anything below 0.05 as true silence so bars are perfectly still.
            let thresholded = value < 0.05 ? Float(0) : value
            result.append(min(max(thresholded, 0), 1))
        }
        return result
    }

    /// Generate sinusoidal energy for processing mode.
    private func processingEnergy(at index: Int, phase: Double) -> Float {
        let normalizedIndex = Double(index) / Double(max(barCount - 1, 1))
        let sineValue = sin(2 * .pi * (normalizedIndex + phase))
        // Map sine (-1...1) to energy (0.2...0.7) for a subtle ambient effect
        return Float(0.2 + 0.25 * (sineValue + 1.0))
    }

    /// Brand-inspired color resolved to a plain Color for Canvas rendering.
    ///
    /// WHY plain Color instead of ShapeStyle/LinearGradient:
    /// Canvas's `context.fill(path, with:)` accepts `Shading` not `ShapeStyle`.
    /// Per-path gradients aren't practical in Canvas. Instead, center bars use the
    /// brand blue midpoint color (dictusGradientStart) which is visually close to
    /// the old top-to-bottom gradient. A minor simplification for major perf gain.
    private func resolvedBarColor(at index: Int) -> Color {
        // Distance from center (0.0 = center, 1.0 = edge)
        let center = Float(barCount - 1) / 2.0
        let distanceFromCenter = abs(Float(index) - center) / center

        // Center bars: brand blue, edge bars: white/gray with decreasing opacity
        if distanceFromCenter < 0.4 {
            // Inner 40%: solid brand blue (midpoint of old gradient)
            return .dictusGradientStart
        } else {
            // Outer 60%: adaptive color with opacity decreasing toward edges
            let opacity = Double(1.0 - distanceFromCenter) * 0.9 + 0.15
            let barColor: Color = colorScheme == .dark ? .white : .gray
            return barColor.opacity(opacity)
        }
    }
}

#Preview("Idle") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(energyLevels: Array(repeating: Float(0), count: 30))
    }
}

#Preview("Active") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(energyLevels: (0..<30).map { i in
            Float.random(in: 0.2...0.8)
        })
    }
}

#Preview("Processing") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(maxHeight: 120, isProcessing: true)
            .opacity(0.3)
            .padding(.horizontal)
    }
}
