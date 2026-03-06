// DictusApp/ContentView.swift
// Legacy wrapper — redirects to MainTabView. Kept for backward compatibility.
import SwiftUI
import DictusCore

/// Thin wrapper that redirects to MainTabView.
///
/// WHY kept instead of deleted:
/// ContentView is still referenced in the pbxproj build phase. Rather than removing
/// build file entries (which risks breaking the project file), we keep this as a
/// minimal redirect. The actual UI lives in MainTabView + HomeView.
struct ContentView: View {
    @EnvironmentObject var coordinator: DictationCoordinator

    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .environmentObject(DictationCoordinator.shared)
}
