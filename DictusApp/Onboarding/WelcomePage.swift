// DictusApp/Onboarding/WelcomePage.swift
// Step 1 of onboarding: animated logo, wordmark, tagline, and "Commencer" button.
import SwiftUI

/// Welcome page shown on first launch with animated brand waveform and tagline.
///
/// WHY BrandWaveform with animated energy:
/// The logo "breathes" on appear (energy 0 -> 0.5) creating an alive first impression.
/// The spring animation with a 1-second delay lets the page settle before animating.
struct WelcomePage: View {
    let onNext: () -> Void

    @State private var logoEnergy: Float = 0
    @State private var showContent = false

    /// Generate a gentle wave pattern for the welcome animation.
    private var logoLevels: [Float] {
        (0..<30).map { i in
            let center = Float(14.5)
            let dist = abs(Float(i) - center) / center
            return logoEnergy * (1.0 - dist * 0.6)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated brand waveform (logo)
            BrandWaveform(energyLevels: logoLevels, maxHeight: 100)
                .padding(.bottom, 24)

            // "dictus" wordmark
            // WHY SF Pro Rounded ultraLight instead of DM Sans:
            // DM Sans requires bundling a custom font file. SF Pro Rounded is
            // available on all iOS devices and provides a similar clean aesthetic.
            Text("dictus")
                .font(.system(size: 42, weight: .ultraLight, design: .rounded))
                .kerning(-0.5)
                .foregroundColor(.white)
                .padding(.bottom, 12)

            // Tagline
            Text("Dictation vocale, 100% offline")
                .font(.dictusBody)
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            // "Commencer" button
            Button(action: onNext) {
                Text("Commencer")
                    .font(.dictusSubheading)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.dictusAccent)
                    )
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .opacity(showContent ? 1 : 0)
        }
        .onAppear {
            // Animate logo breathing with delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                    logoEnergy = 0.5
                }
            }
            // Fade in content
            withAnimation(.easeIn(duration: 0.6).delay(0.5)) {
                showContent = true
            }
        }
    }
}
