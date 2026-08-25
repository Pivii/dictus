# Apple's held-backspace timeline, measured (#419)

Apple documents none of this. It is observable behaviour only, so it was measured
rather than inferred, following this repo's precedent of measuring the platform
(the Apple German keyboard work).

**Where:** iPhone 17 Pro simulator, iOS 26.5, Xcode 26.4.1, headless, 2026-08-25.
**Against:** Apple's own French (AZERTY) software keyboard.
**Raw samples:** `raw/`. **Harness:** `harness/`. Timelines below are reproducible with
`python3 harness/timeline.py raw/<file>`.

Everything here is a **simulator** measurement. Cadences are timer-driven and should
carry over, but nothing below was confirmed on a physical iPhone.

## Why the accessibility tree was not the instrument

The issue proposed sampling the field's value from `axe describe-ui` every ~50 ms.
Measured, that is not available:

- **One `describe-ui` round trip costs 260-310 ms** (six runs: 790, 300, 280, 310,
  270, 260 ms; the first is cold). Under a concurrent held touch the loop actually
  achieved **330-660 ms per sample** -- see `raw/a11y-sampling-safari-address-bar.tsv`,
  26 samples over 10.8 s. At a 100 ms deletion cadence one sample straddles three to
  six deletions.
- **The value can be truncated.** Safari's address field reported a 177-character
  `AXValue` for content that was longer.
- **It cannot see the question the issue is really asking.** A repeat tick that
  deletes nothing changes no value, and "does the repeat keep firing in an empty
  field" is exactly a question about ticks that delete nothing.

So the host was instrumented instead: `harness/BackspaceProbe.swift`, a one-screen app
whose text view logs, on a monotonic millisecond clock, every mutation a keyboard
issues into it -- including `deleteBackward()` calls that delete nothing.

**Control arm.** `-plainField 1` swaps the instrumented subclass for a stock
`UITextView` that overrides nothing. The two arms produced the same range sequence and
the same total (254 characters emptied in 9.15 s vs 9.18 s), so the instrumentation
observed the behaviour rather than altering it. Compare
`raw/apple-instrumented-12s.log` with `raw/apple-control-plainfield-12s.log`.

## The timeline

Seed text, 254 characters, cursor at the end, varied word lengths, with a period, a
double space and a hyphenated word placed where word mode would reach them:

```
alpha bravo charlie. delta  echo foxtrot-golf hotel india juliet kilo lima mike
november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee
zulu one two three four five six seven eight nine ten eleven twelve ZZZZZ...(25)
```

From `raw/apple-control-plainfield-12s.log`, times relative to the touch-down deletion:

```
       0 ms   1 character      <- fires on touch-down, before any repeat
     500 ms   1 character      <- the repeat begins
     616 ms   1 character
     716 ms   1 character
       ...    20 character deletions in all, every 100 ms
    2 416 ms   1 character     <- the last character deletion
    2 517 ms   11 characters   <- word mode, arriving on the next 100 ms tick
    2 875 ms   11 characters   <- and from here the cadence is ~350 ms
    3 226 ms   11 characters
       ...
    9 175 ms   6 characters    <- the field is now empty
   (nothing at all for the remaining 2.8 s of the hold)
```

### Every question the issue asked

| Question | Measured answer |
| --- | --- |
| Initial pause before any repeat | **500 ms** (500.2 instrumented, 499.6 control) |
| Character cadence | **100 ms**, 20 ticks; range 98.6-101.3 ms |
| Does the character cadence accelerate? | **No.** Flat 100 ms for the whole 2 s. The only gear change is the switch to word mode. |
| When does word mode start? | On the **21st repeat tick**, i.e. after 20 character repeats plus the touch-down deletion = **21 characters**, **2.5 s** after touch-down. Whether the trigger is the count or the elapsed time **cannot be distinguished** from this data: the cadence is fixed at 100 ms, so 20 ticks and 2.0 s are the same event. |
| Cadence in word mode | **~350 ms** (345.7-358.6, mean 350.0 over 20 intervals). The first word deletion arrives on the normal 100 ms tick; the new cadence starts after it. |
| Is there a pause between word deletions? | Yes -- that 350 ms gap *is* the pause. This matches the maintainer's "spaced waves"; he estimated half a second, it measures a third. |
| Does a word deletion take the trailing space, the punctuation, both? | It takes the **whitespace run and the word**, and punctuation attached to the word goes with it. `"delta  "` (double space) went in one edit of 7. `"charlie. "` went in one edit of 9 -- the period was not a separate step. A **hyphen is a boundary**: `foxtrot-golf` was removed as `"golf"` then `"foxtrot-"`. |
| **Does Apple stop the repeat when the field empties?** | **It stops.** Two independent runs: after the last deletion emptied the field, **no further event of any kind** arrived for the remaining 2.8 s (control) and 3.6 s (instrumented) of the hold. And holding backspace in an **already empty** field produced **exactly one** `deleteBackward` (the touch-down one) and then nothing for 6 s -- `raw/apple-empty-field-6s.log`. The repeat never starts when there is nothing to delete. |

### One measured detail that is not being copied

Each ~350 ms word-mode tick removed **two** word-units, 5-7 ms apart, not one: the tick
at 2 517 ms removed `"ZZZZ"` then `"twelve "`, the next removed `"eleven "` then
`"ten "`. Both arms agree, so it is not an artefact of the instrumentation. Apple
therefore destroys about 5.7 words per second in word mode.

