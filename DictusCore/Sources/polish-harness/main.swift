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
//
// SPIKE ADDITION (#268, throwaway): `--engine local --model <name> [--base-url <url>]`
// on `show` and `eval` runs the same pipeline against an OpenAI-compatible server
// on localhost instead of Apple FM, so a candidate open-weights model can be
// scored on the shipping fixtures. `--engine apple-fm` is the default and the
// baseline. See `LocalHTTPPolishEngine.swift` for what that measurement is and is
// not worth.

import Foundation
import DictusCore
#if canImport(FoundationModels)
import FoundationModels
#endif

// Everything below is macOS-only. The guard is not about Apple Intelligence —
// that is checked at runtime further down — it is about the entry point. The
// `DictusCore-Package` scheme builds every target in the package, so pointing it
// at an iOS destination compiles this harness too, and its `@available(macOS
// 26.0, *)` uses are errors there. An executable still needs a `main` on every
// platform it is built for, hence the `#else` stub rather than an empty file. (#301)
#if os(macOS)

// MARK: - Arg parsing

func optionValue(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first, ["show", "eval", "ab", "prompt"].contains(command), args.count >= 2 else {
    print("""
    polish-harness — off-device polish eval (macOS + Apple Intelligence)

      show   <fixtures.json> [--runs N] [--instructions <prompt.txt>]
      eval   <fixtures.json> [--instructions <prompt.txt>]
      ab     <fixtures.json> --a <promptA.txt> --b <promptB.txt>
      prompt <fixtures.json> [--id <fixtureID>] [--out <dir>]

    show/eval also accept (#268 spike, throwaway):
      --engine apple-fm | local   (default apple-fm)
      --model <name>              required with --engine local
      --base-url <url>            default http://127.0.0.1:11434
    """)
    exit(2)
}

let fixturesPath = args[1]
let runs = Int(optionValue("--runs", in: args) ?? "1") ?? 1
let instructionsFile = optionValue("--instructions", in: args)
let abA = optionValue("--a", in: args)
let abB = optionValue("--b", in: args)
// #268 spike, throwaway.
let engineKind = optionValue("--engine", in: args) ?? "apple-fm"
let localModel = optionValue("--model", in: args)
let localBaseURL = optionValue("--base-url", in: args) ?? "http://127.0.0.1:11434"
// #268 D2, throwaway. `prompt` only.
let promptFixtureID = optionValue("--id", in: args)
let promptOutputDir = optionValue("--out", in: args)

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

// Apple Intelligence is required only by the apple-fm engine. The #268 spike runs
// candidate models through a local server on machines where the check would be
// beside the point, so it is scoped to the engine that needs it rather than to
// the process.
#if canImport(FoundationModels)
// `prompt` never runs a model — it prints the bytes one would be sent — so it is
// usable on a machine with Apple Intelligence off, which is the point of it.
if command != "prompt", engineKind == "apple-fm" {
    switch SystemLanguageModel.default.availability {
    case .available:
        break
    default:
        print("error: Apple Foundation Models not available (\(SystemLanguageModel.default.availability)). Enable Apple Intelligence in System Settings.")
        exit(1)
    }
}
#else
print("error: FoundationModels not importable on this toolchain.")
exit(1)
#endif

@available(macOS 26.0, *)
func makeEngine(_ override: (@Sendable (PolishMode, SupportedLanguage) -> String)?) -> any PolishEngineProtocol {
    // #268 spike, throwaway. `--instructions` has no meaning for the local engine:
    // it is there to A/B prompts on one model, and the spike A/Bs models on one
    // prompt. Refusing the combination beats silently ignoring the flag.
    if engineKind != "apple-fm" {
        guard engineKind == "local" else {
            print("error: unknown --engine \(engineKind) (expected 'apple-fm' or 'local')")
            exit(2)
        }
        guard let localModel else {
            print("error: --engine local requires --model <name>")
            exit(2)
        }
        if override != nil {
            print("error: --instructions is not supported with --engine local")
            exit(2)
        }
        return LocalHTTPPolishEngine(baseURL: localBaseURL, model: localModel)
    }
    if let override { return AppleFoundationModelsPolishEngine(instructionsOverride: override) }
    return AppleFoundationModelsPolishEngine()
}

@available(macOS 26.0, *)
struct RunOutcome {
    let final: String
    let engineOutput: String?
    let outcome: PolishMetrics.Outcome
    let engineMs: Int
    /// Raw NLLanguage code of the input ("fr", "it", "zh-Hans", …).
    let detected: String?
    let mode: PolishMode?
    /// Set when the engine threw (#315) — the same slug the app exports, so a
    /// failure seen here reads against the field data without a translation.
    let failureReason: PolishFailureReason?

    init(final: String,
         engineOutput: String?,
         outcome: PolishMetrics.Outcome,
         engineMs: Int,
         detected: String?,
         mode: PolishMode?,
         failureReason: PolishFailureReason? = nil) {
        self.final = final
        self.engineOutput = engineOutput
        self.outcome = outcome
        self.engineMs = engineMs
        self.detected = detected
        self.mode = mode
        self.failureReason = failureReason
    }
}

@available(macOS 26.0, *)
func runOnce(_ fx: Fixture, engine: any PolishEngineProtocol) async -> RunOutcome {
    guard let target = fx.language else {
        return await runOnceAuto(fx, engine: engine)
    }
    let preprocessed = VerbalPunctuationPrepass.apply(fx.raw, language: target)
    // Mirror the coordinator's fallback: non-success returns the deterministic
    // floor (decoded pre-pass), never the literal raw. (#185)
    guard let detected = PolishPipeline.detectLanguage(in: preprocessed) else {
        let fallback = PolishPostpass.decodeFromEngine(preprocessed, language: target)
        return RunOutcome(final: fallback, engineOutput: nil, outcome: .skipped, engineMs: 0, detected: nil, mode: nil)
    }
    let mode = PolishPipeline.mode(sttEngine: fx.speechEngine, detected: detected, target: target)
    let r = await PolishPipeline.transform(preprocessed: preprocessed, engine: engine, target: target, mode: mode)
    let final = PolishPipeline.resolvedOutput(r, preprocessed: preprocessed, target: target, mode: mode)
    return RunOutcome(final: final, engineOutput: r.engineOutput, outcome: r.outcome, engineMs: r.engineMs, detected: detected.rawValue, mode: mode, failureReason: r.failureReason)
}

/// Auto-detect path (#239), mirroring `PolishCoordinator.polishAutoDetected`:
/// verbal-punctuation pre-pass keyed on the DETECTED language
/// (`autoPreprocess`), no language typography post-pass, engine runs the
/// language-agnostic auto prompt, non-success falls back to the deterministic
/// floor (the pre-pass output). `target` below is the placeholder the engine
/// API requires — the auto prompt and guardrails ignore it.
@available(macOS 26.0, *)
func runOnceAuto(_ fx: Fixture, engine: any PolishEngineProtocol) async -> RunOutcome {
    guard let detectedCode = PolishPipeline.detectLanguageCode(in: fx.raw) else {
        return RunOutcome(final: fx.raw, engineOutput: nil, outcome: .skipped, engineMs: 0, detected: nil, mode: nil)
    }
    let preprocessed = PolishPipeline.autoPreprocess(fx.raw, detectedCode: detectedCode)
    let r = await PolishPipeline.transform(preprocessed: preprocessed, engine: engine, target: .english, mode: .auto)
    let final = PolishPipeline.resolvedOutput(r, preprocessed: preprocessed, target: .english, mode: .auto)
    return RunOutcome(final: final, engineOutput: r.engineOutput, outcome: r.outcome, engineMs: r.engineMs, detected: detectedCode, mode: .auto, failureReason: r.failureReason)
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
                let why = o.failureReason.map { ", reason=\($0.slug)" } ?? ""
                let route = "\(o.outcome.rawValue), \(o.engineMs)ms, detected=\(o.detected ?? "-")→\(o.mode?.rawValue ?? "-")\(why)"
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

    // #268 D2, throwaway. Prints the exact two strings the polish engine sends —
    // the resolved system instructions and the user turn — for a fixture, so the
    // ANE measurement runs on the shipping prompt rather than on a paraphrase of
    // it. The user turn carries the PRE-PASSED text, because that is what the
    // engine receives: `runOnce` applies `VerbalPunctuationPrepass` first, and the
    // mode is resolved the same way rather than assumed to be `.natural` — a
    // Parakeet fixture whose detected language differs from its target resolves to
    // `.repair`, and printing the Natural instructions for it would be printing a
    // prompt the engine would never send.
    case "prompt":
        let selected = promptFixtureID.map { id in fixtures.filter { $0.id == id } } ?? fixtures
        if selected.isEmpty {
            print("error: no fixture with id \(promptFixtureID ?? "-") in \(fixturesPath)")
            exit(1)
        }
        for fx in selected {
            guard let target = fx.language else {
                print("error: [\(fx.id)] routes through auto mode, which has no per-language prompt")
                exit(1)
            }
            let preprocessed = VerbalPunctuationPrepass.apply(fx.raw, language: target)
            guard let detected = PolishPipeline.detectLanguage(in: preprocessed) else {
                print("error: [\(fx.id)] language detection returned nil — the pipeline "
                      + "would skip the engine entirely, so there is no prompt to print")
                exit(1)
            }
            let mode = PolishPipeline.mode(sttEngine: fx.speechEngine, detected: detected, target: target)
            let system = AppleFoundationModelsPolishEngine.instructions(for: mode, language: target)
            let user = LocalHTTPPolishEngine.userTurn(raw: preprocessed)
            print("━━ [\(fx.id)] lang=\(fx.lang) stt=\(fx.sttEngine ?? "PK") "
                  + "detected=\(detected.rawValue) mode=\(mode.rawValue) "
                  + "systemChars=\(system.count) userChars=\(user.count)")
            if let dir = promptOutputDir {
                let base = URL(fileURLWithPath: dir).appendingPathComponent(fx.id)
                do {
                    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                    try system.write(to: base.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)
                    try user.write(to: base.appendingPathComponent("user.txt"), atomically: true, encoding: .utf8)
                } catch {
                    print("error: cannot write to \(base.path): \(error)")
                    exit(1)
                }
                print("  wrote \(base.path)/{system,user}.txt")
            } else {
                print("──── system ────")
                print(system)
                print("──── user ────")
                print(user)
            }
        }

    default:
        break
    }
}

await runHarness()

#else

print("error: polish-harness runs on macOS only (it drives Apple Foundation Models on a Mac).")
exit(1)

#endif
