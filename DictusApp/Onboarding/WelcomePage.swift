// DictusApp/Onboarding/WelcomePage.swift
// Step 1 of onboarding: animated waveform, wordmark, tagline, and "Commencer" button.
import SwiftUI
import DictusCore

/// Welcome page shown on first launch with animated brand waveform and tagline.
///
/// WHY BrandWaveform with idle animation:
/// A gentle breathing waveform creates an alive first impression instead of a static logo.
/// A Timer generates random low-energy values (0.1-0.4) every 0.5s, making the bars
/// subtly pulse. This is purely decorative — no audio is being captured.
struct WelcomePage: View {
    let onNext: () -> Void

    @State private var showContent = false
    @State private var idleEnergy: [Float] = Array(repeating: 0.15, count: 30)

    /// Timer that generates gentle random energy values for the breathing animation.
    private let idleTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated brand waveform with gentle idle breathing
            BrandWaveform(energyLevels: idleEnergy, maxHeight: 100)
                .padding(.bottom, 24)
                .onReceive(idleTimer) { _ in
                    idleEnergy = (0..<30).map { _ in Float.random(in: 0.1...0.4) }
                }

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
