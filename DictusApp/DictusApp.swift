// DictusApp/DictusApp.swift
import SwiftUI
import DictusCore

@main
struct DictusApp: App {
    @StateObject private var coordinator = DictationCoordinator.shared

    /// Onboarding completion flag stored in App Group for cross-process access.
    ///
    /// WHY AppStorage with suiteName instead of plain @State:
    /// AppStorage with the App Group suite persists the value across app launches AND
    /// makes it accessible to the keyboard extension if needed. The `store:` parameter
    /// points to the shared UserDefaults container.
    ///
    /// Default is `false` — first-time users see the onboarding flow.
    /// Set to `true` when user completes the 5-step onboarding.
    @AppStorage(SharedKeys.hasCompletedOnboarding, store: UserDefaults(suiteName: AppGroup.identifier))
    private var hasCompletedOnboarding = false

    init() {
        let result = AppGroupDiagnostic.run()
        DictusLogger.app.info(
            "AppGroup diagnostic: healthy=\(result.isHealthy)"
        )

        // Persist language default so TranscriptionService always reads "fr"
        // even before user visits Settings. @AppStorage defaults are in-memory only
        // and never written to UserDefaults until the Picker is interacted with.
        // WHY `if nil` check: Only write if the key doesn't exist yet. If user already
        // set a language preference (e.g., "en"), don't overwrite it.
        let defaults = UserDefaults(suiteName: AppGroup.identifier)
        if defaults?.string(forKey: SharedKeys.language) == nil {
            defaults?.set("fr", forKey: SharedKeys.language)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(coordinator)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onChange(of: hasCompletedOnboarding) { completed in
                    // WHY this notification:
                    // MainTabView's HomeView mounts BEHIND the fullScreenCover before
                    // onboarding completes. Its onAppear fires early with stale state.
                    // When onboarding finishes and the cover dismisses, onAppear does NOT
                    // re-fire. This notification tells HomeView to refresh model state.
                    if completed {
                        NotificationCenter.default.post(
                            name: Notification.Name("DictusOnboardingCompleted"),
                            object: nil
                        )
                    }
                }
                .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
                    OnboardingView(isComplete: $hasCompletedOnboarding)
                        .environmentObject(coordinator)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        PersistentLog.log("Received URL: \(url.absoluteString)")
        guard url.scheme == "dictus" else { return }

        switch url.host {
        case "dictate":
            PersistentLog.log("URL dictate → calling startDictation(fromURL: true)")
            coordinator.startDictation(fromURL: true)
        default:
            PersistentLog.log("Unknown URL host: \(url.host ?? "nil")")
        }
    }
}
