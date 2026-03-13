---
phase: 16
slug: testflight-deployment
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift Package, DictusCore target) |
| **Config file** | `DictusCore/Package.swift` |
| **Quick run command** | `cd DictusCore && swift test` |
| **Full suite command** | `cd DictusCore && swift test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cd DictusCore && swift test`
- **After every plan wave:** Run `cd DictusCore && swift test` + manual Xcode build verification
- **Before `/gsd:verify-work`:** Full suite must be green + successful archive + TestFlight distribution
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | TF-01 | manual-only | Xcode build + archive | N/A | ⬜ pending |
| 16-01-02 | 01 | 1 | TF-02 | smoke | Verify plist exists + valid XML | ❌ W0 | ⬜ pending |
| 16-01-03 | 01 | 1 | TF-05 | manual-only | Human review | N/A | ⬜ pending |
| 16-02-01 | 02 | 1 | TF-06 | smoke | File content check | ❌ W0 | ⬜ pending |
| 16-02-02 | 02 | 1 | TF-07 | smoke | File existence check | ❌ W0 | ⬜ pending |
| 16-02-03 | 02 | 1 | TF-08 | smoke | File existence check | ❌ W0 | ⬜ pending |
| 16-03-01 | 03 | 2 | TF-03 | manual-only | Xcode Organizer | N/A | ⬜ pending |
| 16-03-02 | 03 | 2 | TF-04 | manual-only | App Store Connect | N/A | ⬜ pending |
| 16-03-03 | 03 | 2 | TF-09 | smoke | File content check | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Verify PrivacyInfo.xcprivacy plist is valid XML after creation
- [ ] Verify all documentation files exist after creation (README.md, CONTRIBUTING.md, PRIVACY.md, .github/ISSUE_TEMPLATE/*.md)
- [ ] Existing DictusCore tests still pass after version bump

*This phase is primarily configuration + documentation. Automated validation is limited to file existence and format checks.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Signing with professional account | TF-01 | Requires physical device + developer account | Build in Xcode with new Team ID, verify both targets sign successfully |
| Archive + upload | TF-03 | Requires Xcode Organizer + developer account | Archive in Xcode, upload to App Store Connect, verify processing completes |
| TestFlight distribution | TF-04 | Requires App Store Connect web portal | Create public TestFlight group, add build, verify install on device |
| Review guidelines checklist | TF-05 | Human judgment required | Review all permission strings, privacy policy, and content against Apple guidelines |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
