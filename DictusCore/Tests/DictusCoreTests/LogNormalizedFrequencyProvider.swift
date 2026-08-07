// DictusCore/Tests/DictusCoreTests/LogNormalizedFrequencyProvider.swift
// Test double that answers on the frequency scale the shipped trie really uses.
import Foundation
@testable import DictusCore

/// Test double holding raw corpus counts and answering with the log-normalized
/// 16-bit value `tools/dict_builder.py` writes into each trie node:
/// `65535 * ln(1 + freq) / ln(1 + maxFrequency)`.
///
/// WHY this exists (issue #326): `MockFrequencyProvider` answers with raw counts,
/// which no production provider does. `AOSPTrieEngine.frequency(of:)` returns
/// `Trie::getFrequency`, i.e. the stored normalized value. The compression is
/// severe — a 1033x raw ratio becomes 2.06x — so a test written against raw
/// counts wildly overstates how easily the 5x dominance rule in `expandAccents`
/// fires. Any test whose point is to predict on-device behaviour of that rule
/// must drive it through this provider, not `MockFrequencyProvider`.
///
/// Use `MockFrequencyProvider` for algorithm shape (which candidate wins, does a
/// rule fire at all); use this one when the *threshold* is what's under test.
final class LogNormalizedFrequencyProvider: FrequencyProvider {

    var isReady: Bool = true
    private let normalized: [String: UInt16]

    /// - Parameters:
    ///   - rawFrequencies: word → raw corpus count, as found in `<code>_frequency.json`.
    ///   - maxFrequency: the corpus maximum, which is the normalization anchor
    ///     `dict_builder.py` writes into the `.dict` header. For German that is
    ///     5 890 279 (`ich`); passing anything else changes every stored value.
    init(rawFrequencies: [String: Int], maxFrequency: Int, isReady: Bool = true) {
        self.isReady = isReady
        let logMax = maxFrequency > 0 ? log(1.0 + Double(maxFrequency)) : 1.0
        var table: [String: UInt16] = [:]
        table.reserveCapacity(rawFrequencies.count)
        for (word, raw) in rawFrequencies {
            guard raw > 0 else {
                table[word] = 0
                continue
            }
            // Mirrors dict_builder.py's `int(65535 * log(1 + freq) / log_max)`:
            // Swift's Int(Double) truncates toward zero, as Python's int() does.
            let scaled = 65535.0 * log(1.0 + Double(raw)) / logMax
            table[word] = UInt16(min(65535, max(0, Int(scaled))))
        }
        self.normalized = table
    }

    func frequency(of word: String) -> UInt16 {
        normalized[word] ?? 0
    }

    func wordExists(_ word: String) -> Bool {
        normalized[word] != nil
    }
}
