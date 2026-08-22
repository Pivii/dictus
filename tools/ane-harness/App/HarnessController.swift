// tools/ane-harness/App/HarnessController.swift
//
// THROWAWAY — #268 D2. The self-running protocol.
//
// Load (foreground) → wait to be backgrounded → run → write. The only human
// act in the whole protocol is pressing Home, and even that is a wait rather
// than a countdown, so nothing races the person holding the phone.
import Foundation
import SwiftUI
import AneBenchKit
import DictusCore

@MainActor
final class HarnessController: ObservableObject {

    /// How long to wait for someone to background the app before running
    /// anyway. Running anyway matters: a report that says `state=active` is a
    /// useful failure, whereas a harness that waits forever is a dead phone in
    /// a pocket and no data at all.
    private static let backgroundWaitSeconds = 180
    /// Settle time after the app goes to the background, so the transition's own
    /// work is not inside the measurement.
    private static let settleSeconds = 5

    @Published private(set) var headline = "Starting…"
    @Published private(set) var status = ""
    @Published private(set) var countdown: Int?
    @Published private(set) var resultText = ""
    @Published private(set) var resultFileURL: URL?

    private let keepAlive = BackgroundAudioKeepAlive()
    private var started = false

    func start() async {
        guard !started else { return }
        started = true

        let audioOutcome = keepAlive.start()
        append(audioOutcome)

        guard let modelDirectory = Bundle.main.url(forResource: "model", withExtension: nil) else {
            headline = "No model in the bundle"
            append("The 'model' folder reference is missing — see tools/ane-harness/README.md.")
            return
        }

        let runner = AneBenchRunner(configuration: AneBenchRunner.Configuration(
            modelDirectory: modelDirectory
        ))

        headline = "Loading the model — keep the app open"
        writePhase("loading")
        do {
            try await runner.prepare { message in
                Task { @MainActor in self.append(message) }
            }
        } catch {
            headline = "Load failed"
            append("\(error)")
            writePhase("failed")
            record(text: "ane-bench LOAD FAILED: \(error)", json: nil)
            return
        }

        headline = "Loaded. Press Home now."
        writePhase("waiting-for-background")
        // Wait for the lifecycle transition rather than counting down to it. A
        // countdown races the person holding the phone; this cannot.
        var waited = 0
        while await ProcessProbe.applicationState() != "background", waited < Self.backgroundWaitSeconds {
            countdown = Self.backgroundWaitSeconds - waited
            try? await Task.sleep(for: .seconds(1))
            waited += 1
        }
        countdown = nil
        if waited >= Self.backgroundWaitSeconds {
            append("never went to the background within \(Self.backgroundWaitSeconds)s — running anyway")
        }
        try? await Task.sleep(for: .seconds(Self.settleSeconds))

        headline = "Running…"
        writePhase("running")
        append("state at start of run: \(await ProcessProbe.applicationState())")
        do {
            let report = try await runner.run { message in
                Task { @MainActor in self.append(message) }
            }
            let rendered = report.rendered()
            resultText = rendered
            headline = report.allIterationsBackgrounded
                ? "Done — measured while backgrounded"
                : "Done — but NOT fully backgrounded (see state= below)"
            record(text: rendered, json: try? JSONEncoder().encode(report))
            writePhase("done")
        } catch {
            headline = "Run failed"
            append("\(error)")
            record(text: "ane-bench RUN FAILED: \(error)", json: nil)
            writePhase("failed")
        }
    }

    /// One word in a known file, so the run can be followed from the Mac with
    /// `devicectl device copy from` while the phone sits in a pocket. Without it
    /// the only way to know whether the model had finished loading would be to
    /// look at the screen, which is the thing this harness exists to avoid.
    private func writePhase(_ phase: String) {
        let url = Self.documentsDirectory.appendingPathComponent("phase.txt")
        try? phase.write(to: url, atomically: true, encoding: .utf8)
    }

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func append(_ message: String) {
        status = status.isEmpty ? message : status + "\n" + message
    }

    /// Three destinations, because they fail differently.
    ///
    /// #268 asks for the App Group, so that the results come out through the
    /// export path D1's did. This bundle id cannot be signed with that
    /// entitlement on this machine (see project.yml), so that write is attempted
    /// and reported rather than assumed: `PersistentLog` no-ops without the
    /// container. What actually carries the numbers is the app's own Documents
    /// directory — reachable from the Mac over Wi-Fi with `devicectl device copy
    /// from`, from the Files app, and from the share sheet on screen.
    private func record(text: String, json: Data?) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            Self.logToPersistentLog(String(line))
        }
        PersistentLog.flush()

        let name = "ane-bench-\(Int(Date().timeIntervalSince1970))"
        let documents = Self.documentsDirectory
        let textURL = documents.appendingPathComponent("\(name).txt")
        try? text.write(to: textURL, atomically: true, encoding: .utf8)
        resultFileURL = textURL

        if let json {
            try? json.write(to: documents.appendingPathComponent("\(name).json"))
            if let container = AppGroup.containerURL {
                try? json.write(to: container.appendingPathComponent("\(name).json"))
                append("wrote results into the App Group container")
            } else {
                append("App Group container unavailable — results are in the app's Documents only")
            }
        }
    }

    /// `PersistentLog`'s typed `LogEvent` API cannot carry a benchmark line, and
    /// adding a case to it would mean changing a shipped framework for a
    /// throwaway. The deprecated free-text entry point is the honest choice;
    /// marking this wrapper deprecated too is what keeps the build warning-free
    /// without hiding that it is the legacy path.
    @available(*, deprecated)
    private static func logToPersistentLog(_ line: String) {
        PersistentLog.log(line)
    }
}
