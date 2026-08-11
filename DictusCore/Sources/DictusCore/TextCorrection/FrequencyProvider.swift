// DictusCore/Sources/DictusCore/TextCorrection/FrequencyProvider.swift
// Protocol that abstracts the dictionary backend used by autocorrect helpers.
import Foundation

/// Abstracts the dictionary backend so autocorrect helpers (`AccentExpander`,
/// `ContractionExpander`) can be unit-tested without the C++ trie bridge.
///
/// Production: `AOSPTrieEngine` adapts the AOSP trie via this protocol.
/// Tests: a stub provider returns controlled frequencies for golden inputs.
///
/// WHY this exists:
/// The autocorrect algorithms (5x-dominance accent expansion, contraction split,
/// override lookup) are pure logic that depends only on per-word frequency and
/// existence checks. Decoupling them from `AOSPTrieBridge` lets the regression
/// tests live in `DictusCoreTests` without dragging the C++ bridge into the
/// test bundle.
public protocol FrequencyProvider {
    /// Whether the underlying dictionary is loaded and ready for lookups.
    /// Algorithms early-return when false.
    var isReady: Bool { get }

    /// Returns the frequency of `word` in the dictionary, or 0 if not present.
    func frequency(of word: String) -> UInt16

    /// Returns true if `word` exists in the dictionary.
    /// Used as a fallback when frequency is 0 but the word may still be valid.
    func wordExists(_ word: String) -> Bool
}

public extension FrequencyProvider {

    /// Whether the dictionary already knows `word`, asked exactly the way the
    /// corrector asks it (#287): lowercased, and for a contraction only the part
    /// after the last apostrophe — "j'ai" is stored in the trie as "ai", and
    /// `TextPredictionEngine.spellCheck` splits the same way before its
    /// `already-valid` skip.
    ///
    /// WHY this lives on the protocol rather than at either call site: the two
    /// users of it are the word-boundary learning gate in the keyboard extension
    /// and the duplicate prune in `UserDictionary`, and a word must mean the same
    /// thing to both — a gate that refuses to learn "j'ai" while the prune keeps
    /// it would leave entries no reader can reach.
    func knowsWord(_ word: String) -> Bool {
        let lowered = word.lowercased()
        guard let apostrophe = lowered.lastIndex(of: "'") else {
            return wordExists(lowered)
        }
        let afterApostrophe = String(lowered[lowered.index(after: apostrophe)...])
        guard !afterApostrophe.isEmpty else { return false }
        return wordExists(afterApostrophe)
    }
}
