#!/usr/bin/env python3
"""Score a polish-harness `show` capture against the bars pre-registered in
docs/research/414-prompt-examples.md (#414).

Deterministic, and a SCREEN rather than a verdict for P1/P2: every hit it prints
is meant to be read before it is counted, because a word can appear in a prompt
example and in an output for no reason other than that both are French.

    python3 docs/research/414-prompt-examples/score.py raw/A-shipping-5runs.txt \
                                                       prompts/A-shipping.txt
"""
import json, re, sys, unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
MARKERS = "-–—*•·"
# Person names appearing in any candidate prompt's examples. P1 counts only these.
PERSON_NAMES = {"sophie"}
STOP = set("""le la les un une des de du au aux et ou a à il elle je tu on nous vous ils elles
ce cet cette ces qui que quoi dont où pas ne plus moins pour par sur dans avec sans sous entre
est sont être avoir faire fait suis es sommes êtes ai as avons avez ont mon ma mes ton ta tes son
sa ses notre nos votre vos leur leurs y en si comme mais donc or ni car quand alors puis très
the a an of to in on for and or is are be it this that with from at as i we you they will
""".split())


def fold(s):
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c))


def words(s):
    return set(w for w in re.split(r"[^0-9a-zà-öø-ÿ]+", fold(s)) if len(w) > 2 and w not in STOP)


def grounded(word, inputs):
    """Is `word` supported by the input, allowing for inflection?

    A shared 5-character stem, not equality. Rule 1 of the prompt turns a spoken
    verb into an infinitive, so an input saying `j'appelle` legitimately produces
    an output saying `Appeler`, and counting that as copied example content would
    bury the signal under conjugation. Deliberately generous: this is a screen
    whose job is to keep the hand-read list short, and a miss here is caught by
    reading the outputs, which is done anyway.
    """
    if word in inputs:
        return True
    stem = word[:5]
    return any(i[:5] == stem for i in inputs if len(i) >= 5) and len(word) >= 5


def parse(path):
    """(fixture, run, raw, output, outcome) for every call in a `show` capture."""
    out, fx, raw, cur = [], None, None, None
    def flush():
        nonlocal cur
        if cur:
            out.append(dict(fixture=fx, run=cur[0], output="\n".join(cur[1]).strip(),
                            outcome=cur[2], raw=raw))
            cur = None
    for line in Path(path).read_text(encoding="utf-8").split("\n"):
        m = re.match(r"^━━ \[(.+?)\]", line)
        if m: flush(); fx = m.group(1); continue
        m = re.match(r"^  raw:\s+(.*)$", line)
        if m: flush(); raw = m.group(1); continue
        m = re.match(r"^  (polished|engineOut) ?#?(\d*): (.*)$", line)
        if m: flush(); cur = (int(m.group(2) or 1), [m.group(3)], None); continue
        m = re.match(r"^ {12}\((\w+),", line)
        if m and cur: cur = (cur[0], cur[1], m.group(1)); flush(); continue
        if line.startswith(("── outcomes", "Building", "Build of", "[")): flush(); continue
        if cur and line.strip(): cur[1].append(line)
        elif cur: flush()
    flush()
    return [c for c in out if c["output"] and not c["output"].startswith("<refused")]


def example_words(prompt_path):
    """Content words in every piece of example material the prompt shows.

    Worked examples AND counter-examples. Scoping this to the worked examples was
    a real mistake and it hid a real finding: candidate C removes the worked
    examples, so its screen matched nothing, while the model simply copied
    `- Rappeler le client cette semaine` out of the COUNTER-example instead. The
    model does not know which block a line came from — it copies what it was
    shown.
    """
    text = Path(prompt_path).read_text(encoding="utf-8")
    marks = [m for m in ("Examples —", "Short-input example", "COUNTER-EXAMPLES") if m in text]
    if not marks:
        return set()
    return words(text[text.index(marks[0]):])


def is_bullet(line):
    return line.strip()[:1] in MARKERS or re.match(r"^\s*\d{1,3}[.)]", line)


