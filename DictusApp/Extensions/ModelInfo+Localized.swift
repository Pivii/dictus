// DictusApp/Extensions/ModelInfo+Localized.swift
// Localized display strings for ModelInfo, resolved via String Catalog.
import DictusCore
import SwiftUI

extension ModelInfo {
    /// Localized description for display in model cards.
    /// Source strings are in English; French provided via String Catalog.
    var localizedDescription: String {
        switch identifier {
        case "openai_whisper-tiny", "openai_whisper-base":
            return String(localized: "Fast but inaccurate")
        case "openai_whisper-small":
            return String(localized: "Accurate and balanced")
        case "openai_whisper-small_216MB":
            return String(localized: "Compact and fast")
        case "openai_whisper-medium":
            return String(localized: "Best accuracy")
        case "parakeet-tdt-0.6b-v3":
            return String(localized: "Fast and accurate (NVIDIA)")
        case "openai_whisper-large-v3_turbo_954MB":
            return String(localized: "Most accurate but slowest")
        default:
            return description
        }
    }
}

// MARK: - Incompatibility wording (issue #369)

extension ModelInfo.IncompatibilityReason {
    /// One short line telling the user which constraint they are looking at.
    ///
    /// WHY it names the hardware and not the app:
    /// the row is greyed because of the phone, and the sentence has to carry that
    /// or the user reads the disabled card as Dictus being broken or thin. It must
    /// not sound like an error or like something they did.
    var localizedText: String {
        switch self {
        case .hardwareGeneration:
            return String(localized: "Not supported on this iPhone")
        case .insufficientMemory(let requiredGB):
            // Says what the requirement is rather than restating the refusal.
            return String(localized: "Requires \(requiredGB) GB of memory or more")
        }
    }
}

// MARK: - Language support strings (issue #240)

extension ModelLanguageSupport.Coverage {
    /// One-line coverage summary shown at the top of the language detail view.
    var localizedSummary: String {
        switch self {
        case .whisperMultilingual:
            return String(localized: "About 99 languages (multilingual)")
        case .parakeetEuropean:
            return String(localized: "25 European languages")
        }
    }
}

extension ModelLanguageSupport.QualityNote {
    /// Localized wording for a curated per-tier quality note.
    var localizedText: String {
        switch self {
        case .impreciseUpgradeRecommended:
            return String(localized: "Works but imprecise. Medium or Turbo recommended.")
        case .goodOnThisModel:
            return String(localized: "Good quality on this model.")
        }
    }
}

extension ModelLanguageSupport {
    /// User-facing display name for an ISO 639-1 code, localized by the
    /// system (French UI shows "chinois", English UI shows "Chinese").
    ///
    /// WHY Locale instead of hardcoded names:
    /// `Locale.localizedString(forLanguageCode:)` covers every code we curate
    /// in both app languages without maintaining a translation table.
    /// Falls back to the raw code for any code the OS cannot name.
    static func localizedLanguageName(for code: String) -> String {
        guard let name = Locale.current.localizedString(forLanguageCode: code) else {
            return code
        }
        // Locale returns lowercase names in some languages (e.g. "français");
        // capitalize the first letter for list display.
        return name.prefix(1).localizedCapitalized + name.dropFirst()
    }
}
