# Smart Mode visual coherence — colour and fan layout

Design proposal following device testing of the #79 long-press fan on an iPhone 15 Pro Max,
2026-08-24. Two questions were raised: the purple armed-mode pill, and whether the fan should
become a 2-column grid.

Sources: `assets/brand/dictus-brand-kit.html`, issue #79, and the implementation on
`feature/79-smart-modes-keyboard` (`SmartModeFanView.swift`, `ToolbarView.swift`,
`AnimatedMicButton.swift`, `SmartModeFanLayout.swift`, `SmartModeCatalogue.swift`).
Nothing here has been implemented.

---

## Recommendations, first

**Colour.** Keep the mic pill blue in every resting state. Move the armed signal from the
pill's *fill* to the pill's *ring*, and keep it `#8B5CF6`. One stroke colour changes; the fill
never does. Reject the grey-Normal / blue-Smart-Mode inversion, and reject per-mode blues.

**Layout.** Keep the single column and `maximumPinnedModes = 3`. The spare width is not a
resource this gesture can spend: the mic is anchored top-right, so a second column sits at the
far end of the thumb's reach arc, and the seam between columns is a new place to arm the wrong
mode silently. Spend the visual budget instead on giving the fan a surface — the measured
problem in both screenshots is that the host app's text is legible *through* the rows.

---

## 1. The colour

### What is on screen today

`AnimatedMicButton` takes a `tint` and uses it as the pill's fill. `ToolbarView.micPill` passes
`.dictusSmartMode` when a mode is armed. So the armed signal is 56 × 36 pt of `#8B5CF6` at full
saturation — the largest filled surface anywhere in the keyboard, and permanent, because the
mode is sticky.

Every other purple in the feature is already quiet:

| Surface | Purple dose |
|---|---|
| Fan row highlight (a mode) | `#8B5CF6` @ 0.22 capsule fill, purple label |
| Toolbar armed-mode label, priority 4 | 13 pt purple text + `sparkles` glyph |
| Recording overlay badge | 14 pt purple text on `#8B5CF6` @ 0.14 |
| **Mic pill, armed** | **`#8B5CF6` @ 1.0, 2016 pt², permanent** |

The complaint is caused by exactly one of these four.

### Why the brand kit naming it is not the same as it belonging

Occurrence count in `dictus-brand-kit.html`: `#6BA3FF` × 10, `#2563EB` × 10, `#0D2040` × 10,
`#071020` × 9, `#0F3460` × 7, `#3D7EFF` × 3, `#8B5CF6` × 3. All three purple occurrences are in
the state-badge block and the state token table — a 6 pt dot and a table row. The kit assigns
purple a *meaning*; it has never assigned it a *surface*. The observation that a full-strength
purple pill reads as foreign is correct, and it is not a failure of the token. It is a dose
problem.

### Why the grey-Normal proposal is worse than what exists

Three reasons, in descending strength.

**1. It collides with an existing state.** Dictus already renders a grey/faded mic and it means
"you cannot dictate": `fullAccessBar` draws the pill at `.opacity(0.4)`, and
`MicButtonDisabled.swift` exists for the same purpose. A grey resting mic is one visual step
from the disabled mic, and the state it would name is the one 100% of users are in 100% of the
time before they ever buy Pro. The default state must not look broken.

**2. It demotes the only primary control in the bar.** Every other toolbar control is glass plus
`dictusPillIconSecondary` — deliberately 50% strength, and `DictusColors.swift` says why:
"Full-strength icons compete with the mic and the validate button, which are the primary actions
in their respective bars." The mic is the exception that the rest of the bar is calibrated
against. Removing its colour does not make it quieter; it removes the reference point that makes
everything else read as secondary.

**3. It inverts what the colour means.** Today blue means "ready to dictate". Under the proposal
grey means "ready to dictate" and blue means "ready to dictate differently". The saturated state
becomes the rarer one, which is backwards for a signal whose job is to say *this control is the
thing you came here for*.

