---
phase: 6
slug: infrastructure-app-polish
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-07
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Manual validation + build verification (no automated test framework configured) |
| **Config file** | none |
| **Quick run command** | `xcodebuild build -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet` |
| **Full suite command** | `xcodebuild build -scheme DictusApp -quiet && xcodebuild build -scheme DictusKeyboard -quiet` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild build -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
- **After every plan wave:** Run `xcodebuild build -scheme DictusApp -quiet && xcodebuild build -scheme DictusKeyboard -quiet`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-xx | 01 | 1 | INFRA-01 | build | `xcodebuild build -scheme DictusApp -quiet && xcodebuild build -scheme DictusKeyboard -quiet` | N/A | pending |
| 06-02-xx | 02 | 1 | INFRA-02 | manual | Launch in simulator, check home screen icon | N/A | pending |
| 06-03-xx | 03 | 2 | VIS-06 | build | `xcodebuild build -scheme DictusApp -quiet` | N/A | pending |
| 06-03-xx | 03 | 2 | VIS-07 | manual | Complete onboarding, verify HomeView model card | N/A | pending |
| 06-04-xx | 04 | 2 | VIS-08 | manual | Try swiping past incomplete onboarding step | N/A | pending |
| 06-05-xx | 05 | 2 | VIS-04, VIS-05 | manual | Navigate to test recording, verify layout + stop transition | N/A | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. This phase is UI-focused with build verification and manual visual checks as the appropriate validation method. No test framework installation needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| App icon renders in light/dark mode | INFRA-02 | Visual appearance on home screen | Launch simulator, check icon on home screen in both appearance modes |
| Test recording screen layout | VIS-04 | Visual design verification | Navigate to test recording, verify centered mic + ambient waveform |
| Recording stop fade transition | VIS-05 | Animation timing verification | Record, stop, verify waveform-to-text fade transition |
| No duplicate title in HomeView | VIS-06 | Visual check | Open app, verify only logo title shows (no nav bar title) |
| Model card shows correct state | VIS-07 | State verification post-onboarding | Complete onboarding, return to HomeView, verify model card displays "Whisper Small" with size |
| Onboarding blocks progression | VIS-08 | UX interaction test | Try to advance past incomplete step — should be blocked |

---

## Validation Sign-Off

- [x] All tasks have automated verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
