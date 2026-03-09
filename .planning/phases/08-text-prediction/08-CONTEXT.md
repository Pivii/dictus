# Phase 8: Text Prediction - Context

**Gathered:** 2026-03-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Users get French word completions and spelling corrections as they type, bridging the gap between dictation keyboard and full replacement keyboard. Covers a 3-slot suggestion bar with autocorrect and accent suggestions. Next-word prediction (PRED-04) is v1.2 scope.

Requirements: PRED-01, PRED-02, PRED-03

</domain>

<decisions>
## Implementation Decisions

### Suggestion bar placement & design
- Integrated inside the existing ToolbarView, between the gear icon (left) and mic pill (right)
- No extra keyboard height — suggestions share the toolbar row
- 3 slots as plain text separated by thin vertical dividers (Apple-style, not pills)
- Slot central = current word (bold), lateral slots = alternatives
- When no input in progress (after space, start of sentence): toolbar reverts to normal (gear + mic, nothing in between)
- Fallback: if horizontal space is too tight with 3 suggestions + gear + mic, hide the gear icon

### Prediction engine
- UITextChecker for completions and spell-checking (0 MB, Apple built-in)
- Frequency dictionary for ranking suggestions by usage frequency (common words first)
- Two dictionary files bundled in DictusKeyboard: French (~1.5MB) + English (~1.5MB)
- Active dictionary selected via SharedKeys.language from App Group preferences
- Completion of current word only — no next-word prediction (deferred to PRED-04, v1.2)

### Autocorrect behavior
- Auto-replacement on space/punctuation: misspelled word replaced by central slot correction
- Backspace immediately after autocorrection restores the original word (undo mechanism)
- Undo only available on immediate backspace — if user types more, correction is committed
- Tapping a lateral suggestion replaces current word + inserts space
- Autocorrect also fixes missing accents (e.g., "cafe" → "caf\u00e9")
- Toggle "Correction automatique" ON/OFF in Dictus settings (enabled by default, stored in App Group)

### Accent suggestions (PRED-03)
- When the user types a single accentable vowel (a, e, u, i, o) as the first character after a space, the 3 slots show accent variants instead of word completions
- Example: "a" → slots show: a | \u00e0 | \u00e2 ; "e" → slots show: e | \u00e9 | \u00e8
- As soon as a second character is typed ("an", "el"), the bar switches to word completion mode
- Tapping an accent variant replaces the vowel WITHOUT adding a space (user continues typing the word)
- Coexists with the adaptive accent key (KBD-02) — two parallel ways to insert accents
- Accent key remains the quick shortcut; suggestion bar is the discoverable alternative

### Claude's Discretion
- Exact animation/transition when suggestions appear/disappear in toolbar
- Frequency dictionary format and loading strategy (lazy vs eager)
- UITextChecker language parameter handling
- Suggestion update debouncing/throttling for performance
- Exact accent variant ordering per vowel

</decisions>

<specifics>
## Specific Ideas

- Suggestion bar style should match Apple's native keyboard: clean, plain text, thin vertical dividers between slots
- The toolbar should feel the same when empty (no suggestions) — no visual noise or placeholder elements
- Autocorrect undo via backspace matches Apple's established pattern that users already know
- French accent correction is critical for usability — "cafe" → "caf\u00e9" makes the keyboard much more useful for everyday French typing

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DictusKeyboard/Views/ToolbarView.swift`: Current toolbar with ZStack layout (gear left, mic right, Spacer in between). Suggestion slots would replace the Spacer area.
- `DictusCore/AccentedCharacters.swift`: Accent lookup table already exists — reuse for PRED-03 accent variant generation
- `DictusCore/HapticFeedback.swift`: Pre-allocated haptic generators — use for suggestion tap feedback
- `DictusKeyboard/KeyboardState.swift`: Already manages dictation state — extend with current-word tracking and suggestion state

### Established Patterns
- App Group SharedKeys for cross-process preferences (language setting already exists)
- KeyboardView tracks `lastTypedChar` for adaptive accent key — same state useful for accent suggestion mode detection
- `UIInputViewController.textDocumentProxy` for reading/inserting text — needed for word replacement logic

### Integration Points
- `ToolbarView.swift` — Add suggestion slots between gear and mic pill in the ZStack
- `KeyboardView.swift` — Feed keystroke events to suggestion engine, handle suggestion taps
- `KeyboardRootView.swift` — Wire suggestion state between toolbar and keyboard
- `DictusApp Settings` — Add autocorrect toggle (SharedKeys + SettingsView)
- `DictusKeyboard bundle` — Include frequency dictionary JSON files

</code_context>

<deferred>
## Deferred Ideas

- **Next-word prediction (PRED-04)** — Predicting the next word after a space. Requires n-gram model or ML. Deferred to v1.2.
- **Swipe typing (PRED-05)** — Gesture-based word input. Deferred to v1.2.

</deferred>

---

*Phase: 08-text-prediction*
*Context gathered: 2026-03-09*
