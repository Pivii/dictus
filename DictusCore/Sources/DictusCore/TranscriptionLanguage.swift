// DictusCore/Sources/DictusCore/TranscriptionLanguage.swift
// Transcription (STT) language mode, decoupled from the keyboard language (issue #226).
import Foundation

/// The user's transcription language choice, stored in
/// `SharedKeys.transcriptionLanguage`.
///
/// WHY a separate type instead of new `SupportedLanguage` cases:
/// `SupportedLanguage` couples a language to keyboard concerns (layout,
/// key labels, autocorrect dictionaries). Transcription languages are a
/// *superset* of that — Whisper can transcribe dozens of languages that have
/// no Dictus keyboard layout (Chinese, Italian, Portuguese, …). Adding cases
/// to `SupportedLanguage` would force a `defaultLayout`/`spaceName`/profile
/// for every such language and drag the keyboard into a pure STT feature.
/// Instead, this enum models the three *modes* the STT pipeline understands,
/// and only the explicit mode references the four tested keyboard languages.
///
/// WHY string-encoded modes instead of a raw-representable enum:
/// The stored value mixes two namespaces — mode markers ("follow"/"auto") and
/// language codes ("fr"/"en"/…). Custom parsing keeps the App Group encoding
/// explicit and lets unknown values degrade safely to `.followKeyboard`,
/// which is the exact pre-#226 behavior (zero-migration upgrades).
public enum TranscriptionLanguageMode: Equatable, Sendable {
    /// STT uses the current keyboard language (`SharedKeys.language`).
    /// Default — preserves the historical coupled behavior exactly.
    case followKeyboard
    /// Whisper language auto-detection (no language token forced).
    /// Unlocks the Whisper long tail (zh, it, pt, …) without any keyboard work.
    /// Parakeet already auto-detects natively, so this is a no-op change for it.
    case autoDetect
    /// A fixed STT language, independent of the keyboard language.
    /// Limited to the four tested languages by product decision (#226):
    /// untested languages are reachable through `.autoDetect` only.
    case explicit(SupportedLanguage)

    // MARK: - App Group encoding

    /// Stored marker for `.followKeyboard`.
    public static let followStoredValue = "follow"
    /// Stored marker for `.autoDetect`.
    public static let autoStoredValue = "auto"

    /// Parse the App Group stored value. `nil` (key never written) and any
    /// unrecognized string resolve to `.followKeyboard` so existing installs
    /// upgrade with zero behavior change.
    public init(storedValue: String?) {
        switch storedValue {
        case Self.autoStoredValue:
            self = .autoDetect
        case .some(let raw):
            if let language = SupportedLanguage(rawValue: raw) {
                self = .explicit(language)
            } else {
                // Covers "follow" and any unknown/corrupted value.
                self = .followKeyboard
            }
        case .none:
            self = .followKeyboard
        }
    }

    /// Value to persist in `SharedKeys.transcriptionLanguage`.
    public var storedValue: String {
        switch self {
        case .followKeyboard: return Self.followStoredValue
        case .autoDetect: return Self.autoStoredValue
        case .explicit(let language): return language.rawValue
        }
    }

    /// Self-describing form for telemetry (#332). NOT `storedValue`: a stored
    /// "fr" says which language without saying that the user *chose* it, and
    /// telling an explicit choice from a coincidence is the entire question a
    /// polish debug export has to answer.
    public var telemetryDescription: String {
        switch self {
        case .followKeyboard: return "followKeyboard"
        case .autoDetect: return "autoDetect"
        case .explicit(let language): return "explicit(\(language.rawValue))"
        }
    }

    // MARK: - Resolution

    /// Reads the active mode from the App Group. Missing key = `.followKeyboard`.
    public static var active: TranscriptionLanguageMode {
        TranscriptionLanguageMode(
            storedValue: AppGroup.defaults.string(forKey: SharedKeys.transcriptionLanguage)
        )
    }

    /// Resolve the language code to hand to the STT engine.
    ///
    /// - Parameter keyboardLanguageCode: the current `SharedKeys.language`
    ///   value, injected by the caller so this stays a pure function (testable
    ///   without App Group access).
    /// - Returns: a language code for the engine, or `nil` for `.autoDetect` —
    ///   WhisperKit's `DecodingOptions.language` is optional and `nil` enables
    ///   Whisper's built-in language detection.
    public func resolvedLanguageCode(keyboardLanguageCode: String) -> String? {
        switch self {
        case .followKeyboard: return keyboardLanguageCode
        case .autoDetect: return nil
        case .explicit(let language): return language.rawValue
        }
    }

}

