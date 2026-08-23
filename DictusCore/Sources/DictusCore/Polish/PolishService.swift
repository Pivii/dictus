// DictusCore/Sources/DictusCore/Polish/PolishService.swift
import Foundation
import NaturalLanguage

/// Orchestrates the polish layer:
/// 1. Honour the global toggle (`SharedKeys.polishEnabled`).
/// 2. Branch on the resolved prompt selection (#239): per-language path for
///    follow/explicit modes, language-agnostic auto path for Auto-detect.
/// 3. Detect the language of the raw STT output via `NLLanguageRecognizer`;
///    skip on gibberish (top hypothesis below `confidenceThreshold`).
/// 4. Choose mode: `.natural` for Whisper or `.natural`/`.repair` for Parakeet
///    depending on detected-vs-target match; `.auto` in Auto-detect mode.
/// 5. Run the engine with cancellation support, apply the guardrail, emit metrics.
///
/// See ADR 0003 for the contract the prompts are written against.
///
/// ### One service per process (#361)
///
/// This used to be `PolishCoordinator`, a singleton in DictusApp. Polish now runs
/// in whichever process is in the foreground when the model has to run: the keyboard
/// extension for a keyboard dictation, DictusApp for one started inside the app
/// (decision 4). Both instantiate one of these.
///
/// That is not only a code-sharing convenience — `availabilityGate` below is
/// per-process by nature, because the rate limit it tracks is. A gate living in the
/// app could say nothing true about the keyboard's budget, and vice versa
/// (decision 11).
@MainActor
public final class PolishService {

    // MARK: - Private state

    /// Apple Foundation Models engine. Created once on iOS 26+ when the SDK is
    /// available, regardless of `SystemLanguageModel.default.availability` at
    /// that exact moment — that flag is *runtime* (Apple Intelligence may finish
    /// downloading or be toggled on by the user after `init()`). The engine
    /// itself is cheap to instantiate; gating is done dynamically in `polish()`
    /// by `PolishAvailability.isAppleFMAvailable` so a single launch can recover
    /// once iOS flips the state to `.available`.
    private let appleFMEngine: PolishEngineProtocol?
    private let passthroughEngine: PolishEngineProtocol = PassthroughPolishEngine()
    private let defaults: UserDefaults
    private let sink: PolishEventSink
    private var inflight: Task<PolishPipeline.Result, Never>?
    /// When the in-flight call started, so a supersede can say how long it had been
    /// running (#361 decision 15). Nil whenever `inflight` is.
    private var inflightStartedAt: Date?

    /// Whether polish is still calling its engine (#315).
    ///
    /// Deliberately in memory and nowhere else. Apple's background rate limit is
    /// only refunded by a fresh process, so "reset on a fresh process" and "do not
    /// persist" are the same instruction, and this property is the whole of the
    /// implementation. Anything that re-armed it — a timer, a foreground
    /// observer, a retry — would be theatre against the measurements on #315.
    private var availabilityGate = PolishAvailabilityGate()

    /// Called on the single call that puts polish into its unavailable state, so the
    /// owning process can say so on whatever surface it has. The app has none today;
    /// the keyboard writes `PolishAvailabilityChannel` and raises its toolbar notice.
    private let onBecameUnavailable: (() -> Void)?