def main(capture, prompt):
    calls = parse(capture)
    ex = example_words(prompt)
    accepted = [c for c in calls if c["outcome"] == "success"]
    p1 = p2 = 0
    p1_hits, p2_hits = [], []
    for c in calls:
        inp = words(c["raw"])
        for w in words(c["output"]) & ex:
            if grounded(w, inp):
                continue
            tag = f"{c['fixture']}#{c['run']} [{c['outcome']}] {w!r}"
            if w in PERSON_NAMES:
                p1 += 1; p1_hits.append(tag)
            else:
                p2 += 1; p2_hits.append(tag)

    shaped = sum(1 for c in accepted
                 if c["output"].splitlines() and all(is_bullet(l) for l in c["output"].splitlines() if l.strip()))
    n4 = [c for c in accepted if c["fixture"] == "N4-une-idee"]
    n4_one = sum(1 for c in n4 if len([l for l in c["output"].splitlines() if l.strip()]) == 1)
    titled = sum(1 for c in accepted if c["output"].splitlines() and not is_bullet(c["output"].splitlines()[0]))
    bracket = sum(1 for c in accepted if re.search(r"\[[^\]]*\]", c["output"]))

    print(f"\n══ {Path(capture).name}   ({len(calls)} outputs, {len(accepted)} accepted)")
    print(f"  P1  person name from an example, absent from the input : {p1}")
    for h in p1_hits: print(f"        {h}")
    print(f"  P2  other example content word, absent from the input  : {p2}")
    for h in p2_hits[:12]: print(f"        {h}")
    if len(p2_hits) > 12: print(f"        … and {len(p2_hits) - 12} more")
    print(f"  P3  accepted outputs that are entirely bullets         : {shaped}/{len(accepted)}")
    print(f"  P4  N4 (one idea) answered with exactly one bullet     : {n4_one}/{len(n4)}")
    print(f"  P5  title line {titled}, bracketed placeholder {bracket}   (both must be 0)")
    print(f"  --  guardrail success rate (reported, not gated)       : {len(accepted)}/{len(calls)}")


def summary(pairs):
    """The headline table: how many OUTPUTS carried copied example content.

    Counted per output rather than per word, because one copied bullet trips
    several words and the question is how often a user receives a fabricated
    line, not how many syllables it had.
    """
    print(f"\n{'candidate':26s} {'set':17s} {'affected':>9s} {'accepted':>9s}  {'shape':>7s}")
    for capture, prompt in pairs:
        calls = parse(capture)
        ex = example_words(prompt)
        accepted = [c for c in calls if c["outcome"] == "success"]
        affected, affected_ok = set(), set()
        for c in calls:
            inp = words(c["raw"])
            if any(not grounded(w, inp) for w in words(c["output"]) & ex):
                affected.add((c["fixture"], c["run"]))
                if c["outcome"] == "success":
                    affected_ok.add((c["fixture"], c["run"]))
        shaped = sum(1 for c in accepted
                     if c["output"].splitlines()
                     and all(is_bullet(l) for l in c["output"].splitlines() if l.strip()))
        name = Path(capture).stem
        cand, _, which = name.partition("-5runs") if "-5runs" in name else name.partition("-n2stress")
        print(f"{cand:26s} {('n2 stress' if 'n2stress' in name else 'six fixtures'):17s} "
              f"{len(affected):4d}/{len(calls):<4d} {len(affected_ok):4d}/{len(accepted):<4d}  "
              f"{shaped:3d}/{len(accepted):<3d}")


if __name__ == "__main__":
    if sys.argv[1] == "--summary":
        here = Path(__file__).resolve().parent
        pairs = []
        for candidate in ["A-shipping", "B-neutralised", "C-no-worked-examples", "D-neutralised-both"]:
            for suffix in ["5runs", "n2stress-30runs"]:
                capture = here / "raw" / f"{candidate}-{suffix}.txt"
                if capture.exists() and "outcomes" in capture.read_text(encoding="utf-8"):
                    pairs.append((capture, here / "prompts" / f"{candidate}.txt"))
        summary(pairs)
    else:
        main(sys.argv[1], sys.argv[2])
