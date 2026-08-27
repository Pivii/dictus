# Per-Language Long-Press Accents

Long-press accent popups stay a single global union shared by every keyboard
language. They are not scoped per language.

## What this means in practice

`AccentedCharacters.mappings` maps a base letter to its accented variants, and
`accents(for:)` takes a key and nothing else — no language argument. A French
user long-pressing `n` sees `ñ`; a German user long-pressing `c` sees `ç`; every
user long-pressing `s` sees `ß`. The popup contents do not depend on which
language the keyboard is set to.

## Why this is out of scope

The migration was proposed on the grounds that Apple scopes popups per language
and that the union would become a mosaic as languages are added. Both were
reasonable in May 2026. Neither has produced a problem worth the change.

**The union is small.** At four keyboard languages (French, English, Spanish,
German) it is 9 base letters and 22 variants, with at most 4 variants on any one
key:

```swift
"e": ["é", "è", "ê", "ë"]      "c": ["ç"]
"a": ["à", "â", "ä", "á"]      "y": ["ÿ"]
"u": ["ù", "û", "ü", "ú"]      "n": ["ñ"]
"i": ["î", "ï", "í"]           "s": ["ß"]
"o": ["ô", "ö", "ó"]
```

That is fewer options than iOS itself shows on `a`. The predicted mosaic did not
arrive.

**Nobody complained.** `ß` was added to the global `s` popup by #109 in May 2026
and shipped to every language. Three months and a TestFlight cycle later there
is no report about it, on that or on any other cross-language variant. Weak
evidence rather than proof, but it is precisely the signal the May triage note
said it would decide on.

**Scoping makes code-switching worse.** The union's one real benefit is that a
French user citing *Spaß* reaches `ß` without switching keyboards. Per-language
maps take that away in exchange for removing characters nobody has objected to.

**And the language axis is the wrong place to add surface right now.** #272
decoupled keyboard layout from dictionary language and deliberately left
long-press accents alone. The design leans on the union: `FrenchAdaptiveKey`
documents that French-on-QWERTY has no adaptive accent key and that those users
"reach accents through the standard long-press popups, which already carry the
French set". Adding a per-language dependency here would cut against work that
has only just landed.

## When to reopen this

This is a decision for the current size of the product, not a permanent one.
Reopen when either of these becomes true:

- **A single base letter's variant list stops fitting one popup row.** That is
  the point where the union starts costing the user a scan rather than a glance.
- **A language with a large diacritic inventory onboards** — Polish (ą ę ć ł ń ó
  ś ź ż), Czech, Turkish, or similar. Polish alone would roughly double the
  table, and the arithmetic above stops holding.

At that point the middle path from the original issue becomes the likely answer:
a per-language map with the global union as an opt-in fallback for
code-switchers, rather than a straight migration.

## Related work that is not affected

- **#322** — Shift plus long-press `S` offering `SS` instead of `ẞ`. That is the
  uppercase transformation applied to candidates, not the candidate table, and
  it is being fixed independently.
- **#157's second half** — per-language `apostropheOverrides` for the French
  adaptive key. A separate concern, already handled by #272's language guard.

## Prior requests

- #157 — "Migrate AccentedCharacters.mappings to per-language LanguageProfile.longPressAccents" (2026-05-06)
