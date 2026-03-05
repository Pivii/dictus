// DictusApp/DictusApp.swift
import SwiftUI
import DictusCore

@main
struct DictusApp: App {
    init() {
        let result = AppGroupDiagnostic.run()
        if #available(iOS 14.0, *) {
            DictusLogger.app.info("AppGroup diagnostic: healthy=\(result.isHealthy)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
