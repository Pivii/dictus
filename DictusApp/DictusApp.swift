// DictusApp/DictusApp.swift
import SwiftUI
import DictusCore

@main
struct DictusApp: App {
    @StateObject private var coordinator = DictationCoordinator.shared

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
            ContentView()
                .environmentObject(coordinator)
                .onOpenURL { url in
                    handleIncomingURL(url)
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
