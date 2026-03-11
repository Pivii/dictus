---
phase: 11
slug: logging-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing / XCTest (SPM) |
| **Config file** | DictusCore/Package.swift (test target: DictusCoreTests) |
| **Quick run command** | `cd DictusCore && swift test --filter Log` |
| **Full suite command** | `cd DictusCore && swift test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd DictusCore && swift test --filter Log`
- **After every plan wave:** Run `cd DictusCore && swift test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | LOG-01 | unit | `cd DictusCore && swift test --filter LogEventTests` | ❌ W0 | ⬜ pending |
| 11-01-02 | 01 | 1 | LOG-02 | unit | `cd DictusCore && swift test --filter LogPrivacyTests` | ❌ W0 | ⬜ pending |
| 11-01-03 | 01 | 1 | LOG-03 | unit | `cd DictusCore && swift test --filter LogExportTests` | ❌ W0 | ⬜ pending |
| 11-01-04 | 01 | 1 | LOG-04 | unit | `cd DictusCore && swift test --filter PersistentLogTests` | ❌ W0 | ⬜ pending |
| 11-01-05 | 01 | 1 | LOG-05 | unit | `cd DictusCore && swift test --filter LogCoverageTests` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `DictusCore/Tests/DictusCoreTests/LogEventTests.swift` — stubs for LOG-01 (level/subsystem mapping)
- [ ] `DictusCore/Tests/DictusCoreTests/LogPrivacyTests.swift` — stubs for LOG-02 (no sensitive data patterns)
- [ ] `DictusCore/Tests/DictusCoreTests/LogExportTests.swift` — stubs for LOG-03 (header format)
- [ ] `DictusCore/Tests/DictusCoreTests/PersistentLogTests.swift` — stubs for LOG-04 (500-line rotation)
- [ ] `DictusCore/Tests/DictusCoreTests/LogCoverageTests.swift` — stubs for LOG-05 (all subsystems have events)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Share sheet appears with log file | LOG-03 | UIActivityViewController requires device interaction | Tap "Export Logs" in Settings, verify share sheet shows file |
| Keyboard extension writes logs | LOG-05 | Cross-process requires real keyboard activation | Open any text field, activate Dictus keyboard, check log file |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
