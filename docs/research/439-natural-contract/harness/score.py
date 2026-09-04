#!/usr/bin/env python3
"""Score a polish-harness `show` capture against #439's bars.

Usage:  python3 score.py <capture.txt> [<capture.txt> ...]

The bars are in ../bars.md and were committed before the first model call.
The predicates below are the machine-readable form of that document; if the two
ever disagree, bars.md is the one that was declared and this file is the bug.

`eval` already runs the fixture `expect` blocks, but it runs them once and
reports a fixture as a single pass/fail. #439 asks for a DISTRIBUTION over
repeated runs and for a count of repairs across fixtures ("at least 4 of the 6,
per run"), which is a cross-fixture aggregate no per-fixture check can express.
So this reads the raw `show --runs N` capture instead — the same bytes that get
committed as evidence.
"""

import re
import sys
from collections import defaultdict

# ── The six incoherent ASR segments #439 lists, one predicate each ────────────
# A repair counts when the broken form is gone AND, where a reconstruction can
# be named without over-specifying it, the intended form is present. Nothing
# below appears verbatim in any prompt: they are held out of the fix on purpose,
# so that a pass measures the rule rather than the example.
REPAIRS = [
    ("R1 salle à tante → salle d'attente", "3-message-draft",
     lambda t: "salle à tante" not in t and "salle d'attente" in t),
    # The broken form disappearing is NOT enough here: deleting the clause outright
    # satisfies "not in t" and would score as a repair. `rappelle` alone is no better
    # — the raw already contains an unrelated "il faut que je rappelle pour le truc
    # de la voiture", so a run that repairs nothing still matches it. What names the
    # repair is the reconstructed clause: `rappelle` ADJACENT to `comptable`.
    ("R2 je répète le comptable → rappelle", "5-rambling",
     lambda t: "répète le comptable" not in t
     and re.search(r"rappelle\s+(?:le\s+)?comptable", t, re.IGNORECASE) is not None),
    ("R3 si je les zappais → si je l'ai zappé", "5-rambling",
     lambda t: "les zappais" not in t and "zappé" in t),
    ("R4 le cas honnête → honnêtement", "5-rambling",
     lambda t: "honnêtement" in t),
    ("R5 Il prend ses morceaux → ces morceaux", "4-explanation",
     lambda t: "ses morceaux" not in t and "ces morceaux" in t),
    ("R6 Apple Store → App Store", "2-project-update",
     lambda t: "Apple Store" not in t and "App Store" in t),
]

# ── Register preserved (ADR 0003 Preserve), 0 occurrences tolerated ───────────
# The hour and number checks are here rather than under "deleted" because a
# format change is not a deletion: `11h` → `11 h` and `6 mois` → `six mois` keep
# the content and break the Preserve list's *"number formats like 19h stay"*.
# Classified during the baseline run, before any prompt was edited — see
# ../bars.md §4.1. No threshold moved.
REGISTER = [
    ("cela for ça", None, lambda t: "cela" not in t.lower()),
    ("added ne (c'est pas → ce n'est pas)", "6-unscripted",
     lambda t: "ce n'est pas vraiment ma voix" not in t and "c'est pas" in t),
    ("hour format expanded (11h → 11 h / 11 heures)", None,
     lambda t: not re.search(r"\b\d{1,2}\s+h(eures)?\b", t)),
    ("machin not substituted", "5-rambling", lambda t: "machine" not in t),
]

# Digits the speaker's transcript carried, which must not be spelled back out.
NUMBERS = {
    "1-free-form": ["6 mois", "15 trucs"],
    "2-project-update": ["412", "1000", "19"],
    "5-rambling": ["19 euros", "6 mois"],
}

# ── Dictated content deleted, 0 occurrences tolerated ─────────────────────────
# Spans the measured run dropped, plus the figures, names and the trailing
# sentence the same run kept: a deletion fix that costs one of those is not a fix.
# Matched case-insensitively — a proper noun the model failed to capitalize is a
# rule-2 miss, not a deletion, and #439 does not bar it.
KEEP = {
    "1-free-form": ["bosser", "trucs"],
    "2-project-update": ["StoreKit", "Thomas", "Sarah", "fin octobre"],
    "3-message-draft": ["dentiste", "t'arrange"],
    "4-explanation": ["en calcul", "trois étapes", "90"],
    # `comptable` is here so that deleting it reads as a violation rather than as a
    # silence. R2's predicate refuses to score the repair without it; this makes the
    # deletion itself visible in the run's violation list.
    "5-rambling": ["ça me reviendra", "Julien", "mardi", "février", "comptable"],
    "6-unscripted": ["Dictus", "gros pavé", "c'est pas"],
}

