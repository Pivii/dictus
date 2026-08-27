// DictusCore/Sources/DictusCore/History/TranscriptionRecord.swift
// One saved dictation: the text and the four facts that let the user recognise it.
import Foundation

/// One dictation the user can find again (#70).
///
/// WHY `language` and `sttProvider` are `String` and not `SupportedLanguage` /
/// `SpeechEngine`: the whole history is one JSON array, so a value the running
/// build cannot map to an enum case would fail the decode of *every* record, not
/// just its own. A language Dictus stops shipping, or a third STT engine written
/// by a later build and read by an older one, are both things this file has to
/// survive — it is the user's own transcriptions, and losing them to a rename is
/// not a trade worth making for type safety on a badge label. The enums are still
/// reachable through `supportedLanguage` and `engine`, which return nil rather
/// than throwing.
public struct TranscriptionRecord: Identifiable, Codable, Equatable, Sendable {

    public let id: UUID

    /// The text as it was finally produced. Mutable because a keyboard dictation is
    /// recorded before it is polished — see `TranscriptionHistoryStore.updateText`.
    public private(set) var text: String

    /// The transcription language code: "fr", "en", … or `autoDetectedCode` when the
    /// user is in auto-detect mode and no single language was chosen up front.
    public let language: String

    /// Length of the audio that produced this text, rounded to the second.
    public let durationSeconds: Int

    public let createdAt: Date

    /// The STT engine's stored marker (`SpeechEngine.rawValue`: "WK" / "PK").
    public let sttProvider: String

    /// The value `language` carries when the user let the engine detect it (#226's
    /// auto-detect mode). Not a language code, deliberately: the record must not
    /// claim a language nobody chose and nothing measured.
    public static let autoDetectedCode = "auto"

    public init(id: UUID = UUID(),
                text: String,
                language: String,
                durationSeconds: Int,
                createdAt: Date = Date(),
                sttProvider: String) {
        self.id = id
        self.text = text
        self.language = language
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.sttProvider = sttProvider
    }

    /// Build a record from the per-dictation snapshot the pipeline already carries.
    ///
    /// The policy is the only honest source for the language: it is captured once at
    /// transcription start (#226) and is what STT and polish both ran against, so a
    /// record built from it cannot disagree with the dictation it describes.
    public init(text: String,
                policy: TranscriptionLanguagePolicy,
                duration: TimeInterval,
                createdAt: Date = Date()) {
        self.init(
            text: text,
            language: Self.languageCode(for: policy),
            // Rounded rather than truncated: a 0.9 s dictation reading "0s" looks
            // like a bug, and the second is the only precision the card shows.
            durationSeconds: Int(duration.rounded()),
            createdAt: createdAt,
            sttProvider: policy.engine.rawValue
        )
    }

    /// What to record as the language of a dictation run under `policy`.
    ///
    /// Deliberately not `policy.sttLanguageCode`: that property answers "what do I
    /// hand the engine", which for Parakeet is always the keyboard language even
    /// though Parakeet auto-detects and ignores it. Here the question is what to
    /// show the user, and the keyboard language is a guess in that case.
    static func languageCode(for policy: TranscriptionLanguagePolicy) -> String {
        switch policy.mode {
        case .explicit(let language):
            return language.rawValue
        case .followKeyboard:
            return policy.keyboardLanguage.rawValue
        case .autoDetect:
            return autoDetectedCode
        }
    }

    // MARK: - Display

    /// The language as an enum, when the running build still knows it.
    public var supportedLanguage: SupportedLanguage? {
        SupportedLanguage(rawValue: language)
    }

    /// The engine as an enum, when the running build still knows it.
    public var engine: SpeechEngine? {
        SpeechEngine(rawValue: sttProvider)
    }

    /// Short uppercase badge for the card: "FR", "EN", "AUTO".
    public var languageBadge: String {
        language.uppercased()
    }

    /// `12s`, `1m 05s`. Not localised: both forms are digits plus a unit letter that
    /// reads the same in French and English, and the card has room for one line.
    public var durationLabel: String {
        let seconds = max(0, durationSeconds)
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%dm %02ds", seconds / 60, seconds % 60)
    }

    // MARK: - Mutation

    /// Replace the text, keeping every other field. The identity of the dictation
    /// does not change when the keyboard reports what it actually typed.
    func withText(_ newText: String) -> TranscriptionRecord {
        var copy = self
        copy.text = newText
        return copy
    }
}