**Per-mode blues, separately: reject.** Two blues are only distinguishable when they are adjacent
for comparison, and these never are — one pill is on screen at a time, seen peripherally,
through a translucent keyboard, over an arbitrary host background. `#3D7EFF` and `#2563EB`
differ by 0.10 in relative luminance; that is not a signal, it is a coincidence the user will
never decode. If the mode's identity needs to be readable, the mode's *name* is already on
screen at priority 4 and in the recording overlay. Names scale to six modes; blues do not scale
to two.

### What to do instead

`AnimatedMicButton` already draws a ring behind the pill — 66 × 46 pt, currently stroking
`.dictusAccent` at an opacity breathing 0.3 → 0.6 over 2 s. Turn *that* purple when a mode is
armed and leave the fill alone.

This works for four reasons that are specific to this button, not general taste:

- **The dose drops by roughly an order of magnitude.** A 3 pt stroke around a 66 × 46 capsule is
  about 300 pt² of purple against 2016 pt² today. Same token, same meaning, one seventh the ink.
- **The signal lands on the edge, which is where the fan already puts its own.**
  `SmartModeFanView` documents this: "the thumb is covering this row while choosing it. Only the
  edges are visible, so the signal has to be at the edges." The pill has the same problem for
  the same reason — the thumb that armed the mode is on it.
- **It is free structurally.** The ring is already a per-state `switch` in `ringEffect`. This is
  a colour argument, not a new layer.
- **It adds a second channel.** Drop the breathing pulse when armed. The idle pulse says "tap
  me", which is about the button; armed is a statement about a *setting*, and settings do not
  breathe. Normal-idle and armed-idle then differ by colour *and* by motion, which matters for
  the accessibility case below.

Recording is untouched in both modes. Red owns that moment on every screen of the product, the
overlay names the armed mode in its centre while recording, and #79's failure analysis depends
on the user being able to see and cancel a recording without ambiguity.

### The colour table

Pill body 56 × 36 pt, ring 66 × 46 pt, glyph `mic.fill` 14 pt. `dictusGlass` fills the ring's
interior in every state (`.glassEffect(.regular)` on iOS 26, `.regularMaterial` below).

| State | Pill fill | Ring stroke | Glyph | Motion |
|---|---|---|---|---|
| idle / ready / failed — Normal | `#3D7EFF` | `#3D7EFF` @ 0.3→0.6, 2 pt | white | ring breathes, 2 s |
| **idle / ready / failed — armed** | **`#3D7EFF`** | **`#8B5CF6` @ 1.0, 3 pt** | white | **none** |
| requested — Normal | `#3D7EFF` | `#3D7EFF` @ 0.3, 2 pt | white | none |
| requested — armed | `#3D7EFF` | `#8B5CF6` @ 1.0, 3 pt | white | none |
| recording — either | `#EF4444` | `#EF4444` @ 0.5, 3 pt | white | ring 1.0→1.3, 0.8 s |
| transcribing / processing — Normal | `#3D7EFF` *(see below)* | `#3D7EFF` @ 0.4, 2 pt | white | shimmer, 1.5 s |
| transcribing / processing — armed | `#3D7EFF` *(see below)* | `#8B5CF6` @ 0.8, 2 pt | white | shimmer, 1.5 s |
| success flash (0.3 s) | `#22C55E` @ 0.6 over fill | inherited | white | fade out |
| no Full Access | `#3D7EFF` @ 0.4 | none | white @ 0.4 | none |

Bold rows are the change. Everything else is today's behaviour written down.

Rows unchanged elsewhere in the feature, for completeness:

