---
phase: 10
slug: model-catalog
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-10
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (already configured in DictusCore) |
| **Config file** | DictusCore/Package.swift (test target exists) |
| **Quick run command** | `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test --filter ModelInfoTests` |
| **Full suite command** | `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test --filter ModelInfoTests`
- **After every plan wave:** Run `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | MOD-01 | unit | `swift test --filter ModelInfoTests` | Exists (needs update) | ⬜ pending |
| 10-01-02 | 01 | 1 | MOD-01 | unit | `swift test --filter ModelInfoTests` | Wave 0 | ⬜ pending |
| 10-02-01 | 02 | 2 | MOD-02 | unit | `swift test --filter SpeechEngineTests` | Wave 0 | ⬜ pending |
| 10-02-02 | 02 | 2 | MOD-02 | manual-only | N/A | N/A | ⬜ pending |
| 10-03-01 | 03 | 2 | MOD-03 | unit | `swift test --filter ModelInfoTests` | Wave 0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Update `ModelInfoTests.swift` — currently asserts 4 models, needs update for new catalog
- [ ] `SpeechEngineTests.swift` — covers SpeechEngine enum if created
- [ ] No new framework install needed — XCTest already configured

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Parakeet transcription produces text | MOD-02 | Requires FluidAudio model download + audio input on real device | 1. Download Parakeet model 2. Record audio 3. Verify transcription output |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
