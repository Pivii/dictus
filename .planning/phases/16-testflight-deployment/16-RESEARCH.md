# Phase 16: TestFlight Deployment - Research

**Researched:** 2026-03-13
**Domain:** iOS app distribution (TestFlight), Privacy Manifests, open-source repo presentation
**Confidence:** HIGH

## Summary

Phase 16 covers the final step to beta: migrating code signing to a professional developer account, adding Privacy Manifests, archiving and uploading to App Store Connect, distributing via TestFlight, and making the GitHub repo presentable for contributors. This is primarily a configuration and documentation phase with minimal code changes.

The project is well-positioned. Code signing uses `Automatic` style, so switching the DEVELOPMENT_TEAM value in 4 places in `project.pbxproj` is the only code-level signing change. The App Group ID (`group.com.pivi.dictus`) stays the same -- the key risk is ensuring the new provisioning profiles include this App Group capability. Privacy Manifest is straightforward: the app uses UserDefaults (App Group) extensively but does NOT use file timestamp APIs, disk space APIs, or system boot time APIs based on code analysis.

**Primary recommendation:** Do signing migration and Privacy Manifest first, then archive+upload as a validation gate before investing time in documentation (README, CONTRIBUTING, issue templates). If the binary is rejected, documentation effort is wasted context.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Enrollment type**: Individual (Pierre Viviere), not Organisation -- faster, no D-U-N-S needed
- **Account not yet purchased** -- Pierre will enroll before Phase 16 execution. Plan assumes account will be ready with a new Team ID
- **Bundle ID**: Keep `com.pivi.dictus` unchanged -- no App Group migration risk
- **App Group**: Keep `group.com.pivi.dictus` unchanged
- **Migration**: Only the `DEVELOPMENT_TEAM` value changes in project.pbxproj (from `QN58279822` to new Team ID)
- **Privacy policy**: Create `PRIVACY.md` in repo root -- bilingual (French + English)
- **Privacy Manifest**: Create `PrivacyInfo.xcprivacy` for both DictusApp and DictusKeyboard targets
- **README.md**: Full rewrite in English. Logo, app description, features, requirements (iOS 17+, iPhone 12+, Xcode 16+), build instructions, TestFlight link, license
- **CONTRIBUTING.md**: Standard open-source format in English -- fork + PR, code conventions (from CLAUDE.md), no CLA
- **Issue templates**: 3 types -- Bug report (with debug logs section), Feature request, Question/Help
- **Beta distribution strategy**: Public TestFlight link from day one -- no private beta phase
- **TestFlight group**: Single public group, no segmentation

### Claude's Discretion
- Privacy Manifest exact API declarations (based on code analysis)
- App Store Review Guidelines checklist format and completeness
- README structure and visual presentation (badges, sections, etc.)
- Issue template fields and labels
- CONTRIBUTING.md level of detail
- Archive and upload process documentation