| Surface | Value |
|---|---|
| Fan row highlight, Normal | `#3D7EFF` @ 0.22 capsule, `#3D7EFF` label, semibold |
| Fan row highlight, a mode | `#8B5CF6` @ 0.22 capsule, `#8B5CF6` label, semibold |
| Fan row, not highlighted | no capsule, `.primary` label, regular |
| Fan row, disabled | `.secondary` label, whole row @ 0.4 |
| Toolbar armed label | `#8B5CF6`, 13 pt semibold, `sparkles` 11 pt |
| Overlay armed badge | `#8B5CF6` on `#8B5CF6` @ 0.14, 28 pt capsule |

### Sketch

```
TODAY — armed                          PROPOSED — armed
┌────────────────────────────┐         ┌────────────────────────────┐
│ ☰      ✦ Notes      ╭────╮ │         │ ☰      ✦ Notes     ╭─────╮ │
│                     │▓▓🎤▓│ │  52pt   │                    ┃ ▓🎤▓ ┃ │  52pt
│                     ╰────╯ │         │                    ╰─────╯ │
└────────────────────────────┘         └────────────────────────────┘
  ▓ = #8B5CF6 fill, 2016 pt²             ▓ = #3D7EFF fill (unchanged)
                                         ┃ = #8B5CF6 ring, 3pt, ~300 pt²

TODAY — Normal                         PROPOSED — Normal   (identical)
┌────────────────────────────┐         ┌────────────────────────────┐
│ ☰  Hold the mic for  ╭────╮│         │ ☰  Hold the mic for  ╭────╮│
│    Smart Modes       │░🎤░││         │    Smart Modes       │░🎤░││
│                      ╰────╯│         │                      ╰────╯│
└────────────────────────────┘         └────────────────────────────┘
  ░ = #3D7EFF fill, ring breathes        unchanged
```

---

## 2. The layout

### The arithmetic, restated

From `SmartModeFanLayout` and `SmartModeCatalogue`, against the real `KeyMetrics` values:

| Entries | standard iPhone (205 pt) | iPhone SE (187 pt) |
|---|---|---|
| 4 — Normal + 3 modes (shipped) | 51.2 pt | 46.7 pt |
| 5 — Normal + 4 modes | 41.0 pt | 37.4 pt ✗ |
| **6 as 2 × 3** | **68.3 pt** | **62.3 pt** |

The observation is correct: a 2 × 3 grid costs no row height, it gains 16 pt of it on the SE.
Width is not a constraint either — on the narrowest supported screen, two columns inside the
existing 8 pt outer padding with an 8 pt gutter give 175 pt per cell, and the widest label in
the catalogue is "Notes".

And there is a second fact in its favour that the framing did not mention: `SmartModeCatalogue`
ships exactly **five** modes today — Notes plus `→ FR / EN / DE / ES`. Six entries is the whole
catalogue. A 2 × 3 grid would make pinning unnecessary in this build.

### Recommendation: keep the single column

Three arguments, in descending strength.

**1. The two columns are not equal, because the mic is not centred.** `ToolbarView.dictationBar`
puts the mic last in its `HStack` — top-right corner. The right column falls directly under the
thumb's starting point and down its natural flexion arc. The left column requires a diagonal
sweep of ~180 pt on an SE and ~220 pt on a Pro Max, ending at the far side of the screen near
the bottom — the worst cell of every thumb-reach map, where the thumb is extended rather than
flexed and precision is at its lowest. #79 chose downward deployment on exactly this
reasoning ("thumb flexion toward the palm is more precise than extension"). A 2-column grid
does not buy six good targets; it buys three good ones and three that undo the argument that
made the gesture acceptable.

**2. The seam is a place to arm the wrong mode, silently.** `SmartModeFanLayout` is explicit:
"there is deliberately no dead space between or below them, because every point of it would be a
place to release and get nothing." A grid runs a vertical boundary down the full height of the
fan, and the failure at that boundary is worse than nothing — the neighbouring cell is a
*different mode*, not a no-op. Releasing 4 pt to the left of "→ EN" arms "→ DE", and the user
discovers it after they have finished speaking. That is precisely the failure #79 names as the
worst available ("French sent to an American client"). It is not hierarchical, so it does not
fall foul of the rejected gesture menu directly — but it reintroduces the error mode that the
rejection was about.

