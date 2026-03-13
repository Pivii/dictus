// DictusApp/Views/MainTabView.swift
// Root navigation container with 3 tabs and full-screen recording overlay.
import SwiftUI
import DictusCore

/// Root view presenting the 3-tab navigation structure.
///
/// WHY TabView instead of NavigationStack:
/// The app has 3 distinct sections (Home, Models, Settings) that the user should be able
/// to switch between freely. A TabView provides standard iOS navigation for this pattern.
/// Each tab wraps its content in its own NavigationStack so push navigation works
/// independently per tab.
///
/// WHY ZStack overlay for RecordingView:
/// When dictation is active, the recording UI must cover the entire screen INCLUDING
/// the tab bar. A ZStack overlay with ignoresSafeArea achieves this, while a sheet or
/// fullScreenCover would leave the tab bar visible underneath on some iOS versions.
struct MainTabView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @StateObject private var modelManager = ModelManager()

    @State private var selectedTab: Int = 0

    /// In-memory flag: true after the first URL has been handled in this process.
    /// Resets naturally when iOS terminates the process (true cold start).
    /// WHY static on MainTabView (not DictusApp): onOpenURL fires inner-to-outer in SwiftUI,
    /// so MainTabView's handler fires BEFORE DictusApp's. We need the detection here.
    private static var hasHandledURL = false

    /// Tracks whether the app was opened from the keyboard for cold start dictation.
    @State private var isColdStartMode = false

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if isColdStartMode {
                // Full-screen branded overlay with animated swipe gesture and bilingual text.
                // WHY SwipeBackOverlayView instead of inline code:
                // The overlay has its own animation state and bilingual logic -- keeping it
                // in a separate file follows "one file = one responsibility".
                SwipeBackOverlayView()
            } else {
                // Main tab navigation (normal launch path)
                TabView(selection: $selectedTab) {
                    // Tab 0: Home dashboard
                    NavigationStack {
                        HomeView(modelManager: modelManager)
                    }
                    .tabItem {
                        Label("Accueil", systemImage: "house.fill")
                    }
                    .tag(0)

                    // Tab 1: Model management
                    NavigationStack {
                        ModelManagerView(modelManager: modelManager)
                    }
                    .tabItem {
                        Label("Modèles", systemImage: "cpu")
                    }
                    .tag(1)

                    // Tab 2: Settings
                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem {
                        Label("Réglages", systemImage: "gearshape.fill")
                    }
                    .tag(2)
                }
                .tint(.dictusAccent)
            }

            // Full-screen recording overlay covers everything including tab bar.
            // WHY not shown in cold start mode: During cold start, the recording runs
            // in the background while the user sees the SwipeBackOverlayView. Showing
            // RecordingView would cover the swipe-back instructions.
            if coordinator.status != .idle && !isColdStartMode {
                RecordingView(mode: .standalone)
            }
        }
        // Detect cold start directly from URL params. MainTabView's onOpenURL fires
        // BEFORE DictusApp's (SwiftUI propagates inner-to-outer), so we can't rely
        // on DictusApp having set the AppGroup flag yet.
        .onOpenURL { url in
            if let host = url.host, host == "dictate",
               let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               query.contains(where: { $0.name == "source" && $0.value == "keyboard" }) {
                if !Self.hasHandledURL {
                    // True cold start: process was just launched by keyboard URL.
                    isColdStartMode = true
                }
                Self.hasHandledURL = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                isColdStartMode = false
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(DictationCoordinator.shared)
}
