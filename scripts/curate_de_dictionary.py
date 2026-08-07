#!/usr/bin/env python3
"""
Curate German frequency dictionary from HermitDave's FrequencyWords (2018).

Downloads de_50k.txt (OpenSubtitles 2018, German top 50K words), takes top 40K,
outputs JSON {word: count} where higher count = more common.

WHY HermitDave: Same source family used implicitly by ngram_builder.py
(OpenSubtitles via orgtre's top sentences). Stable, well-known, conversational
register that matches the keyboard's typical use case.

WHY the umlaut-deduplication filter: HermitDave's OpenSubtitles 2018 leaks
unaccented variants of common umlaut words (e.g., `uber` 463 vs `über` 196855,
`madchen` 160 vs `mädchen` 72685). These are mostly English brand mentions,
romanized proper nouns, or transcription errors. If both forms land in the
dict, the AccentExpander's 5x-dominance rule can't correct `uber → über`
because `uber` is already "valid". We drop the unaccented form when an umlaut
variant exists with high dominance, so the user always gets the umlauted
correction. Native words like `schon` (442 343) → `schön` (106 669) are
preserved because the unaccented form is itself dominant — both are real
German words in that direction.

WHY the filter cannot be left to the runtime 5x rule (issue #326): the
dictionary the keyboard reads does not store raw counts. `tools/dict_builder.py`
writes `65535 * ln(1 + freq) / ln(1 + max_freq)` into each trie node, so the
AccentExpander's dominance comparison happens in log space. `fuer` (712) against
`für` (735 252) is 1033x raw but only 2.06x once stored — under the 5x bar, so
the correction never fires on device. Passing 5x in log space needs the target
to be roughly the input raised to the fifth power, which nothing inside a 40K
corpus reaches. Dropping the transliteration here is therefore the only place
the fix can live: with the ASCII form absent, the expander takes its
`input frequency == 0` branch and the dominance comparison is never consulted.

Per ADR 0001 (non-native maintainer launch), no curated additions
(SMS abbreviations, proper nouns) are layered in for first ship —
populated post-launch from feedback on issue #109.
"""

import json
import os
import urllib.request

HERMITDAVE_URL = "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/de/de_50k.txt"
TXT_FILE = "de_50k.txt"
OUTPUT = os.path.join(os.path.dirname(__file__), "..", "DictusKeyboard", "Resources", "de_frequency.json")

# Minimum frequency multiplier of an umlaut variant over the unaccented input
# required to drop the unaccented form. 5x mirrors AccentExpander's dominance
# rule: any pair below this ratio represents a genuine native pair where both
# forms are real (e.g., `schon` "already" / `schön` "beautiful"), so we keep both.
UMLAUT_DEDUP_MIN_RATIO = 5

# Per-letter substitutions used to enumerate accented variants of an ASCII word.
# Length-changing collapses live in GERMAN_COLLAPSES below because they shorten
# the word; single-codepoint substitutions are tried position-by-position.
GERMAN_SINGLE_ACCENTS = {
    "a": "ä",  # ä
    "o": "ö",  # ö
    "u": "ü",  # ü
}

# Two-character sequences that collapse to a single German character. Mirrors
# `germanProfile.collapseRules` in DictusCore/Sources/DictusCore/Languages/German.swift
# one for one — the curation and the runtime expander must agree on what counts
# as a transliteration, or a word gets dropped here that the expander can never
# reconstruct (or the reverse, which is issue #326).
#
# `ae/oe/ue` are Umlautersatz: the ASCII convention Germans use where umlauts
# are unavailable — URLs, filenames, email addresses — and out of habit
# elsewhere. `fuer`, `koennen`, `schoen` are not German words in any context,
# only transliterations of `für`, `können`, `schön`, so the corpus counting them
# as vocabulary is corpus noise exactly like `uber` is.
#
# Real words that merely contain the sequence survive on the 5x rule below,
# without a second heuristic: their collapsed forms are not words, so no umlaut
# variant is found and nothing is dropped. `bauer` → `baür`, `feuer` → `feür`,
# `zueinander` → `zünander`, `poet` → `pöt`, `koexistenz` → `köxistenz` are all
# absent from the corpus.
GERMAN_COLLAPSES = {
    "ae": "ä",  # ae → ä   (Mädchen, Bäume, Universität)
    "oe": "ö",  # oe → ö   (können, schön, möchte)
    "ue": "ü",  # ue → ü   (Tür, müssen, fünf, früh)
    "ss": "ß",  # ss → ß   (straße, weiß, groß, Spaß)
}


