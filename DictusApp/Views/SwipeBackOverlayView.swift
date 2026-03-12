// DictusApp/Views/SwipeBackOverlayView.swift
// Full-screen branded overlay guiding users to swipe back to the keyboard after cold start.
import SwiftUI
import DictusCore

/// Full-screen overlay shown when the app is opened from the keyboard during cold start.
///
/// WHY a separate view instead of inline code in MainTabView:
/// This view has its own animation state, bilingual text logic, and brand styling.
/// Keeping it in its own file follows the "one file = one responsibility" convention
/// and makes it easy to preview in isolation.
///
/// WHY full-screen replacement (not overlay on top of tabs):
/// User decision from CONTEXT.md -- when the keyboard opens the app for cold start,
/// the user should NOT see the normal app UI. They should see a clean, branded screen
/// with clear instructions on how to swipe back to the keyboard.
struct SwipeBackOverlayView: View {
    /// Language preference from App Group shared storage.
    /// WHY @AppStorage with App Group store:
    /// The language is set in Settings and shared between app and keyboard extension
    /// via the App Group UserDefaults. Reading it here ensures the overlay text
    /// matches the user's chosen language.
    @AppStorage(SharedKeys.language, store: AppGroup.defaults)
    private var language = "fr"

    var body: some View {
        ZStack {
            // Brand gradient background matching the app icon gradient
            LinearGradient(
                colors: [Color(hex: 0x0D2040), Color(hex: 0x071020)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Animated iPhone outline with swipe gesture
                SwipeAnimationView()
                    .frame(width: 200, height: 300)

                // Primary instruction text
                Text(language == "fr"
                     ? "Glisse pour revenir au clavier"
                     : "Swipe back to the keyboard")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Secondary detail text
                Text(language == "fr"
                     ? "Glisse vers la droite en bas de l'ecran"
                     : "Swipe right on the bottom of your iPhone")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()
            }
        }
    }
}

// MARK: - Swipe Animation View

/// Animated iPhone outline with a sliding indicator showing the swipe-right gesture.
///
/// WHY pure SwiftUI animation instead of Lottie:
/// User decision from CONTEXT.md -- no external animation libraries. SwiftUI's built-in
/// animation system provides smooth, hardware-accelerated motion without adding a dependency.
///
/// The animation shows:
/// 1. A simplified iPhone outline (rounded rectangle with correct aspect ratio)
/// 2. A home indicator bar at the bottom
/// 3. An accent-colored circle that slides right repeatedly, simulating the swipe gesture
/// 4. A fading trail behind the circle to reinforce the swipe direction
private struct SwipeAnimationView: View {
    /// Controls the repeating swipe animation.
    /// WHY @State with onAppear toggle:
    /// SwiftUI animations need a state change to trigger. Setting this to true in onAppear
    /// starts the repeating animation immediately when the view appears.
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // iPhone outline
            // WHY 9:19.5 aspect ratio: matches modern iPhone screen proportions
            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.white.opacity(0.3), lineWidth: 2)

            // Home indicator bar at the bottom
            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 80, height: 5)
                    .padding(.bottom, 16)
            }

            // Swipe gesture animation area (positioned at bottom)
            VStack {
                Spacer()

                ZStack {
                    // Trail: fading chevrons behind the moving circle
                    // WHY chevrons as trail: they reinforce the swipe direction
                    // more clearly than a simple opacity fade
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color.dictusAccent.opacity(0.3 - Double(index) * 0.1))
                            .offset(x: isAnimating
                                    ? CGFloat(30 - index * 15)
                                    : CGFloat(-50 - index * 15))
                    }

                    // Moving accent circle (thumb indicator)
                    Circle()
                        .fill(Color.dictusAccent)
                        .frame(width: 30, height: 30)
                        .shadow(color: Color.dictusAccent.opacity(0.5), radius: 8)
                        .offset(x: isAnimating ? 50 : -30)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // WHY withAnimation + repeatForever:
            // Triggers a smooth, continuously repeating animation.
            // autoreverses: false makes the circle jump back to start
            // after reaching the end, creating a clear "swipe right" motion.
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Previews

#Preview("French") {
    SwipeBackOverlayView()
}

#Preview("English") {
    SwipeBackOverlayView()
        // Override language for preview
        .onAppear {
            AppGroup.defaults.set("en", forKey: SharedKeys.language)
        }
}
