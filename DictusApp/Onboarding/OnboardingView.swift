// DictusApp/Onboarding/OnboardingView.swift
// Container for the 5-step onboarding flow using a paged TabView.
import SwiftUI

/// 5-step onboarding flow presented as a fullScreenCover on first launch.
///
/// WHY TabView with page style:
/// TabView(.page) provides native iOS swipe-between-pages UX with page dots.
/// Each page manages its own completion state and calls `onNext` when done,
/// advancing the user to the next step. The user cannot swipe forward past
/// incomplete steps because we disable the tab content for future pages.
///
/// WHY @Binding isComplete:
/// The parent (DictusApp.swift) owns `hasCompletedOnboarding` via @AppStorage.
/// When the last page (TestRecordingPage) finishes, it sets isComplete = true,
/// which writes to App Group UserDefaults and dismisses the fullScreenCover.
struct OnboardingView: View {
    @Binding var isComplete: Bool

    @State private var currentPage: Int = 0

    /// Track which steps have been completed to prevent skipping ahead.
    @State private var completedSteps: Set<Int> = []

    var body: some View {
        ZStack {
            Color.dictusBackground
                .ignoresSafeArea()

            TabView(selection: $currentPage) {
                // Step 0: Welcome
                WelcomePage(onNext: { advanceToPage(1) })
                    .tag(0)

                // Step 1: Microphone permission
                MicPermissionPage(onNext: { advanceToPage(2) })
                    .tag(1)

                // Step 2: Keyboard setup
                KeyboardSetupPage(onNext: { advanceToPage(3) })
                    .tag(2)

                // Step 3: Model download
                ModelDownloadPage(onNext: { advanceToPage(4) })
                    .tag(3)

                // Step 4: Test recording
                TestRecordingPage(onComplete: {
                    isComplete = true
                })
                .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .animation(.easeInOut(duration: 0.3), value: currentPage)
        }
        // Prevent interactive dismiss (swipe down) on the fullScreenCover
        .interactiveDismissDisabled()
    }

    // MARK: - Private

    private func advanceToPage(_ page: Int) {
        completedSteps.insert(currentPage)
        withAnimation {
            currentPage = page
        }
    }
}
