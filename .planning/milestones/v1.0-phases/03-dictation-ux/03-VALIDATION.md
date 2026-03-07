---
phase: 3
slug: dictation-ux
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in) |
| **Config file** | DictusCore/Package.swift (test target defined) |
| **Quick run command** | `xcodebuild test -scheme DictusCore -destination 'platform=iOS Simulator,name=iPhone 16' -quiet` |
| **Full suite command** | `xcodebuild test -scheme DictusCore -destination 'platform=iOS Simulator,name=iPhone 16'` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -scheme DictusCore -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
- **After every plan wave:** Run `xcodebuild test -scheme DictusCore -destination 'platform=iOS Simulator,name=iPhone 16'` + manual on-device testing
- **Before `/gsd:verify-work`:** Full suite must be green + manual UAT of complete dictation round-trip
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-xx | 01 | 1 | DUX-01 | manual-only | N/A -- requires keyboard extension context | N/A | pending |
| 03-01-xx | 01 | 1 | DUX-03 | manual-only | N/A -- requires physical device Taptic Engine | N/A | pending |
| 03-01-xx | 01 | 1 | DUX-04 | manual-only | N/A -- visual + cross-process | N/A | pending |
| 03-01-xx | 01 | 1 | KBD-05 | manual-only | N/A -- visual state changes in extension | N/A | pending |
| 03-02-xx | 02 | 1 | KBD-02 | unit | `swift test --filter AccentedCharacterTests` | No -- Wave 0 | pending |
| 03-02-xx | 02 | 1 | KBD-03 | unit | `swift test --filter QWERTYLayoutTests` | No -- Wave 0 | pending |
| 03-03-xx | 03 | 2 | APP-04 | manual-only | N/A -- end-to-end with audio | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `DictusCore/Tests/DictusCoreTests/QWERTYLayoutTests.swift` -- stubs for KBD-03 (QWERTY row counts, key labels)
- [ ] `DictusCore/Tests/DictusCoreTests/AccentedCharacterTests.swift` -- stubs for KBD-02 (accent mappings for all AZERTY keys)
- [ ] Move `KeyboardLayout` and `KeyDefinition` to DictusCore so they are testable (currently in DictusKeyboard target which has no test target)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Auto-insert text via textDocumentProxy | DUX-01 | Requires keyboard extension context + active text field | 1. Open Messages 2. Activate Dictus keyboard 3. Tap mic 4. Speak 5. Verify text appears in message field |
| Haptic feedback triggers | DUX-03 | Requires physical device Taptic Engine | 1. On physical device 2. Start recording (feel haptic) 3. Stop recording (feel haptic) 4. Wait for insertion (feel haptic) |
| Waveform animation during recording | DUX-04 | Visual + cross-process rendering | 1. Start recording 2. Verify animated waveform visible in keyboard 3. Verify waveform responds to voice volume |
| Mic button visual states | KBD-05 | Visual state changes in extension | 1. Observe idle state (muted mic) 2. Start recording (keyboard transforms) 3. Stop recording (processing state) 4. After insertion (back to idle) |
| In-app test dictation screen | APP-04 | End-to-end with audio | 1. Open Dictus app 2. Navigate to test screen 3. Record audio 4. Verify transcription result displayed |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
