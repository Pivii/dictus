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

    /// The polish target language for this mode, or `nil` when polish must be
    /// bypassed entirely.
    ///
    /// WHY polish follows the *transcription* language, not the keyboard:
    /// The polish prompts and typography passes must match the language of the
    /// STT output. In `.explicit` mode the user dictates in that language even
    /// if the keyboard shows another one — targeting the keyboard language
    /// would, e.g., apply French NBSP typography to English text.
    /// In `.autoDetect` mode the output language is unknown and the fr/en/es/de
    /// prompts don't apply — polish is skipped as a stopgap until the dedicated
    /// auto-detect prompt lands (follow-up #239).
    public func polishTargetLanguage(keyboardLanguage: SupportedLanguage) -> SupportedLanguage? {
        switch self {
        case .followKeyboard: return keyboardLanguage
        case .autoDetect: return nil
        case .explicit(let language): return language
        }
    }
}
