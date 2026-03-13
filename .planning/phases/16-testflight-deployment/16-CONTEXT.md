# Phase 16: TestFlight Deployment - Context

**Gathered:** 2026-03-13
**Status:** Ready for planning

<domain>
## Phase Boundary

First beta build distributed to testers, with open-source repo ready for contributors. Covers developer account signing migration, Privacy Manifest, App Store Review preparation, archive/upload to App Store Connect, beta distribution, and open-source repo presentation (README, CONTRIBUTING, issue templates, privacy policy).

</domain>

<decisions>
## Implementation Decisions

### Developer account & signing
- **Enrollment type**: Individual (Pierre Vivière), not Organisation — faster, no D-U-N-S needed, migration to Organisation possible later
- **Account not yet purchased** — Pierre will enroll before Phase 16 execution. Plan assumes account will be ready with a new Team ID
- **Bundle ID**: Keep `com.pivi.dictus` unchanged — no App Group migration risk
- **App Group**: Keep `group.com.pivi.dictus` unchanged
- **Migration**: Only the `DEVELOPMENT_TEAM` value changes in project.pbxproj (from `QN58279822` to new Team ID)
- Pierre will provide the new Team ID when enrolled

### Privacy & App Review
- **Privacy policy**: Create `PRIVACY.md` in repo root — bilingual (French + English)
- **Tone**: Detailed and transparent — explain why Full Access is required, what it enables (microphone only), and explicitly list what Dictus does NOT access (network, clipboard, keystroke data, etc.)
- **Privacy Manifest**: Create `PrivacyInfo.xcprivacy` for both DictusApp and DictusKeyboard targets — declare required API usage (UserDefaults, AVAudioSession, file timestamps)
- **App Store Review**: Prepare justification for microphone permission and Full Access requirement. Verify all permission strings are clear and accurate
- **Privacy policy URL**: Pierre is building a launch website — he'll provide the URL when ready. For now, PRIVACY.md serves as the source content

### Open-source repo presentation
- **README.md**: Full rewrite in English. Logo, app description, features, requirements (iOS 17+, iPhone 12+, Xcode 16+), build instructions, TestFlight link, license. Current README is outdated and must be replaced
- **CONTRIBUTING.md**: Standard open-source format in English — fork + PR, code conventions (from CLAUDE.md), no CLA. Welcoming to beginners
- **Issue templates**: 3 types — Bug report (with debug logs section leveraging Phase 11 logging), Feature request, Question/Help
- **Language**: All repo documentation in English (code comments already in English, issues in English)

### Beta distribution
- **Strategy**: Public TestFlight link from day one — no private beta phase
- **Rationale**: Small audience expected (personal network + GitHub visitors), TestFlight inherently signals beta status, public logging system enables remote debugging
- **TestFlight link**: Goes in README.md once available
- **Promotion**: Pierre shares his launch website (which links to TestFlight + GitHub) via personal networks. No Reddit/forum promotion planned initially
- **TestFlight group**: Single public group, no segmentation needed at this scale

### Claude's Discretion
- Privacy Manifest exact API declarations (based on code analysis)
- App Store Review Guidelines checklist format and completeness
- README structure and visual presentation (badges, sections, etc.)
- Issue template fields and labels
- CONTRIBUTING.md level of detail
- Archive and upload process documentation

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `README.md`: Exists but outdated — needs full rewrite (currently mentions iOS 16, smart modes, filler words)
- `DEVELOPMENT.md`: Exists — may need update for current build process
- `assets/brand/dictus-brand-kit.html`: Contains SVG logos and brand colors for README
- `PersistentLog` system (Phase 11): Bug report template can reference log export feature

### Established Patterns
- Bundle ID: `com.pivi.dictus` (app), `com.pivi.dictus.keyboard` (extension)
- App Group: `group.com.pivi.dictus`
- Current Team ID: `QN58279822` (personal team — will change)
- Entitlements: `DictusApp/DictusApp.entitlements`, `DictusKeyboard/DictusKeyboard.entitlements`
- Code signing: Automatic in Xcode (`CODE_SIGN_STYLE = Automatic`)

### Integration Points
- `Dictus.xcodeproj/project.pbxproj` — Team ID update
- App Store Connect — new app listing, TestFlight configuration
- GitHub repo settings — issue templates go in `.github/ISSUE_TEMPLATE/`

### Files to Create
- `PRIVACY.md` — bilingual privacy policy
- `CONTRIBUTING.md` — contribution guidelines
- `.github/ISSUE_TEMPLATE/bug_report.md`
- `.github/ISSUE_TEMPLATE/feature_request.md`
- `.github/ISSUE_TEMPLATE/question.md`
- `PrivacyInfo.xcprivacy` (×2, one per target)

</code_context>

<specifics>
## Specific Ideas

- Pierre is building a launch website for Dictus (separate repo) — will have TestFlight link + GitHub link. The site is the primary distribution channel, not the README
- Privacy policy content from PRIVACY.md will be reused on the launch website
- Pierre's company is PV Solutions (pierre@pivi.solutions) — enrolled as Individual, pays with company
- Bug report template should include a section for exported debug logs (leveraging the Phase 11 logging system)
- Pierre wants the repo to feel like a standard open-source project he'd want to use himself

</specifics>

<deferred>
## Deferred Ideas

- **Phase 15.1 (before Phase 16)**: Issues #30 (button alignment), #33 (app name "DictusApp" → "Dictus" + logo centering), #34 (swipe-back overlay improvements), #24 (sound feedback for recording start/stop)
- **Post-beta**: #29 (keyboard key spacing to match Apple), #31 (settings button shortcuts in keyboard)
- **Fastlane/CI automation** (INFRA-F03) — manual archive/upload is fine for now
- **Organisation enrollment** — can migrate from Individual later if needed

</deferred>

---

*Phase: 16-testflight-deployment*
*Context gathered: 2026-03-13*
