// AOSP-inspired trie engine for Dictus. Apache 2.0.
#ifndef DICTUS_PROXIMITY_H
#define DICTUS_PROXIMITY_H

#include <cstdint>

namespace dictus {

/// Number of characters a substitution cost can be defined between.
/// See substitutionSlot() for the ranges.
static constexpr int SUBSTITUTION_SLOT_COUNT = 58;

/// Compact table slot for a character, or -1 when there is none.
///
/// Covers a-z plus the lowercase half of the Latin-1 supplement (U+00E0..U+00FF), which
/// is where every accented key of every layout Dictus ships lives: é è ê ë à â ä ç î ï
/// ô ö ù û ü. Uppercase is folded first. Anything else -- digits, punctuation, ß
/// (U+00DF, deliberately outside the accent relation), letters beyond Latin-1 -- returns
/// -1 and its callers treat it as unrelated.
///
/// WHY a slot map rather than the c - 'a' indexing this replaced: that indexing made the
/// tables 26 ASCII letters *by construction*, so QWERTZ's ü/ö/ä keys were not mis-scored,
/// they were unrepresentable (#321).
inline int substitutionSlot(uint16_t c) {
    if (c >= 'A' && c <= 'Z') c = static_cast<uint16_t>(c - 'A' + 'a');
    // Latin-1 uppercase to lowercase. U+00D7 is the multiplication sign, not a letter.
    if (c >= 0x00C0 && c <= 0x00DE && c != 0x00D7) c = static_cast<uint16_t>(c + 0x20);

    if (c >= 'a' && c <= 'z') return static_cast<int>(c - 'a');
    if (c >= 0x00E0 && c <= 0x00FF) return 26 + static_cast<int>(c - 0x00E0);
    return -1;
}

/// Keyboard proximity costs for weighted edit distance scoring.
///
/// The table is computed in DictusCore (`KeyboardProximity`) and installed here. WHY the
/// split: the key geometry and the distance formula are data, evaluated once per
/// dictionary load, and DictusCore is the only place in this repo that can run a test
/// against them -- the keyboard target has no test bundle. What stays here is the lookup
/// the scorer's inner loop performs.
class ProximityMap {
public:
    ProximityMap();

    /// Install a precomputed cost table.
    /// characters: `count` UTF-16 code units, one per table row and column.
    /// distances: `count * count` costs in [0.0, 1.0], row-major.
    /// Returns false and leaves the table untouched if the arguments are inconsistent.
    /// Characters with no slot are skipped: they keep costing 1.0.
    bool setTable(const uint16_t* characters, int count, const float* distances);

    /// Get proximity cost between two characters.
    /// Returns value in [0.0, 1.0]. Lower = closer on keyboard.
    /// Returns 1.0 for anything the active layout has no key for.
    float cost(uint16_t a, uint16_t b) const;

private:
    /// Reset to neutral: 0.0 against itself, 1.0 against everything else.
    void reset();

    float distances_[SUBSTITUTION_SLOT_COUNT][SUBSTITUTION_SLOT_COUNT];
};

} // namespace dictus

#endif // DICTUS_PROXIMITY_H
