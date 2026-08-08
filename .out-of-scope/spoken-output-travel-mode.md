# Spoken Output and Travel / Conversation Mode

Dictus does not speak. Text-to-speech output, and the travel or conversation
product it implies, are out of scope.

## Why this is out of scope

Dictus is a keyboard extension. Its output is text inserted into whatever app
the user is already in. Speaking a result aloud is not a variant of that — it is
a different kind of output, and there is no surface in the product that can
carry it.

The keyboard cannot carry it. It runs under a ~50 MB ceiling and owns no audio
session; recording itself had to be moved into DictusApp for exactly that
reason, and the cross-process machinery that move required is the source of a
long tail of issues (#249, #260, #261, #262). Adding audio *output* to the
extension would mean rebuilding that machinery in the opposite direction, for a
feature that plays sound while the user is typing in someone else's app.

DictusApp could technically speak. But in that scenario the user is looking at
DictusApp, not typing — so the keyboard, which is the entire product, is not
involved. What is being built at that point is a conversation app.

And a travel conversation app is not an increment on a dictation keyboard. It
needs the round trip in both directions, a two-sided interface, and speaker and
microphone handover between two people. Apple ships that in Translate: free,
on-device, preinstalled on every target device. Meeting it head-on from a
dictation keyboard has no winning path.

## What is in scope, and where it lives

The *translation* half of the original request is a real Dictus feature and it
already has an owner. **#79 (Smart Modes)** ships `Translate → X` as a
first-class entry in the v1 mode catalogue, alongside Notes and Email, with the
design settled: a flat entry in the mode list rather than a sub-menu, a prompt
that names its target language, and validation through
`detectedLanguageMatches(polished:target:)` — the one mode where the output
language check becomes an asset, because it catches the model failing to
translate at all.

So Dictus translates. It renders the result as text, into the user's keyboard,
like everything else it does. It does not read it out.

## If this is reconsidered

The decision turns on what Dictus is, not on effort. If the product direction
ever becomes a voice companion rather than a keyboard, this file should be
deleted and the request re-triaged from scratch — the reasoning above would no
longer apply, because its whole premise is that text insertion is the only
output.

## Prior requests

- #111 — "Explore translated text-to-speech / travel mode for Dictus" (2026-04-13)
