// DictusCore/Sources/DictusCore/Vocabulary/VocabularyReplacer.swift
// The deterministic text pass that IS the custom-vocabulary feature (#80).
import Foundation

/// Rewrites the engine's variants into the user's canonical spellings.
///
/// ### Why a text pass and not engine biasing (#80 decision 1)
///
/// The issue measured both purpose-built mechanisms and rejected both. WhisperKit
/// 0.16.0 exposes no `initialPrompt` — only raw `promptTokens`, capped at 111 tokens
/// and mutually exclusive with the prefill cache we enable at both production sites.
/// Parakeet, which is the recommended engine on any iPhone with 6 GB or more, does
/// ship `configureVocabularyBoosting` — but its judge is
/// `FluidInference/parakeet-ctc-110m-coreml`, which declares `["en"]` while our TDT
/// speaks 25 languages, and its stopword list is hardcoded English. On a French
/// dictation both sides of that rescorer would be scored by a model that has never
/// heard French.
///
/// A text replacement after transcription is the only stage that treats every
/// user's language and every device alike. It cannot recover a term the engine never
/// heard — it is a rewrite, not a recognition — and that boundary is the issue's
/// first decision.
///
/// ### Where it runs
///
/// At the consumer of `TranscriptionService.transcribe()`, in `DictationCoordinator`
/// — never inside `transcribe`, which returns from more than one branch depending on
/// the engine. That single point is upstream of both the in-app tail and the
/// keyboard hand-off, so one call serves both processes.
///
/// It runs **before** `VerbalPunctuationPrepass`, so a spoken punctuation command
/// sitting inside a term cannot split it before it is matched, and **before** the
/// polish, so nothing rewrites text that has already passed `PolishGuardrail` —
/// which is the class of defect #414 and #466 closed.
public enum VocabularyReplacer {

    // MARK: - Entry point

    /// Apply the user's vocabulary to a transcript.
    ///
    /// Returns `text` untouched when there is nothing to do, which is the state
    /// every user who never opens the feature is in. That identity is the issue's
    /// pre-registered bar: with an empty vocabulary nothing downstream may be able
    /// to tell the feature shipped.
    public static func apply(_ text: String, entries: [VocabularyEntry]) -> String {
        guard !text.isEmpty else { return text }
        let rules = rules(from: entries)
        guard !rules.isEmpty else { return text }
        return apply(text, rules: rules)
    }

    // MARK: - Rules

    /// One variant, resolved into everything the scan needs to match it.
    struct Rule: Equatable {
        /// The variant, one lowercased string per source `Character`. Lowercasing
        /// per character rather than per string keeps this array the same length as
        /// the variant, which is what lets the scan advance by a character count.
        let needle: [String]
        /// What is written when the needle matches: the entry's canonical term.
        let replacement: String
        /// The entry this variant came from. Only the idempotence filter reads it:
        /// a needle covering the whole of **its own** term is a fixed point, and a
        /// needle reaching any other term is a cycle.
        let owner: UUID
        /// Whether a word boundary is required before the match. False when the
        /// variant opens on a script that does not separate words with spaces.
        let needsLeadingBoundary: Bool
        /// Whether a word boundary is required after the match.
        let needsTrailingBoundary: Bool
    }

    /// Build the scan's rules from the entries the user enabled.
    ///
    /// ### Order independence
    ///
    /// Rules are sorted by needle length descending, so the **longest variant wins**
    /// when two overlap. Ties break on the needle and then on the replacement, so a
    /// variant claimed by two entries resolves the same way whatever order the file
    /// happens to hold — "longest wins" would otherwise still leave the result
    /// depending on storage order, which the issue forbids.
    ///
    /// ### Idempotence
    ///
    /// A variant that would match **inside any enabled canonical term** is dropped,
    /// with one exception: a variant that covers the whole of **its own** term. That
    /// is `ampli` → `Ampli`, which re-matches on a second application and emits the
    /// same `Ampli` — a fixed point, not a cycle, and the one shape that lets a
    /// case-insensitive matcher fix a proper noun the engine wrote in lowercase.
    ///
    /// Every other overlap is a cycle waiting to run: `東京` → `東京都` grows the text
    /// on every pass, and `foo` → `bar` beside `bar` → `foo` flips it. With those
    /// dropped, the image of the map meets its domain only at fixed points, so a
    /// second application changes nothing.
    ///
    /// The one residue this does not cover is a variant that straddles the join
    /// between an emitted term and the text that follows it — reachable only in a
    /// non-spaced script, where there is no boundary to stop it, and only with a
    /// variant deliberately built to span that join. It is left standing rather than
    /// papered over: closing it means re-scanning emitted text, which is a bigger
    /// hole than the one it fills.
    static func rules(from entries: [VocabularyEntry]) -> [Rule] {
        let enabled = entries.filter { $0.isEnabled && $0.isValid }
        guard !enabled.isEmpty else { return [] }

        var candidates: [Rule] = []
        for entry in enabled {
            for variant in entry.variants {
                let needle = Array(variant).map { $0.lowercased() }
                guard !needle.isEmpty else { continue }
                candidates.append(Rule(
                    needle: needle,
                    replacement: entry.term,
                    owner: entry.id,
                    needsLeadingBoundary: !isNonSpacedScript(variant.first),
                    needsTrailingBoundary: !isNonSpacedScript(variant.last)
                ))
            }
        }
        guard !candidates.isEmpty else { return [] }

        candidates.sort {
            if $0.needle.count != $1.needle.count { return $0.needle.count > $1.needle.count }
            let left = $0.needle.joined(), right = $1.needle.joined()
            if left != right { return left < right }
            return $0.replacement < $1.replacement
        }

        // The two filters that make the pass idempotent, in the order that keeps
        // them cheap: drop a needle already claimed, then drop one that lives inside
        // a term this pass can emit.
        let terms = enabled.map { entry -> (id: UUID, characters: [Character], lowered: [String]) in
            let characters = Array(entry.term)
            return (entry.id, characters, characters.map { $0.lowercased() })
        }
        var claimed = Set<String>()
        var rules: [Rule] = []
        for rule in candidates {
            guard claimed.insert(rule.needle.joined()).inserted else { continue }
            let cycles = terms.contains { term in
                guard occurs(rule, in: term.characters, lowered: term.lowered) else { return false }
                let coversItsOwnTerm = term.id == rule.owner && term.lowered.count == rule.needle.count
                return !coversItsOwnTerm
            }
            guard !cycles else { continue }
            rules.append(rule)
        }
        return rules
    }

