// DictusApp/Design/BrandWaveform.swift
// Logo-inspired 3-bar waveform component matching Dictus brand proportions.
import SwiftUI

/// Renders 3 asymmetric vertical bars matching the Dictus logo proportions.
///
/// WHY not reuse RecordingView's WaveformView:
/// WaveformView shows 50 bars from live audio energy — it's a real-time visualizer.
/// BrandWaveform shows exactly 3 bars matching the logo design (18pt/42pt/27pt proportions).
/// They serve different purposes: branding vs. audio feedback.
///
/// Bar proportions derived from the brand kit:
/// - Left bar: 18/42 = 0.43 of max height, white at 45% opacity
/// - Center bar: 42/42 = 1.0 of max height, blue gradient
/// - Right bar: 27/42 = 0.64 of max height, white at 65% opacity
struct BrandWaveform: View {
    /// Energy level from 0.0 (idle) to 1.0 (max). Drives bar height animation.
    let energy: Float

    /// Maximum height of the tallest bar (center).
    var maxHeight: CGFloat = 80

    /// Bar width scales with Dynamic Type for accessibility.
    @ScaledMetric private var barWidth: CGFloat = 12

    /// Base height proportions matching logo: left=0.43, center=1.0, right=0.64
    private let baseHeights: [CGFloat] = [0.43, 1.0, 0.64]

    /// Opacity values for left and right bars (center uses gradient instead).
    private let barOpacities: [Double] = [0.45, 1.0, 0.65]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                barView(index: index)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: energy)
    }

    // MARK: - Private

    private func barView(index: Int) -> some View {
        let energyClamped = CGFloat(min(max(energy, 0), 1))
        let height = baseHeights[index] * (0.3 + energyClamped * 0.7) * maxHeight

        return Group {
            if index == 1 {
                // Center bar: blue gradient (brand signature)
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(
                        LinearGradient(
                            colors: [.dictusGradientStart, .dictusGradientEnd],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: height)
            } else {
                // Side bars: white with opacity
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(Color.white.opacity(barOpacities[index]))
                    .frame(width: barWidth, height: height)
            }
        }
    }
}

#Preview("Idle") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(energy: 0)
    }
}

#Preview("Active") {
    ZStack {
        Color(hex: 0x0A1628).ignoresSafeArea()
        BrandWaveform(energy: 0.7)
    }
}
