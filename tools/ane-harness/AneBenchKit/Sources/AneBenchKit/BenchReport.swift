// tools/ane-harness/Sources/AneBenchKit/BenchReport.swift
//
// THROWAWAY — #268 D2. The shape of what comes back off the phone.
import Foundation

/// One memory/thermal/lifecycle reading, taken at a named point in the run.
///
/// `appState` is the reason this struct exists at all. A latency figure from a
/// foregrounded app answers a different question than the one #268 asks, and
/// nothing in the numbers themselves would reveal the difference — so every
/// reading carries the lifecycle state it was taken in, and the report refuses
/// to be read as a background measurement unless they all say `background`.
public struct ProcessSample: Codable, Sendable {
    public let label: String
    /// Seconds since the run started.
    public let atSeconds: Double
    /// `os_proc_available_memory()` in MB — jetsam headroom. 0 off-device.
    public let availableMemoryMB: Int
    /// `phys_footprint` in MB — what jetsam counts against the app.
    public let footprintMB: Int
    public let thermalState: String
    public let appState: String

    public var line: String {
        String(format: "%-22@ t=%6.2fs available=%5dMB footprint=%5dMB thermal=%@ state=%@",
               label as NSString, atSeconds, availableMemoryMB, footprintMB,
               thermalState as NSString, appState as NSString)
    }
}

/// What one prompt costs, split the way the budget is written: prefill and
/// decode are separate numbers because they scale with different things and
/// only one of them is under the product's control.
public struct IterationReport: Codable, Sendable {
    public let index: Int
    public let promptTokens: Int
    public let generatedTokens: Int
    public let prefillMs: Int
    public let decodeMs: Int
    public let stopReason: String
    public let output: String
    public let samples: [ProcessSample]

    public var totalMs: Int { prefillMs + decodeMs }
    public var decodeTokensPerSecond: Double {
        decodeMs > 0 ? Double(generatedTokens) * 1000.0 / Double(decodeMs) : 0
    }
    public var prefillTokensPerSecond: Double {
        prefillMs > 0 ? Double(promptTokens) * 1000.0 / Double(prefillMs) : 0
    }
}

/// Which compute device Core ML says it will run each operation on, counted
/// over one `.mlmodelc`. Read from `MLComputePlan`, not inferred from timings.
public struct ComputePlanSummary: Codable, Sendable {
    public let modelName: String
    public let neuralEngineOps: Int
    public let cpuOps: Int
    public let gpuOps: Int
    public let unknownOps: Int

    public var totalOps: Int { neuralEngineOps + cpuOps + gpuOps + unknownOps }
    public var neuralEngineShare: Double {
        totalOps > 0 ? Double(neuralEngineOps) / Double(totalOps) : 0
    }

    public var line: String {
        String(format: "%@: ANE %d / CPU %d / GPU %d / unknown %d  (%.1f%% ANE)",
               modelName, neuralEngineOps, cpuOps, gpuOps, unknownOps, neuralEngineShare * 100)
    }
}

public struct BenchReport: Codable, Sendable {
    public let startedAt: Date
    public let codeRevision: String
    public let deviceModel: String
    public let systemVersion: String
    public let physicalMemoryGB: Int
    public let modelBundle: String
    /// The `MLComputeUnits` the models were loaded with — the independent
    /// variable of the whole experiment, so it travels with the numbers.
    public let computeUnits: String
    public let contextLength: Int
    public let batchSize: Int
    public let fixtureID: String
    public let systemPromptChars: Int
    public let userTurnChars: Int
    public let modelLoadMs: Int
    public let computePlans: [ComputePlanSummary]
    public let iterations: [IterationReport]
    public let notes: [String]

    /// True only when every sample in every iteration was taken with the app
    /// backgrounded. The whole point of D2.
    public var allIterationsBackgrounded: Bool {
        !iterations.isEmpty && iterations.allSatisfy { iteration in
            !iteration.samples.isEmpty && iteration.samples.allSatisfy { $0.appState == "background" }
        }
    }

    public func rendered() -> String {
        var out: [String] = []
        out.append("ane-bench — #268 D2")
        out.append("rev \(codeRevision) | \(deviceModel) | \(systemVersion) | ramGB=\(physicalMemoryGB)")
        out.append("model \(modelBundle) ctx=\(contextLength) batch=\(batchSize) computeUnits=\(computeUnits)")
        out.append("prompt \(fixtureID) systemChars=\(systemPromptChars) userChars=\(userTurnChars)")
        out.append("modelLoadMs=\(modelLoadMs)")
        for plan in computePlans { out.append("computePlan \(plan.line)") }
        for iteration in iterations {
            out.append(String(format: "iteration %d promptTokens=%d prefillMs=%d (%.0f tok/s) "
                              + "decodeMs=%d generated=%d (%.1f tok/s) totalMs=%d stop=%@",
                              iteration.index, iteration.promptTokens, iteration.prefillMs,
                              iteration.prefillTokensPerSecond, iteration.decodeMs,
                              iteration.generatedTokens, iteration.decodeTokensPerSecond,
                              iteration.totalMs, iteration.stopReason as NSString))
            for sample in iteration.samples { out.append("  \(sample.line)") }
            out.append("  output: \(iteration.output)")
        }
        out.append("allIterationsBackgrounded=\(allIterationsBackgrounded)")
        for note in notes { out.append("note: \(note)") }
        return out.joined(separator: "\n")
    }
}
