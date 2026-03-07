---
phase: 2
slug: transcription-pipeline
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in, already in use) |
| **Config file** | DictusCore/Tests/DictusCoreTests/DictusCoreTests.swift |
| **Quick run command** | `xcodebuild test -project Dictus.xcodeproj -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing DictusCoreTests` |
| **Full suite command** | `xcodebuild test -project Dictus.xcodeproj -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16'` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project Dictus.xcodeproj -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing DictusCoreTests`
- **After every plan wave:** Run `xcodebuild test -project Dictus.xcodeproj -scheme DictusApp -destination 'platform=iOS Simulator,name=iPhone 16'`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | STT-01 | integration (device) | Manual: requires microphone + WhisperKit model on device | N/A | pending |
| 02-02-01 | 02 | 2 | STT-02 | unit | `xcodebuild test ... -only-testing DictusCoreTests/FillerWordFilterTests` | W0 | pending |
| 02-02-02 | 02 | 2 | STT-03 | unit | `xcodebuild test ... -only-testing DictusCoreTests/FillerWordFilterTests` | W0 | pending |
| 02-02-03 | 02 | 2 | STT-04 | unit | `xcodebuild test ... -only-testing DictusCoreTests/SmartModelRouterTests` | W0 | pending |
| 02-02-04 | 02 | 2 | STT-05 | manual-only | Physical device benchmark (no Neural Engine in simulator) | N/A | pending |
| 02-03-01 | 03 | 2 | APP-02 | integration (device) | Manual: requires network + HuggingFace access | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `DictusCore/Tests/DictusCoreTests/FillerWordFilterTests.swift` — stubs for STT-02, STT-03
- [ ] `DictusCore/Tests/DictusCoreTests/SmartModelRouterTests.swift` — stubs for STT-04
- [ ] `DictusCore/Tests/DictusCoreTests/ModelInfoTests.swift` — stubs for APP-02 (model metadata)

*Note: FillerWordFilter and SmartModelRouter live in DictusCore (pure logic, no WhisperKit dependency) for unit testability.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| French speech produces transcription | STT-01 | Requires physical microphone input + WhisperKit model loaded | 1. Launch app 2. Record 10s French speech 3. Verify text output |
| Transcription under 3s for 10s audio | STT-05 | Requires Neural Engine (not available in simulator) | 1. Record 10s audio on iPhone 12+ 2. Measure transcription time 3. Must be < 3s |
| Model download/select/delete | APP-02 | Requires network + HuggingFace + storage space | 1. Open Model Manager 2. Download tiny model 3. Select it 4. Download another 5. Delete first 6. Verify cannot delete last |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
