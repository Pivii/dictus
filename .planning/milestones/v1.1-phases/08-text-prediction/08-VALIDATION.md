---
phase: 8
slug: text-prediction
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-09
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (built-in) via Swift Package Manager |
| **Config file** | DictusCore/Package.swift (testTarget with Fixtures resources) |
| **Quick run command** | `cd DictusCore && swift test --filter FrequencyDictionaryTests 2>&1 \| tail -10` |
| **Full suite command** | `cd DictusCore && swift test 2>&1 \| tail -30` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run quick command (FrequencyDictionaryTests)
- **After every plan wave:** Run full DictusCore test suite
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-T1 | 01 | 1 | PRED-01 | unit | `cd DictusCore && swift test --filter FrequencyDictionaryTests` | Created in task | ⬜ pending |
| 08-01-T2 | 01 | 1 | PRED-01, PRED-02, PRED-03 | build | `xcodebuild build -scheme DictusKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` | N/A (build verify) | ⬜ pending |
| 08-01-T3 | 01 | 1 | PRED-01 | data | `python3 -c "import json; fr=json.load(open('DictusKeyboard/Resources/fr_frequency.json')); assert len(fr) > 1000"` | N/A (data verify) | ⬜ pending |
| 08-02-T1 | 02 | 2 | PRED-01, PRED-03 | build | `xcodebuild build -scheme DictusKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` | N/A (build verify) | ⬜ pending |
| 08-02-T2 | 02 | 2 | PRED-02 | build | `xcodebuild build -scheme Dictus -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` | N/A (build verify) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

All Wave 0 test files are created within Plan 01 Task 1 (not a separate plan):

- [x] `DictusCore/Tests/DictusCoreTests/FrequencyDictionaryTests.swift` — covers dictionary loading, ranking, case insensitivity, invalid data
- [x] `DictusCore/Tests/DictusCoreTests/Fixtures/fr_frequency_test.json` — test fixture with ~20 French words
- [x] `DictusCore/Package.swift` updated with `resources: [.copy("Fixtures")]` for test bundle

Note: TextPredictionEngine uses UITextChecker (UIKit) which cannot be tested in SPM's macOS test runner. Behavioral verification of TextPredictionEngine relies on simulator build verification + manual testing (see Manual-Only Verifications below). FrequencyDictionary is the testable pure-logic component and has full unit test coverage.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Suggestion bar renders in toolbar with correct layout | PRED-01 | UI visual validation requires simulator | Build & run on iPhone 17 Pro simulator, type a word, verify 3 slots appear between gear and mic |
| Autocorrect undo via backspace | PRED-02 | Requires UITextDocumentProxy interaction | Type misspelled word, press space (autocorrects), press backspace immediately, verify original word restored |
| Accent suggestions appear for single vowel | PRED-03 | Requires full keyboard context | Type "a" after a space, verify slots show a/a-grave/a-circumflex, tap accent, verify accent inserted without space |
| TextPredictionEngine returns ranked completions | PRED-01 | UITextChecker requires iOS simulator runtime | Type partial word "bonj" in keyboard, verify "bonjour" appears as top suggestion |
| Spell-check corrects misspelling | PRED-02 | UITextChecker requires iOS simulator runtime | Type "bonnour", press space, verify autocorrected to "bonjour" |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify (unit tests for Task 1, build verify for Tasks 2-3, build+data verify for Plan 02)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 test files created within Plan 01 Task 1 (no separate Wave 0 plan needed)
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready
