#!/usr/bin/env python3
"""Turn a BackspaceProbe log into the deletion timeline quoted in findings.md.

    python3 timeline.py ../raw/apple-control-plainfield-12s.log

One row per edit the keyboard issued into the field: milliseconds since the first
deletion, the gap from the previous one, and the range it replaced. `len=1` is a
character deletion, `len>1` a word deletion, `len=0` a delete the host had nothing
to apply -- which is the shape #419 calls "the repeat keeps ticking in an empty
field".
"""
import sys


def main(path: str) -> None:
    events = []
    for line in open(path):
        parts = line.rstrip("\n").split("\t")
        events.append((float(parts[0]), parts[1], parts[2:]))

    edits = [(t, rest) for t, kind, rest in events if kind == "shouldChange"]
    if not edits:
        print("no edits in this log")
        return

    t0 = edits[0][0]
    print(f"{'t(ms)':>9} {'gap':>7}  edit")
    previous = None
    for t, rest in edits:
        gap = "" if previous is None else f"{t - previous:7.1f}"
        previous = t
        print(f"{t - t0:9.1f} {gap}  {' '.join(rest)}")

    emptied = [t - t0 for t, kind, rest in events
               if kind == "didChange" and rest and rest[0] == "len=0"]
    print()
    print(f"edits: {len(edits)}")
    if emptied:
        print(f"field emptied at {emptied[0]:.1f} ms")
        after = [t - t0 for t, _, _ in events if t - t0 > emptied[0]]
        print(f"events after it emptied: {len(after)}")
    print(f"last event at {events[-1][0] - t0:.1f} ms")


if __name__ == "__main__":
    main(sys.argv[1])
