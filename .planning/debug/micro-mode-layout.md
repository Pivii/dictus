---
status: resolved
trigger: "Investigate layout and design issues in MicroModeView"
created: 2026-03-10T00:00:00Z
updated: 2026-03-10T00:00:00Z
---

## Current Focus

hypothesis: Four distinct issues with clear root causes identified
test: Code review and structural analysis complete
expecting: N/A — diagnosis mode
next_action: Report findings

## Symptoms

expected: MicroModeView should have consistent background, no redundant globe, utility keys (emoji, space, return, delete), and reliable mic trigger
actual: Gray/light color mismatch, redundant globe, no utility keys, intermittent mic failure
errors: None (visual/UX issues + intermittent functional issue)
reproduction: Open keyboard in micro mode
started: Since micro mode was implemented

## Eliminated

(none — all four issues confirmed)

## Evidence

- timestamp: 2026-03-10
  checked: MicroModeView.swift background handling
  found: MicroModeView has NO background modifier at all. KeyboardRootView uses .background(Color.clear). The UIKit layer (KeyboardViewController) uses KeyboardInputView with .keyboard inputViewStyle, and hosting.view.backgroundColor = .clear. The mismatch comes from iOS's own keyboard chrome showing through differently in the area MicroModeView occupies vs the system row below.
  implication: MicroModeView relies entirely on the system keyboard chrome for its background — the two-tone effect is iOS drawing its own background behind the extension.

- timestamp: 2026-03-10
  checked: Globe button implementation in MicroModeView
  found: Lines 66-79 — standalone Button calling controller.advanceToNextInputMode(). Positioned bottom-left with ZStack alignment .bottomLeading. iOS already renders a system globe icon in the bottom system row for all third-party keyboards.
  implication: Globe is redundant. Can be removed by deleting lines 65-79 and simplifying the ZStack to a plain VStack/centered layout.

- timestamp: 2026-03-10
  checked: Layout structure for utility keys
  found: MicroModeView is a single ZStack with a centered VStack (mic + label) and a globe overlay. No bottom row exists. EmojiMicroModeView shows the pattern: VStack with a toolbar HStack on top + content below. MicroModeView needs a similar bottom HStack for utility keys.
  implication: Need to restructure from ZStack to VStack: top area (centered mic) + bottom row (emoji, space, return, delete).

- timestamp: 2026-03-10
  checked: Mic button trigger mechanism
  found: MicroModeView.onMicTap calls state.startRecording() (KeyboardRootView line 72). KeyboardState.startRecording() posts a Darwin notification, then falls back to URL scheme after 500ms if status is still .requested. The button is .disabled when dictationStatus == .recording || .transcribing. This is the SAME mechanism as the full keyboard (ToolbarView also calls onMicTap -> state.startRecording()). However, the mic button in MicroModeView is a raw Button, while ToolbarView uses AnimatedMicButton which may handle touch differently.
  implication: The intermittent mic failure is NOT a MicroModeView-specific wiring issue — it uses the same startRecording() path. The intermittent nature likely comes from the Darwin notification + URL fallback mechanism itself (app not alive, URL scheme timing). One subtle difference: MicroModeView disables the button during .recording/.transcribing, which could cause missed taps if dictationStatus is briefly stuck in a transitional state.

## Resolution

root_cause: Four distinct issues identified (see below)
fix: (not applied — diagnosis only)
verification: (pending)
files_changed: []
