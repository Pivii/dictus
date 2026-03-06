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
    /// NOTE: Default is `true` during development so the app is immediately usable.
    /// Plan 04-02 will set this to `false` and build the real OnboardingView.
    @AppStorage(SharedKeys.hasCompletedOnboarding, store: UserDefaults(suiteName: AppGroup.identifier))
    private var hasCompletedOnboarding = true

    init() {
        let result = AppGroupDiagnostic.run()
        if #available(iOS 14.0, *) {
            DictusLogger.app.info(
                "AppGroup diagnostic: healthy=\(result.isHealthy)"
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(coordinator)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
                    // Onboarding placeholder — replaced by OnboardingView in Plan 04-02
                    VStack(spacing: 20) {
                        Image(systemName: "hand.wave.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.dictusAccent)
                        Text("Bienvenue dans Dictus")
                            .font(.dictusHeading)
                        Text("L'onboarding sera disponible bientot.")
                            .font(.dictusBody)
                            .foregroundColor(.secondary)
                    }
                    .interactiveDismissDisabled()
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Received URL: \(url.absoluteString)")
        }
        guard url.scheme == "dictus" else { return }

        switch url.host {
        case "dictate":
            coordinator.startDictation()
        default:
            if #available(iOS 14.0, *) {
                DictusLogger.app.warning("Unknown URL host: \(url.host ?? "nil")")
            }
        }
    }
}