The fix deliberately does **not** copy this, and removes one word-unit per wave
(~2.9 words/s). The complaint that opened #419 is lost text, the maintainer asked for
waves about half a second apart, and one word per wave at 350 ms is the conservative
reading of that. Matching Apple exactly is a one-line change if he prefers it.

## Dictus before the fix, same harness, same hold

`raw/dictus-before-12s.log`, our keyboard at `e41f4c3`:

```
       0 ms   1 character      <- touch-down
     500 ms   1 character      <- repeat begins  (matches Apple)
       ...    10 character deletions, every 100 ms  (Apple: 20)
   1 405 ms   1 character
   1 502 ms   14 characters    <- word mode, 1.0 s earlier than Apple
   1 607 ms   7 characters     <- and every 100 ms, not every 350 ms
   1 710 ms   7 characters
       ...
   5 209 ms   the field is empty
   5 304 ms   len=0            <- and then 73 more ticks, 100 ms apart,
       ...                        each one a haptic and a click for a
  12 604 ms   len=0               deletion that deletes nothing
```

Two numbers say the whole issue:

- **The field is destroyed in 5.2 s where Apple takes 9.2 s** -- 1.76x faster, at
  10 words per second against Apple's 5.7, with no pause between waves.
- **73 ticks into an empty field.** Each one reaches a live proxy, so
  `didTriggerRepeat` reports a deletion and the tick fires its haptic and its click
  (`KeyboardView.swift`). That is complaint #2, and the count is the measurement.

## What could not be measured here

- **Haptics.** Unobservable off-device, in every run. Every claim about a vibration in
  this document and in the PR is a claim about which code path runs, and is labelled
  as one.
- **A secure field served by our extension.** iOS **did not offer Dictus at all** to a
  host app that merely had a secure `UITextField` in its hierarchy -- measured: with
  the field mounted, the globe menu listed only Français, English and Emoji; with the
  same build and the field not mounted, Dictus appeared. So no case could be
  constructed here in which our keyboard serves a secure field, and the acceptance
  criterion about secure fields was **not exercised**. The code is written so that it
  holds regardless -- see the predicate's comment in `DictusKeyboardBridge`.
- **Device timing.** Simulator cadences on a Mac, not an iPhone 15 Pro Max.

## Harness notes for whoever runs this next

- `axe type` into Safari left the software keyboard suppressed for every app: the
  field kept first responder and the accessibility tree reported the keyboard sitting
  just below the screen. Only a device reboot restored it. `ConnectHardwareKeyboard`
  was already `false` and was not the cause.
- A held press needs a single `axe batch` (`touch --down` / `sleep` / `touch --up`).
  The release does land on a UIKit keyboard: a 4 s hold produced its last deletion at
  4 257 ms and nothing afterwards (`raw/apple-release-4s.log`).
- The Dictus keyboard's keys are **not in the accessibility tree** -- only the system
  globe and dictation buttons are. Its delete key has to be tapped by coordinate, read
  off a screenshot.

## Dictus after the fix, same harness, same hold

Verified on the same simulator, same seed text, same 12 s hold at the same
coordinate. `raw/dictus-after-12s.log`:

```
       0 ms   1 character      <- touch-down
     505 ms   1 character      <- repeat begins        (Apple: 500)
       ...    20 character deletions, every ~100 ms    (Apple: 20, 100 ms)
   2 402 ms   1 character
   2 503 ms   4 characters     <- word mode            (Apple: 2 517 ms)
   2 854 ms   7 characters     <- and every ~350 ms    (Apple: ~350 ms)
       ...    343.8-356.4 ms across 28 intervals
  12 303 ms   5 characters     <- still 65 characters left when the finger lifts
```

The same 12 s hold that used to leave the field empty after 5.2 s and then tick
73 more times now leaves 65 of the 254 characters standing. Our keyboard's own log
counts it in one line each way (`raw/dictus-keyrepeat-events.txt`):

```
keyRepeatStopped ticks=122 reason=touch            <- before
keyRepeatStopped ticks=49  reason=touch            <- after
```

### The empty field, and the case that reverted the last attempt

| Case | Before | After | Apple |
| --- | --- | --- | --- |
| Field empties mid-hold (`dictus-after-empties-midhold.log`) | 73 further ticks over 7.4 s | stops on the tick that finds it empty, `ticks=23 reason=documentEmpty`, nothing for the remaining 9 s | stops |
| Hold on an already empty field (`dictus-after-empty-from-start.log`) | ticked for the whole hold | one delete on touch-down, then nothing for 8 s, `ticks=1 reason=documentEmpty` | one delete on touch-down, then nothing for 6 s |
| **Select all, then tap backspace** (`dictus-after-selectall-tap.log`) | deletes | **deletes** -- one edit, `loc=0 len=19`, the whole selection | n/a |
| **Select all, then hold backspace** (`dictus-after-selectall-hold.log`) | deletes | **deletes** the selection on touch-down, then the now-empty field stops the repeat | n/a |

The select-all rows are the ones that matter: the selection is anchored at offset 0,
so the before-context is empty throughout, and the guard let the deletion through
anyway. That is `selectedText` doing the job the context alone could not.

### #390 still holds

Held backspace, host app terminated mid-hold, from `raw/dictus-keyrepeat-events.txt`:

```
keyRepeatStarted
keyRepeatStopped ticks=22 reason=windowDetached
```

The repeat died with the view rather than outliving it. None of #390's teardown paths
were touched; the `unavailable` outcome preserves its behaviour exactly.
