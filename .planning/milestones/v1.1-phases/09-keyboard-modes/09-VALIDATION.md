---
phase: 9
slug: keyboard-modes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing / XCTest via SPM |
| **Config file** | DictusCore/Package.swift (test target exists) |
| **Quick run command** | `swift test --package-path DictusCore` |
| **Full suite command** | `swift test --package-path DictusCore` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `swift test --package-path DictusCore`
- **After every plan wave:** Run `swift test --package-path DictusCore`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | MODE-01 | unit | `swift test --package-path DictusCore --filter KeyboardModeTests` | ❌ W0 | ⬜ pending |
| 09-01-02 | 01 | 1 | MODE-04 | unit | `swift test --package-path DictusCore --filter KeyboardModeTests` | ❌ W0 | ⬜ pending |
| 09-02-01 | 02 | 1 | MODE-02 | manual-only | Xcode simulator | N/A | ⬜ pending |
| 09-02-02 | 02 | 1 | MODE-03 | manual-only | Xcode simulator | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `DictusCore/Tests/DictusCoreTests/KeyboardModeTests.swift` — stubs for MODE-01 (enum cases, displayName, rawValue) and MODE-04 (reading from UserDefaults)

*Existing infrastructure covers remaining requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| User selects mode in Settings | MODE-02 | Pure SwiftUI view — no XCUITest target | Open Settings > tap each mode card > verify selection persists |
| Settings shows non-interactive preview | MODE-03 | Visual layout verification | Open Settings > verify each mode card shows representative layout preview |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
