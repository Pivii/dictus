// DictusCore/Sources/DictusCore/Polish/PolishGlossary.swift
import Foundation

/// Domain-vocabulary nudge injected into every polish prompt.
///
/// Static and maintainer-curated. Distinct from `LanguageProfile.overrides`
/// (keyboard autocorrect) and from #80 custom vocabulary (premium, per-user).
/// Evolves by PR as terms appear mistranscribed in debug logs.
public enum PolishGlossary {
    public static let terms: [String] = [
        "Dictus",
        "WhisperKit",
        "Parakeet v3",
        "FluidAudio",
        "GitHub",
        "TestFlight",
        "iOS",
        "App Store",
        "Argmax",
        "Apple Intelligence"
    ]

    /// Block format injected into the prompt's instructions section.
    /// Tuned in step 5 once a real engine is online.
    ///
    /// **The maintainer's terms only.** Kept pure on purpose: it is what the prompt
    /// tests assert on, and #80's pre-registered bar is that a user with an empty
    /// vocabulary gets output identical to today's, byte for byte. Production reads
    /// `activePromptBlock`.
    public static var promptBlock: String {
        block(for: terms)
    }

    /// What production actually sends: the curated terms plus the user's own (#80
    /// decision 7).
    ///
    /// This is what keeps an entry with no variants from being inert — the paywall
    /// promises "Teach Dictus your technical terms", and a term nobody mangles still
    /// has a spelling worth defending. It reaches only users with Apple
    /// Intelligence, so the issue treats it as a bonus rather than as the feature.
    ///
    /// **Known limit.** `SmartModeCatalogue.builtIns` is a `static let`, so a Smart
    /// Mode's prompt is assembled once per process: a term added while a process is
    /// alive reaches the free polish on the next dictation and that process's Smart
    /// Modes at its next launch. Making the catalogue computed would rebuild five
    /// prompt strings on every access, including inside the keyboard's fan
    /// (`KeyboardSmartModeFan.swift`), which is not a trade worth making silently for
    /// the bonus half of a bonus path.
    public static var activePromptBlock: String {
        block(for: terms + CustomVocabulary.glossaryTerms())
    }

    /// The one formatter, so the pure block and the active one cannot drift.
    static func block(for terms: [String]) -> String {
        "Spell these terms exactly as written: " + terms.joined(separator: ", ") + "."
    }
}
