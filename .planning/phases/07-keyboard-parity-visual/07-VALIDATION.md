---
phase: 7
slug: keyboard-parity-visual
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-08
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual UAT (keyboard extension — no XCTest for keyboard extensions) |
| **Config file** | none |
| **Quick run command** | Build & run on device, verify changed feature |
| **Full suite command** | Full UAT checklist across all test scenarios |
| **Estimated runtime** | ~5 minutes (build + install + manual verification) |

---

## Sampling Rate

- **After every task commit:** Build and run on device, verify changed feature
- **After every plan wave:** Full UAT of all keyboard interactions
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~5 minutes (build cycle)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-xx | 01 | 1 | KBD-01 | manual | Build, long-press spacebar in Notes, drag to move cursor | N/A | ⬜ pending |
| 07-01-xx | 01 | 1 | KBD-03 | manual | Tap every key type, feel haptic feedback | N/A | ⬜ pending |
| 07-01-xx | 01 | 1 | KBD-06 | manual | Side-by-side typing comparison with Apple keyboard | N/A | ⬜ pending |
| 07-02-xx | 02 | 1 | KBD-02 | manual | Type vowels on AZERTY, check apostrophe/accent key | N/A | ⬜ pending |
| 07-02-xx | 02 | 1 | KBD-04 | manual | Tap emoji button, verify system emoji appears | N/A | ⬜ pending |
| 07-02-xx | 02 | 1 | KBD-05 | manual | Check bottom bar for system dictation mic | N/A | ⬜ pending |
| 07-03-xx | 03 | 2 | VIS-01 | manual | Visual inspection of mic button in toolbar | N/A | ⬜ pending |
| 07-03-xx | 03 | 2 | VIS-02 | manual | Start recording, check cancel/validate pill buttons | N/A | ⬜ pending |
| 07-03-xx | 03 | 2 | VIS-03 | manual | Record silence, observe waveform at 60fps + zero state | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.* Keyboard extension testing is inherently manual — no XCTest for keyboard extensions. The existing build + install + manual test workflow is the standard approach.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Spacebar trackpad cursor movement | KBD-01 | Gesture + haptic requires physical device | Long-press spacebar, drag left/right, verify cursor moves with haptic ticks |
| Accent/apostrophe contextual key | KBD-02 | Contextual AZERTY behavior requires typing flow | Type vowels, check key shows accent; type consonant, check apostrophe |
| Haptic on all keys | KBD-03 | Haptic perception requires physical device | Tap letters, space, return, delete, symbols — feel haptic on each |
| Emoji button cycles keyboard | KBD-04 | System keyboard switching requires real device | Tap emoji button, verify system emoji keyboard appears |
| Apple dictation mic removed | KBD-05 | Visual inspection of system UI | Check if system mic appears below keyboard (known iOS limitation) |
| No perceptible input lag | KBD-06 | Perception-based, needs side-by-side comparison | Type on Dictus vs Apple keyboard, compare responsiveness |
| Mic button pill shape | VIS-01 | Visual design validation | Inspect mic button shape in keyboard toolbar |
| Recording pill buttons | VIS-02 | Visual design validation | Start recording, inspect cancel/validate button shapes |
| Waveform 60fps + zero state | VIS-03 | Animation smoothness requires device rendering | Record silence, observe waveform stillness; record audio, observe 60fps |

---

## Validation Sign-Off

- [ ] All tasks have manual verify instructions
- [ ] Sampling continuity: each commit verified on device
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5 minutes
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
