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

    /// Bar width scales with Dynamic Type for accessibility.
    @ScaledMetric private var barWidth: CGFloat = 4

    /// Number of bars to display.
    private let barCount = 30

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                barView(index: index)
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.15), value: energyLevels)
    }

    // MARK: - Private

    private func barView(index: Int) -> some View {
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
            return AnyShapeStyle(Color.white.opacity(opacity))
        }
    }
}
