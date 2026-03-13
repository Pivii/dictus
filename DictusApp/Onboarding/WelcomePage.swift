// DictusApp/Onboarding/WelcomePage.swift
// Step 1 of onboarding: animated waveform, wordmark, tagline, and "Commencer" button.
import SwiftUI
import DictusCore

/// Welcome page shown on first launch with animated brand waveform and tagline.
///
/// WHY BrandWaveform with processing (sinusoidal) animation:
/// A smooth traveling sine wave creates a polished first impression instead of
/// random jittery bars. The sinusoidal mode is inherently fluid (60fps via
/// TimelineView) and requires no Timer — simpler code, better visual result.
struct WelcomePage: View {
    let onNext: () -> Void

    @State private var showContent = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Smooth sinusoidal waveform — same as the transcription processing animation
            BrandWaveform(maxHeight: 100, isProcessing: true)
                .opacity(0.5)
                .padding(.bottom, 24)

            // "Dictus" wordmark
            Text("Dictus")
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
