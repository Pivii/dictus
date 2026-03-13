---
phase: 15
slug: design-polish
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing / XCTest via SPM |
| **Config file** | `DictusCore/Package.swift` |
| **Quick run command** | `cd DictusCore && swift test --filter DictusCoreTests` |
| **Full suite command** | `cd DictusCore && swift test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd DictusCore && swift test --filter DictusCoreTests`
- **After every plan wave:** Run `cd DictusCore && swift test` + Xcode build for DictusApp and DictusKeyboard targets
- **Before `/gsd:verify-work`:** Full suite must be green + visual verification on Simulator
- **Max feedback latency:** 20 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | DSGN-01 | manual-only | Visual inspection in Simulator | N/A | ⬜ pending |
| 15-02-01 | 02 | 1 | DSGN-02 | manual-only | Visual inspection in Simulator | N/A | ⬜ pending |
| 15-02-02 | 02 | 1 | DSGN-03 | manual-only | Interaction testing in Simulator | N/A | ⬜ pending |
| 15-02-03 | 02 | 1 | DSGN-04 | manual-only | Interaction testing in Simulator | N/A | ⬜ pending |
| 15-03-01 | 03 | 1 | DSGN-05 | manual-only | Test on device (haptics require hardware) | N/A | ⬜ pending |
| 15-03-02 | 03 | 1 | DSGN-06 | manual-only | Visual inspection in Simulator | N/A | ⬜ pending |
| 15-04-01 | 04 | 1 | DSGN-07 | manual-only | Visual inspection in Simulator | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. DSGN requirements are visual/interaction polish validated manually.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| French accent strings correct | DSGN-01 | Visual text — no programmatic check | Build, run Simulator, verify accented characters in all screens |
| Active model blue highlight | DSGN-02 | Visual styling | Open model manager, verify blue border on active model |
| Model card layout (tap/swipe) | DSGN-03 | Interaction design | Tap cards, swipe to delete, verify animations |
| Tap-to-select model card | DSGN-04 | Interaction design | Tap downloaded model, verify it becomes active |
| X button 44pt hit area + haptic | DSGN-05 | Haptics require physical device | Start recording, tap X with offset, verify dismiss + haptic |
| Overlay dismiss animation | DSGN-06 | Visual animation timing | Dismiss overlay, verify smooth easeOut |
| Mic button transcription opacity | DSGN-07 | Visual state feedback | Start dictation, verify reduced opacity during processing |

---

## Validation Sign-Off

- [ ] All tasks have manual verification instructions
- [ ] Sampling continuity: regression test after every commit
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 20s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
