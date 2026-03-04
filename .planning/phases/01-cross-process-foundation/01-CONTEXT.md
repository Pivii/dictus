# Phase 1: Cross-Process Foundation - Context

**Gathered:** 2026-03-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove the two-process dictation architecture works end-to-end on a real device. The keyboard extension triggers the main app via URL scheme, the app records audio and writes a transcription result to the App Group shared container, and the keyboard reads and displays the result. Basic AZERTY typing works in any app without Full Access. This phase delivers infrastructure — no transcription quality, no UX polish, no design system.

</domain>

<decisions>
## Implementation Decisions

### App-switching experience
- App opens instantly on mic tap and starts recording automatically — no splash screen or confirmation step
- After transcription completes, auto-return to the previous app (via dictus://return or system back navigation) — no manual "Done" button
- Keyboard shows a subtle status indicator while the main app is working ("Recording in Dictus...", "Transcribing...") so the user knows what's happening
- On failure (app doesn't open, recording fails, App Group write fails), keyboard shows a subtle inline error that auto-dismisses after a few seconds ("Dictation failed — try again")

### AZERTY layout
- Match the standard iOS native French AZERTY keyboard layout exactly — same key positions, same row structure
- Bottom row: Globe (switch keyboards) + 123 (numbers/symbols toggle) + Mic + Space + Return
- Include letters AND numbers/symbols layers from the start — full keyboard immediately usable for real typing
- Accented characters via long-press popup (é, è, ê, à, ù...) matching standard iOS behavior

### Graceful degradation
- When Full Access is off, mic button is visible but dimmed — tapping it shows a brief explanation of why it's disabled and how to enable Full Access
- Persistent banner visible every time the keyboard appears when Full Access is off — non-dismissible, matches REQUIREMENTS (APP-01)
- Keyboard looks identical to the full version when degraded — same styling, only difference is grayed-out mic + banner
- Banner deep-links directly to iOS Settings > Keyboards > Dictus for fastest user path

### Keyboard shell style
- Match the native iOS keyboard as closely as possible — same key shapes, colors, shadows, system-like appearance
- Key taps include visual popup preview above the key + system click sound — matching native iOS keyboard behavior
- Mic button uses a distinct accent color (e.g., blue or teal) to stand out as a clear call-to-action
- Keyboard adapts to iOS light/dark mode automatically from day one

### Claude's Discretion
- Exact App Group data format for transcription results (JSON, plist, UserDefaults keys)
- URL scheme parameter design for dictus://dictate and dictus://return
- DictusCore SPM package internal structure
- AppGroupDiagnostic implementation details
- Exact key dimensions and spacing
- Animation timing for status indicators and error messages
- Audio engine setup for recording stub

</decisions>

<specifics>
## Specific Ideas

- Keyboard should feel native from day one — users shouldn't notice it's a third-party keyboard during regular typing
- The mic button should be the only obviously "different" element, drawing the eye as the main feature
- Pierre is learning Swift — code structure should be clean and educational, one file = one responsibility

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- No existing code — greenfield project, Phase 1 starts from scratch

### Established Patterns
- No patterns yet — this phase establishes the foundational patterns for the entire project
- CLAUDE.md specifies: camelCase for variables/functions, PascalCase for types/structs, one file = one responsibility

### Integration Points
- Xcode workspace with two targets: DictusApp (main app) and DictusKeyboard (keyboard extension)
- DictusCore SPM package for shared code between targets
- App Group: group.com.pivi.dictus for cross-process data sharing
- URL scheme: dictus://dictate (keyboard → app) and dictus://return (app → keyboard)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-cross-process-foundation*
*Context gathered: 2026-03-04*
