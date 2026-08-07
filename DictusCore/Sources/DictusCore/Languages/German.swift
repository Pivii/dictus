// DictusCore/Sources/DictusCore/Languages/German.swift
// German language profile. First non-French/English/Spanish language onboarded
// via the LanguageProfile system. Override map and seed bigrams ship empty per
// ADR 0001 — the maintainer is non-native, populated post-launch from feedback.
import Foundation

/// German (`de`).
///
/// Layout: QWERTZ (#151) — dedicated ä/ö/ü keys, ß by long-press on `s`.
/// Overrides: empty per ADR 0001 (populated post-launch from native-speaker feedback on issue #109).
/// Contractions: empty — German `geht's`/`gibt's` style elisions are rare and not curated.
public let germanProfile = LanguageProfile(
    code: "de",
    displayName: "Deutsch",
    shortCode: "DE",
    defaultLayout: .qwertz,
    spaceName: "Leertaste",
    returnName: "Eingabe",
    overrides: [:],
    accentMap: [
        "a": ["\u{00E4}"],          // ä  (a-umlaut)
        "o": ["\u{00F6}"],          // ö  (o-umlaut)
        "u": ["\u{00FC}"]          // ü  (u-umlaut)
        // ß is reached via the collapseRules ss→ß below, not single-char
        // substitution — it would require deleting a position, which the
        // single-char accent substitution algorithm doesn't model. Long-press
        // on `s` is still wired via AccentedCharacters.mappings.
    ],
    contractionPrefixes: [],
    collapseRules: [
        // German Umlautersatz: standard ASCII transliterations Germans use where
        // umlauts are unavailable or unwanted — URLs, filenames, email addresses —
        // and out of habit anywhere else. They stay after #151 gave the layout real
        // ä/ö/ü keys: the keys removed the *need* to transliterate, not the habit,
        // and a user who still types `koennen` expects `können`. Each rule converts
        // the 2-char ASCII sequence to its single-char umlaut counterpart. The same
        // 5x-dominance protection as single-char accent expansion guards against
        // false positives like `bauer` (farmer) → `baür` (not a word, no false
        // correction).
        //
        // Without these rules, `tuer` → `tier` (animal, edit-distance 1) via
        // the trie's spell-check fallback instead of `Tür` (door).
        ("ae", "\u{00E4}"),         // ae → ä   (Mädchen, Bäume, Universität)
        ("oe", "\u{00F6}"),         // oe → ö   (können, schön, möchte)
        ("ue", "\u{00FC}"),         // ue → ü   (Tür, müssen, fünf, früh)
        // German ß: lets users get `straße`, `weiß`, `groß`, `Spaß`, `heißen`.
        // `muss` (valid post-1996-reform 1st/3rd-person form) is protected by
        // the 5x dominance rule against archaic `muß`.
        ("ss", "\u{00DF}")
    ]
)