**3. The capacity it buys is not currently short.** Four of the five catalogue entries are
translation targets, and #79 records the usage assumption: "in practice a user has one or two
target languages, not ten." Notes plus two targets is three modes — exactly today's cap. The cap
binds only on a user who translates into three or more languages. #269 will grow the catalogue,
but it grows it past six as easily as past four: a user with custom modes will have eight or
ten, and no grid holds those either. The mechanism that scales is pinning, and pinning already
exists.

### What to change instead: give the fan a surface

The measured problem in both screenshots is not capacity. It is that the host app's text is
**sharply legible through the fan** — in IMG_7424 the document's own sentences read straight
through the "Notes" and "→ EN" rows, and in IMG_7425 coloured artefacts from the host bleed
behind "→ EN".

The cause is structural. The keyboard container is translucent, and the keys are what normally
give the eye an opaque surface to lock onto. The fan removes the keys and replaces them with
text on nothing. Every other Dictus surface that sits over the host — the mic pill, the
hamburger, the panel, the recording overlay — carries its own backing. The fan is the only one
that does not.

Fix: a blurred backdrop behind the fan area, `.dictusGlass(in: Rectangle())`, which is the
repo's existing idiom and resolves to Liquid Glass on iOS 26 and `.regularMaterial` below. It
adapts to light and dark for free and, unlike an opacity change, it *blurs* — which is what kills
sharp host text rather than merely dimming it. This is also the change that most directly serves
"the feature should not dénature the app": the fan currently looks like an overlay someone
forgot to finish, and that reads as foreign independently of any colour in it.

### Sketches

```
RECOMMENDED — single column, with backdrop      (standard iPhone, 205 pt)

┌──────────────────────────────────────────┐
│ ☰        ✦ Notes             ╭─────╮     │  52 pt  toolbar
│                              ┃ ▓🎤▓ ┃     │
└──────────────────────────────┴─────┴─────┘
┌──────────────────────────────────────────┐  ← .dictusGlass(in: Rectangle())
│ ╭──────────────────────────────────────╮ │     blurs the host app away
│ │           🎤  Normal                 │ │  51.2 pt   ← thumb lands here first
│ ╰──────────────────────────────────────╯ │
│ ╭──────────────────────────────────────╮ │
│ │           ☰  Notes                   │ │  51.2 pt
│ ╰──────────────────────────────────────╯ │
│ ╭──────────────────────────────────────╮ │
│ │           💬  → EN                   │ │  51.2 pt
│ ╰──────────────────────────────────────╯ │
│ ╭──────────────────────────────────────╮ │
│ │           💬  → DE                   │ │  51.2 pt
│ ╰──────────────────────────────────────╯ │
└──────────────────────────────────────────┘
   one axis · no seam · every row full width · abort = drag back above y=0
```

```
REJECTED — 2 columns × 3 rows

┌──────────────────────────────────────────┐
│ ☰                            ╭─────╮     │
│                              ┃ ▓🎤▓ ┃     │  ← finger starts HERE
└──────────────────────────────┴──┬──┴─────┘
┌────────────────────┬────────────┼─────────┐
│                    ┊            ▼         │
│    Normal          ┊        Notes         │  68.3 pt
│                    ┊                      │
├────────────────────┼──────────────────────┤
│                    ┊                      │
│    → EN            ┊        → DE          │  68.3 pt
│                    ┊                      │
├────────────────────┼──────────────────────┤
│                    ┊                      │
│    → ES            ┊        → FR          │  68.3 pt
│                    ┊                      │
└────────────────────┴──────────────────────┘
      ↑ extension arc         ↑ flexion arc
      far from the thumb      natural
      lowest precision        highest precision
                    ┊
                    └── the seam: 187 pt of boundary where a 4 pt
                        miss arms a different language, and the
                        user only finds out after speaking
```

