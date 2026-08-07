// AOSP-inspired trie engine for Dictus. Apache 2.0.
#ifndef DICTUS_SCORER_H
#define DICTUS_SCORER_H

#include <cstdint>
#include <vector>

#include "dictus_proximity.h"

namespace dictus {

class Trie;

/// A spell correction candidate with score.
struct Candidate {
    char word[128];     // UTF-8, null-terminated (avoids std::string allocation)
    float score;
    uint16_t frequency;
};

/// Accent substitution costs: what it costs to type `e` where `é` belonged, or `u` where
/// `ü` did, instead of treating the two spellings as unrelated characters.
///
/// The relation and its costs are declared in DictusCore (`AccentRelation`) and installed
/// here as flat pairs. WHY the split: the table is data, built once per dictionary load,
/// and DictusCore is the only place in this repo a test can execute. WHY *pairs* rather
/// than the accented-to-base map this replaced: re-deriving the pairs here would put the
/// precedence rules (base-to-accent 0.15, accent-to-accent 0.20) in two languages, free
/// to drift. This class holds no rules of its own.
///
/// ß (U+00DF) is deliberately absent, which is why it has no slot in substitutionSlot():
/// its relation to `ss` changes length, and this path models one-to-one substitution only.
/// The full reasoning is on `AccentRelation.baseLetters`; the ss->ß relation is modelled
/// in `germanProfile.collapseRules` instead.
class AccentCostTable {
public:
    AccentCostTable();

    /// Install `count` (from, to, cost) triples as three parallel arrays.
    /// Returns false and leaves the table untouched if the arguments are inconsistent.
    bool setPairs(const uint16_t* from, const uint16_t* to, const float* costs, int count);

    /// Substitution cost between two accent-related characters.
    /// Returns >= 0.0 if the pair is a known relation, -1.0 otherwise.
    float cost(uint16_t from, uint16_t to) const;

private:
    /// Reset to unrelated: 0.0 against itself, -1.0 against everything else.
    void reset();

    float costs_[SUBSTITUTION_SLOT_COUNT][SUBSTITUTION_SLOT_COUNT];
};

/// Weighted edit distance scorer for spell correction.
/// Traverses the trie with edit operations, using keyboard proximity
/// and accent-aware costs for substitutions.
class Scorer {
public:
    Scorer();

    /// Set the active keyboard proximity map.
    void setProximityMap(const ProximityMap* map);

    /// Set the active accent cost table.
    void setAccentCostTable(const AccentCostTable* table);

    /// Find spell corrections for the input word.
    /// input: UTF-16 code units, inputLen: number of code units.
    /// maxEditDist: maximum cumulative edit cost (default 2.0).
    /// maxResults: maximum candidates to return (default 5).
    /// Returns candidates sorted by score descending.
    std::vector<Candidate> correct(const Trie& trie,
                                   const uint16_t* input, int inputLen,
                                   float maxEditDist = 2.0f,
                                   int maxResults = 5) const;

private:
    const ProximityMap* proximityMap_;
    const AccentCostTable* accentCostTable_;

    void search(const Trie& trie,
                uint32_t nodeOffset, int childIndex, int childCount,
                const uint16_t* input, int inputLen, int inputPos,
                uint16_t* wordBuf, int wordLen,
                float cost, float maxEditDist,
                std::vector<Candidate>& results, int maxResults) const;
};

} // namespace dictus

#endif // DICTUS_SCORER_H
