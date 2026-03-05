// DictusApp/ContentView.swift
import SwiftUI
import DictusCore

struct ContentView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @State private var diagnosticResult: DiagnosticResult?

    var body: some View {
        ZStack {
            // Base content: diagnostic view (will be replaced by Model Manager in Plan 2.3)
            NavigationStack {
                VStack(spacing: 20) {
                    Text("Dictus")
                        .font(.largeTitle.bold())

                    if let result = coordinator.lastResult, coordinator.status == .idle {
                        Text("Last result: \(result)")
                            .font(.body)
                            .padding()
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(8)
                    }

                    Divider()

                    if let result = diagnosticResult {
                        DiagnosticView(result: result)
                    } else {
                        ProgressView("Running diagnostics...")
                    }
                }
                .padding()
                .navigationTitle("Dictus")
            }

            // Full-screen overlay when dictation is active
            // WHY a ZStack overlay instead of NavigationStack push:
            // RecordingView is a full-screen takeover (dark background, focused UI).
            // It doesn't belong in a navigation hierarchy — it appears when dictation
            // starts and disappears when it ends, like a modal.
            if coordinator.status != .idle {
                RecordingView()
                    .transition(.opacity)
            }
        }
        .task {
            diagnosticResult = AppGroupDiagnostic.run()
        }
    }
}

struct DiagnosticView: View {
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

#Preview {
    ContentView()
        .environmentObject(DictationCoordinator.shared)
}