---

## 3. Light and dark appearance

The keyboard is translucent over an arbitrary host, so contrast is not guaranteed. `ToolbarView`
already carries a recorded fallback for this class of problem on `proEntry` ("on the light
keyboard a white rounded pill with a shadow resembles a key"). The proposal has been checked
against both extremes rather than assumed.

Contrast ratios, WCAG 2.1 relative luminance, against white (worst case for a light keyboard)
and `#1C1C1E` (dark keyboard). The bar for a non-text graphical object is **3:1**.

| Element | vs white | vs `#1C1C1E` | Verdict |
|---|---|---|---|
| `#8B5CF6` armed ring | **4.23 : 1** | **4.03 : 1** | passes both |
| `#3D7EFF` pill fill | 3.73 : 1 | 4.57 : 1 | passes both |
| `#EF4444` recording fill | 3.76 : 1 | 4.52 : 1 | passes both |
| white glyph on `#8B5CF6` | 4.23 : 1 | — | passes |
| white glyph on `#3D7EFF` | 3.73 : 1 | — | passes |

Purple is not the contrast problem here — it is the *best* performing of the three brand fills
against a light background, and the only one clearing 4:1 on both. That is a further reason to
keep the token rather than replace it: the armed signal survives a white host app better than
the blue it sits on.

**The armed ring specifically.** At 2 pt and the idle 0.3–0.6 breathing opacity it would not
survive a light keyboard — 0.3 × `#8B5CF6` composited on a light grey is under 2:1. The
recommendation is therefore full opacity and 3 pt, matching the recording ring's weight, and no
pulse. The measured pass above assumes those values; a breathing purple ring does not pass and
should not ship.

**The fan backdrop.** `.regularMaterial` / `.glassEffect(.regular)` are both appearance-adaptive
by construction, which is the reason to prefer them over any fixed `dictusSurface` value: a
hand-picked fill would need a light and a dark variant and would still be wrong over a saturated
host. The row labels stay `.primary` / `.secondary`, which are already adaptive.

**One measured finding outside the two questions.** The transcribing / processing pill is
`#6BA3FF` at 0.5 opacity. Composited over a light keyboard (`#D1D5DB`) that yields a fill whose
contrast against its own background is **1.31 : 1** — the pill's shape effectively disappears —
and whose white `mic.fill` glyph sits at **1.93 : 1**, well under any threshold. On a light
keyboard the user currently watches an almost invisible button for the whole LLM stage, which is
the longest wait in the product. Recommendation: make the transcribing fill `#3D7EFF` at full
opacity (3.73 : 1) and let the shimmer sweep carry "in progress" on its own — it already does,
and it is a motion channel rather than a colour one. This is adjacent to #79 rather than part of
it and should be its own issue.

---

## 4. Accessibility

Colour must not be the only carrier of "a mode is armed". Under the proposal it is not, but two
of the three carriers have gaps that should be closed in the same pass.

**What carries the meaning without colour today**

| Carrier | Non-colour channel | Available when |
|---|---|---|
| Toolbar centre slot, priority 4 | the mode's **name**, plus `sparkles` | idle, and nothing higher-priority is showing |
| Recording overlay badge | the mode's **name**, plus `sparkles` | the whole recording, including the transcribing wait |
| Fan row highlight | **font weight** regular → semibold | during the gesture |
| Mic pill ring (proposed) | **absence of motion** vs the breathing idle ring | always |

Priority 4 is outranked by suggestions, so while the user is typing the pill is the only
signal — which is the case #79 designed the pill signal for ("zero width cost, visible even
while typing"). The name returns the moment typing stops, and the overlay guarantees it at the
one moment it can cost a dictation. The system is redundant enough that a small ring is safe;
it would not be if the ring were the sole carrier.

**Gaps to close**

1. **`AnimatedMicButton` has no accessibility label at all.** It is a `Button` wrapping an
   `Image(systemName:)`, so VoiceOver announces the symbol name or nothing useful. It should
   carry an explicit label and, when a mode is armed, an accessibility *value* naming it —
   "Dictate", value "Smart Mode: Notes". That is the true non-colour carrier, it costs one
   modifier, and it makes the armed state legible to a user who sees no colour at all.

2. **The fan is unreachable under VoiceOver, and this cannot be fixed here.** `SmartModeFanView`
   sets `allowsHitTesting(false)` — load-bearing, per its own doc comment — and with VoiceOver
   running, a long-press-then-drag gesture is intercepted before it reaches the recogniser. So
   arming a mode by gesture is not available to a VoiceOver user in any form. **The app's mode
   list must therefore be a full arming surface, not only a pinning surface.** This should be
   stated in the follow-up issue rather than discovered later; it is a real limitation of the
   chosen gesture, and the app is the only place it can be answered.

3. **Differentiate Without Colour.** When `\.accessibilityDifferentiateWithoutColor` is set, the
   ring alone is not enough. Add the `sparkles` glyph beside the mic glyph inside the pill under
   that setting only — the pill is 56 pt wide and can carry a 9 pt secondary glyph when it has
   to, and the trade (crowded pill) is correct for a user who has asked for exactly this.

4. **Reduce Motion.** The armed ring is static by design, so it is already correct. The idle
   breathing ring and the recording pulse predate this proposal and should honour
   `\.accessibilityReduceMotion`; noting it rather than proposing it, since it is not #79's.

5. **Dynamic Type in the fan.** Row labels are `.system(size: 17)`, a fixed size, so they do not
   scale. `RecordingOverlay` uses `@ScaledMetric` for its timer and states why. The fan cannot
   scale freely — the rows divide a fixed height — but it should at least scale up to the point
   where 4 rows still fit, then stop. Worth a line in the follow-up; not a blocker.

---

## 5. What I would not change, and why

**The blue mic at rest.** Covered above: it collides with the disabled state, it is the
reference point the rest of the toolbar's 50% icons are calibrated against, and it would make
the default state the desaturated one. This is the part of the idea that is worse than what
exists.

**Per-mode blues.** Two blues seen one at a time, peripherally, over an unknown background, are
not distinguishable. The mode's name already scales to any catalogue size; colour does not scale
past two states.

**Purple itself.** The instinct to remove it entirely would be an over-correction. Purple is the
right token — it is the kit's own name for this, it is the best-contrasting of the three brand
fills on a white host, and the fan is where the association is taught. The problem is 2016 pt²
of it, not its existence.

**Recording red, anywhere.** `#EF4444` fill and red ring stay put in both Normal and armed. The
overlay names the armed mode in its centre, so nothing is lost by red owning the pill for those
seconds.

**`maximumPinnedModes = 3` and everything in `SmartModeFanLayout`.** That arithmetic is a
measurement that settled a contradiction in #79's own text, and it is the only part of this
feature with tests behind it. Nothing in this proposal touches row height, the y-to-row mapping,
or the abort rule.

**A device-dependent cap** (4 entries on an SE, 5 on a Pro Max). Already rejected on record in
`SmartModeCatalogue`: it would make one setting in the app mean two different things on two
phones. Naming it so it is not re-proposed.

**Normal as the first row.** It is the nearest target to the thumb and it is the selection made
under mild frustration. Correct as is.

**Full-width rows.** The thumb enters from the right, so the left half of each row is never
covered and stays readable throughout the drag. A narrower, right-anchored fan would put the
highlight under the thumb.

**The declared keyboard height constraint.** Untouched — #166 and three regressions since. This
proposal changes colours and adds a backdrop inside the existing keyboard area. It changes no
height, in either the toolbar's 52 pt or the area below it.

**The `sparkles` glyph as the armed-mode marker.** Already used identically in the toolbar label
and the overlay badge. Consistent, keep.

---

## 6. Code changes this would require

By file. Nothing here has been implemented.

| File | Change |
|---|---|
| `DictusCore/Sources/DictusCore/Design/AnimatedMicButton.swift` | Replace the `tint` parameter with `ringTint` (or add it and pin `tint` back to `.dictusAccent`); `buttonFillColor` stops consulting it. `ringEffect`'s `.idle/.ready/.failed` branch strokes `ringTint` — 3 pt and opaque when it is not the accent, 2 pt and breathing when it is. Same for the `.transcribing/.processing` branch at 0.8. `.recording` untouched. Add `accessibilityLabel` and an `accessibilityValue` parameter. Optionally, the transcribing fill fix (`#6BA3FF` @ 0.5 → `#3D7EFF`) — better as its own issue. |
| `DictusKeyboard/Views/ToolbarView.swift` | `micPill` passes `ringTint:` instead of `tint:`, same ternary on `armedSmartModeName`. Passes the armed name through as the accessibility value. The centre-slot priority table, the fan gesture and `fanGestureDidOpen` are untouched. |
| `DictusKeyboard/Views/SmartModeFanView.swift` | Add `.dictusGlass(in: Rectangle())` behind the `VStack`, inside the existing `.frame(maxWidth:maxHeight:alignment:.top)` and before `.allowsHitTesting(false)` so the backdrop cannot take a touch. Add the Differentiate-Without-Colour branch on the row's highlight. Row heights, the entry loop and the reason strip are untouched. |
| `DictusKeyboard/Views/RecordingOverlay.swift` | None. |
| `DictusCore/…/Polish/SmartModeFanLayout.swift` | None. |
| `DictusCore/…/Polish/SmartModeCatalogue.swift` | Optionally `icon: "globe"` → `"character.bubble"` for translate rows: the fan's "→ EN" globe is the same glyph as the keyboard's own next-keyboard key, visible simultaneously in both screenshots. `character.bubble` is iOS 16+, so it clears the iOS 17 minimum; `translate` does not (iOS 18). `maximumPinnedModes` unchanged. |
| `DictusCore/Sources/DictusCore/Design/DictusColors.swift` | None. No new token: the backdrop uses the adaptive material, and `dictusSmartMode` already exists. |

**Localisation.** The only new user-facing string is the mic pill's accessibility label and
value. DictusCore ships no string catalog, so both must be built in `DictusKeyboard` and passed
in — the same rule `SmartModeFanView` follows for "Normal" and states in its own comment.

**Test coverage.** None of this is testable in `DictusCore`'s suite: the changes are all in
SwiftUI views, and `SmartModeFanLayout` — the one tested piece — does not move. Validation is a
device pass on both appearances, per the keyboard device smoke gate.

---

## 7. Open questions for the follow-up issue

1. **Does the fan actually cover the whole keyboard area?** Both screenshots show a row of
   glyphs — a globe at the left and a mic at the right — below the last fan row, at what looks
   like the keyboard's own bottom row. If that row is still live under the fan, it is a visible
   strip that looks like a target and is not one (`entryIndex` returns nil past the last row, so
   a release there aborts). Worth confirming against `KeyboardRootView` before deciding whether
   the backdrop should cover it too. Stated as an observation from two screenshots, not a
   finding.

2. **Does the armed ring survive a saturated host app?** The contrast figures above are against
   white and near-black. A keyboard over a photo or a coloured header is the case `proEntry`'s
   recorded fallback exists for. If 3 pt at full opacity is not enough on device, the fallback is
   the same shape as `proEntry`'s: a filled purple ring segment or a second concentric hairline
   in white, light appearance only.

3. **How does the app's mode list arm a mode?** Item 2 in the accessibility section makes this
   load-bearing rather than convenient. It is `feature/79-smart-modes-app`'s question, not this
   document's, but the two answers have to agree.