    // MARK: - The scan

    /// One left-to-right pass. On a hit the canonical term is emitted and the cursor
    /// advances **past the variant**, so text this pass wrote is never re-examined
    /// by it.
    private static func apply(_ text: String, rules: [Rule]) -> String {
        let characters = Array(text)
        let lowered = characters.map { $0.lowercased() }

        // Bucketed on the first lowercased character so a transcript is not walked
        // once per rule. With 200 entries this is the difference between a few
        // thousand comparisons and a few hundred thousand.
        var buckets: [String: [Rule]] = [:]
        for rule in rules {
            buckets[rule.needle[0], default: []].append(rule)
        }

        var output = String()
        output.reserveCapacity(text.count)
        var index = 0
        while index < characters.count {
            var matched = false
            if let bucket = buckets[lowered[index]] {
                for rule in bucket where matches(rule, in: characters, lowered: lowered, at: index) {
                    output.append(rule.replacement)
                    index += rule.needle.count
                    matched = true
                    break
                }
            }
            if !matched {
                output.append(characters[index])
                index += 1
            }
        }
        return output
    }

    /// Whether `rule` matches at `index`, boundaries included.
    private static func matches(_ rule: Rule,
                                in characters: [Character],
                                lowered: [String],
                                at index: Int) -> Bool {
        let end = index + rule.needle.count
        guard end <= lowered.count else { return false }
        for offset in 0..<rule.needle.count where lowered[index + offset] != rule.needle[offset] {
            return false
        }
        if rule.needsLeadingBoundary, index > 0, isWordCharacter(characters[index - 1]) {
            return false
        }
        if rule.needsTrailingBoundary, end < characters.count, isWordCharacter(characters[end]) {
            return false
        }
        return true
    }

    /// The rule-build helper: does this needle occur anywhere in a canonical term.
    /// Boundaries are applied exactly as the scan applies them, so the filter and
    /// the scan cannot disagree about what "matches" means.
    private static func occurs(_ rule: Rule,
                               in characters: [Character],
                               lowered: [String]) -> Bool {
        guard rule.needle.count <= lowered.count else { return false }
        for start in 0...(lowered.count - rule.needle.count)
        where matches(rule, in: characters, lowered: lowered, at: start) {
            return true
        }
        return false
    }

    // MARK: - Script rules

    /// A word character for boundary purposes: what `\b` sits between.
    ///
    /// Letters and digits only. An apostrophe is deliberately not one, so a French
    /// `l'ampli` offers a boundary before `ampli`.
    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Whether a character belongs to a script that does not separate words with
    /// spaces, and therefore cannot be asked for a word boundary (#80 matching
    /// rules).
    ///
    /// Hiragana, Katakana, CJK Unified (with its first extension and the
    /// compatibility block), Hangul and Thai. Judged on the first Unicode scalar,
    /// which for these scripts is the character: none of them compose graphemes from
    /// a base in another script.
    static func isNonSpacedScript(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x309F,               // Hiragana
             0x30A0...0x30FF,               // Katakana
             0x31F0...0x31FF,               // Katakana phonetic extensions
             0xFF66...0xFF9D,               // Halfwidth katakana
             0x3400...0x4DBF,               // CJK Unified Ideographs Extension A
             0x4E00...0x9FFF,               // CJK Unified Ideographs
             0xF900...0xFAFF,               // CJK Compatibility Ideographs
             0x20000...0x2A6DF,             // CJK Unified Ideographs Extension B
             0x1100...0x11FF,               // Hangul Jamo
             0x3130...0x318F,               // Hangul Compatibility Jamo
             0xAC00...0xD7AF,               // Hangul Syllables
             0x0E00...0x0E7F:               // Thai
            return true
        default:
            return false
        }
    }
}
