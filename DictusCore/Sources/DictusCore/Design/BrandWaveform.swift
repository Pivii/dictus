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

    public init(energyLevels: [Float], maxHeight: CGFloat = 80) {
        self.energyLevels = energyLevels
        self.maxHeight = maxHeight
    }

    /// WHY @Environment colorScheme:
    /// Outer bars use white in dark mode (original) and gray in light mode.
    /// Without this, white bars on a light background are invisible.
    @Environment(\.colorScheme) private var colorScheme

    /// Number of bars to display.
    private let barCount = 30

    /// Consistent spacing between bars.
    private let barSpacing: CGFloat = 2

    public var body: some View {
        GeometryReader { geometry in
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let barWidth = max((geometry.size.width - totalSpacing) / CGFloat(barCount), 2)

            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    barView(index: index, barWidth: barWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.08), value: energyLevels)
    }

    // MARK: - Private

    private func barView(index: Int, barWidth: CGFloat) -> some View {
        let energy = energyForBar(at: index)
        // Minimum bar height so bars are visible even at zero energy
        let minHeight: CGFloat = 4
        let height = minHeight + CGFloat(energy) * (maxHeight - minHeight)

        return RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(colorForBar(at: index))
            .frame(width: barWidth, height: height)
    }

    /// Map bar index to an energy value from the energyLevels array.
    ///
    /// WHY interpolation:
    /// energyLevels may have fewer or more entries than barCount.
    /// We map each bar position proportionally into the array.
    private func energyForBar(at index: Int) -> Float {
        guard !energyLevels.isEmpty else { return 0 }
        let position = Float(index) / Float(max(barCount - 1, 1))
        let arrayIndex = position * Float(energyLevels.count - 1)
        let lower = Int(arrayIndex)
        let upper = min(lower + 1, energyLevels.count - 1)
        let fraction = arrayIndex - Float(lower)
        let value = energyLevels[lower] * (1 - fraction) + energyLevels[upper] * fraction
        return min(max(value, 0), 1)
    }

    /// Brand-inspired color: blue gradient in center, white with opacity on sides.
    ///
    /// WHY this pattern:
    /// Mirrors the Dictus logo where the center bar is blue gradient and side bars
    /// are white at varying opacity. Here the gradient fades from blue center to
    /// translucent white edges, creating a branded but natural waveform look.
    private func colorForBar(at index: Int) -> some ShapeStyle {
        // Distance from center (0.0 = center, 1.0 = edge)
        let center = Float(barCount - 1) / 2.0
        let distanceFromCenter = abs(Float(index) - center) / center

        // Center bars: brand blue, edge bars: white with decreasing opacity
        if distanceFromCenter < 0.4 {
            // Inner 40%: blue gradient blend
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.dictusGradientStart, .dictusGradientEnd],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            // Outer 60%: adaptive color with opacity decreasing toward edges
            // Gray in light mode (visible on light backgrounds), white in dark mode
            let opacity = Double(1.0 - distanceFromCenter) * 0.9 + 0.15
            let barColor: Color = colorScheme == .dark ? .white : .gray
            return AnyShapeStyle(barColor.opacity(opacity))
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
