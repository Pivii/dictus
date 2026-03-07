// DictusKeyboard/Design/ProcessingAnimation.swift
// Branded processing/transcribing animation — keyboard extension copy.
import SwiftUI

/// Animated processing indicator using brand colors.
/// Keyboard extension copy of DictusApp/Design/ProcessingAnimation.swift.
struct ProcessingAnimation: View {
    @State private var phase: CGFloat = 0

    var height: CGFloat = 48

    @ScaledMetric private var barWidth: CGFloat = 8

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                let delay = Double(index) * 0.2
                let scale = pulseScale(for: delay)

                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(
                        LinearGradient(
                            colors: [.dictusGradientStart, .dictusGradientEnd],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: height * scale)
                    .opacity(0.5 + scale * 0.5)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func pulseScale(for delay: Double) -> CGFloat {
        let adjustedPhase = (phase + CGFloat(delay)).truncatingRemainder(dividingBy: 1.4)
        return 0.4 + 0.6 * abs(sin(adjustedPhase * .pi))
    }
}
