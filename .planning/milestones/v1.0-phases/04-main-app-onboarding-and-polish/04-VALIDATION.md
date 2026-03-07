---
phase: 4
slug: main-app-onboarding-and-polish
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-06
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (via Swift Package Manager) |
| **Config file** | `DictusCore/Package.swift` |
| **Quick run command** | `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test` |
| **Full suite command** | `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test`
- **After every plan wave:** Run full test suite + Xcode build verification for both targets (`xcodebuild -scheme DictusApp build` and `xcodebuild -scheme DictusKeyboard build`)
- **Before `/gsd:verify-work`:** Full suite must be green + manual visual verification on device
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | APP-01 | unit | `cd DictusCore && swift test --filter SharedKeys` | Partial | pending |
| 04-01-02 | 01 | 1 | APP-01 | manual | N/A (onboarding UI flow) | N/A | pending |
| 04-01-03 | 01 | 1 | APP-01 | manual | N/A (permission dialog) | N/A | pending |
| 04-01-04 | 01 | 1 | APP-01 | manual | N/A (keyboard setup UX) | N/A | pending |
| 04-01-05 | 01 | 1 | APP-01 | manual | N/A (model download + test) | N/A | pending |
| 04-02-01 | 02 | 1 | APP-03 | unit | `cd DictusCore && swift test --filter SharedKeys` | Partial | pending |
| 04-02-02 | 02 | 1 | APP-03 | manual | N/A (settings UI) | N/A | pending |
| 04-03-01 | 03 | 2 | DSN-01, KBD-06 | build | `xcodebuild -scheme DictusApp build` | N/A | pending |
| 04-03-02 | 03 | 2 | DSN-02 | manual | N/A (animation visual) | N/A | pending |
| 04-03-03 | 03 | 2 | DSN-03 | manual | N/A (light/dark mode) | N/A | pending |
| 04-03-04 | 03 | 2 | DSN-04 | manual | N/A (Dynamic Type) | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `DictusCore/Tests/DictusCoreTests/SharedKeysExtensionTests.swift` — stubs for new keys (language, hapticsEnabled, hasCompletedOnboarding)
- [ ] Xcode build verification for DictusApp + DictusKeyboard targets after glass modifier changes

*Most Phase 4 requirements are UI/visual and require manual verification on device. Automated testing is limited to data layer changes in SharedKeys.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Onboarding flow completion | APP-01 | UI flow requires device interaction | Launch fresh install, complete all 5 steps, verify main app appears |
| Settings persistence | APP-03 | Requires app restart to verify | Change all settings, kill app, relaunch, verify values persist |
| Glass effect on all surfaces | DSN-01, KBD-06 | Visual — requires iOS 26 device/sim | Check TabBar, nav bars, cards, onboarding pages, keyboard for glass |
| Mic button animations | DSN-02 | Animation timing is visual | Trigger idle/recording/transcribing/success states, verify animations |
| Light/dark mode | DSN-03 | Visual color verification | Toggle system appearance, verify no hardcoded colors on all screens |
| Dynamic Type | DSN-04 | Layout verification at all sizes | Test in Accessibility Inspector at AX1-AX5 sizes, verify no truncation |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
