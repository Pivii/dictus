# #80 — custom vocabulary: the replayable corpus

The test bench for the deterministic replacement pass (#80 decision 12). Committed,
versioned, and replayable by anyone on any Mac — it drives no model and needs no
Apple Intelligence.

## Replaying it

```bash
cd DictusCore
swift run polish-harness vocabulary ../docs/research/80-vocabulary/corpus.json
```

It exits non-zero on any case whose output differs from the committed expectation,
or on any case where a second application of the pass changes the result. As of
2026-09-07: **14/14 correct, 14/14 idempotent.**

## What is in the file, and what is not

Each record is a vocabulary, a transcript, and the text the pass must produce from
it. `covers` names the matching rules the case exercises; the harness prints the
union of them so the acceptance criteria can be checked without reading every
record.

**Every case committed on 2026-09-07 carries `"origin": "constructed"`, and none of
them is a real mis-transcription.** That is a limitation of this file, not a
shortcut around one.

The issue records the measurement behind it: the available polish debug exports hold
**182 raw/polished pairs**, and a scan showed them to be overwhelmingly *polish*
rewrites — added connectors, grammar — rather than the engine mangling technical
terms, because the captures are ordinary French speech. The corpus decision 13 asks
for — harvested from real captures, then sanitised, keeping the error pair and
rewriting the carrier sentence neutral — **cannot be mined from what already
exists**. It needs a deliberate capture session, on a device, which no agent can run.

So the cases here are constructed from the matching rules the issue names. They are
worth what a unit test is worth: they prove the pass does what it was specified to
do. They do **not** prove the specification matches what the engines actually
produce, and no reader should take them for evidence that it does.

## The capture session that is still owed

Run by the maintainer, on a device, and the result appended to `corpus.json` with
`"origin": "captured"`.

1. Settings → enable the polish debug capture, so raw transcripts are written down.
2. Pick 15–20 technical terms that matter in real use: product names, colleagues'
   surnames, library names, company names. Mix French and English ones.
3. Dictate each one **inside an ordinary sentence**, not alone — an isolated word
   gives the engine no context and is not the case the feature serves.
4. Do it twice: once with Parakeet active, once with a Whisper model. The two
   engines mangle differently, and the issue's whole argument is that the fix must
   not depend on which one is running.
5. Export the debug log and read the raw transcripts. For every term the engine got
   wrong, record the pair: what you said, what it wrote.
6. **Rewrite the carrier sentence to neutral content**, keeping the error pair
   intact. No maintainer personal content enters this public repo — no real
   colleague names, no client names, no private facts.
7. Add each as a record with `"origin": "captured"` and a `note` saying which engine
   produced it.

What that session answers, and this corpus cannot: whether the variants users would
actually type are the variants the engines actually produce, and whether a single
canonical spelling plus a handful of variants is enough coverage per term.

## Shape

```json
{
  "source": "constructed-2026-09-07",
  "fixture": "V1-mangled-technical-term",
  "origin": "constructed",
  "note": "what this case is for",
  "covers": ["mangled technical term", "mid-sentence"],
  "entries": [{ "term": "Kubernetes", "variants": ["cubernetes"] }],
  "raw": "what the engine produced",
  "expected": "what the pass must produce"
}
```

`isEnabled` is optional on an entry and defaults to true, which is what the add sheet
produces. The decoder is `VocabularyCorpus` in `DictusCore/Sources/polish-harness/`.
