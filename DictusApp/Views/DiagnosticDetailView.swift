// DictusApp/Views/DiagnosticDetailView.swift
// App Group diagnostic display, extracted from ContentView for reuse in Settings.
import SwiftUI
import DictusCore

/// Displays App Group diagnostic results (read/write health check).
///
/// WHY extracted from ContentView:
/// This view was originally defined inline in ContentView. Now that ContentView is
/// replaced by MainTabView + HomeView, DiagnosticView moves to its own file so it
/// can be reused in Settings > A propos > Diagnostic (Plan 04-02).
struct DiagnosticDetailView: View {
    let result: DiagnosticResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "App Group: \(result.appGroupID)",
                systemImage: result.containerExists ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundColor(result.containerExists ? .green : .red)

            Label(
                "Read: \(result.canRead ? "OK" : "Failed")",
                systemImage: result.canRead ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundColor(result.canRead ? .green : .red)

            Label(
                "Write: \(result.canWrite ? "OK" : "Failed")",
                systemImage: result.canWrite ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundColor(result.canWrite ? .green : .red)
        }
        .font(.system(.body, design: .monospaced))
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}
