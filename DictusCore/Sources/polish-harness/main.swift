// DictusCore/Sources/polish-harness/main.swift
//
// Off-device polish eval harness. Runs the REAL pipeline (PolishPipeline +
// AppleFoundationModelsPolishEngine) on text fixtures, on a Mac with Apple
// Intelligence. The polish input is text (the `raw` field of a device export),
// so no audio is needed. NOT run by CI — Apple FM is non-deterministic and
// absent from CI runners.
//
// Usage:
//   swift run polish-harness show  <fixtures.json> [--runs N] [--instructions <prompt.txt>]
//   swift run polish-harness eval  <fixtures.json> [--instructions <prompt.txt>]
//   swift run polish-harness ab    <fixtures.json> --a <promptA.txt> --b <promptB.txt>
//
// `--instructions <file>` overrides the system prompt (A/B a candidate without
// recompiling). `ab` runs two prompt files side by side.

import Foundation
import DictusCore
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Arg parsing

func optionValue(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first, ["show", "eval", "ab"].contains(command), args.count >= 2 else {
    print("""
    polish-harness — off-device polish eval (macOS + Apple Intelligence)

      show <fixtures.json> [--runs N] [--instructions <prompt.txt>]
      eval <fixtures.json> [--instructions <prompt.txt>]
      ab   <fixtures.json> --a <promptA.txt> --b <promptB.txt>
    """)
    exit(2)
}

let fixturesPath = args[1]
let runs = Int(optionValue("--runs", in: args) ?? "1") ?? 1
let instructionsFile = optionValue("--instructions", in: args)
let abA = optionValue("--a", in: args)
let abB = optionValue("--b", in: args)

// MARK: - Load fixtures

let fixtures: [Fixture]
do {
    fixtures = try FixtureLoader.load(fixturesPath)
} catch {
    print("error: cannot load fixtures at \(fixturesPath): \(error)")
    exit(1)
}

func loadInstructions(_ path: String?) -> (@Sendable (PolishMode, SupportedLanguage) -> String)? {
    guard let path else { return nil }
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("error: cannot read instructions file \(path)")
        exit(1)
    }
    return { _, _ in text }
}

// MARK: - Run

guard #available(macOS 26.0, *) else {
    print("error: this harness requires macOS 26 with Apple Intelligence.")
    exit(1)
}

#if canImport(FoundationModels)
switch SystemLanguageModel.default.availability {
case .available:
    break
default:
    print("error: Apple Foundation Models not available (\(SystemLanguageModel.default.availability)). Enable Apple Intelligence in System Settings.")
    exit(1)
}
#else
print("error: FoundationModels not importable on this toolchain.")
exit(1)
#endif

@available(macOS 26.0, *)
func makeEngine(_ override: (@Sendable (PolishMode, SupportedLanguage) -> String)?) -> AppleFoundationModelsPolishEngine {
    if let override { return AppleFoundationModelsPolishEngine(instructionsOverride: override) }
    return AppleFoundationModelsPolishEngine()
}

@available(macOS 26.0, *)
struct RunOutcome {
    let final: String
    let engineOutput: String?
    let outcome: PolishMetrics.Outcome
    let engineMs: Int
    let detected: SupportedLanguage?
    let mode: PolishMode?
}

@available(macOS 26.0, *)
func runOnce(_ fx: Fixture, engine: AppleFoundationModelsPolishEngine) async -> RunOutcome {
    let target = fx.language
    let preprocessed = VerbalPunctuationPrepass.apply(fx.raw, language: target)
    // Mirror the coordinator's fallback: non-success returns the deterministic
    // floor (decoded pre-pass), never the literal raw. (#185)
    guard let detected = PolishPipeline.detectLanguage(in: preprocessed) else {
        let fallback = PolishPostpass.decodeFromEngine(preprocessed, language: target)
        return RunOutcome(final: fallback, engineOutput: nil, outcome: .skipped, engineMs: 0, detected: nil, mode: nil)
    }
    let mode = PolishPipeline.mode(sttEngine: fx.speechEngine, detected: detected, target: target)
    let r = await PolishPipeline.transform(preprocessed: preprocessed, engine: engine, target: target, mode: mode)
    let final = PolishPipeline.resolvedOutput(r, preprocessed: preprocessed, target: target)
    return RunOutcome(final: final, engineOutput: r.engineOutput, outcome: r.outcome, engineMs: r.engineMs, detected: detected, mode: mode)
}

@available(macOS 26.0, *)
func runHarness() async {
    switch command {
    case "show":
        let engine = makeEngine(loadInstructions(instructionsFile))
        for fx in fixtures {
            print("\n━━ [\(fx.id)] lang=\(fx.lang) stt=\(fx.sttEngine ?? "PK")")
            print("  raw:      \(fx.raw)")
            for run in 1...max(1, runs) {
                let o = await runOnce(fx, engine: engine)
                let tag = runs > 1 ? " #\(run)" : ""
                let route = "\(o.outcome.rawValue), \(o.engineMs)ms, detected=\(o.detected?.rawValue ?? "-")→\(o.mode?.rawValue ?? "-")"
                print("  polished\(tag): \(o.final)")
                print("            (\(route))")
                // When the guardrail rejects, `final` is the raw fallback — surface
                // what the engine actually produced so repair/guardrail issues are visible.
                if o.outcome != .success, let engineOutput = o.engineOutput {
                    print("  engineOut\(tag): \(engineOutput)")
                }
            }
        }

    case "eval":
        let engine = makeEngine(loadInstructions(instructionsFile))
        var passed = 0, total = 0
        for fx in fixtures {
            let o = await runOnce(fx, engine: engine)
            let checks = fx.expect ?? []
            let failures = checks.compactMap { $0.failure(polished: o.final, raw: fx.raw) }
            total += 1
            if failures.isEmpty {
                passed += 1
                print("✓ [\(fx.id)]  (\(o.outcome.rawValue), \(o.engineMs)ms)")
            } else {
                print("✗ [\(fx.id)]  (\(o.outcome.rawValue), \(o.engineMs)ms)")
                for f in failures { print("    – \(f)") }
                print("    → \(o.final)")
            }
        }
        print("\nSummary: \(passed)/\(total) fixtures passed all checks (LLM is non-deterministic — re-run to gauge variance)")

    case "ab":
        guard let abA, let abB else { print("error: ab requires --a <file> --b <file>"); exit(2) }
        let engineA = makeEngine(loadInstructions(abA))
        let engineB = makeEngine(loadInstructions(abB))
        for fx in fixtures {
            print("\n━━ [\(fx.id)] lang=\(fx.lang)")
            print("  raw: \(fx.raw)")
            let a = await runOnce(fx, engine: engineA)
            let b = await runOnce(fx, engine: engineB)
            print("  A (\(a.engineMs)ms): \(a.final)")
            print("  B (\(b.engineMs)ms): \(b.final)")
        }

    default:
        break
    }
}

await runHarness()
