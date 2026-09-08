// DictusCore/Sources/DictusCore/Polish/PolishInputLanguageSupport.swift
// Whether a backend can read the language a transcript is written in (#490).
import Foundation

/// A backend's answer to "can you read this transcript at all?".
///
/// Three values rather than a `Bool` because "I cannot say" is a real and frequent
/// answer, and it must not be confused with "no". A backend that publishes no
/// language list, a transcript nothing could be read out of, an OS too old to ask —
/// all three are `unknown`, and `unknown` always lets the engine try. Only
/// `unsupported` refuses, and it costs the user their polish, so it is the one
/// value nothing is allowed to guess at.
public enum PolishInputLanguageSupport: Equatable, Sendable {

    /// At least one of the languages the transcript was measured to contain is one
    /// the backend reports it can read.
    case supported

    /// Nothing in the transcript is in a language the backend reports. This is the
    /// only verdict that refuses a call.
    case unsupported

    /// No verdict available: the backend publishes no list, or the transcript was
    /// read as nothing at all.
    case unknown
}

/// The rule deciding a `PolishInputLanguageSupport`, kept apart from every backend
/// so it can be tested without one (#490).
///
/// ### Why this exists
///
/// Apple Foundation Models runs a language classifier over the user turn and refuses
/// before generating anything — measured at 3 to 22 ms, on device and on the Mac. The
/// refusal is on the language of what was *said*, never on the requested target and
/// never on the process locale, so nothing before the dictation can predict it. What
/// can be predicted, the moment the transcript exists, is the case where the model
/// was never going to read it: Parakeet transcribes 25 European languages and ignores
/// the requested one, and fourteen of those (`bg cs el hr hu lt lv mt pl ro ru sk sl
/// uk`) are outside Apple's set entirely.
///
/// ### Why it refuses on the whole mix and not on the leader
///
/// The dominant language alone would refuse a transcript that is 60 % Czech and 40 %
/// French — an input Apple has not been measured on, and one where a refusal costs a
/// polish that might have succeeded. Requiring *every* counted language to be
/// unreadable makes the pre-flight strictly conservative: it can only ever refuse a
/// call that had no readable language in it at all, which is the case the measurement
/// on #490 covers (`{"cs": 1}`, refused 5/5 per language for `cs`, `ru`, `uk`, `el`).
public enum PolishInputLanguage {

    /// Judge `countedCodes` — the `NLLanguage` raw codes a transcript was measured to
    /// be made of (`PolishLanguageMix.countedCodes`) — against the codes a backend
    /// reports it can read.
    ///
    /// Both sides are compared on the primary subtag, lowercased: our reading says
    /// `zh-Hans` where Apple's list says `zh`, and a script tag is not what either is
    /// arguing about. Comparing wider than the data supports would refuse; comparing
    /// on the subtag can only let a call through, which is the safe direction.
    public static func support(countedCodes: Set<String>,
                               readableCodes: Set<String>) -> PolishInputLanguageSupport {
        guard !readableCodes.isEmpty else { return .unknown }
        guard !countedCodes.isEmpty else { return .unknown }
        let readable = Set(readableCodes.map(primarySubtag))
        let counted = countedCodes.map(primarySubtag)
        return counted.contains(where: readable.contains) ? .supported : .unsupported
    }

    /// `"zh-Hans"` → `"zh"`, `"fr-Latn-FR"` → `"fr"`, `"cs"` → `"cs"`.
    static func primarySubtag(_ code: String) -> String {
        let normalized = code.replacingOccurrences(of: "_", with: "-")
        return String(normalized.split(separator: "-").first ?? "").lowercased()
    }
}

/// A language code as the user's own language names it, for the one message that has
/// to say which language was dictated (#490).
///
/// Not a display concern of `SupportedLanguage`: the code named here is precisely one
/// that is *not* in that enum — Czech, Ukrainian, Greek — so it arrives as a raw
/// `NLLanguage` string and has nowhere else to be turned into a word.
public enum PolishLanguageName {

    /// The localized name for `code`, falling back to the code itself.
    ///
    /// Tried at full width first (`zh-Hans` names Simplified Chinese, `zh` does not),
    /// then on the primary subtag, then given up on. The fallback is the raw code
    /// rather than a second sentence: a code with no name in the user's locale is a
    /// case the polish pipeline has never produced, and inventing a second string for
    /// it would be a translation to maintain against nothing.
    public static func display(for code: String, locale: Locale = .current) -> String {
        if let full = locale.localizedString(forLanguageCode: code), full != code {
            return full
        }
        let subtag = PolishInputLanguage.primarySubtag(code)
        if let short = locale.localizedString(forLanguageCode: subtag), short != subtag {
            return short
        }
        return code
    }
}