    public init(sink: PolishEventSink, onBecameUnavailable: (() -> Void)? = nil) {
        self.defaults = AppGroup.defaults
        self.sink = sink
        self.onBecameUnavailable = onBecameUnavailable
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.appleFMEngine = AppleFoundationModelsPolishEngine()
        } else {
            self.appleFMEngine = nil
        }
        #else
        self.appleFMEngine = nil
        #endif
    }

    /// Resolve the engine for this call. Re-checked on every `polish()` so a
    /// late availability flip (model finishes downloading, user toggles Apple
    /// Intelligence on) takes effect without an app relaunch.
    private var activeEngine: PolishEngineProtocol {
        if let appleFMEngine, PolishAvailability.isAppleFMAvailable {
            return appleFMEngine
        }
        return passthroughEngine
    }

    // MARK: - Public API

    /// Whether this process has stopped calling its polish engine (#315).
    public var hasGivenUpOnEngine: Bool {
        !availabilityGate.allowsCall(engine: activeEngine.identifier)
    }

    /// Cancel any in-flight polish, without starting another.
    ///
    /// Called when a new recording begins, so a polish from the previous dictation
    /// does not pile up behind it.
    public func cancelInflight() {
        supersedeInflight()
    }

    /// Warm up the Apple FM engine (if present) for the user's current target
    /// language. Apple recommends calling `prewarm()` ≥1s before `respond()`, and
    /// the recording duration is exactly that window. Each call recreates a fresh
    /// session, so the engine's stateless invariant holds (see
    /// `AppleFoundationModelsPolishEngine`).
    ///
    /// No-op when the toggle is off (don't pay to load the model into memory if
    /// no polish will run) or when the engine has nothing to warm.
    public func prewarm() {
        guard defaults.bool(forKey: SharedKeys.polishEnabled) else { return }
        guard let engineToWarm = appleFMEngine else { return }
        // Resolve the prompt selection through the language policy
        // (#226/#239/#332): explicit mode targets the language the user chose,
        // not the keyboard one; Auto mode warms the language-agnostic auto
        // session (the language argument is a placeholder the engine
        // normalizes). Prewarm has no dictation-scoped policy to receive (it
        // fires at app launch and ~1.5s into recording), so it snapshots on
        // its own — and passes no detected language, since there is no
        // transcript yet. A stale warm target is harmless: prewarm is
        // best-effort, and `polish()` resolves the real target from scratch.
        let selection = TranscriptionLanguagePolicy.snapshot()
            .polishPromptSelection(detectedLanguage: nil)
        Task {
            switch selection {
            case .language(let target):
                await engineToWarm.prewarm(mode: .natural, targetLanguage: target)
            case .autoDetected:
                await engineToWarm.prewarm(mode: .auto, targetLanguage: .english)
            }
        }
    }

    /// Polish raw STT output. Returns `raw` unchanged when the toggle is off, when
    /// language detection skips, when the engine throws/cancels, or when the
    /// guardrail rejects the output.
    ///
    /// `languagePolicy` is the per-dictation snapshot captured by
    /// DictationCoordinator at transcription start (#226). It carries the STT
    /// engine, the model identifier (e.g. "openai_whisper-small",
    /// "parakeet-tdt-0.6b-v3" — kept in metrics so the JSON export is
    /// self-describing), and the polish target. Using the snapshot instead of
    /// re-reading App Group state here guarantees polish targets the same
    /// language the STT engine was given, even if the user changed the
    /// keyboard language while transcription was running. Since #361 the snapshot
    /// also crosses the App Group to reach the keyboard, for the same reason.
    ///
    /// `onEngineWillRun` fires at most once, immediately before the engine call,
    /// and only for engines that declare the wait worth announcing (#267). It is
    /// how the caller knows to move the dictation status to `.processing`: every
    /// gate that can skip the model -- the toggle above, the duration gate, the
    /// gibberish gate, a passthrough backend -- has been cleared by the time it
    /// fires, so the state marks a wait that is really happening rather than one
    /// that might.
    public func polish(raw: String,
                       languagePolicy: TranscriptionLanguagePolicy,
                       recordingDuration: TimeInterval,
                       onEngineWillRun: (() -> Void)? = nil) async -> String {
        guard defaults.bool(forKey: SharedKeys.polishEnabled) else {
            return raw
        }

        // `methodStart` anchors the full wall-clock the user actually waits
        // for, detection and the deterministic passes included. Captured here
        // rather than inside each path (#332) so moving detection above the
        // branch does not quietly drop its cost out of `preprocessMs`.
        let methodStart = Date()

        // Detection runs BEFORE the branch (#332). The polish target is
        // resolved from it — an explicit choice aside, the language the STT
        // output actually reads as outranks the keyboard language — so it can
        // no longer happen after the target has been chosen. Detecting once
        // here also stops the two paths from each running their own pass.
        //
        // Detection reads `raw`, not the pre-pass output: the pre-pass is
        // keyed on the target (circular now), and all it does is swap spoken
        // punctuation words for marks, which can only remove language signal.
        // The auto path already detected on `raw` for the same reason.
        let detectedCode = PolishPipeline.detectLanguageCode(in: raw)
        // The per-language path only understands the four tested languages;
        // anything else is `nil` to it and falls through to its skip gate.
        let request = Request(
            raw: raw,
            languagePolicy: languagePolicy,
            recordingDuration: recordingDuration,
            methodStart: methodStart,
            detectedCode: detectedCode,
            detected: detectedCode.flatMap(SupportedLanguage.init(rawValue:))
        )

        // Transcription language decoupling (#226/#239/#332): the prompt
        // selection branches on the resolved mode. Follow/explicit modes run
        // the per-language path (prompts + typography passes tuned for the
        // four tested languages; explicit targets the language the user
        // chose, follow targets what detection found and only falls back to
        // the keyboard). Auto-detect mode — BOTH engines, per the #239
        // amendment — runs the language-agnostic auto path: the output
        // language is unknown (could be zh, it, pt, …), so the engine uses
        // the auto prompt; the verbal-punctuation pre-pass runs keyed on the
        // DETECTED language, and the typography post-pass stays off.
        switch languagePolicy.polishPromptSelection(detectedLanguage: request.detected) {
        case .language(let target):
            return await polishTargeted(request, target: target, onEngineWillRun: onEngineWillRun)
        case .autoDetected:
            return await polishAutoDetected(request, onEngineWillRun: onEngineWillRun)
        }
    }

    /// One dictation's polish input, as both paths need it: the raw text, the
    /// policy snapshot, and the detection the caller ran before branching.
    ///
    /// Grouped rather than passed loose because #332 moved detection above the
    /// branch, and threading five values through two paths made the parameter
    /// lists longer than the linter (rightly) tolerates. Path-specific values —
    /// the resolved target — stay separate arguments.
    private struct Request {
        let raw: String
        let languagePolicy: TranscriptionLanguagePolicy
        let recordingDuration: TimeInterval
        /// Anchors the wall-clock the user waits for. Captured before
        /// detection so its cost lands in `preprocessMs` like everything else.
        let methodStart: Date
        /// Raw `NLLanguage` code, the whole long tail ("it", "zh-Hans", …).
        /// What the auto path gates and pre-processes on.
        let detectedCode: String?
        /// The same detection narrowed to the four languages the per-language
        /// prompts exist for, or `nil` — gibberish, or outside that set.
        let detected: SupportedLanguage?
    }

    // MARK: - Per-language path

    /// The historical polish path: verbal-punctuation pre-pass, duration gate,
    /// gibberish gate, per-language prompt, typography post-pass.
    ///
    /// `target` is the resolved polish language — what the model will be told
    /// to write in — and `request.detected` is what detection read in the raw
    /// text, already run by the caller because the target is resolved from it
    /// (#332). They are separate values because they legitimately differ: an
    /// explicit transcription language outranks detection, and that gap is
    /// exactly what selects `PolishMode.repair` below.
    private func polishTargeted(_ request: Request,
                                target: SupportedLanguage,
                                onEngineWillRun: (() -> Void)?) async -> String {
        let raw = request.raw
        let languagePolicy = request.languagePolicy
        let methodStart = request.methodStart
        let sttEngine = languagePolicy.engine
        let sttModelID = languagePolicy.modelIdentifier
        let resolution = PolishMetrics.LanguageResolution(policy: languagePolicy)

        // Pre-pass: deterministic regex substitution of verbal punctuation
        // commands. Round 3 testing showed Apple FM cannot be coaxed into
        // doing this reliably in French — handling it in code bypasses the
        // model entirely for this concern.
        let preprocessed = VerbalPunctuationPrepass.apply(raw, language: target)

        // Duration gate (#141): on a flash dictation (< engineMinDuration) the
        // user wants instant text and the LLM rarely adds value — so we skip the
        // model entirely. We KEEP the free deterministic passes though (verbal
        // punctuation above + NBSP below, both ~0ms) so typography stays
        // consistent with longer clips. No language detection / guardrail here
        // since the engine never runs.
        if request.recordingDuration < Self.engineMinDuration {
            let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)
            let postStart = Date()
            // No engine ran → no newline markers to decode; this only applies
            // the language typography (French NBSP).
            let finalShort = PolishPostpass.decodeFromEngine(preprocessed, language: target)
            let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
            let m = PolishMetrics(
                engine: activeEngine.identifier,
                mode: nil,
                targetLanguage: target,
                // Detection ran before the target was chosen (#332), so it is
                // in hand even here, where the engine never runs. It used to
                // be recorded as nil because detection happened after this
                // gate; keeping that would throw away a fact the event needs.
                detectedLanguage: request.detectedCode,
                rawCharCount: raw.count,
                polishedCharCount: finalShort.count,
                latencyMs: preprocessMs + postMs,
                outcome: .skippedShort,
                sttEngine: sttEngine.rawValue,
                sttModelID: sttModelID,
                timings: PolishTimings(preprocessMs: preprocessMs, engineMs: 0, postprocessMs: postMs),
                languageResolution: resolution
            )
            await emit(m, raw: raw, polished: finalShort)
            return finalShort
        }

        // Skip on gibberish — preserves trust per ADR 0002 §"skip-on-gibberish rule".
        // Also covers a confident detection outside the four supported
        // languages, which this path has no prompt for.
        guard let detected = request.detected else {
            // Return the deterministic floor, NOT the literal raw: the verbal-
            // punctuation pre-pass already ran (~0ms) and the user expects their
            // spoken "virgule"/"point" turned into marks even when the LLM is
            // skipped. Same value the < engineMinDuration gate returns. (#185)
            let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)
            let postStart = Date()
            let fallback = PolishPostpass.decodeFromEngine(preprocessed, language: target)
            let postMs = Int(Date().timeIntervalSince(postStart) * 1000)
            let m = PolishMetrics(
                engine: activeEngine.identifier,
                mode: nil,
                targetLanguage: target,
                // The raw code, not nil: this exit is reached BOTH when
                // detection was unconfident and when it confidently found a
                // language outside the four this path has prompts for. Those
                // are different events — "we could not read it" versus "you
                // dictated Italian" — and only the code tells them apart. A
                // nil here now means gibberish and nothing else.
                detectedLanguage: request.detectedCode,
                rawCharCount: raw.count,
                polishedCharCount: fallback.count,
                latencyMs: preprocessMs + postMs,
                outcome: .skipped,
                sttEngine: sttEngine.rawValue,
                sttModelID: sttModelID,
                timings: PolishTimings(preprocessMs: preprocessMs, engineMs: 0, postprocessMs: postMs),
                languageResolution: resolution
            )
            await emit(m, raw: raw, polished: nil)
            return fallback
        }

        let mode = PolishPipeline.mode(sttEngine: sttEngine, detected: detected, target: target)

        // Resolve the engine for this call — see `activeEngine` doc-comment.
        let currentEngine = activeEngine

        supersedeInflight()
        announceEngineStage(currentEngine, to: onEngineWillRun)
        // Everything above (pre-pass + detection + mode) is the preprocess cost;
        // the engine-facing transform (encode → engine → decode → guardrail) is
        // delegated to `PolishPipeline` so the eval harness runs identical code.
        let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)

        let task = Task {
            // Read inside the task, not snapshotted above (#315): a polish call
            // that overlaps this one can flip the gate between the two, and a
            // snapshot taken at creation time would send one more request to an
            // engine already known to be refusing.
            await PolishPipeline.transform(
                preprocessed: preprocessed, engine: currentEngine, target: target,
                mode: mode, gate: self.availabilityGate
            )
        }
        trackInflight(task)

        let bundle = await task.value
        clearInflight(task)
        recordAvailability(bundle, engine: currentEngine)
        // True total, methodStart → here. Any gap vs (pre+engine+post) is
        // Swift Task scheduling / actor-hop overhead — itself worth seeing.
        let totalMs = Int(Date().timeIntervalSince(methodStart) * 1000)
        // On any non-success (engine failed, guardrail rejected, cancelled) fall
        // back to the deterministic floor, never the literal raw — see
        // `PolishPipeline.resolvedOutput`. (#185)
        let returned = PolishPipeline.resolvedOutput(
            bundle, preprocessed: preprocessed, target: target, mode: mode
        )

        let m = PolishMetrics(
            engine: currentEngine.identifier,
            mode: mode,
            targetLanguage: target,
            detectedLanguage: detected.rawValue,
            rawCharCount: raw.count,
            polishedCharCount: returned.count,
            latencyMs: totalMs,
            outcome: bundle.outcome,
            sttEngine: sttEngine.rawValue,
            sttModelID: sttModelID,
            timings: PolishTimings(
                preprocessMs: preprocessMs,
                engineMs: bundle.engineMs,
                postprocessMs: bundle.postprocessMs
            ),
            failureReason: bundle.failureReason,
            languageResolution: resolution
        )
        await emit(m, raw: raw, polished: bundle.engineOutput)

        return returned
    }

    // MARK: - Auto-detect path (#239)

    /// Polish for Auto-detect transcription mode, BOTH engines: the input
    /// language is whatever the STT engine detected, so the engine runs with
    /// the language-agnostic auto prompt (`PolishMode.auto`).
    ///
    /// Deterministic passes in auto mode: the verbal-punctuation pre-pass DOES
    /// run, keyed on the DETECTED language (`PolishPipeline.autoPreprocess`) —
    /// device testing showed spoken commands stayed literal without it, and
    /// the regex is the only reliable conversion for French. The per-language
    /// typography POST-pass (French NBSP) stays off: it is keyed on a target
    /// language that does not exist here, and regexes tuned for the four
    /// tested languages would mangle e.g. CJK full-width punctuation. Every
    /// non-success outcome returns the deterministic floor (`preprocessed`,
    /// == raw for languages without rules), never losing the conversion work.
    ///
    /// Metrics convention: `targetLanguage` is session context only (nothing
    /// is targeted in auto mode) — the keyboard language documents the state,
    /// matching the JSON export's settings block. `detectedLanguage` carries
    /// the raw NLLanguage code of the INPUT (e.g. "it", "zh-Hans"), which is
    /// how device tests validate output language == input language. Engine
    /// runs are identified by `mode == .auto` in the debug export.
    private func polishAutoDetected(_ request: Request,
                                    onEngineWillRun: (() -> Void)?) async -> String {
        let raw = request.raw
        let languagePolicy = request.languagePolicy
        let methodStart = request.methodStart
        // Engine-API placeholder in auto mode — never used for typography or
        // guardrails (see PolishPipeline); doubles as the metrics context.
        let contextLanguage = languagePolicy.keyboardLanguage

        // `detectedCode` is detected by the caller, before the duration gate,
        // because the verbal-punctuation pre-pass needs the detected language
        // as its key — and, exactly like the per-language path, flash
        // dictations must still get their spoken commands converted even when
        // the LLM is skipped (#185).
        let preprocessed = PolishPipeline.autoPreprocess(raw, detectedCode: request.detectedCode)

        // Duration gate (#141): on a flash dictation the user wants instant
        // text, so the LLM is skipped — but the deterministic floor is kept.
        if request.recordingDuration < Self.engineMinDuration {
            let detectMs = Int(Date().timeIntervalSince(methodStart) * 1000)
            let m = autoEventMetrics(
                outcome: .skippedShort, raw: raw, finalCount: preprocessed.count,
                languagePolicy: languagePolicy, engineID: activeEngine.identifier,
                detectedLanguage: request.detectedCode, latencyMs: detectMs,
                timings: PolishTimings(preprocessMs: detectMs, engineMs: 0, postprocessMs: 0)
            )
            await emit(m, raw: raw, polished: nil)
            return preprocessed
        }

        // Gibberish gate — same skip-on-gibberish rule as the per-language
        // path (ADR 0002), but on the raw NLLanguage code: auto mode must
        // accept the whole long tail (zh, it, pt, …), not just the four
        // supported languages. No detection → no pre-pass ran → raw is intact.
        guard let detectedCode = request.detectedCode else {
            let detectMs = Int(Date().timeIntervalSince(methodStart) * 1000)
            let m = autoEventMetrics(
                outcome: .skipped, raw: raw, finalCount: raw.count,
                languagePolicy: languagePolicy, engineID: activeEngine.identifier,
                latencyMs: detectMs,
                timings: PolishTimings(preprocessMs: detectMs, engineMs: 0, postprocessMs: 0)
            )
            await emit(m, raw: raw, polished: nil)
            return raw
        }

        let currentEngine = activeEngine
        supersedeInflight()
        announceEngineStage(currentEngine, to: onEngineWillRun)
        // Pre-engine work in auto mode: detection + detected-language pre-pass.
        let preprocessMs = Int(Date().timeIntervalSince(methodStart) * 1000)
        let task = Task {
            // Read inside the task rather than snapshotted — same reason as the
            // per-language path above (#315).
            await PolishPipeline.transform(
                preprocessed: preprocessed, engine: currentEngine, target: contextLanguage,
                mode: .auto, gate: self.availabilityGate
            )
        }
        trackInflight(task)

        let bundle = await task.value
        clearInflight(task)
        recordAvailability(bundle, engine: currentEngine)
        let totalMs = Int(Date().timeIntervalSince(methodStart) * 1000)
        let returned = PolishPipeline.resolvedOutput(
            bundle, preprocessed: preprocessed, target: contextLanguage, mode: .auto
        )
        let m = autoEventMetrics(
            outcome: bundle.outcome, raw: raw, finalCount: returned.count,
            languagePolicy: languagePolicy, engineID: currentEngine.identifier,
            mode: .auto, detectedLanguage: detectedCode, latencyMs: totalMs,
            timings: PolishTimings(
                preprocessMs: preprocessMs,
                engineMs: bundle.engineMs,
                postprocessMs: bundle.postprocessMs
            ),
            failureReason: bundle.failureReason
        )
        await emit(m, raw: raw, polished: bundle.engineOutput)
        return returned
    }

    /// Metrics for one auto-path event. Defaults cover the skip exits (no
    /// mode, no detection, ~0ms); the engine-run exit overrides them.
    ///
    /// `targetLanguage` is recorded as `nil`, because on this path there is no
    /// target: the prompt is language-agnostic and the model writes in the
    /// language the input is already in. It used to be filled with the
    /// keyboard language "for session context", which meant an export showed
    /// `target=de` beside `detected=fr` on a dictation that correctly came out
    /// French — a reader auditing that would conclude the #332 bug was live.
    /// The keyboard language is still on the event, under its own name, in
    /// `languageResolution`.
    private func autoEventMetrics(outcome: PolishMetrics.Outcome,
                                  raw: String,
                                  finalCount: Int,
                                  languagePolicy: TranscriptionLanguagePolicy,
                                  engineID: String,
                                  mode: PolishMode? = nil,
                                  detectedLanguage: String? = nil,
                                  latencyMs: Int = 0,
                                  timings: PolishTimings =
                                      PolishTimings(preprocessMs: 0, engineMs: 0, postprocessMs: 0),
                                  failureReason: PolishFailureReason? = nil
    ) -> PolishMetrics {
        PolishMetrics(
            engine: engineID,
            mode: mode,
            targetLanguage: nil,
            detectedLanguage: detectedLanguage,
            rawCharCount: raw.count,
            polishedCharCount: finalCount,
            latencyMs: latencyMs,
            outcome: outcome,
            sttEngine: languagePolicy.engine.rawValue,
            sttModelID: languagePolicy.modelIdentifier,
            timings: timings,
            failureReason: failureReason,
            languageResolution: PolishMetrics.LanguageResolution(policy: languagePolicy)
        )
    }

    // MARK: - Serialisation (#361 decisions 10 and 15)

    /// Cancel whatever is in flight, and say so when there was something.
    ///
    /// N+1 cancels N and takes its place — no queueing, no bounded wait. The
    /// measurement on #357 Q4 is why: a generation the keyboard dismissed part-way
    /// through resumed and completed forty-four minutes later, so "N+1 waits for N"
    /// can mean forty-four minutes of a user's next dictation blocked behind a
    /// generation `PendingDictation.mayInsert(into:keyboardIsAttached:)` will refuse
    /// anyway. A
    /// bounded wait was the alternative and was rejected for inventing a second
    /// temporal threshold to calibrate when the design already has one.
    ///
    /// The line is written only when a call was actually displaced, so it counts
    /// supersedes rather than polish calls.
    private func supersedeInflight() {
        guard let inflight else { return }
        let ageMs = inflightStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        PersistentLog.log(.polishCallSuperseded(inflightMs: ageMs))
        inflight.cancel()
        self.inflight = nil
        inflightStartedAt = nil
    }

    private func trackInflight(_ task: Task<PolishPipeline.Result, Never>) {
        inflight = task
        inflightStartedAt = Date()
    }

    /// Forget a task that has returned, unless a newer one has already taken the
    /// slot — otherwise a slow call resuming after being superseded would clear the
    /// record of the call that replaced it, and the one after that would find
    /// nothing to cancel.
    private func clearInflight(_ task: Task<PolishPipeline.Result, Never>) {
        guard inflight == task else { return }
        inflight = nil
        inflightStartedAt = nil
    }

    // MARK: - Stage announcement and availability

    /// Tell the caller the LLM stage is starting, if this engine's wait is one
    /// worth announcing (#267). Both polish paths reach the engine by different
    /// routes and each has to make this call; the check lives here so neither can
    /// make it differently.
    ///
    /// The availability gate (#315) is read here for the same reason it is read
    /// inside the transform: while polish is unavailable there is no wait to
    /// announce — the transform returns in about a millisecond without touching
    /// the engine — and a `.processing` stage raised for it would flash a label
    /// and a new animation for a single frame. Both decisions come off the one
    /// gate value, so they cannot drift apart.
    private func announceEngineStage(_ engine: PolishEngineProtocol, to callback: (() -> Void)?) {
        guard availabilityGate.allowsCall(engine: engine.identifier) else { return }
        guard engine.announcesProcessingStage else { return }
        callback?()
    }

    /// Feed one completed transform outcome to the availability gate (#315), and
    /// on the single call that flips it, say so where both the user and a future
    /// capture can see it.
    ///
    /// Both polish paths call this with the result they just got, so the rule
    /// runs once per engine-facing dictation whichever route it took.
    private func recordAvailability(_ bundle: PolishPipeline.Result,
                                    engine: PolishEngineProtocol) {
        let becameUnavailable = availabilityGate.record(
            outcome: bundle.outcome,
            reason: bundle.failureReason,
            engine: engine.identifier
        )
        guard becameUnavailable else { return }
        PersistentLog.log(.polishEngineUnavailable(
            engine: engine.identifier,
            reason: bundle.failureReason?.slug ?? "-",
            consecutiveRefusals: PolishAvailabilityGate.consecutiveRefusalsBeforeUnavailable
        ))
        onBecameUnavailable?()
    }

    /// Log one metrics event and hand it to whichever sink this process owns.
    private func emit(_ m: PolishMetrics, raw: String, polished: String?) async {
        PolishMetrics.log(m)
        // An engine failure also goes to the persistent log (#315), where it can
        // be read against the dictation timeline around it. Keyed on the
        // outcome, not on the reason being present, so no failure can slip
        // through unlogged; "unclassified" would mean the engine returned no
        // reason at all, which no engine does today.
        if m.outcome == .engineFailed {
            PersistentLog.log(.polishEngineFailed(
                reason: m.failureReason?.slug ?? "unclassified",
                engine: m.engine,
                mode: m.mode?.rawValue ?? "-",
                engineMs: m.timings?.engineMs ?? 0
            ))
        }
        await sink.record(PolishDebugEntry(raw: raw, polished: polished, metrics: m))
    }

    /// Recording duration (seconds) below which the LLM polish is skipped (#141).
    /// On flash dictations the user wants instant text and the model rarely adds
    /// value for ~3-6s of latency. Deterministic passes still run. Tunable.
    private static let engineMinDuration: TimeInterval = 2.0
}
