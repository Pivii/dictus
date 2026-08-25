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
//   swift run polish-harness ab    <fixtures.json> [--a <promptA.txt>] [--b <promptB.txt>]
//
// `--instructions <file>` overrides the system prompt (A/B a candidate without
// recompiling). `ab` runs two sides side by side.
//
// `--mode <identifier>` (#393) runs an armed Smart Mode instead of the free polish:
// the mode's prompt, its per-mode user-turn framing, and — the part that cannot be
// inherited — its own acceptance contract. `ab` takes one per side (`--mode-a`,
// `--mode-b`), which is how a mode is compared against free polish rather than
// against another prompt file.
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

      show   <fixtures.json> [--runs N] [--instructions <prompt.txt>] [--framing <framing.txt>] [--mode <id>]
      eval   <fixtures.json> [--instructions <prompt.txt>] [--framing <framing.txt>] [--mode <id>]
      ab     <fixtures.json> [--a <promptA.txt>] [--b <promptB.txt>] [--mode <id>] [--mode-a <id>] [--mode-b <id>]
      prompt <fixtures.json> [--id <fixtureID>] [--out <dir>] [--mode <id>]

    --mode (#393) arms a Smart Mode by catalogue identifier, so its prompt, its
    user-turn framing and its OWN acceptance contract are what run. On `ab`,
    --mode-a / --mode-b arm one side each; a side with no mode is the free polish,
    so `ab --mode-b notes` is the mode against free polish.

    --framing (#79) overrides the USER turn, which is otherwise hardcoded as
    "Polish this text…". `{{INPUT}}` marks where the text goes. Requires
    --instructions, and cannot be combined with --mode.

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
// #79. Overrides the USER turn the way `--instructions` overrides the system
// prompt. See `FramedAppleFMPolishEngine` for why an Email prompt cannot be
// measured underneath a user turn that says "Polish this text".
let framingFile = optionValue("--framing", in: args)
// #393. A Smart Mode by catalogue identifier ("notes", "translate.en"). `ab` takes
// one per side and falls back to `--mode` for both, so a single flag A/Bs two prompt
// candidates on one mode while `--mode-b` alone A/Bs a mode against the free polish.
let modeIdentifier = optionValue("--mode", in: args)
let modeAIdentifier = optionValue("--mode-a", in: args) ?? modeIdentifier
let modeBIdentifier = optionValue("--mode-b", in: args) ?? modeIdentifier

// MARK: - Load fixtures

let fixtures: [Fixture]
do {
    fixtures = try FixtureLoader.load(fixturesPath)
} catch {
    print("error: cannot load fixtures at \(fixturesPath): \(error)")
    exit(1)
}

func loadInstructions(_ path: String?) -> (@Sendable (PolishTask, SupportedLanguage) -> String)? {
    guard let path else { return nil }
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("error: cannot read instructions file \(path)")
        exit(1)
    }
    return { _, _ in text }
}

/// Resolve a Smart Mode by catalogue identifier, or exit naming what this build
/// ships (#393).
///
/// Resolved against `builtIns`, never `all`: `all` stamps the user's pin state,
/// which lives in the App Group and has nothing to say about a measurement. The
/// mode a run exercises must not depend on what a machine happens to have pinned.
func loadSmartMode(_ identifier: String?) -> SmartMode? {
    guard let identifier else { return nil }
    guard let mode = SmartModeCatalogue.builtIns.first(where: { $0.id == identifier }) else {
        print("error: no Smart Mode '\(identifier)'. This build ships: "
              + SmartModeCatalogue.builtIns.map(\.id).joined(separator: ", "))
        exit(2)
    }
    return mode
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

func loadFraming(_ path: String?) -> String? {
    guard let path else { return nil }
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("error: cannot read framing file \(path)")
        exit(1)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

@available(macOS 26.0, *)
func makeEngine(_ override: (@Sendable (PolishTask, SupportedLanguage) -> String)?) -> any PolishEngineProtocol {
    // #79. A user-turn override needs an engine whose user turn is not
    // hardcoded, so it takes the resolved instructions eagerly rather than as
    // a per-call closure. That is only well-defined when the caller also
    // supplied the system prompt: refusing beats silently measuring the
    // shipping prompt under an Email framing.
    if let framing = loadFraming(framingFile) {
        guard engineKind == "apple-fm" else {
            print("error: --framing is only supported with --engine apple-fm")
            exit(2)
        }
        guard let override else {
            print("error: --framing requires --instructions (the framing overrides the "
                  + "user turn; the system prompt must be stated too)")
            exit(2)
        }
        // A Smart Mode's user turn comes off the mode (#79), and this flag replaces
        // it. Combining the two would measure a framing the app has no way to send,
        // under a mode's name. Refusing beats measuring the wrong thing quietly —
        // the same rule the two guards above follow.
        guard modeIdentifier == nil else {
            print("error: --framing cannot be combined with --mode (a mode carries its "
                  + "own user turn; overriding it measures a framing the app cannot send)")
            exit(2)
        }
        return FramedAppleFMPolishEngine(
            instructions: override(.natural, .french),
            framing: framing
        )
    }
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
    /// What would reach the document, or nil when nothing would (#79): a Smart Mode
    /// that did not clear its contract inserts nothing rather than the untransformed
    /// floor. Nil is a result, not a missing value.
    let final: String?
    let engineOutput: String?
    let outcome: PolishMetrics.Outcome
    let engineMs: Int
    /// Raw NLLanguage code of the input ("fr", "it", "zh-Hans", …).
    let detected: String?
    let task: PolishTask?
    /// Set when the engine threw (#315) — the same slug the app exports, so a
    /// failure seen here reads against the field data without a translation.
    let failureReason: PolishFailureReason?

    init(final: String?,
         engineOutput: String?,
         outcome: PolishMetrics.Outcome,
         engineMs: Int,
         detected: String?,
         task: PolishTask?,
         failureReason: PolishFailureReason? = nil) {
        self.final = final
        self.engineOutput = engineOutput
        self.outcome = outcome
        self.engineMs = engineMs
        self.detected = detected
        self.task = task
        self.failureReason = failureReason
    }

    /// `final`, rendered for a log line. The refusal has to read as a refusal in a
    /// committed capture: an empty string there is indistinguishable from a model
    /// that returned nothing.
    var displayText: String { final ?? "<refused — a Smart Mode inserts nothing>" }

    /// The contract this output was judged against, for the route line.
    ///
    /// Printed only for a Smart Mode, and printed at all because #393's second
    /// criterion is precisely that **the mode's own contract is what judges the
    /// output** — free-polish bands would reject Notes for condensing and Translate
    /// for changing language. An outcome alone does not say which contract produced
    /// it; this does, in the raw capture that is the evidence.
    var contractNote: String {
        guard let task, task.isSmart else { return "" }
        let contract = task.contract
        return String(
            format: ", contract=%.2f–%.2f/%@",
            contract.minimumLengthRatio,
            contract.maximumLengthRatio,
            contract.outputLanguage.storedValue
        )
    }
}

/// Outcome counts over a whole run (#393).
///
/// The number the issue asks for is a **rate**, not a pass/fail. "How often does
/// Notes leave the speaker's language" is what decides whether a prompt needs a fix
/// or a mode needs a cut, and it is exactly what a device session cannot produce —
/// the first field evidence on #79 was one drift in six dictations, which is a
/// discovery, not a measurement. Non-successes are also counted per fixture, because
/// a drift concentrated on one input is a different finding from one spread evenly.
struct OutcomeTally {
    private var counts: [String: Int] = [:]
    private var nonSuccess: [String: [String: Int]] = [:]
    private var total = 0

    mutating func record(_ outcome: PolishMetrics.Outcome, fixture: String) {
        total += 1
        counts[outcome.rawValue, default: 0] += 1
        guard outcome != .success else { return }
        nonSuccess[outcome.rawValue, default: [:]][fixture, default: 0] += 1
    }

    var report: String {
        var lines = ["\n── outcomes: \(counts[PolishMetrics.Outcome.success.rawValue] ?? 0)/\(total) success"]
        for (outcome, byFixture) in nonSuccess.sorted(by: { $0.key < $1.key }) {
            let hits = byFixture.values.reduce(0, +)
            let detail = byFixture.sorted { $0.key < $1.key }
                .map { "\($0.key)×\($0.value)" }
                .joined(separator: ", ")
            lines.append("   \(outcome): \(hits)/\(total) — \(detail)")
        }
        return lines.joined(separator: "\n")
    }
}

/// One dictation through the per-language path, mirroring `PolishService.polishTargeted`.
///
/// `mode` is the armed Smart Mode (#393), or nil for the free polish. It is a
/// parameter rather than something read here for the reason it is a parameter in the
/// app: the mode is a property of the dictation, decided before it starts.
@available(macOS 26.0, *)
func runOnce(_ fx: Fixture,
             engine: any PolishEngineProtocol,
             mode: SmartMode? = nil) async -> RunOutcome {
    guard let target = fx.language else {
        return await runOnceAuto(fx, engine: engine, mode: mode)
    }
    let smartTask = mode.map(PolishTask.smart)
    let preprocessed = VerbalPunctuationPrepass.apply(fx.raw, language: target)
    // The raw NLLanguage code, kept for the route line even where the engine never
    // runs, for the reason `PolishService` records it at its own skip exits: "we
    // could not read it" and "you dictated Italian" are different events, and only
    // the code tells them apart.
    let detectedCode = PolishPipeline.detectLanguageCode(in: preprocessed)
    let detected = detectedCode.flatMap(SupportedLanguage.init(rawValue:))
    // Gibberish gate, off `PolishGatePolicy` so the harness skips exactly where the
    // app does. The free polish returns the deterministic floor (decoded pre-pass),
    // never the literal raw (#185). An armed mode does not skip at all: short
    // sentences to translate land here routinely, and a mode's prompt does not depend
    // on detection having succeeded — which is also what lets a fixture in a language
    // outside the four reach the engine (#79).
    if PolishGatePolicy.skipsForGibberish(
        hasDetectedLanguage: detected != nil, task: smartTask ?? .natural
    ) {
        let fallback = PolishPostpass.decodeFromEngine(preprocessed, language: target)
        return RunOutcome(final: fallback, engineOutput: nil, outcome: .skipped, engineMs: 0, detected: detectedCode, task: nil)
    }
    // The armed mode when there is one, otherwise the free-polish variant the STT
    // engine and the detected-vs-target gap select. `detected ?? target` matches the
    // app: past the gate a mode may have no detection, and the variant it falls back
    // to is one its own prompt ignores.
    let job = PolishJob(
        task: smartTask ?? .polish(PolishPipeline.mode(
            sttEngine: fx.speechEngine, detected: detected ?? target, target: target
        )),
        promptLanguage: target,
        languageAgnosticPath: false
    )
    let r = await PolishPipeline.transform(preprocessed: preprocessed, engine: engine, job: job)
    // nil for a Smart Mode on any non-success: it inserts nothing rather than the
    // untransformed floor, which #79 names as the worst outcome available.
    let final = PolishPipeline.resolvedOutput(r, preprocessed: preprocessed, job: job)
    return RunOutcome(final: final, engineOutput: r.engineOutput, outcome: r.outcome, engineMs: r.engineMs, detected: detectedCode, task: job.task, failureReason: r.failureReason)
}

/// Auto-detect path (#239), mirroring `PolishCoordinator.polishAutoDetected`:
/// verbal-punctuation pre-pass keyed on the DETECTED language
/// (`autoPreprocess`), no language typography post-pass, engine runs the
/// language-agnostic auto prompt, non-success falls back to the deterministic
/// floor (the pre-pass output). `target` below is the placeholder the engine
/// API requires — the auto prompt and guardrails ignore it.
///
/// An armed Smart Mode replaces the auto task here exactly as it does on the
/// per-language path, and its non-success falls back to nothing at all (#79).
@available(macOS 26.0, *)
func runOnceAuto(_ fx: Fixture,
                 engine: any PolishEngineProtocol,
                 mode: SmartMode? = nil) async -> RunOutcome {
    let smartTask = mode.map(PolishTask.smart)
    let detectedCode = PolishPipeline.detectLanguageCode(in: fx.raw)
    // Same gate rule as the per-language path, on the raw NLLanguage code: auto mode
    // accepts the whole long tail. No detection means no pre-pass ran, so the raw is
    // intact and is what the free polish returns.
    if PolishGatePolicy.skipsForGibberish(
        hasDetectedLanguage: detectedCode != nil, task: smartTask ?? .auto
    ) {
        return RunOutcome(final: fx.raw, engineOutput: nil, outcome: .skipped, engineMs: 0, detected: nil, task: nil)
    }
    let preprocessed = PolishPipeline.autoPreprocess(fx.raw, detectedCode: detectedCode)
    let job = PolishJob(task: smartTask ?? .auto, promptLanguage: .english, languageAgnosticPath: true)
    let r = await PolishPipeline.transform(preprocessed: preprocessed, engine: engine, job: job)
    let final = PolishPipeline.resolvedOutput(r, preprocessed: preprocessed, job: job)
    return RunOutcome(final: final, engineOutput: r.engineOutput, outcome: r.outcome, engineMs: r.engineMs, detected: detectedCode, task: job.task, failureReason: r.failureReason)
}

/// What `prompt` prints for one fixture: the task the engine would run, the text it
/// would receive, and the language its instructions resolve for.
@available(macOS 26.0, *)
struct PromptResolution {
    let task: PolishTask
    let preprocessed: String
    let language: SupportedLanguage
    /// Raw NLLanguage code of the input, for the header line.
    let detected: String?
}

/// Resolve a fixture the way the pipeline would, or print why it cannot be printed
/// and exit.
@available(macOS 26.0, *)
func promptResolution(_ fx: Fixture, mode: SmartMode?) -> PromptResolution {
    let detectedCode = PolishPipeline.detectLanguageCode(in: fx.raw)
    // A Smart Mode's prompt is written once for every input language and its gates
    // are disabled (#79), so neither the per-language resolution nor the gibberish
    // exit below applies: an auto-path fixture and an undetectable one are both
    // printable. `language` is the placeholder the engine API requires and a mode's
    // instructions ignore.
    if let mode {
        let preprocessed = fx.language.map { VerbalPunctuationPrepass.apply(fx.raw, language: $0) }
            ?? PolishPipeline.autoPreprocess(fx.raw, detectedCode: detectedCode)
        return PromptResolution(
            task: .smart(mode),
            preprocessed: preprocessed,
            language: fx.language ?? .english,
            detected: detectedCode
        )
    }
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
    let polishMode = PolishPipeline.mode(
        sttEngine: fx.speechEngine, detected: detected, target: target
    )
    return PromptResolution(
        task: .polish(polishMode),
        preprocessed: preprocessed,
        language: target,
        detected: detected.rawValue
    )
}

@available(macOS 26.0, *)
func runHarness() async {
    switch command {
    case "show":
        let mode = loadSmartMode(modeIdentifier)
        let engine = makeEngine(loadInstructions(instructionsFile))
        var tally = OutcomeTally()
        for fx in fixtures {
            print("\n━━ [\(fx.id)] lang=\(fx.lang) stt=\(fx.sttEngine ?? "PK")")
            print("  raw:      \(fx.raw)")
            for run in 1...max(1, runs) {
                let o = await runOnce(fx, engine: engine, mode: mode)
                tally.record(o.outcome, fixture: fx.id)
                let tag = runs > 1 ? " #\(run)" : ""
                let why = o.failureReason.map { ", reason=\($0.slug)" } ?? ""
                let route = "\(o.outcome.rawValue), \(o.engineMs)ms, detected=\(o.detected ?? "-")→\(o.task?.identifier ?? "-")\(o.contractNote)\(why)"
                print("  polished\(tag): \(o.displayText)")
                print("            (\(route))")
                // When the guardrail rejects, `final` is the raw fallback — or, for a
                // Smart Mode, nothing at all. Surface what the engine actually
                // produced so guardrail and prompt issues are both visible; for a
                // mode this line IS the failure, since nothing else shows it.
                if o.outcome != .success, let engineOutput = o.engineOutput {
                    print("  engineOut\(tag): \(engineOutput)")
                }
            }
        }
        // The rate, not just the outputs. Printed for a mode run only: it is the
        // number #393 asks for, and the free-polish paths already have their own
        // evidence in `eval`.
        if mode != nil { print(tally.report) }

    case "eval":
        let mode = loadSmartMode(modeIdentifier)
        let engine = makeEngine(loadInstructions(instructionsFile))
        var passed = 0, total = 0
        for fx in fixtures {
            let o = await runOnce(fx, engine: engine, mode: mode)
            let checks = fx.expect ?? []
            // A mode that failed closed has no output to check, and that is a
            // failure of the fixture rather than a reason to skip it: the mode's own
            // contract refused what the engine produced, which is precisely what
            // `eval` is being asked about.
            let failures = o.final.map { final in
                checks.compactMap { $0.failure(polished: final, raw: fx.raw) }
            } ?? ["the mode inserted nothing (\(o.outcome.rawValue))"]
            total += 1
            if failures.isEmpty {
                passed += 1
                print("✓ [\(fx.id)]  (\(o.outcome.rawValue), \(o.engineMs)ms)")
            } else {
                print("✗ [\(fx.id)]  (\(o.outcome.rawValue), \(o.engineMs)ms)")
                for f in failures { print("    – \(f)") }
                print("    → \(o.displayText)")
                if o.final == nil, let engineOutput = o.engineOutput {
                    print("    engineOut: \(engineOutput)")
                }
            }
        }
        print("\nSummary: \(passed)/\(total) fixtures passed all checks (LLM is non-deterministic — re-run to gauge variance)")

    // Two sides on the same fixtures. A side is a prompt file, a Smart Mode, or
    // both — because #393's central comparison, a mode against the free polish,
    // differs by TASK rather than by prompt file: `ab --mode-b notes` puts the
    // shipping polish prompt on the left and the shipping Notes prompt, framing and
    // contract on the right. `--a`/`--b` are therefore optional, and a side without
    // one runs the prompt that side's task ships with.
    case "ab":
        guard abA != abB || modeAIdentifier != modeBIdentifier else {
            print("error: ab needs two different sides — give --a/--b, --mode-a/--mode-b, or both")
            exit(2)
        }
        let modeA = loadSmartMode(modeAIdentifier)
        let modeB = loadSmartMode(modeBIdentifier)
        let engineA = makeEngine(loadInstructions(abA))
        let engineB = makeEngine(loadInstructions(abB))
        // The committed capture is the evidence, so each side names what it ran.
        let labelA = modeA.map { "smart.\($0.id)" } ?? "polish"
        let labelB = modeB.map { "smart.\($0.id)" } ?? "polish"
        for fx in fixtures {
            print("\n━━ [\(fx.id)] lang=\(fx.lang)")
            print("  raw: \(fx.raw)")
            let a = await runOnce(fx, engine: engineA, mode: modeA)
            let b = await runOnce(fx, engine: engineB, mode: modeB)
            print("  A [\(labelA)] (\(a.engineMs)ms): \(a.displayText)")
            print("  B [\(labelB)] (\(b.engineMs)ms): \(b.displayText)")
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
        let promptMode = loadSmartMode(modeIdentifier)
        for fx in selected {
            let resolved = promptResolution(fx, mode: promptMode)
            let task = resolved.task
            let system = AppleFoundationModelsPolishEngine.instructions(
                for: task, language: resolved.language
            )
            let user = task.userTurn(raw: resolved.preprocessed)
            print("━━ [\(fx.id)] lang=\(fx.lang) stt=\(fx.sttEngine ?? "PK") "
                  + "detected=\(resolved.detected ?? "-") mode=\(task.identifier) "
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
