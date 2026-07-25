// DictusCore/Sources/DictusCore/Languages/French.swift
// French language profile. Mirrors the data previously hardcoded in
// AOSPTrieEngine and SupportedLanguage; behavior must be byte-identical
// pre/post the LanguageProfile refactor.
import Foundation

/// French (`fr`) — Dictus's default and most-used language.
public let frenchProfile = LanguageProfile(
    code: "fr",
    displayName: "Fran\u{00E7}ais",
    shortCode: "FR",
    defaultLayout: .azerty,
    spaceName: "espace",
    returnName: "retour",
    overrides: [
        // Common unambiguous accent-missing words. These are NOT valid French without accents.
        // Excluded: "a"/"à" (both valid), "ou"/"où" (both valid), "meme" (could be English)
        "ca": "\u{00E7}a",                       // ca -> ça
        "tres": "tr\u{00E8}s",                   // tres -> très
        "apres": "apr\u{00E8}s",                 // apres -> après
        "deja": "d\u{00E9}j\u{00E0}",            // deja -> déjà
        "ete": "\u{00E9}t\u{00E9}",              // ete -> été
        "etre": "\u{00EA}tre",                   // etre -> être
        "voila": "voil\u{00E0}",                 // voila -> voilà
        "bientot": "bient\u{00F4}t",             // bientot -> bientôt
        "plutot": "plut\u{00F4}t",               // plutot -> plutôt
        "probleme": "probl\u{00E8}me",           // probleme -> problème
        "systeme": "syst\u{00E8}me",             // systeme -> système
        "etait": "\u{00E9}tait",                 // etait -> était
        "etaient": "\u{00E9}taient",             // etaient -> étaient
        "evenement": "\u{00E9}v\u{00E9}nement",  // evenement -> événement
        // Missed-apostrophe contractions colliding with rare-but-real dictionary
        // words. Without an override, the valid-word guard protects the rare word
        // and the contraction never fires ("je lai vu" stays broken). The rare
        // legitimate uses (a medieval "lai", nautical "lest") lose to the
        // overwhelmingly more frequent contraction (#222).
        // Excluded: "louvre" (l'ouvre) — the override lookup re-capitalizes, so
        // it would corrupt "Louvre" (the museum) into "L'ouvre".
        "lai": "l'ai",                           // lai -> l'ai (je l'ai vu)
        "lest": "l'est",                         // lest -> l'est (il l'est)
    ],
    accentMap: [
        "e": ["\u{00E9}", "\u{00E8}", "\u{00EA}", "\u{00EB}"],  // é, è, ê, ë
        "a": ["\u{00E0}", "\u{00E2}"],                          // à, â
        "i": ["\u{00EE}", "\u{00EF}"],                          // î, ï
        "o": ["\u{00F4}"],                                      // ô
        "u": ["\u{00F9}", "\u{00FB}", "\u{00FC}"],              // ù, û, ü
        "c": ["\u{00E7}"],                                      // ç
    ],
    contractionPrefixes: [
        // 1-character prefixes (l', d', c', j', n', s', m', t')
        "l'", "d'", "c'", "j'", "n'", "s'", "m'", "t'",
        // 2-character prefix (qu')
        "qu'",
    ]
)
