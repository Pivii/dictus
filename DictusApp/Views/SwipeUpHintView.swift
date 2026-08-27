// DictusApp/Views/SwipeUpHintView.swift
// The affordance at the bottom of the home screen that says the history is there.
import SwiftUI
import DictusCore

/// Chevron plus label at the bottom of the home screen, hinting at the swipe-up
/// that opens the transcription history (#70).
///
/// WHY it is a Button and not decoration: a drag is the only way the issue names to
/// reach the history, and a drag is exactly the gesture a user with a motor
/// impairment, or anyone driving the app with VoiceOver, cannot perform. Tapping the
/// hint opens the same screen. It costs nothing and it is the difference between the
/// feature existing for everyone and existing for most people.
///
/// WHY the bounce is a repeating animation on an offset rather than a transition:
/// the hint has to keep saying "there is something under here" for as long as the
/// home screen is on show, and a one-shot animation stops saying it after a second.
/// It stops entirely under Reduce Motion, where a permanently moving element is the
/// exact thing the setting exists to remove.
struct SwipeUpHintView: View {

    /// Called when the hint is tapped. The swipe itself is handled by the parent,
    /// which owns the drag area.
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isBouncing = false

    /// How far the chevron travels. 4pt: visible as movement, too small to read as
    /// the view sliding.
    private let bounceDistance: CGFloat = 4

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.dictusAccent)
                    .offset(y: isBouncing ? -bounceDistance : 0)
                Text("Swipe for history")
                    .font(.dictusCaption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            // The tappable area covers the full width of the screen, so the hint is
            // as easy to hit as it is to see.
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.97))
        .accessibilityLabel("History")
        .accessibilityHint("Shows your saved transcriptions")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isBouncing = true
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            // Turning the setting on mid-session has to stop the loop, not wait for
            // the next launch: the animation is already running with `repeatForever`.
            if isReduced {
                withAnimation(.easeOut(duration: 0.2)) { isBouncing = false }
            } else {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    isBouncing = true
                }
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        SwipeUpHintView {}
    }
    .background(Color.dictusBackground.ignoresSafeArea())
}
