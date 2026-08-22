// tools/ane-harness/App/AneHarnessApp.swift
//
// THROWAWAY — #268 D2, phone side.
//
// The measurement has to happen while the app is backgrounded, and a
// backgrounded app cannot be tapped. So the harness is self-running: it loads
// in the foreground, tells the maintainer to press Home, and then runs on its
// own whether or not anyone is watching. It stays alive backgrounded the same
// way DictusApp does — `UIBackgroundModes: audio` plus a running audio engine —
// because reproducing that state is the point, not a workaround for it.
import SwiftUI
import DictusCore

@main
struct AneHarnessApp: App {
    @StateObject private var controller = HarnessController()

    var body: some Scene {
        WindowGroup {
            HarnessView(controller: controller)
                .task { await controller.start() }
        }
    }
}

struct HarnessView: View {
    @ObservedObject var controller: HarnessController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(controller.headline)
                        .font(.headline)
                    if let countdown = controller.countdown {
                        Text("Press Home now — waiting \(countdown) s, then it runs anyway.")
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.orange)
                    }
                    Text(controller.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !controller.resultText.isEmpty {
                        Divider()
                        Text(controller.resultText)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        if let url = controller.resultFileURL {
                            ShareLink(item: url) { Label("Export the JSON", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("ANE bench — #268")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
