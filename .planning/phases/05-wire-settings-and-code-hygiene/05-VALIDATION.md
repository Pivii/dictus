---
phase: 5
slug: wire-settings-and-code-hygiene
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-07
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (via Swift Package Manager) |
| **Config file** | DictusCore/Package.swift |
| **Quick run command** | `cd DictusCore && swift test --filter DictusCoreTests` |
| **Full suite command** | `cd DictusCore && swift test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd DictusCore && swift test`
- **After every plan wave:** Run `cd DictusCore && swift test` + Xcode build both targets
- **Before `/gsd:verify-work`:** Full suite must be green + device verification of all 5 success criteria
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | STT-01 | unit | `swift test --filter SharedKeysExtensionTests` | Partial | pending |
| 05-01-02 | 01 | 1 | STT-02 | unit | `swift test --filter FillerWordFilterTests` | Existing | pending |
| 05-01-03 | 01 | 1 | DUX-03 | manual | Physical device (Taptic Engine) | N/A | pending |
| 05-01-04 | 01 | 1 | APP-03 | integration | Manual on-device (settings -> behavior) | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test files needed. Existing `SharedKeysExtensionTests.swift` may be extended to verify default value behavior (`object(forKey:) as? Bool ?? true` pattern).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Haptics fire on key tap and dictation events | DUX-03 | Requires Taptic Engine (physical device) | 1. Open any app with keyboard 2. Type keys — feel light haptic 3. Start/stop recording — feel medium/light haptic 4. Receive transcription — feel success haptic |
| Language change affects transcription | STT-01 | Requires WhisperKit model on device | 1. Set language to English in Settings 2. Dictate English text 3. Verify transcription is English, not French |
| Filler filter toggle works | STT-02 | Requires dictation on device | 1. Toggle filler words OFF 2. Dictate with filler words 3. Verify fillers appear in output 4. Toggle ON, repeat, verify fillers removed |
| Haptics toggle suppresses all haptics | APP-03 | Requires Taptic Engine | 1. Toggle haptics OFF in Settings 2. Type keys — no haptic 3. Dictate — no haptic on start/stop/insert |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