/// Polish-stage prompt selection, resolved per dictation from the language
/// policy (#239).
///
/// WHY an enum instead of an optional `SupportedLanguage`:
/// Before #239, `nil` meant "bypass polish entirely" (the #226 stopgap). Now
/// auto mode DOES polish — with a dedicated language-agnostic prompt — so the
/// two meanings ("no language known" vs "don't polish") would collide in an
/// optional. The enum makes the branch explicit at every call site.
public enum PolishPromptSelection: Equatable, Sendable {
    /// Polish with the per-language prompt catalog (fr/en/es/de) and the
    /// language-specific typography pre/post passes.
    case language(SupportedLanguage)
    /// Polish with the language-agnostic auto-detect prompt (#239): the input
    /// language is whatever the STT engine detected, the prompt polishes in
    /// that same language and never translates. The verbal-punctuation
    /// pre-pass runs keyed on the DETECTED language
    /// (`PolishPipeline.autoPreprocess`); the typography POST-pass stays OFF —
    /// it is tuned per language and would mangle e.g. CJK full-width
    /// punctuation.
    case autoDetected
}

/// One immutable language-policy snapshot per dictation.
///
/// WHY a snapshot instead of reading `TranscriptionLanguageMode.active` /
/// `SupportedLanguage.active` at each pipeline stage (#226 review follow-up):
/// Transcription is async and takes seconds. If polish and finalization re-read
/// App Group state after STT completes, a keyboard-toolbar language change (or
/// a Settings change) mid-dictation could transcribe with one language and
/// polish/finalize with another. Capturing mode, keyboard language, and engine
/// once — at transcription start — makes the whole pipeline self-consistent.
///
/// WHY the engine is part of the policy:
/// The "Transcription language" setting is Whisper-only-effective. Parakeet
/// ignores the language parameter and auto-detects natively, so with Parakeet
/// active EVERY mode must behave exactly like the historical follow behavior
/// (polish toward the keyboard language, normal separators) — otherwise
/// selecting Auto-detect would silently degrade Parakeet flows that the
/// setting cannot influence in the first place.
///
/// WHY it is `Codable` since #361: polish moved into the keyboard extension, so the
/// snapshot has to cross the App Group with the raw text it describes. Re-reading
/// the mode on the other side would reintroduce the exact bug the snapshot exists
/// to prevent, and reintroduce it in the worst place — the keyboard toolbar is
/// where the language change comes from.
public struct TranscriptionLanguagePolicy: Equatable, Sendable, Codable {
    /// The user's transcription language mode at snapshot time.
    public let mode: TranscriptionLanguageMode
    /// The keyboard language at snapshot time.
    public let keyboardLanguage: SupportedLanguage
    /// The active STT engine at snapshot time.
    public let engine: SpeechEngine
    /// The active model identifier at snapshot time (metrics metadata).
    /// Captured here so polish metrics describe the model that actually
    /// transcribed, even if the user switches models mid-dictation.
    public let modelIdentifier: String

    public init(mode: TranscriptionLanguageMode,
                keyboardLanguage: SupportedLanguage,
                engine: SpeechEngine,
                modelIdentifier: String) {
        self.mode = mode
        self.keyboardLanguage = keyboardLanguage
        self.engine = engine
        self.modelIdentifier = modelIdentifier
    }

    // MARK: - App Group transport (#361)

    private enum CodingKeys: String, CodingKey {
        case mode, keyboardLanguage, engine, modelIdentifier
    }