### Deferred Ideas (OUT OF SCOPE)
- Phase 15.1 issues (#30, #33, #34, #24) -- handled separately before Phase 16
- Post-beta issues (#29, #31)
- Fastlane/CI automation (INFRA-F03) -- manual archive/upload is fine
- Organisation enrollment -- migrate later if needed
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TF-01 | Xcode signing migrated to professional developer account | DEVELOPMENT_TEAM appears 4 times in project.pbxproj (lines 690, 712, 733, 755). Replace `QN58279822` with new Team ID. Automatic signing handles provisioning. |
| TF-02 | Privacy Manifest (PrivacyInfo.xcprivacy) created for both targets | Code analysis: only UserDefaults (CA92.1) needed. No file timestamp, disk space, or boot time APIs detected. |
| TF-03 | App successfully archived and uploaded to App Store Connect | Version must be bumped from 1.0/1 to 1.2/1. Archive via Product > Archive, upload via Organizer. |
| TF-04 | First TestFlight beta build distributed to testers | External testers require Beta App Review (1-3 days). Public link created in App Store Connect > TestFlight. |
| TF-05 | App Store Review Guidelines checklist verified | Keyboard extension with Full Access + microphone needs explicit reviewer notes. Privacy policy URL required. |
| TF-06 | README.md updated with build instructions and prerequisites | Current README is outdated (mentions iOS 16, filler words, smart modes). Full rewrite needed. |
| TF-07 | CONTRIBUTING.md with PR guidelines and code conventions | New file. Conventions from CLAUDE.md. |
| TF-08 | GitHub issue templates (bug report with debug logs, feature request) | 3 templates in `.github/ISSUE_TEMPLATE/`. Bug template references PersistentLog export. |
| TF-09 | Public TestFlight link in README for joining the beta | Added after TF-04 is complete and link is available. |
</phase_requirements>

## Standard Stack

This phase has no new library dependencies. It is a configuration + documentation phase.

### Tools Required
| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode 16+ | Archive, signing, upload | Already installed |
| App Store Connect | App listing, TestFlight management | Web portal, requires paid developer account |
| GitHub | Issue templates, repo presentation | Already configured |

### Version Bump
| File | Current | Target |
|------|---------|--------|
| `project.pbxproj` MARKETING_VERSION | 1.0 | 1.2 |
| `project.pbxproj` CURRENT_PROJECT_VERSION | 1 | 1 (or increment) |
| `DictusApp/Info.plist` CFBundleShortVersionString | 1.0 | 1.2 |
| `DictusApp/Info.plist` CFBundleVersion | 1 | 1 |
| `DictusKeyboard/Info.plist` CFBundleShortVersionString | 1.0 | 1.2 |
| `DictusKeyboard/Info.plist` CFBundleVersion | 1 | 1 |

Note: If `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are set in build settings (they are), the Info.plist values may use `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`. Check whether Info.plist uses hardcoded values or build setting variables. Current Info.plist has hardcoded `1.0` and `1`.

## Architecture Patterns

### Recommended Task Ordering

```
Wave 1: Signing + Privacy Manifest + Version Bump
  - Update DEVELOPMENT_TEAM in project.pbxproj (4 occurrences)
  - Create PrivacyInfo.xcprivacy for both targets
  - Bump version to 1.2
  - Add PrivacyInfo.xcprivacy to Xcode project (pbxproj references)

Wave 2: App Store Connect Setup + Archive + Upload (MANUAL - Pierre)
  - Create app listing in App Store Connect
  - Archive in Xcode (Product > Archive)
  - Upload via Organizer
  - Wait for processing (5-15 min)
  - This is a GATE: if upload fails, fix before proceeding

Wave 3: Documentation
  - PRIVACY.md (bilingual privacy policy)
  - README.md (full rewrite)
  - CONTRIBUTING.md
  - .github/ISSUE_TEMPLATE/ (3 templates)

Wave 4: TestFlight Distribution + Final README Update
  - Submit build for Beta App Review
  - Create public TestFlight link
  - Add TestFlight link to README.md
```

### Privacy Manifest Structure

Each target needs its own `PrivacyInfo.xcprivacy` file. Based on code analysis:

**APIs used by Dictus:**
- `UserDefaults` via `AppGroup.defaults` (extensively throughout DictusCore, DictusApp, DictusKeyboard)

**APIs NOT used (verified by grep):**
- No `attributesOfItem`, `modificationDate`, `creationDate`, `resourceValues` -- no file timestamp APIs
- No `volumeAvailableCapacity`, `attributesOfFileSystem` -- no disk space APIs
- No `systemUptime`, `ProcessInfo.systemUptime`, `mach_absolute_time` -- no boot time APIs

**Recommended Privacy Manifest content (both targets identical):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key>
  <false/>
  <key>NSPrivacyTrackingDomains</key>
  <array/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>CA92.1</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
```

**Key details:**
- `NSPrivacyTracking`: false (no tracking)
- `NSPrivacyCollectedDataTypes`: empty array (no data collection -- matches "Data Not Collected" nutrition label)
- `CA92.1` reason: "Access UserDefaults to read and write data specific to the app or extension using the AppGroup container"
- Both targets need the file because both access UserDefaults via AppGroup

**Important:** WhisperKit and other SPM dependencies may include their own Privacy Manifests. Xcode aggregates them automatically during archive. If WhisperKit uses file timestamp or disk space APIs, those are covered by WhisperKit's own manifest, not the app's.

### Signing Migration

The project uses `CODE_SIGN_STYLE = Automatic` for all targets. Migration steps:

1. Replace `DEVELOPMENT_TEAM = QN58279822` with `DEVELOPMENT_TEAM = <NEW_TEAM_ID>` in 4 places in `project.pbxproj`
2. In Xcode: sign in with the new developer account (Xcode > Settings > Accounts)
3. Xcode auto-generates provisioning profiles for both targets
4. Verify App Group capability is present in both profiles (Signing & Capabilities tab)

**No entitlements file changes needed** -- both `DictusApp.entitlements` and `DictusKeyboard.entitlements` already correctly declare `group.com.pivi.dictus`.

### App Store Connect App Listing

Required fields for creating the app:
- Platform: iOS
- Name: Dictus
- Primary language: French
- Bundle ID: com.pivi.dictus (must match exactly)
- SKU: dictus-ios (or similar unique string)
- Privacy Policy URL: required for keyboard extensions with Full Access

### App Store Review Notes (for Beta App Review)

The current DEVELOPMENT.md review note is **outdated** -- it mentions smart modes and OpenAI API keys which no longer exist in the codebase. Updated note:

```
Dictus is an iOS keyboard with 100% on-device voice dictation.

Key points for review:

1. MICROPHONE
   The app uses the microphone for speech-to-text transcription only.
   All processing happens on-device via WhisperKit (Apple CoreML).
   No audio is sent to any server.

2. FULL ACCESS (keyboard extension)
   Full Access is required solely for microphone access from the
   keyboard extension. The app does not access the network, clipboard
   content, or keystroke data.

3. BACKGROUND AUDIO
   UIBackgroundModes:audio is used to keep the audio session alive
   when the user switches from the app back to the keyboard during
   cold start dictation. No audio plays in the background.

4. URL SCHEMES (LSApplicationQueriesSchemes)
   Used to detect the source app for auto-return after cold start
   dictation (e.g., returning to WhatsApp after dictating).

5. DATA COLLECTION
   Dictus collects no user data. Privacy Nutrition Label: "Data Not Collected".

To test dictation:
1. Install app > Complete onboarding > Download a model
2. Open any text field (e.g., Notes)
3. Switch to Dictus keyboard (globe button)
4. Tap the microphone button > Speak > Text appears
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Privacy Manifest | Manual XML editing without validation | Xcode's built-in Privacy Manifest editor (File > New > File > App Privacy) | Xcode validates the plist structure and offers autocomplete for API categories |
| Code signing | Manual provisioning profile management | Xcode Automatic Signing | Automatic signing handles profile creation, renewal, and App Group capability |
| TestFlight upload | xcodebuild command line | Xcode Organizer GUI | For first-time upload, GUI provides better error messages and validation |

## Common Pitfalls

### Pitfall 1: App Group Not in New Provisioning Profile
**What goes wrong:** After switching DEVELOPMENT_TEAM, Xcode generates new provisioning profiles that don't include the App Group capability. The app builds but cross-process communication (keyboard <-> app) silently fails.
**Why it happens:** App Group must be registered in the Apple Developer portal under the new team. Automatic signing usually handles this, but sometimes the capability isn't auto-created.
**How to avoid:** After changing DEVELOPMENT_TEAM, open Signing & Capabilities for BOTH targets and verify the App Group shows a checkmark (not a warning). If there's a warning, Xcode will auto-fix it when you click "Fix Issue."
**Warning signs:** "No matching provisioning profile" error. Keyboard can't read shared UserDefaults. DictationCoordinator can't communicate with keyboard.

### Pitfall 2: ITMS-91053 Missing Privacy Manifest
**What goes wrong:** App Store Connect rejects the binary with "ITMS-91053: Missing API declaration" because PrivacyInfo.xcprivacy is missing or incomplete.
**Why it happens:** Required since May 2024. UserDefaults is a required-reason API.
**How to avoid:** Create PrivacyInfo.xcprivacy for BOTH targets (DictusApp AND DictusKeyboard). Both use UserDefaults via AppGroup.
**Warning signs:** Upload succeeds but email from Apple says "Invalid Binary" or processing shows warnings.

### Pitfall 3: Beta App Review Rejection for Missing Privacy Policy URL
**What goes wrong:** External TestFlight distribution requires Beta App Review. Keyboard extensions requesting Full Access are scrutinized. Missing privacy policy URL causes immediate rejection.
**Why it happens:** Apple requires a working privacy policy URL for apps that request sensitive permissions.
**How to avoid:** Pierre's launch website should have the privacy policy hosted before submitting for Beta App Review. PRIVACY.md in the repo is the source content but the URL must point to a web page, not a GitHub raw file (though a GitHub rendered page may be acceptable).
**Warning signs:** Review rejection with "Guideline 5.1.1 - Legal - Privacy - Data Collection and Storage"

### Pitfall 4: Version Number Conflict
**What goes wrong:** App Store Connect rejects the upload because the version/build combination already exists.
**Why it happens:** The current version is 1.0 (1). If Pierre has ever uploaded a test build with version 1.0, a new upload with the same version will fail.
**How to avoid:** Bump MARKETING_VERSION to 1.2 and ensure CURRENT_PROJECT_VERSION is 1. If upload fails with version conflict, increment CURRENT_PROJECT_VERSION.
**Warning signs:** "The bundle version must be higher than the previously uploaded version" error during upload.

### Pitfall 5: PrivacyInfo.xcprivacy Not Added to Xcode Target
**What goes wrong:** The file exists on disk but is not included in the Xcode target's "Copy Bundle Resources" build phase, so it's not included in the archive.
**Why it happens:** Creating the file via code editor (not Xcode) doesn't automatically add it to the project.
**How to avoid:** After creating the file, verify it appears in the target's Build Phases > Copy Bundle Resources. If editing project.pbxproj directly, add PBXBuildFile, PBXFileReference, and PBXGroup entries.
**Warning signs:** ITMS-91053 error despite the file existing in the repo.

### Pitfall 6: Outdated Review Notes Cause Rejection
**What goes wrong:** The reviewer reads notes mentioning "smart modes" and "OpenAI API key" but can't find these features, causing confusion and potential rejection for incomplete functionality.
**Why it happens:** DEVELOPMENT.md has outdated review notes from an earlier version.
**How to avoid:** Write fresh review notes based on current functionality. No smart modes, no network access, no API keys -- purely offline dictation.

## Code Examples

### Updating DEVELOPMENT_TEAM in project.pbxproj

The value appears exactly 4 times (2 targets x 2 configurations: Debug + Release):
```
Line 690: DEVELOPMENT_TEAM = QN58279822;  (DictusApp Debug)
Line 712: DEVELOPMENT_TEAM = QN58279822;  (DictusApp Release)
Line 733: DEVELOPMENT_TEAM = QN58279822;  (DictusKeyboard Debug)
Line 755: DEVELOPMENT_TEAM = QN58279822;  (DictusKeyboard Release)
```

Simple find-and-replace: `QN58279822` -> `<NEW_TEAM_ID>`

### GitHub Issue Template: Bug Report

```markdown
---
name: Bug Report
about: Report a bug or unexpected behavior
title: "[Bug] "
labels: bug
assignees: ''
---

## Description
<!-- A clear description of the bug -->

## Steps to Reproduce
1.
2.
3.

## Expected Behavior
<!-- What should happen -->

## Actual Behavior
<!-- What actually happens -->

## Environment
- iPhone model:
- iOS version:
- Dictus version:
- Active model:

## Debug Logs
<!--
Export logs from Dictus:
Settings > Export Debug Logs > Share
Paste the log content below or attach the file.
-->
<details>
<summary>Logs</summary>

```
(paste logs here)
```

</details>

## Screenshots / Screen Recording
<!-- If applicable -->
```

### GitHub Issue Template: Feature Request

```markdown
---
name: Feature Request
about: Suggest a new feature or improvement
title: "[Feature] "
labels: enhancement
assignees: ''
---

## Problem
<!-- What problem does this solve? -->

## Proposed Solution
<!-- How would you like it to work? -->

## Alternatives Considered
<!-- Other approaches you've thought about -->

## Additional Context
<!-- Any other information -->
```

### GitHub Issue Template: Question / Help

```markdown
---
name: Question / Help
about: Ask a question or get help
title: "[Question] "
labels: question
assignees: ''
---

## Question
<!-- Your question -->

## Context
<!-- What are you trying to do? -->

## What I've Tried
<!-- Steps you've already taken -->
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No Privacy Manifest | PrivacyInfo.xcprivacy required | May 2024 | Binary rejection without it |
| Internal TestFlight = no review | External TestFlight = Beta App Review | Always been this way | Budget 1-3 days for first review |
| Privacy policy optional for TestFlight | Privacy policy URL required for Full Access apps | 2024+ | Must have URL before submitting |

## Open Questions

1. **Privacy Policy URL**
   - What we know: Pierre is building a launch website that will host the privacy policy
   - What's unclear: Whether the website will be ready before Phase 16 execution
   - Recommendation: Use `https://github.com/Pivii/dictus/blob/main/PRIVACY.md` as interim URL if website isn't ready. GitHub renders Markdown nicely and Apple has accepted GitHub-hosted policies.

2. **WhisperKit Privacy Manifest**
   - What we know: WhisperKit is included via SPM and may have its own PrivacyInfo.xcprivacy
   - What's unclear: Whether WhisperKit declares additional required-reason APIs (file timestamps for model files, disk space checks)
   - Recommendation: Xcode aggregates Privacy Manifests from SPM dependencies automatically. If WhisperKit uses these APIs, they're covered. Check Xcode's privacy report after archiving (Organizer > Generate Privacy Report).

3. **App Store Connect App Name Availability**
   - What we know: The app will be listed as "Dictus"
   - What's unclear: Whether "Dictus" is available as an App Store name (could be taken by another app)
   - Recommendation: Pierre should check name availability when creating the app listing. Have "Dictus - Voice Keyboard" as fallback.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (Swift Package, DictusCore target) |
| Config file | `DictusCore/Package.swift` |
| Quick run command | `cd DictusCore && swift test` |
| Full suite command | `cd DictusCore && swift test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TF-01 | Signing with professional account | manual-only | Xcode build + archive | N/A -- requires physical device + account |
| TF-02 | Privacy Manifest exists and is valid | smoke | Verify file exists + plist structure | No -- Wave 0 |
| TF-03 | Archive + upload succeeds | manual-only | Xcode Organizer | N/A -- requires developer account |
| TF-04 | TestFlight build distributed | manual-only | App Store Connect | N/A -- web portal |
| TF-05 | Review guidelines checklist | manual-only | Human review | N/A -- documentation |
| TF-06 | README has build instructions | smoke | File content check | No -- Wave 0 |
| TF-07 | CONTRIBUTING.md exists | smoke | File existence check | No -- Wave 0 |
| TF-08 | Issue templates exist | smoke | File existence check | No -- Wave 0 |
| TF-09 | TestFlight link in README | smoke | File content check | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `cd /Users/pierreviviere/dev/dictus/DictusCore && swift test`
- **Per wave merge:** Full suite + manual Xcode build verification
- **Phase gate:** Successful archive + TestFlight distribution

### Wave 0 Gaps
Most TF requirements are manual (signing, upload, distribution) or documentation (README, CONTRIBUTING). Automated validation is limited to:
- [ ] Verify PrivacyInfo.xcprivacy plist is valid XML
- [ ] Verify all documentation files exist after creation
- [ ] Existing DictusCore tests still pass after version bump

No new test files needed -- this phase is configuration + documentation, not code.

## Sources

### Primary (HIGH confidence)
- Project codebase analysis -- `project.pbxproj`, `Info.plist` files, `.entitlements` files, Swift source grep
- [Apple Privacy Manifest documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) -- required API categories and reason codes
- [Apple App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) -- keyboard extension requirements
- Existing `.planning/research/PITFALLS.md` -- Pitfall 5 (TestFlight submission)

### Secondary (MEDIUM confidence)
- [Expo Privacy Manifests guide](https://docs.expo.dev/guides/apple-privacy/) -- API category reference and reason codes
- [Apple Developer Program Enrollment](https://developer.apple.com/help/account/membership/program-enrollment/) -- Individual vs Organization
- [Apple TestFlight documentation](https://developer.apple.com/testflight/) -- distribution process

### Tertiary (LOW confidence)
- WebSearch results on keyboard extension rejection patterns -- general patterns, not Dictus-specific

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, pure configuration
- Architecture (signing/manifest): HIGH -- verified against actual project files
- Architecture (TestFlight process): MEDIUM -- process is well-documented but first-time submissions can have unexpected issues
- Pitfalls: HIGH -- based on Apple documentation + existing project research
- Documentation templates: HIGH -- standard open-source patterns

**Research date:** 2026-03-13
**Valid until:** 2026-04-13 (stable domain, Apple policies rarely change mid-cycle)
