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
public struct TranscriptionLanguagePolicy: Equatable, Sendable {
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
    /// 2. otherwise the language detection found in the STT output;
    /// 3. the keyboard language only as a last resort, never over either.
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
    /// - Parameter detectedLanguage: what `NLLanguageRecognizer` read in the
    ///   raw STT output, or `nil` when it was not confident or landed outside
    ///   the four supported languages. Injected by the caller rather than
    ///   detected here so this stays a pure, testable function.
    public func polishPromptSelection(
        detectedLanguage: SupportedLanguage?
    ) -> PolishPromptSelection {
        switch mode {
        case .autoDetect:
            return .autoDetected
        case .explicit(let language):
            return .language(language)
        case .followKeyboard:
            // No explicit choice to honour, so detection decides. Only when it
            // has nothing to say does the keyboard language get used — and
            // then it is a guess about the user's speech, not an instruction
            // from them.
            return .language(detectedLanguage ?? keyboardLanguage)
        }
    }

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