def _umlaut_variants(word: str) -> list[str]:
    """All accent variants of `word` we want to compare against.

    Single-substitution at any position (a→ä, o→ö, u→ü), and each GERMAN_COLLAPSES
    two-character sequence collapsed anywhere in the word. Empty list if the
    input has no candidate positions, so callers can short-circuit.
    """
    variants: set[str] = set()
    chars = list(word)
    for i, ch in enumerate(chars):
        if ch in GERMAN_SINGLE_ACCENTS:
            variant = chars[:]
            variant[i] = GERMAN_SINGLE_ACCENTS[ch]
            variants.add("".join(variant))
    # Collapses, one occurrence at a time. Words needing two collapses at once
    # (`fuenfhundertdreissig`) are rare enough that the single-occurrence forms
    # already cover what the corpus contains, and enumerating combinations would
    # widen the drop set without a corresponding win.
    for i in range(len(word) - 1):
        replacement = GERMAN_COLLAPSES.get(word[i:i+2])
        if replacement:
            variants.add(word[:i] + replacement + word[i+2:])
    return sorted(variants)


def drop_ascii_duplicates_of_umlaut_words(freq_dict: dict[str, int]) -> dict[str, int]:
    """Remove `uber` if `über` exists with ≥ UMLAUT_DEDUP_MIN_RATIO higher freq.

    Operates only on ASCII-only inputs whose accent variants are present in the
    dict. Native ambiguous pairs (`schon`/`schön`) survive because the
    unaccented form dominates the umlaut form in real German usage.
    """
    dropped: list[tuple[str, int, str, int]] = []
    result: dict[str, int] = {}
    for word, count in freq_dict.items():
        if word.isascii():
            best_variant: tuple[str, int] | None = None
            for variant in _umlaut_variants(word):
                v_count = freq_dict.get(variant)
                if v_count is None:
                    continue
                if best_variant is None or v_count > best_variant[1]:
                    best_variant = (variant, v_count)
            if best_variant and best_variant[1] >= count * UMLAUT_DEDUP_MIN_RATIO:
                dropped.append((word, count, best_variant[0], best_variant[1]))
                continue
        result[word] = count

    if dropped:
        print(f"[INFO] Dropped {len(dropped)} unaccented duplicates of umlaut words "
              f"(ratio threshold: {UMLAUT_DEDUP_MIN_RATIO}x)")
        for word, c, variant, vc in dropped[:8]:
            print(f"       - {word!r} ({c}) << {variant!r} ({vc}) [{vc//max(c,1)}x]")
        if len(dropped) > 8:
            print(f"       ... and {len(dropped) - 8} more")
    return result


def download_hermitdave():
    """Download HermitDave de_50k.txt if not already present."""
    if os.path.exists(TXT_FILE):
        print(f"[INFO] Using existing {TXT_FILE}")
        return
    print(f"[INFO] Downloading HermitDave de_50k.txt from {HERMITDAVE_URL}...")
    urllib.request.urlretrieve(HERMITDAVE_URL, TXT_FILE)
    print(f"[INFO] Downloaded {os.path.getsize(TXT_FILE)} bytes")


def main():
    download_hermitdave()
    print("[INFO] Parsing de_50k.txt...")

    freq_dict = {}
    with open(TXT_FILE, "r", encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                word = parts[0].strip().lower()
                try:
                    count = int(parts[1])
                except ValueError:
                    continue
                if word and count > 0:
                    freq_dict[word] = count

    print(f"[INFO] Parsed {len(freq_dict)} words from de_50k.txt")

    # Drop ASCII-only false-friends of umlaut words BEFORE the 40K cap so the
    # cap fills with real entries instead of noise. See the module docstring
    # for the full rationale (autocorrect 5x-dominance interaction).
    freq_dict = drop_ascii_duplicates_of_umlaut_words(freq_dict)

    # Sort by count descending, take top 40,000
    sorted_words = sorted(freq_dict.items(), key=lambda x: -x[1])[:40000]
    result = {word: count for word, count in sorted_words}

    # Output
    output_path = os.path.abspath(OUTPUT)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, separators=(",", ":"))

    print(f"[DONE] Wrote {len(result)} entries to {output_path}")

    # Cleanup downloaded file
    if os.path.exists(TXT_FILE):
        os.remove(TXT_FILE)
        print(f"[INFO] Cleaned up {TXT_FILE}")


if __name__ == "__main__":
    main()
