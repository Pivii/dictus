// DictusCore/Sources/DictusCore/FrequencyDictionary.swift
// Loads word frequency counts from JSON and provides count-based lookup.
import Foundation

/// A dictionary that maps words to frequency counts (higher count = more common).
///
/// WHY a struct with mutating load:
/// FrequencyDictionary is a value type holding a simple [String: Int] dictionary.
/// Load is mutating because we only load the active language (not both at once)
/// to keep memory usage low -- important for keyboard extension's ~50MB limit.
/// The `load(from:)` entry point accepts raw Data so unit tests can inject
/// JSON without needing a Bundle, keeping tests fast and deterministic.
public struct FrequencyDictionary {

    private var counts: [String: Int] = [:]

    /// Maximum words to keep in memory. Only the most frequent words are retained.
    /// This dictionary is only used for ranking UITextChecker completions —
    /// we don't need rare words for ranking purposes.
    /// 10K words ≈ 3 MiB vs 40K ≈ 6 MiB. Every MiB counts in a 50MB extension.
    private static let maxWords = 10000

    public init() {}

    /// Loads frequency data from raw JSON Data.
    /// Expected format: `{"word": count, ...}` where count is an Int (higher = more common).
    /// This is the testable entry point -- no Bundle dependency.
    public mutating func load(from data: Data) {
        do {
            let decoded = try JSONDecoder().decode([String: Int].self, from: data)
            // Keep only the top N most frequent words to save memory.
            // Words not in this dictionary get a count of 0 (lowest priority in
            // sorting), which is the correct behavior for rare words.
            if decoded.count > Self.maxWords {
                let top = decoded.sorted { $0.value > $1.value }.prefix(Self.maxWords)
                counts = [:]
                counts.reserveCapacity(Self.maxWords)
                for (key, value) in top {
                    counts[key] = value
                }
            } else {
                counts = decoded
            }
        } catch {
            print("[FrequencyDictionary] Failed to decode frequency data: \(error)")
            counts = [:]
        }
    }

    /// Loads frequency data for the given language from a JSON file in the specified bundle.
    /// Looks for `{language}_frequency.json` (e.g., `fr_frequency.json`).
    /// If the file is missing, prints a warning and leaves counts empty.
    public mutating func load(language: String, bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "\(language)_frequency", withExtension: "json") else {
            print("[FrequencyDictionary] Missing \(language)_frequency.json in bundle")
            counts = [:]
            return
        }
        do {
            let data = try Data(contentsOf: url)
            load(from: data)
        } catch {
            print("[FrequencyDictionary] Failed to read \(language)_frequency.json: \(error)")
            counts = [:]
        }
    }

    /// Returns the word frequency count (higher = more common).
    /// Returns 0 if the word is not in the dictionary.
    /// Lookup is case-insensitive.
    ///
    /// WHY not `frequency(of:)`: `FrequencyProvider.frequency(of:)` answers with
    /// the AOSP trie's log-normalized `UInt16`, a different number from a
    /// different source. Two names for one word would invite mixing them.
    public func frequencyCount(of word: String) -> Int {
        return counts[word.lowercased()] ?? 0
    }

    /// Returns `words` ordered most common first.
    ///
    /// WHY the ordering lives here and not at the call site: the direction is the
    /// whole contract, and it used to be a bare `>` in a closure sitting under a
    /// comment that described it backwards (#365). Spelled out once, in a name
    /// that says which way it goes, it can be read without reading the count's
    /// documentation — and the only test suite the repo has can reach it.
    ///
    /// Words the dictionary does not know count 0 and therefore land last.
    public func sortedMostCommonFirst(_ words: [String]) -> [String] {
        return words.sorted { frequencyCount(of: $0) > frequencyCount(of: $1) }
    }

    /// Returns the top N most frequent words, sorted by count descending.
    /// Used as fallback when n-gram predictions return no results.
    ///
    /// WHY filter short words: Single-letter words ("a", "y") and common
    /// stopwords are poor standalone predictions. We require at least 2 chars
    /// to provide useful fallback suggestions.
    public func topWords(count: Int) -> [String] {
        return counts
            .filter { $0.key.count >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { $0.key }
    }
}
