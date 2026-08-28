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
///
/// WHY there is a locked variant rather than two views: the history is a Pro feature
/// (`HistoryAvailability`), and #395's precedent is to **mark** a locked feature, not
/// to drop it — so this draws a lock and leads to the paywall instead. The caller
/// decides which it is; a view that answered the entitlement itself would be the
/// second place the answer lives. Note that `.hidden` never reaches here at all: the
/// home screen does not build this view then.
struct SwipeUpHintView: View {

    /// Whether the user is not entitled to the history. Locked draws the lock and
    /// the Pro badge, and the caller's action is expected to open the paywall.
    let isLocked: Bool

    /// Called when the hint is tapped. The swipe itself is handled by the parent,
    /// which owns the drag area.
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isBouncing = false

    /// How far the chevron travels. 4pt: visible as movement, too small to read as
    /// the view sliding.
    private let bounceDistance: CGFloat = 4

    init(isLocked: Bool = false, action: @escaping () -> Void) {
        self.isLocked = isLocked
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if isLocked {
                    // No chevron: there is nothing to swipe toward yet, and an arrow
                    // pointing at a paywall would be a lie about the gesture.
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.dictusAccent)
                } else {
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.dictusAccent)
                        .offset(y: isBouncing ? -bounceDistance : 0)
                }
                label
            }
            .frame(maxWidth: .infinity)
            // The tappable area covers the full width of the screen, so the hint is
            // as easy to hit as it is to see.
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.97))
        .accessibilityLabel("History")
        .accessibilityHint(isLocked
            ? "Part of Dictus Pro. Opens the subscription screen."
            : "Shows your saved transcriptions")
        .onAppear {
            guard !isLocked, !reduceMotion else { return }
            startBouncing()
        }
        .onChange(of: reduceMotion) { _, isReduced in
            // Turning the setting on mid-session has to stop the loop, not wait for
            // the next launch: the animation is already running with `repeatForever`.
            if isReduced || isLocked {
                withAnimation(.easeOut(duration: 0.2)) { isBouncing = false }
            } else {
                startBouncing()
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        if isLocked {
            HStack(spacing: 6) {
                Text("History")
                    .font(.dictusCaption)
                    .foregroundColor(.secondary)
                // The same badge Settings' locked rows carry, so a locked feature
                // reads the same wherever the user meets one.
                Text("PRO")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(Color.dictusAccent)
                    .clipShape(Capsule())
                    .accessibilityHidden(true)
            }
        } else {
            Text("Swipe for history")
                .font(.dictusCaption)
                .foregroundColor(.secondary)
        }
    }

    private func startBouncing() {
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            isBouncing = true
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        Spacer()
        SwipeUpHintView {}
        SwipeUpHintView(isLocked: true) {}
    }
    .background(Color.dictusBackground.ignoresSafeArea())
}
