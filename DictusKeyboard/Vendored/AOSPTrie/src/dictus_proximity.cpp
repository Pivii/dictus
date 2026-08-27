// AOSP-inspired trie engine for Dictus. Apache 2.0.
#include "dictus_proximity.h"

namespace dictus {

ProximityMap::ProximityMap() {
    reset();
}

void ProximityMap::reset() {
    for (int i = 0; i < SUBSTITUTION_SLOT_COUNT; i++) {
        for (int j = 0; j < SUBSTITUTION_SLOT_COUNT; j++) {
            distances_[i][j] = (i == j) ? 0.0f : 1.0f;
        }
    }
}

bool ProximityMap::setTable(const uint16_t* characters, int count, const float* distances) {
    if (!characters || !distances || count <= 0) return false;

    // Neutral first: keys the new layout does not have must stop scoring as near misses
    // from whatever layout was installed before.
    reset();

    for (int i = 0; i < count; i++) {
        int row = substitutionSlot(characters[i]);
        if (row < 0) continue;
        for (int j = 0; j < count; j++) {
            int column = substitutionSlot(characters[j]);
            if (column < 0) continue;
            distances_[row][column] = distances[i * count + j];
        }
    }
    return true;
}

float ProximityMap::cost(uint16_t a, uint16_t b) const {
    int slotA = substitutionSlot(a);
    int slotB = substitutionSlot(b);
    if (slotA < 0 || slotB < 0) return 1.0f;
    return distances_[slotA][slotB];
}

} // namespace dictus
