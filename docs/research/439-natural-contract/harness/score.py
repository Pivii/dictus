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
    ("R2 je répète le comptable → rappelle", "5-rambling",
     lambda t: "répète le comptable" not in t),
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
REGISTER = [
    ("cela for ça", None, lambda t: "cela" not in t.lower()),
    ("added ne (c'est pas → ce n'est pas)", "6-unscripted",
     lambda t: "ce n'est pas vraiment ma voix" not in t and "c'est pas" in t),
    ("19h/11h/14h not expanded", None,
     lambda t: not re.search(r"\b\d{1,2} heures\b", t)),
    ("machin not substituted", "5-rambling", lambda t: "machine" not in t),
]

# ── Dictated content deleted, 0 occurrences tolerated ─────────────────────────
# Spans the measured run dropped, plus the figures/names/trailing sentence the
# same run kept: a deletion fix that costs one of those is not a fix.
KEEP = {
    "1-free-form": ["bosser", "trucs", "6 mois"],
    "2-project-update": ["StoreKit", "Thomas", "Sarah", "412", "1000", "14h", "fin octobre"],
    "3-message-draft": ["11h", "dentiste", "t'arrange"],
    "4-explanation": ["en calcul", "trois étapes", "90"],
    "5-rambling": ["ça me reviendra", "19 euros", "Julien", "mardi", "février"],
    "6-unscripted": ["Dictus", "gros pavé", "c'est pas"],
}

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
                if fixture in outputs and needle not in outputs[fixture]:
                    violations.append(f"deleted: \"{needle}\" [{fixture}]")
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