# ── Bar 4 (invented content) is NOT scored here, and that is deliberate ──────
# There is no predicate for "this sentence was not in the dictation" that does not
# either miss paraphrase or fire on it. Bar 4 is carried by `eval`: every fixture's
# `expect` block bounds `lengthRatioMax` at 1.15, which is what an invented clause
# breaks first, and the outputs are read. Anything this file prints is silent about
# bar 4 — do not read a clean run here as evidence for it.

# ── Scope fence (#437 owns line breaks; this round must not move them) ────────
# and the length band the guardrail enforces.
RATIO_MIN, RATIO_MAX = 0.92, 1.15


def parse(path):
    """Yield (fixture_id, run_index, raw, polished) from a `show` capture."""
    fixture = raw = None
    run = 0
    buf = None
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        m = re.match(r"━━ \[([^\]]+)\]", line)
        if m:
            fixture, run = m.group(1), 0
            continue
        if line.startswith("  raw:"):
            raw = line.split(":", 1)[1].strip()
            continue
        m = re.match(r"  polished(?: #(\d+))?: (.*)$", line)
        if m:
            run = int(m.group(1) or 1)
            buf = [m.group(2)]
            continue
        # The route line closes the polished block, which may span lines once
        # #437 lands and the model starts emitting breaks.
        if buf is not None and re.match(r" {12}\(", line):
            yield fixture, run, raw, "\n".join(buf)
            buf = None
            continue
        if buf is not None:
            buf.append(line)


def score(path):
    runs = defaultdict(dict)          # run index → fixture id → polished
    raws = {}
    for fixture, run, raw, polished in parse(path):
        runs[run][fixture] = polished
        raws[fixture] = raw

    print(f"\n══ {path}")
    repairs_per_run, violations_per_run = [], []
    for run in sorted(runs):
        outputs = runs[run]
        hits = [name for name, fx, ok in REPAIRS
                if fx in outputs and ok(outputs[fx])]
        violations = []
        for name, fx, ok in REGISTER:
            for fixture, text in outputs.items():
                if fx in (None, fixture) and not ok(text):
                    violations.append(f"register: {name} [{fixture}]")
        for fixture, needles in KEEP.items():
            for needle in needles:
                if fixture in outputs and needle.lower() not in outputs[fixture].lower():
                    violations.append(f"deleted: \"{needle}\" [{fixture}]")
        for fixture, needles in NUMBERS.items():
            for needle in needles:
                if fixture in outputs and needle not in outputs[fixture]:
                    violations.append(f"number reworded: \"{needle}\" [{fixture}]")
        for fixture, text in outputs.items():
            ratio = len(text) / len(raws[fixture])
            if not RATIO_MIN <= ratio <= RATIO_MAX:
                violations.append(f"ratio {ratio:.2f} [{fixture}]")
            if "\n" in text:
                violations.append(f"line break ×{text.count(chr(10))} [{fixture}]")
            if "<<NL>>" in text:
                violations.append(f"<<NL>> leak [{fixture}]")
        repairs_per_run.append(len(hits))
        violations_per_run.append(violations)
        print(f"  run {run}: repairs {len(hits)}/6 "
              f"({', '.join(h.split()[0] for h in hits) or 'none'}) · "
              f"violations {len(violations)}")
        for v in violations:
            print(f"      – {v}")

    n = len(repairs_per_run)
    if not n:
        return
    print(f"\n  ── repairs/6 over {n} runs: "
          f"min {min(repairs_per_run)} · median {sorted(repairs_per_run)[n // 2]} "
          f"· max {max(repairs_per_run)} · {repairs_per_run}")
    print(f"  ── runs clearing the ≥4/6 bar: "
          f"{sum(1 for r in repairs_per_run if r >= 4)}/{n}")
    print(f"  ── runs with 0 violations: "
          f"{sum(1 for v in violations_per_run if not v)}/{n}")
    per_repair = {name: sum(1 for run in sorted(runs)
                            if fx in runs[run] and ok(runs[run][fx]))
                  for name, fx, ok in REPAIRS}
    for name, hit in per_repair.items():
        print(f"     {name}: {hit}/{n}")


for arg in sys.argv[1:]:
    score(arg)
