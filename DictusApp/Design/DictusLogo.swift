// DictusApp/Design/DictusLogo.swift
// Static 3-bar logo matching brand kit proportions.
import SwiftUI

/// Static 3-bar logo component matching the Dictus brand kit.
///
/// WHY separate from BrandWaveform:
/// BrandWaveform is a multi-bar audio visualizer for recording feedback.
/// DictusLogo is the actual logo: exactly 3 bars at brand proportions (18/42/27pt).
/// Used on HomeView and onboarding WelcomePage where the logo identity matters.
struct DictusLogo: View {
    /// Overall height of the tallest bar (center).
    var height: CGFloat = 80

    /// Bar width.
    @ScaledMetric private var barWidth: CGFloat = 12

    /// Bar proportions from brand kit: left=18/42, center=42/42, right=27/42
    private let proportions: [CGFloat] = [0.43, 1.0, 0.64]

    /// Opacity for side bars (center uses gradient)
    private let opacities: [Double] = [0.45, 1.0, 0.65]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                let barHeight = proportions[index] * height
                if index == 1 {
                    // Center bar: brand blue gradient
                    RoundedRectangle(cornerRadius: 4.5)
                        .fill(
                            LinearGradient(
                                colors: [.dictusGradientStart, .dictusGradientEnd],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barWidth, height: barHeight)
                } else {
                    // Side bars: white with brand opacity
                    RoundedRectangle(cornerRadius: 4.5)
                        .fill(Color.white.opacity(opacities[index]))
                        .frame(width: barWidth, height: barHeight)
                }
            }
        }
        .frame(height: height)
    }
}
