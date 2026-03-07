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

    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Static brand logo (3 bars)
            DictusLogo(height: 100)
                .padding(.bottom, 24)

            // "dictus" wordmark
            Text("dictus")
                .font(.system(size: 42, weight: .ultraLight, design: .rounded))
                .kerning(-0.5)
                .foregroundStyle(.primary)
                .padding(.bottom, 12)

            // Tagline
            Text("Dictation vocale, 100% offline")
                .font(.dictusBody)
                .foregroundStyle(.secondary)

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
            withAnimation(.easeIn(duration: 0.6).delay(0.5)) {
                showContent = true
            }
        }
    }
}
