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
    public static var promptBlock: String {
        "Spell these terms exactly as written: " + terms.joined(separator: ", ") + "."
    }
}
