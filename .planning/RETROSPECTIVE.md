# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — MVP

**Shipped:** 2026-03-07
**Phases:** 5 | **Plans:** 18 | **Commits:** 137

### What Was Built
- Two-process dictation architecture (keyboard extension + main app via Darwin notifications)
- On-device French speech-to-text with WhisperKit model manager (5 models)
- Full AZERTY/QWERTY keyboard with accented character long-press
- Wispr Flow-inspired dictation UX with auto-insert, waveform, haptics
- iOS 26 Liquid Glass design system with iOS 16-25 Material fallback
- 5-step guided onboarding flow
- Settings wired end-to-end (language, haptics, filler words, layout)

### What Worked
- **Coarse granularity + yolo mode**: 5 phases in 4 days, minimal overhead
- **UAT gap closure pattern**: Phases 3-4 each needed extra plans (3.4, 4.4, 4.5) to close device-testing gaps — the pattern of "execute, test on device, fix gaps" was effective
- **Phase 5 from audit**: Running `/gsd:audit-milestone` before completion caught real integration gaps (unwired settings toggles), Phase 5 closed them cleanly
- **Darwin notification + Bool flag pattern**: Reliable cross-process IPC despite no payload support
- **Two-process architecture**: Correct decision given 50MB keyboard extension limit

### What Was Inefficient
- **Design file duplication**: 6 files manually synced between DictusApp and DictusKeyboard — a DictusUI SPM package would eliminate this
- **SmartModelRouter built then dropped**: Full TDD implementation (24 tests) that was bypassed at runtime because model switching breaks background recording. Should have prototyped before committing to the approach
- **Multiple UAT rounds**: Phases 3 and 4 each needed 1-2 extra gap closure plans. Earlier device testing during initial plans would reduce rework
- **FillerWordFilter built then removed**: Whisper model handles filler removal natively. Research should have caught this before implementation

### Patterns Established
- `dictusGlass()` modifier for all glass surfaces (single point of iOS 26 upgrade)
- Darwin notification + Bool flag + UserDefaults for cross-process communication
- `canImport(UIKit) && !os(macOS)` guard for shared SPM packages
- Fixed font sizes for keyboard keys (native iOS behavior, not Dynamic Type)
- `Task.sleep` over `Timer.scheduledTimer` in keyboard extensions
- Precomposed Unicode for accented characters

### Key Lessons
1. **Test on device early**: Simulator misses AVAudioSession behavior, haptics, keyboard extension memory, and UI sizing issues. Every phase needed device verification.
2. **Audit before milestone completion**: The milestone audit caught 3 unwired settings toggles that would have shipped broken. Always audit.
3. **Prototype runtime behavior before building features**: SmartModelRouter and FillerWordFilter were well-engineered but unnecessary. A 30-minute prototype would have revealed this.
4. **iOS keyboard extensions are severely constrained**: 50MB memory, no UIApplication.shared, no URL opening, unreliable Timer — design around these from day one.
5. **WhisperKit owns the audio session**: It calls setCategory + setActive internally. Must align our config with WhisperKit's expectations, not fight it.

### Cost Observations
- Model mix: ~80% opus, ~20% sonnet (balanced profile)
- Sessions: ~15 across 4 days
- Notable: Yolo mode + coarse granularity kept planning overhead minimal. Most time spent on actual implementation and device testing.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | ~15 | 5 | Initial process — coarse granularity, yolo mode, UAT gap closure pattern |

### Cumulative Quality

| Milestone | Tests | LOC | Files |
|-----------|-------|-----|-------|
| v1.0 | 52 | 7,305 | 156 |

### Top Lessons (Verified Across Milestones)

1. Device testing catches issues simulators miss — always verify on hardware
2. Milestone audits catch integration gaps — always audit before shipping
