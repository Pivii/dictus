// DictusApp/Onboarding/OnboardingView.swift
// Container for the 5-step onboarding flow with programmatic-only step advancement.
import SwiftUI
import DictusCore

/// 5-step onboarding flow presented as a fullScreenCover on first launch.
///
/// WHY switch/case instead of TabView:
/// TabView(.page) allows the user to swipe between pages, which means they could
/// skip required steps (mic permission, keyboard setup, model download).
/// Using a manual switch/case with @State currentPage ensures the user can ONLY
/// advance via each page's completion button — no swiping. This guarantees every
/// prerequisite is properly set up before the user reaches the test recording step.
///
/// WHY @Binding isComplete:
/// The parent (DictusApp.swift) owns `hasCompletedOnboarding` via @AppStorage.
/// When the last page (TestRecordingPage) finishes, it sets isComplete = true,
/// which writes to App Group UserDefaults and dismisses the fullScreenCover.
struct OnboardingView: View {
    @Binding var isComplete: Bool

    /// WHY @SceneStorage instead of @State:
    /// @SceneStorage persists the value across scene phase changes (background/foreground).
    /// Without this, returning from iOS Settings (e.g., after adding the keyboard) would
    /// reset the onboarding to step 1 because the view gets recreated. @SceneStorage
    /// remembers which page the user was on.
    @SceneStorage("onboarding_currentPage") private var currentPage: Int = 0

    /// Track which steps have been completed to show in the step indicator.
    @State private var completedSteps: Set<Int> = []

    /// Total number of onboarding steps.
    private let totalSteps = 5

    var body: some View {
        ZStack {
            Color.dictusBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Current page content — only one page visible at a time
                // WHY Group instead of ZStack: Group avoids stacking all 5 pages
                // on top of each other (unnecessary view hierarchy). Only the
                // matched case is instantiated.
                Group {
                    switch currentPage {
                    case 0:
                        WelcomePage(onNext: { advanceToPage(1) })
                    case 1:
                        MicPermissionPage(onNext: { advanceToPage(2) })
                    case 2:
                        KeyboardSetupPage(onNext: { advanceToPage(3) })
                    case 3:
                        ModelDownloadPage(onNext: { advanceToPage(4) })
                    case 4:
                        TestRecordingPage(onComplete: {
                            isComplete = true
                        })
                    default:
                        // Safety fallback — should never happen
                        WelcomePage(onNext: { advanceToPage(1) })
                    }
                }
                // Slide transition: new page slides in from trailing edge,
                // old page slides out to leading edge — standard forward navigation feel.
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
                .id(currentPage) // Force SwiftUI to treat each page as a unique view for transitions

                // Step indicator dots at the bottom
                stepIndicator
                    .padding(.bottom, 24)
            }
        }
        // Prevent interactive dismiss (swipe down) on the fullScreenCover
        .interactiveDismissDisabled()
        .animation(.easeInOut(duration: 0.3), value: currentPage)
    }

    // MARK: - Step Indicator

    /// Row of dots showing onboarding progress.
    ///
    /// WHY custom dots instead of TabView's built-in page indicator:
    /// Since we replaced TabView with manual switch/case, we need our own dots.
    /// Filled dot = current or completed step. Outlined dot = future step.
    /// This gives the user a clear sense of progress through the flow.
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(dotColor(for: step))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 16)
    }

    /// Determine dot color based on step state.
    private func dotColor(for step: Int) -> Color {
        if step == currentPage {
            return .dictusAccent
        } else if completedSteps.contains(step) {
            return .dictusAccent.opacity(0.5)
        } else {
            return .gray.opacity(0.3)
        }
    }

    // MARK: - Navigation

    private func advanceToPage(_ page: Int) {
        completedSteps.insert(currentPage)
        withAnimation {
            currentPage = page
        }
    }
}
