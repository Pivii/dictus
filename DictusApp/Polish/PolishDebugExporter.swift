// DictusApp/Polish/PolishDebugExporter.swift
import Foundation
import UIKit
import DictusCore

/// Wire format for Polish debug exports. Stable schema — when iterating on the
/// Light/Repair prompts, this is what gets shared from the device for analysis.
/// Pretty-printed JSON with sorted keys keeps diffs readable and ingestion robust.
///
/// Schema rationale:
/// - `raw` and `polished` are split fields (not a single diff string) so the
///   reader can compute the diff themselves with any tool.
/// - `outcomes` is an aggregate over `events` for at-a-glance triage; redundant
///   with iterating events but cheap to emit.
/// - `device` and `settings` snapshots make each export self-describing — no
///   need to ask the user which model was active or which language was selected.
struct PolishDebugExport: Codable {
    let exportedAt: String
    let device: DeviceInfo
    let settings: SettingsInfo
    let outcomes: [String: Int]
    let events: [Event]

    struct DeviceInfo: Codable {
        /// Hardware identifier from `uname()` — e.g. "iPhone16,2" for iPhone 15 Pro Max.
        let hardware: String
        /// `UIDevice.current.model` — coarse "iPhone" / "iPad".
        let modelClass: String
        let systemName: String
        let systemVersion: String
        let appVersion: String
        let buildNumber: String
    }

    struct SettingsInfo: Codable {
        let polishEnabled: Bool
        let targetLanguage: String
        let activeModelID: String?
        let activeModelEngine: String?
        let appleFMAvailable: Bool
        /// Specific reason the model is or isn't available — useful for
        /// triage when `appleFMAvailable` is false (e.g. user has Siri in
        /// English but iPhone in French → "appleIntelligenceNotEnabled").
        let appleFMState: String
    }

    struct Event: Codable {
        let id: String
        let timestamp: String
        let engine: String
        let mode: String?
        let targetLanguage: String
        let detectedLanguage: String?
        let outcome: String
        let latencyMs: Int
        /// Latency breakdown — `latencyMs` ≈ preprocess + engine + postprocess.
        /// `engineMs` is the pure LLM cost; the other two are our regex passes.
        let preprocessMs: Int?
        let engineMs: Int?
        let postprocessMs: Int?
        let rawCharCount: Int
        let polishedCharCount: Int
        let raw: String
        let polished: String?
        let sttEngine: String?
        let sttModelID: String?
    }
}

@MainActor
enum PolishDebugExporter {

    /// Build the export payload from the current ring state.
    static func makeExport(entries: [PolishDebugEntry]) -> PolishDebugExport {
        let formatter = ISO8601DateFormatter()
        let info = Bundle.main.infoDictionary ?? [:]
        let device = PolishDebugExport.DeviceInfo(
            hardware: Self.hardwareIdentifier(),
            modelClass: UIDevice.current.model,
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            buildNumber: info["CFBundleVersion"] as? String ?? "?"
        )

        let defaults = AppGroup.defaults
        let activeModelID = defaults.string(forKey: SharedKeys.activeModel)
        let activeEngine = activeModelID.flatMap { ModelInfo.forIdentifier($0)?.engine.rawValue }
        let settings = PolishDebugExport.SettingsInfo(
            polishEnabled: defaults.bool(forKey: SharedKeys.polishEnabled),
            targetLanguage: SupportedLanguage.active.rawValue,
            activeModelID: activeModelID,
            activeModelEngine: activeEngine,
            appleFMAvailable: PolishAvailability.isAppleFMAvailable,
            appleFMState: String(describing: PolishAvailability.state)
        )

        var outcomes: [String: Int] = [
            "success": 0, "rejectedGuardrail": 0, "skipped": 0,
            "skippedShort": 0, "cancelled": 0, "engineFailed": 0
        ]
        for e in entries {
            outcomes[e.metrics.outcome.rawValue, default: 0] += 1
        }

        let events = entries.map { entry in
            PolishDebugExport.Event(
                id: entry.id.uuidString,
                timestamp: formatter.string(from: entry.timestamp),
                engine: entry.metrics.engine,
                mode: entry.metrics.mode?.rawValue,
                targetLanguage: entry.metrics.targetLanguage.rawValue,
                detectedLanguage: entry.metrics.detectedLanguage,
                outcome: entry.metrics.outcome.rawValue,
                latencyMs: entry.metrics.latencyMs,
                preprocessMs: entry.metrics.timings?.preprocessMs,
                engineMs: entry.metrics.timings?.engineMs,
                postprocessMs: entry.metrics.timings?.postprocessMs,
                rawCharCount: entry.metrics.rawCharCount,
                polishedCharCount: entry.metrics.polishedCharCount,
                raw: entry.raw,
                polished: entry.polished,
                sttEngine: entry.metrics.sttEngine,
                sttModelID: entry.metrics.sttModelID
            )
        }

        return PolishDebugExport(
            exportedAt: formatter.string(from: Date()),
            device: device,
            settings: settings,
            outcomes: outcomes,
            events: events
        )
    }

    /// Encode the export and drop it into a temp file. Returns the URL for
    /// passing to `UIActivityViewController`. Pass the full 7-day window from
    /// `PolishCoordinator.metricsAllEntries()` to ship every event Pierre needs.
    static func writeToTempFile(entries: [PolishDebugEntry]) throws -> URL {
        let export = makeExport(entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(export)
        let filename = "dictus-polish-debug-\(Self.fileTimestamp()).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fileTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    /// Reads the hardware identifier via `uname()` — gives precise device codes
    /// like "iPhone16,2" so log analysis can tie behavior to a specific SoC.
    private static func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { acc, child in
            if let value = child.value as? Int8, value != 0 {
                acc.append(Character(UnicodeScalar(UInt8(value))))
            }
        }
    }
}
