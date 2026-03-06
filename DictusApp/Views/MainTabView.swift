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

    var body: some View {
        ZStack {
            // Main tab navigation
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
                    Label("Modeles", systemImage: "cpu")
                }
                .tag(1)

                // Tab 2: Settings (placeholder — built in Plan 04-02)
                NavigationStack {
                    settingsPlaceholder
                }
                .tabItem {
                    Label("Reglages", systemImage: "gearshape.fill")
                }
                .tag(2)
            }
            .tint(.dictusAccent)

            // Full-screen recording overlay covers everything including tab bar
            // WHY coordinator.status != .idle:
            // RecordingView handles all non-idle states (requested, recording,
            // transcribing, ready, failed). The ZStack overlay makes it cover the tab bar.
            //
            // WHY .tint on TabView:
            // Uses brand accent color for the selected tab icon/text instead of default blue.
            // On iOS 26, TabView automatically gets Liquid Glass styling -- no manual glass needed.
            if coordinator.status != .idle {
                RecordingView()
                    .transition(.opacity)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Settings Placeholder

    /// Temporary placeholder for Settings tab.
    /// Will be replaced by SettingsView in Plan 04-02.
    private var settingsPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Reglages")
                .font(.dictusHeading)
            Text("Bientot disponible")
                .font(.dictusBody)
                .foregroundColor(.secondary)
        }
        .navigationTitle("Reglages")
    }
}

#Preview {
    MainTabView()
        .environmentObject(DictationCoordinator.shared)
}
