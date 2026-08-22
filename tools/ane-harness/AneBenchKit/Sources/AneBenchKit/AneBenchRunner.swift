// tools/ane-harness/Sources/AneBenchKit/AneBenchRunner.swift
//
// THROWAWAY — #268 D2. The measurement itself.
//
// Load and run are two separate calls on purpose. Placing a 1.9 GB model on the
// Neural Engine is a one-off cost the OS pays and caches; #268 asks what a
// polish call costs, and a polish call in the shipping product never pays it.
// Splitting them also lets the iOS harness load while the maintainer is still
// looking at the screen and run once he has backgrounded the app, which is the
// only state the question is about.
import Foundation
import CoreML
import AnemllCore
import DictusCore

public actor AneBenchRunner {

    public struct Configuration: Sendable {
        /// Directory holding meta.yaml and the .mlmodelc bundles.
        public let modelDirectory: URL
        /// Upper bound on generated tokens. The shipping polish output for the
        /// `3-long` fixture is ~200 tokens; the cap is a guard, not a target.
        public let maxNewTokens: Int
        public let iterations: Int
        public let fixtureID: String
        /// `.cpuAndNeuralEngine` is the experiment. `.cpuOnly` exists so the
        /// same harness can produce the contrast that proves the ANE was doing
        /// the work — a fast number alone does not name a processor.
        public let computeUnits: MLComputeUnits
        /// Leave Qwen 3's reasoning on. Off by default because a polish call is a
        /// rewrite and no shipping product would pay for the tokens; exposed
        /// because "the converted model barely polishes" and "the converted model
        /// was not allowed to think" are two different explanations and only a
        /// run with this flipped tells them apart.
        public let allowThinking: Bool

        public init(modelDirectory: URL,
                    maxNewTokens: Int = 280,
                    iterations: Int = 3,
                    fixtureID: String = "3-long",
                    computeUnits: MLComputeUnits = .cpuAndNeuralEngine,
                    allowThinking: Bool = false) {
            self.modelDirectory = modelDirectory
            self.maxNewTokens = maxNewTokens
            self.iterations = iterations
            self.fixtureID = fixtureID
            self.computeUnits = computeUnits
            self.allowThinking = allowThinking
        }
    }

    public enum RunError: Error, CustomStringConvertible {
        case metaMissing(URL)
        case notLoaded
        /// The shipping polish prompts are reached through an entry point gated on
        /// iOS/macOS 26. Its own case, because "the OS is too old" and "you called
        /// run() before prepare()" send a reader to different places.
        case unsupportedOSVersion

        public var description: String {
            switch self {
            case .metaMissing(let url): return "meta.yaml not found at \(url.path)"
            case .notLoaded: return "prepare() must succeed before run()"
            case .unsupportedOSVersion:
                return "the shipping polish prompts need iOS 26 / macOS 26 or later"
            }
        }
    }

    private let configuration: Configuration
    private var config: YAMLConfig?
    private var tokenizer: Tokenizer?
    private var inference: InferenceManager?
    private var prompt: PolishPrompt?
    private var promptTokens: [Int] = []
    private var modelLoadMs = 0
    private var modelRevision = "unknown"
    private var computePlans: [ComputePlanSummary] = []
    private var notes: [String] = []

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    // MARK: - Phase 1: load (foreground)

    /// Load the tokenizer and the Core ML bundles, build the prompt, and read
    /// Core ML's compute plan. Everything expensive and everything that is not
    /// the measurement.
    public func prepare(progress: @Sendable @escaping (String) -> Void) async throws {
        let metaURL = configuration.modelDirectory.appendingPathComponent("meta.yaml")
        guard FileManager.default.fileExists(atPath: metaURL.path) else {
            throw RunError.metaMissing(metaURL)
        }

        modelRevision = (try? String(contentsOf: configuration.modelDirectory
            .appendingPathComponent("REVISION.txt"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

        progress("Reading meta.yaml…")
        let config = try YAMLConfig.load(from: metaURL.path)
        self.config = config

        progress("Loading tokenizer…")
        let tokenizer = try await Tokenizer(modelPath: config.tokenizerModel, template: "qwen")
        self.tokenizer = tokenizer

        progress("Building the shipping polish prompt…")
        guard #available(iOS 26.0, macOS 26.0, *) else {
            // The prompts are reached through the Apple FM engine's one entry
            // point, which carries that gate. Nothing here calls Apple's model.
            throw RunError.unsupportedOSVersion
        }
        let prompt = try PolishPrompt.resolved(fixtureID: configuration.fixtureID)
        self.prompt = prompt
        self.promptTokens = Self.tokens(for: prompt,
                                        tokenizer: tokenizer,
                                        allowThinking: configuration.allowThinking)

        progress("Loading Core ML models onto the Neural Engine…")
        let loadStart = Date()
        let loader = ModelLoader()
        // `.cpuAndNeuralEngine` is not a preference here, it is the experiment:
        // it is the same value FluidAudio sets for Parakeet, which is the one
        // path this product already knows runs backgrounded.
        let models = try await loader.loadModel(
            from: config,
            configuration: ModelLoader.Configuration(computeUnits: configuration.computeUnits)
        )
        modelLoadMs = Int(Date().timeIntervalSince(loadStart) * 1000)

        inference = try InferenceManager(
            models: models,
            contextLength: config.contextLength,
            batchSize: config.batchSize,
            splitLMHead: config.splitLMHead,
            v110: config.configVersion == "0.1.1",
            argmaxInModel: config.argmaxInModel,
            slidingWindow: config.slidingWindow,
            updateMaskPrefill: config.updateMaskPrefill,
            prefillDynamicSlice: config.prefillDynamicSlice,
            modelPrefix: config.modelPrefix,
            vocabSize: config.vocabSize,
            lmHeadChunkSizes: config.lmHeadChunkSizes
        )

        progress("Reading the Core ML compute plan…")
        if #available(iOS 17.4, macOS 14.4, *) {
            for path in [config.ffnPath, config.lmheadPath, config.embedPath] {
                if let summary = await ComputePlanProbe.summarize(modelAt: URL(fileURLWithPath: path),
                                                                 computeUnits: configuration.computeUnits) {
                    computePlans.append(summary)
                } else {
                    notes.append("compute plan unavailable for \(URL(fileURLWithPath: path).lastPathComponent)")
                }
            }
        }
        progress("Ready.")
    }

    // MARK: - Phase 2: measure (background)

    public func run(progress: @Sendable @escaping (String) -> Void) async throws -> BenchReport {
        guard let inference, let tokenizer, let prompt, let config else { throw RunError.notLoaded }
        let origin = Date()
        var iterations: [IterationReport] = []

        for index in 1...max(1, configuration.iterations) {
            progress("Iteration \(index)…")
            var samples: [ProcessSample] = []
            samples.append(await ProcessProbe.sample("iteration\(index).start", since: origin))

            var generated: [Int] = []
            let callStart = Date()
            let (tokens, prefillSeconds, stopReason) = try await inference.generateResponse(
                initialTokens: promptTokens,
                temperature: 0,
                maxTokens: configuration.maxNewTokens,
                eosTokens: tokenizer.eosTokenIds,
                tokenizer: tokenizer,
                onToken: { token in generated.append(token) }
            )
            let totalSeconds = Date().timeIntervalSince(callStart)
            samples.append(await ProcessProbe.sample("iteration\(index).done", since: origin))

            // Not clamped. The runtime reports prefill separately and this
            // derives decode by subtraction, so a negative difference would mean
            // the two clocks disagree — a measurement fault. Clamping it to zero
            // would print a plausible decode time for a run that should be thrown
            // away, which is the one thing a harness must never do.
            let prefillMs = Int(prefillSeconds * 1000)
            let decodeMs = Int(totalSeconds * 1000) - prefillMs
            if decodeMs < 0 {
                notes.append("iteration \(index): prefill (\(prefillMs) ms) exceeds the "
                             + "measured call (\(Int(totalSeconds * 1000)) ms) — timings are unreliable")
            }
            iterations.append(IterationReport(
                index: index,
                promptTokens: promptTokens.count,
                generatedTokens: tokens.count,
                prefillMs: prefillMs,
                decodeMs: decodeMs,
                stopReason: stopReason,
                output: tokenizer.detokenize(tokens),
                samples: samples
            ))
            _ = generated
        }

        let capabilities = DeviceCapabilities.current()
        return BenchReport(
            startedAt: origin,
            codeRevision: PersistentLog.codeRevision,
            deviceModel: capabilities.deviceModelIdentifier,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            physicalMemoryGB: capabilities.physicalMemoryGB,
            modelBundle: configuration.modelDirectory.lastPathComponent,
            modelRevision: modelRevision,
            computeUnits: Self.describe(configuration.computeUnits)
                + (configuration.allowThinking ? " +thinking" : ""),
            contextLength: config.contextLength,
            batchSize: config.batchSize,
            fixtureID: "\(prompt.fixtureID) (\(prompt.mode))",
            systemPromptChars: prompt.system.count,
            userTurnChars: prompt.user.count,
            modelLoadMs: modelLoadMs,
            computePlans: computePlans,
            iterations: iterations,
            notes: notes
        )
    }

    private static func describe(_ units: MLComputeUnits) -> String {
        switch units {
        case .cpuOnly: return "cpuOnly"
        case .cpuAndGPU: return "cpuAndGPU"
        case .all: return "all"
        case .cpuAndNeuralEngine: return "cpuAndNeuralEngine"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Prompt tokenisation

    /// System + user through the model's own ChatML template, then the empty
    /// thinking block Qwen 3's template emits for `enable_thinking=false`.
    ///
    /// This is not a detail. The predecessor spike measured a reasoning model
    /// with thinking silently ON and discarded the whole pass when it noticed —
    /// a polish call is a rewrite, not a puzzle, and letting the model reason
    /// reports a latency no shipped product would pay.
    private static func tokens(for prompt: PolishPrompt,
                               tokenizer: Tokenizer,
                               allowThinking: Bool) -> [Int] {
        let templated = tokenizer.applyChatTemplate(
            input: [Tokenizer.ChatMessage.system(prompt.system),
                    Tokenizer.ChatMessage.user(prompt.user)],
            addGenerationPrompt: true
        )
        guard !allowThinking else { return templated }
        return templated + tokenizer.tokenize("<think>\n\n</think>\n\n")
    }
}
