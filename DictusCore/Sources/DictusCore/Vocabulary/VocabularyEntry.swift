// DictusCore/Sources/DictusCore/Vocabulary/VocabularyEntry.swift
// One term the user taught Dictus, and the shapes the engine produces instead (#80).
import Foundation

/// A canonical spelling plus zero or more variants the engine writes in its place.
///
/// ### What an entry does, and why the variants are optional (#80 decisions 4 and 7)
///
/// 1. **Each variant triggers a replacement** to `term` on the raw transcript. That
///    works for every user, every engine and every language, because it is text and
///    not acoustics — see `VocabularyReplacer`.
/// 2. **`term` joins the polish glossary**, so a term with no variant at all is not
///    inert: the polish prompt is told to spell it exactly as written.
///
/// The second point is what keeps the paywall sentence honest. "Teach Dictus your
/// technical terms" has to mean something for a user who types `Kubernetes` and
/// cannot yet say what the engine mangles it into.
///
/// ### Why there is no language tag (#80 decision 9)
///
/// A term is a spelling, not a sentence: `Kubernetes` is `Kubernetes` in French and
/// in English, and asking the user which language their company's name belongs to is
/// a question with no good answer. The accepted consequence is written on the issue:
/// if #288 ever forces tagging, it is a migration on data that survives a reinstall.
///
/// ### Why `id`
///
/// The brief names four fields. The fifth is SwiftUI's: a `List` needs stable
/// identity per row, and `term` cannot supply it while the user is mid-edit on a
/// duplicate. `TranscriptionRecord` carries one for the same reason.
public struct VocabularyEntry: Codable, Identifiable, Equatable, Sendable {

    /// Longest accepted `term`, and longest accepted variant (#80 decision 10).
    ///
    /// A hundred characters is far beyond any real technical term; the limit exists
    /// so a paste accident cannot put a paragraph into the matcher, where it would
    /// cost a scan of the whole transcript per character and match nothing.
    public static let maxFieldLength = 100

    public let id: UUID

    /// The canonical spelling. What replacements emit, and what the glossary carries.
    public let term: String

    /// What the engine produces instead. May be empty.
    public let variants: [String]

    /// The per-entry switch (#80 decision 8). The replacement is silent, so this and
    /// the global toggle are the only two places a user can stop one.
    public let isEnabled: Bool

    public let dateAdded: Date

    /// Build an entry from user input, or refuse.
    ///
    /// Refuses only on the term, because the term is the entry: an empty or
    /// over-long canonical spelling has nothing to store. Variants are cleaned
    /// rather than refused — an over-long or duplicated one is dropped and the rest
    /// of the entry survives, which is what a user who pasted a stray line expects.
    ///
    /// A variant **byte-identical** to its term is dropped, and so is a variant that
    /// merely repeats another with different case.
    ///
    /// A variant that differs from its term only by case is **kept**, deliberately.
    /// `ampli` for `Ampli` is not a no-op: an engine writing a proper noun in
    /// lowercase is the commonest mangling there is, and it is the one thing a
    /// case-insensitive matcher can fix on its own. `VocabularyReplacer` treats that
    /// rule as a fixed point rather than as a cycle.
    public init?(term: String,
                 variants: [String] = [],
                 isEnabled: Bool = true,
                 id: UUID = UUID(),
                 dateAdded: Date = Date()) {
        let cleanTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTerm.isEmpty, cleanTerm.count <= Self.maxFieldLength else { return nil }

        var seen = Set<String>()
        var cleanVariants: [String] = []
        for variant in variants {
            let clean = variant.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.count <= Self.maxFieldLength else { continue }
            guard clean != cleanTerm else { continue }
            guard seen.insert(clean.lowercased()).inserted else { continue }
            cleanVariants.append(clean)
        }

        self.id = id
        self.term = cleanTerm
        self.variants = cleanVariants
        self.isEnabled = isEnabled
        self.dateAdded = dateAdded
    }

    /// Whether an entry that came off disk still satisfies what `init?` enforces.
    ///
    /// `Codable` synthesises its own initialiser and cannot be routed through the
    /// failable one, so the file is the one place an invalid entry can enter. The
    /// store filters on this at load; nothing else has to remember to.
    public var isValid: Bool {
        guard !term.isEmpty, term.count <= Self.maxFieldLength else { return false }
        return variants.allSatisfy { !$0.isEmpty && $0.count <= Self.maxFieldLength }
    }

    /// The same entry with its switch flipped. Used by the list's per-row toggle.
    public func enabled(_ newValue: Bool) -> VocabularyEntry {
        VocabularyEntry(
            term: term, variants: variants, isEnabled: newValue, id: id, dateAdded: dateAdded
        ) ?? self
    }

    /// The variants as the add sheet writes them: one comma-separated line.
    public var variantsLine: String {
        variants.joined(separator: ", ")
    }

    /// Split a comma-separated line into candidate variants.
    ///
    /// Static and on the model rather than in the view, so the harness and the tests
    /// parse a user's line exactly the way the sheet does.
    public static func variants(fromLine line: String) -> [String] {
        line.split(separator: ",").map { String($0) }
    }
}