    /// Encoded by hand rather than synthesised, because `mode` mixes two namespaces
    /// (the markers "follow"/"auto" and a language code) and already has one
    /// canonical spelling — `storedValue`, the same string the App Group holds for
    /// the user's setting. Reusing it means the transport and the setting cannot
    /// disagree about what "auto" is, and an unrecognised value degrades to
    /// `.followKeyboard` on the far side exactly as it does on this one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = TranscriptionLanguageMode(
            storedValue: try container.decode(String.self, forKey: .mode)
        )
        // These two throw rather than falling back, unlike `mode` above. The mode
        // has a documented degradation (an unknown value IS `.followKeyboard`,
        // which is how #226 shipped without a migration); a language and an engine
        // do not. Both are written from the enums themselves, so an unrecognised
        // value means the record is corrupt — and guessing a language here is
        // guessing what to translate the user's speech into.
        self.keyboardLanguage = try Self.decode(
            SupportedLanguage.self, from: container, forKey: .keyboardLanguage
        )
        self.engine = try Self.decode(SpeechEngine.self, from: container, forKey: .engine)
        self.modelIdentifier = try container.decode(String.self, forKey: .modelIdentifier)
    }

    /// Decode a string-raw enum, naming the key that failed instead of reporting a
    /// bare type mismatch.
    private static func decode<T: RawRepresentable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> T where T.RawValue == String {
        let raw = try container.decode(String.self, forKey: key)
        guard let value = T(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: container, debugDescription: "unrecognised value '\(raw)'"
            )
        }
        return value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode.storedValue, forKey: .mode)
        try container.encode(keyboardLanguage.rawValue, forKey: .keyboardLanguage)
        try container.encode(engine.rawValue, forKey: .engine)
        try container.encode(modelIdentifier, forKey: .modelIdentifier)
    }

    /// Capture the current App Group state. Call once per dictation, at
    /// transcription start, and propagate the result through STT, polish,
    /// and finalization.
    public static func snapshot() -> TranscriptionLanguagePolicy {
        let defaults = AppGroup.defaults
        let modelIdentifier = defaults.string(forKey: SharedKeys.activeModel) ?? ""
        return TranscriptionLanguagePolicy(
            mode: TranscriptionLanguageMode(
                storedValue: defaults.string(forKey: SharedKeys.transcriptionLanguage)
            ),
            keyboardLanguage: SupportedLanguage.active,
            engine: ModelInfo.forIdentifier(modelIdentifier)?.engine ?? .whisperKit,
            modelIdentifier: modelIdentifier
        )
    }

    /// Language code for the STT engine, or `nil` for Whisper auto-detection.
    /// Parakeet ignores the parameter either way; it receives the keyboard
    /// code exactly as it did before #226 so its flows stay byte-identical.
    public var sttLanguageCode: String? {
        guard engine == .whisperKit else { return keyboardLanguage.rawValue }
        return mode.resolvedLanguageCode(keyboardLanguageCode: keyboardLanguage.rawValue)
    }

    /// Polish-stage prompt selection (#239, resolution order fixed in #332).
    ///
    /// The polish target is the language the LLM is *instructed to write in*
    /// (`AppleFoundationModelsPolishEngine.resolvedInstructions(mode:language:)`),
    /// so getting it wrong does not mis-tune typography — it TRANSLATES the
    /// user's speech. That is the most destructive thing this pipeline can do,
    /// which is why the order below is strict and the keyboard comes last:
    ///
    /// 1. an explicitly chosen transcription language, whenever one is set;
    /// 2. otherwise the language that occupies most of the STT output (#456);
    /// 3. the keyboard language only as a last resort — when nothing was read at
    ///    all, or when no language holds enough of the transcript to be named.
    ///
    /// WHY the engine no longer splits case 1 (#332): until this fix, explicit
    /// mode resolved to `engine == .whisperKit ? language : keyboardLanguage`,
    /// on the reasoning that the setting is Whisper-only-effective so Parakeet
    /// should keep the pre-#226 behavior. Parakeet is the shipping engine, so
    /// in practice every explicit choice was discarded: three device
    /// reproductions caught French speech polished into German and into
    /// English purely because the keyboard had been switched. "The setting
    /// cannot steer Parakeet's STT" is true and irrelevant here — the user
    /// still named a language, and polish still needs a target.
    ///
    /// WHY auto mode ignores the engine (#239 scope amendment): Parakeet
    /// natively transcribes whichever of its 25 languages is spoken, so in
    /// Auto mode its output language is just as unknown as Whisper's —
    /// targeting the keyboard language made polish TRANSLATE foreign speech
    /// (observed on device: en dictation on a fr keyboard → French output).
    /// Both engines therefore use the language-agnostic auto prompt in Auto
    /// mode. This is a polish-stage decision only — `sttLanguageCode` keeps
    /// Parakeet's follow behavior because the engine ignores the parameter.
    ///
    /// WHY detection became a proportion (#456): case 2 above used to be a single
    /// `NLLanguageRecognizer` verdict on the whole transcript, and that recogniser
    /// weights the string's opening rather than its bulk. A captured French dictation
    /// whose first two sentences Parakeet mistranscribed as English read `en` at
    /// **0.9995** on a transcript that was 78 % French by character count, and Apple FM
    /// duly translated the other three quarters into English. Nothing below detection
    /// disagreed, because #332 had — correctly — put detection above the keyboard.
    ///
    /// The rule that replaces it is the maintainer's: **the target is the language
    /// occupying the most of the transcript, measured as a proportion.** No confidence
    /// floor could have caught the captured case (0.9995 is the ceiling), and no
    /// second guardrail could either — the output was English and the target was
    /// English, so every check downstream agreed with a target that was already wrong.
    ///
    /// - Parameter languageMix: what the raw STT output is made of, by language —
    ///   see `PolishLanguageMix`. Injected by the caller rather than measured here so
    ///   this stays a pure, testable function.
    public func polishPromptSelection(
        languageMix: PolishLanguageMix
    ) -> PolishPromptSelection {
        switch mode {
        case .autoDetect:
            return .autoDetected
        case .explicit(let language):
            return .language(language)
        case .followKeyboard:
            // No explicit choice to honour, so the transcript's own proportions
            // decide. The keyboard language is used only when no language holds
            // enough of the transcript to be named — and then it is a guess about
            // the user's speech, not an instruction from them.
            let elected = languageMix.electedLanguage(floor: Self.dominantLanguageShareFloor)
            return .language(elected ?? keyboardLanguage)
        }
    }

    /// Share of the transcript the leading language must hold for a polish target to
    /// be elected from it in `.followKeyboard`. Below it, `keyboardLanguage` takes
    /// over (#456).
    ///
    /// **Why fall back rather than crown the leader anyway.** On a genuinely bilingual
    /// dictation no language legitimately wins, and the cost of guessing is the worst
    /// outcome this pipeline can produce: half the user's words translated. The
    /// keyboard language is then the only signal left that came from the user rather
    /// than from a classifier.
    ///
    /// **Where 60 comes from, and why it stayed.** It was a judgement call in the
    /// brief, declared as one, and it was measured before it shipped. Scored over the
    /// 13 hand-labelled transcripts in `docs/research/456-target-election/corpus.json`
    /// with `swift run polish-harness target … --sweep`, which drives no model. A real
    /// fixture bounds it on each side:
    ///
    /// | | reads | so the floor must be |
    /// |---|---|---|
    /// | `A6` a deliberately half-and-half FR/EN dictation | **en 0.519** | above 0.519 |
    /// | `A4` French speech quoting one English clause | **fr 0.710** | at most 0.710 |
    ///
    /// Below the lower bound the election crowns a winner on a coin flip — at 0.50 the
    /// sweep elects English for `A6` and translates half a French dictation, the exact
    /// failure this issue is about. Above the upper bound `A4` stops being decided by
    /// its own content and starts depending on the keyboard being right, which is what
    /// #332 was about. 0.60 sits inside `(0.519, 0.710]`, nearer the bottom, because
    /// the two errors are not symmetrical: too high only defers to the keyboard, which
    /// in `.followKeyboard` is usually the same language anyway, while too low is what
    /// translates a user's speech.
    ///
    /// **The `correct` column alone does not bound this number** — every floor from
    /// 0.55 to 0.90 scores 13/13, because a fallback to the keyboard usually lands on
    /// the language the proportion would have elected. The `by keyboard` column is
    /// what shows the floor going wrong.
    public static let dominantLanguageShareFloor: Double = 0.60

    /// Whether the STT engine actually honours `sttLanguageCode` (#332).
    ///
    /// Parakeet auto-detects from audio and ignores the parameter entirely
    /// (`ParakeetEngine.transcribe(audioSamples:language:)`), so the code it
    /// receives is inert. The language-resolution probe logs a code either
    /// way, which made `stt=en engine=PK` read as "transcribed in English"
    /// when the raw text was French; recording this alongside it is what
    /// removes the ambiguity.
    public var sttLanguageIsEffective: Bool {
        engine == .whisperKit
    }

    /// `sttLanguageCode` rendered for logs and the debug export, with `nil`
    /// (Whisper auto-detection) spelled out rather than dropped.
    public var sttLanguageCodeDescription: String {
        sttLanguageCode ?? "auto"
    }

    /// True when the transcription must be inserted literally as-is (no
    /// trailing-separator coercion): Whisper Auto-detect only, where the
    /// output language is unknown and appending Western punctuation to e.g.
    /// CJK text would corrupt it.
    public var insertsTranscriptionAsIs: Bool {
        engine == .whisperKit && mode == .autoDetect
    }
}
