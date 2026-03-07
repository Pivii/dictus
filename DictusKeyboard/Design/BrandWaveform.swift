// IMPORTANT: This file is duplicated in DictusApp/Design/ and DictusKeyboard/Design/. Keep both copies in sync.
// DictusKeyboard/Design/BrandWaveform.swift
// Multi-bar waveform with brand-inspired colors (blue gradient center, white opacity sides).
import SwiftUI

/// Multi-bar audio waveform styled with Dictus brand colors.
/// Keyboard extension copy — identical to DictusApp/Design/BrandWaveform.swift.
///
/// WHY a separate copy:
/// Keyboard extensions can't import DictusApp targets. The design system files
/// are duplicated in DictusKeyboard/Design/ for the extension target.
struct BrandWaveform: View {
    /// Array of energy levels (0.0-1.0) for each bar. Count determines bar count.
    let energyLevels: [Float]

    /// Fixed height of the waveform container. Bars grow within this space.
    var maxHeight: CGFloat = 80

    /// Adaptive color for outer bars: gray in light mode, white in dark mode.
    @Environment(\.colorScheme) private var colorScheme

    /// Number of bars to display.
    private let barCount = 30

    /// Consistent spacing between bars.
    private let barSpacing: CGFloat = 2

    var body: some View {
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
        let minHeight: CGFloat = 4
        let height = minHeight + CGFloat(energy) * (maxHeight - minHeight)

        return RoundedRectangle(cornerRadius: barWidth / 2)
            .fill(colorForBar(at: index))
            .frame(width: barWidth, height: height)
    }

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

    private func colorForBar(at index: Int) -> some ShapeStyle {
        let center = Float(barCount - 1) / 2.0
        let distanceFromCenter = abs(Float(index) - center) / center

        if distanceFromCenter < 0.4 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [.dictusGradientStart, .dictusGradientEnd],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            let opacity = Double(1.0 - distanceFromCenter) * 0.9 + 0.15
            let barColor: Color = colorScheme == .dark ? .white : .gray
            return AnyShapeStyle(barColor.opacity(opacity))
        }
    }
}
