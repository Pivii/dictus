# Phase 5: Wire Settings & Code Hygiene - Research

**Researched:** 2026-03-07
**Domain:** SwiftUI settings wiring, UIKit haptics in keyboard extensions, WhisperKit language configuration
**Confidence:** HIGH

## Summary

Phase 5 is a wiring and cleanup phase. All the infrastructure already exists -- SettingsView writes to App Group, SharedKeys are defined, HapticFeedback has methods, FillerWordFilter works, DictusColors is complete. The gap is that 3 of 4 settings toggles (language, fillerWords, haptics) are never read by their consumers. Additionally, haptics were reported as not firing at all during testing, AccentPopup uses a hardcoded Color.blue, and BrandWaveform has diverged between app (30 bars) and keyboard (40 bars).

Every change in this phase is localized -- no new files, no new frameworks, no architectural decisions. It is purely about connecting existing writes to existing reads, fixing a haptic bug, and unifying diverged code.

**Primary recommendation:** Wire each setting by reading from App Group UserDefaults at the point of use (same pattern as `keyboardLayout` which is already wired), diagnose the haptic bug (likely `prepare()` timing or missing Full Access check), and unify BrandWaveform to 30 bars with adaptive bar width.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- French and English only for v1 -- no additional languages
- Language picker affects WhisperKit transcription language only -- app UI stays in French (no localization)
- Switching language just changes the language hint passed to WhisperKit on next transcription -- no model reload needed
- No language indicator badge on keyboard toolbar -- keep toolbar clean
- Always filter both French and English fillers regardless of active transcription language (users mix languages)
- Toggle OFF = skip FillerWordFilter.clean() entirely -- raw Whisper output goes straight through
- Toggle ON = current behavior (apply FillerWordFilter.clean() to all output)
- BUG: haptics currently don't fire at all -- must be diagnosed and fixed in this phase
- Add light haptic feedback on every key tap (UIImpactFeedbackGenerator(.light)) -- matching native iOS keyboard feel
- Keep existing distinct patterns for dictation events: medium impact (recording start), light impact (recording stop), success notification (text insertion)
- One master toggle in Settings controls all haptics (key taps + dictation events) -- no per-event granularity
- Replace hardcoded Color.blue with DictusColors equivalent -- straightforward swap
- Unify to 30 bars everywhere (app and keyboard) -- not just document the divergence
- Bar width adapts automatically to fit available space in each context (no fixed bar width)

### Claude's Discretion
- Exact diagnosis and fix for haptic feedback bug
- Bar width calculation approach for adaptive BrandWaveform sizing
- Where to read the haptics setting in DictusKeyboard (KeyboardState or KeyButton level)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| APP-03 | Settings screen for active model, transcription language, keyboard layout, filler word toggle, haptic toggle | Wire language/fillerWords/haptics toggles to their consumers. keyboardLayout already wired. activeModel wired in Phase 2. |
| STT-01 | User can dictate text and receive accurate French transcription via on-device WhisperKit | Language setting must be read from App Group instead of hardcoded "fr" in TranscriptionService |
| STT-02 | Filler words are automatically removed from transcription | FillerWordFilter.clean() call must be conditional on fillerWordsEnabled setting |
| DUX-03 | Haptic feedback triggers on recording start, recording stop, and text insertion | Haptic bug must be diagnosed and fixed; key tap haptics added; master toggle wired |
</phase_requirements>

## Standard Stack

### Core (already in project)
| Library | Version | Purpose | Status |
|---------|---------|---------|--------|
| SwiftUI | iOS 16+ | UI framework | Already used |
| UIKit | iOS 16+ | UIImpactFeedbackGenerator, UINotificationFeedbackGenerator | Already used in HapticFeedback.swift |
| WhisperKit | 0.16.0+ | Speech-to-text with language parameter | Already integrated |
| DictusCore | local SPM | SharedKeys, HapticFeedback, FillerWordFilter, AppGroup | Already shared across targets |

### No New Dependencies
This phase requires zero new libraries. All work is wiring existing code.

## Architecture Patterns

### Pattern 1: Read Settings at Point of Use
**What:** Read from App Group UserDefaults at the moment the setting is needed, not cached.
**When:** Every time TranscriptionService transcribes or HapticFeedback fires.
**Why:** This is the established pattern -- TranscriptionService and KeyboardState already read from `AppGroup.defaults` on each operation. No caching, no observers needed.

```swift
// Pattern already used in KeyboardState and other consumers:
let defaults = UserDefaults(suiteName: AppGroup.identifier)
let language = defaults?.string(forKey: SharedKeys.language) ?? "fr"
```

### Pattern 2: Guard-Check for Toggle Settings
**What:** Wrap the action in an `if` check on the toggle value.
**When:** Haptic feedback calls, filler word filtering.

```swift
// Filler words: conditional call
let fillerWordsEnabled = defaults?.bool(forKey: SharedKeys.fillerWordsEnabled) ?? true
let cleaned = fillerWordsEnabled ? FillerWordFilter.clean(trimmed) : trimmed

// Haptics: guard at entry point
public static func recordingStarted() {
    #if canImport(UIKit) && !os(macOS)
    guard isEnabled() else { return }
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.prepare()
    generator.impactOccurred()
    #endif
}
```

### Pattern 3: GeometryReader for Adaptive Bar Width
**What:** Use GeometryReader to calculate bar width from available space.
**When:** BrandWaveform needs to fill available width with exactly 30 bars.

```swift
// barWidth = (availableWidth - totalSpacing) / barCount
GeometryReader { geometry in
    let spacing: CGFloat = 2
    let totalSpacing = spacing * CGFloat(barCount - 1)
    let barWidth = (geometry.size.width - totalSpacing) / CGFloat(barCount)
    HStack(spacing: spacing) {
        ForEach(0..<barCount, id: \.self) { index in
            barView(index: index, barWidth: barWidth)
        }
    }
}
```

### Anti-Patterns to Avoid
- **Caching settings in init:** Don't read the setting once and store it. The user can change settings while the keyboard is visible. Read at point of use.
- **Separate haptic toggle per event type:** User explicitly chose one master toggle. Don't add per-event granularity.
- **Reading settings in HapticFeedback from UIKit side:** HapticFeedback is in DictusCore (SPM package). It cannot import AppGroup directly on macOS for tests. The `isEnabled()` check should read from UserDefaults internally with proper platform guards.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Haptic feedback | Custom AVFoundation audio feedback | UIImpactFeedbackGenerator / UINotificationFeedbackGenerator | Apple's Taptic Engine API. Already used in HapticFeedback.swift |
| Settings sync | KVO observers or Combine publishers for UserDefaults | Direct read from AppGroup.defaults at point of use | Simpler, no subscription lifecycle to manage, matches existing pattern |
| Adaptive layout | Manual frame calculations | GeometryReader | SwiftUI-native way to get parent container dimensions |

## Common Pitfalls

### Pitfall 1: Haptic Feedback Not Firing in Keyboard Extension
**What goes wrong:** UIImpactFeedbackGenerator works in the main app but produces no haptic output in the keyboard extension.
**Why it happens:** Multiple possible causes:
1. **prepare() called too late or not at all:** The Taptic Engine needs ~50ms to spin up. Calling `prepare()` immediately before `impactOccurred()` on the same line may not give it enough time. However, the current code does call prepare() right before impactOccurred() and this pattern works in most apps.
2. **Keyboard extension sandboxing:** iOS keyboard extensions run in a separate process with limited capabilities. However, haptic feedback IS supported in keyboard extensions (native iOS keyboard uses it).
3. **Full Access not enabled:** Some haptic APIs may require Full Access in keyboard extensions, though UIImpactFeedbackGenerator should work without it.
4. **Device-specific:** Haptics require a device with Taptic Engine (iPhone 7+). Simulator does not produce haptic output.
**How to avoid:** Test on a physical device. Pre-warm generators (call `prepare()` earlier, e.g., when KeyboardState initializes). Verify Full Access is enabled.
**Confidence:** MEDIUM -- this requires on-device diagnosis.

### Pitfall 2: UserDefaults Default Values
**What goes wrong:** `UserDefaults.bool(forKey:)` returns `false` when the key has never been set (no default registered). This means haptics and filler words appear "off" before the user ever opens Settings.
**Why it happens:** Bool defaults to false in UserDefaults. The SettingsView @AppStorage initializers set defaults (`= true`) but those only take effect when SettingsView has been rendered at least once.
**How to avoid:** Use `object(forKey:) == nil` check to distinguish "never set" from "explicitly false", or register defaults in AppGroup early (e.g., in DictusApp init or DictusCore). The simplest approach: read with a nil-coalescing default:
```swift
let hapticsEnabled = defaults?.object(forKey: SharedKeys.hapticsEnabled) as? Bool ?? true
```
**Confidence:** HIGH -- this is a known Swift/UserDefaults behavior.

### Pitfall 3: BrandWaveform Copy Divergence
**What goes wrong:** DictusApp and DictusKeyboard have separate copies of BrandWaveform.swift. After unifying to 30 bars with adaptive width, both copies must be updated identically.
**Why it happens:** Keyboard extensions cannot import DictusApp code, and moving design files to DictusCore would add UIKit/SwiftUI dependency breaking macOS tests.
**How to avoid:** Update both files in the same commit. Add a comment at the top of both files referencing each other.
**Confidence:** HIGH -- established project pattern.

### Pitfall 4: WhisperKit Language Parameter Scope
**What goes wrong:** Passing unsupported language codes to WhisperKit.
**Why it happens:** WhisperKit accepts ISO language codes. "fr" and "en" are both supported.
**How to avoid:** Only allow "fr" and "en" (already constrained by the Picker in SettingsView).
**Confidence:** HIGH -- WhisperKit supports both languages.

## Code Examples

### Wiring Language Setting in TranscriptionService
```swift
// TranscriptionService.swift — replace hardcoded "fr" with App Group read
func transcribe(audioSamples: [Float]) async throws -> String {
    // ... existing guard checks ...

    // Read language from App Group (defaults to "fr" if never set)
    let defaults = UserDefaults(suiteName: AppGroup.identifier)
    let language = defaults?.string(forKey: SharedKeys.language) ?? "fr"

    let options = DecodingOptions(
        task: .transcribe,
        language: language,  // was: "fr"
        temperature: 0.0,
        usePrefillPrompt: true,
        usePrefillCache: true,
        skipSpecialTokens: true
    )
    // ... rest unchanged ...
}
```

### Conditional Filler Word Filtering
```swift
// TranscriptionService.swift — make FillerWordFilter conditional
let defaults = UserDefaults(suiteName: AppGroup.identifier)
let fillerWordsEnabled = defaults?.object(forKey: SharedKeys.fillerWordsEnabled) as? Bool ?? true

let cleaned = fillerWordsEnabled ? FillerWordFilter.clean(trimmed) : trimmed
return cleaned
```

### Adding Haptic Toggle Check to HapticFeedback
```swift
// HapticFeedback.swift — add isEnabled() check
public enum HapticFeedback {

    /// Check if haptic feedback is enabled in user settings.
    /// Reads from App Group UserDefaults each time to respect runtime changes.
    private static func isEnabled() -> Bool {
        #if canImport(UIKit) && !os(macOS)
        let defaults = UserDefaults(suiteName: "group.com.pivi.dictus")
        return defaults?.object(forKey: SharedKeys.hapticsEnabled) as? Bool ?? true
        #else
        return false
        #endif
    }

    public static func recordingStarted() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
    // ... same pattern for recordingStopped(), textInserted()

    /// New: light haptic for key taps (matching native iOS keyboard feel)
    public static func keyTapped() {
        #if canImport(UIKit) && !os(macOS)
        guard isEnabled() else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}
```

### Key Tap Haptic in KeyButton
```swift
// KeyButton.swift — add haptic feedback on tap
.onEnded { _ in
    isPressed = false
    longPressTimer?.cancel()
    longPressTimer = nil

    if showingAccents {
        if let index = selectedAccentIndex, index >= 0, index < accentOptions.count {
            onTap(accentOptions[index])
        }
        showingAccents = false
        accentOptions = []
        selectedAccentIndex = nil
    } else {
        onTap(outputChar)
        HapticFeedback.keyTapped()  // NEW: haptic on key tap
    }
    dragStartX = nil
}
```

### AccentPopup Color Fix
```swift
// AccentPopup.swift line 35 — replace Color.blue with DictusColors
.fill(index == selectedIndex
      ? Color.dictusAccent  // was: Color.blue
      : KeyMetrics.letterKeyColor)
```

### Adaptive BrandWaveform
```swift
// BrandWaveform.swift — adaptive bar width via GeometryReader
struct BrandWaveform: View {
    let energyLevels: [Float]
    var maxHeight: CGFloat = 80

    @Environment(\.colorScheme) private var colorScheme
    private let barCount = 30
    private let barSpacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let barWidth = max((geometry.size.width - totalSpacing) / CGFloat(barCount), 2)

            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    barView(index: index, barWidth: barWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.08), value: energyLevels)
    }
    // ... barView takes barWidth parameter instead of using stored property
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hardcoded `language: "fr"` | Read from App Group | This phase | Enables English transcription |
| Unconditional `FillerWordFilter.clean()` | Conditional on toggle | This phase | User can get raw Whisper output |
| Unconditional haptic calls | Guard on `hapticsEnabled` | This phase | User can disable haptics |
| Fixed bar width (5pt keyboard, 4pt app) | Adaptive via GeometryReader | This phase | Consistent 30 bars in all contexts |
| `Color.blue` in AccentPopup | `Color.dictusAccent` | This phase | Design system consistency |

## Open Questions

1. **Haptic Bug Root Cause**
   - What we know: HapticFeedback calls exist in KeyboardState (4 sites). User reports haptics are completely unfelt.
   - What's unclear: Whether this is a `prepare()` timing issue, a keyboard extension sandboxing issue, or a device/simulator issue.
   - Recommendation: Diagnose on-device. Try pre-warming generators. If `prepare()`+`impactOccurred()` in sequence is the issue, keep a generator instance alive on KeyboardState and call `prepare()` during init.

2. **AppGroup.identifier access from HapticFeedback**
   - What we know: HapticFeedback.swift is in DictusCore. AppGroup is also in DictusCore. Both compile on iOS.
   - What's unclear: Whether `AppGroup.identifier` (which is a DictusCore type) is available at the call site within the `#if canImport(UIKit) && !os(macOS)` guard.
   - Recommendation: It should work since both are in DictusCore. The `#if` guard only excludes the UIKit import, not Foundation types. Hardcoding the suite name string as fallback if needed.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (via Swift Package Manager) |
| Config file | DictusCore/Package.swift |
| Quick run command | `cd DictusCore && swift test --filter DictusCoreTests` |
| Full suite command | `cd DictusCore && swift test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| APP-03 | Settings toggles wired end-to-end | integration | Manual on-device (settings -> behavior) | N/A -- requires device |
| STT-01 | Language parameter read from settings | unit | `swift test --filter DictusCoreTests.SharedKeysExtensionTests` | Partial (SharedKeys tests exist) |
| STT-02 | Filler filter conditional on toggle | unit | `swift test --filter DictusCoreTests.FillerWordFilterTests` | Existing tests cover filter logic |
| DUX-03 | Haptics fire and respect toggle | manual-only | Physical device required (Taptic Engine) | N/A |

### Sampling Rate
- **Per task commit:** `cd DictusCore && swift test` (all 52 existing tests)
- **Per wave merge:** Full suite + Xcode build both targets
- **Phase gate:** All DictusCore tests green + device verification of all 5 success criteria

### Wave 0 Gaps
None -- existing test infrastructure covers the testable components. The core changes (wiring settings reads) are integration-level and require device verification. No new unit test files needed, though the existing `SharedKeysExtensionTests.swift` could be extended to verify default value behavior.

## Sources

### Primary (HIGH confidence)
- Project source code: TranscriptionService.swift, KeyboardState.swift, HapticFeedback.swift, SettingsView.swift, BrandWaveform.swift (both copies), AccentPopup.swift, DictusColors.swift, SharedKeys.swift, FillerWordFilter.swift
- .planning/v1.0-MILESTONE-AUDIT.md -- exact gap descriptions and integration issues
- .planning/phases/05-wire-settings-and-code-hygiene/05-CONTEXT.md -- locked decisions and code context

### Secondary (MEDIUM confidence)
- UIImpactFeedbackGenerator behavior in keyboard extensions -- based on Apple documentation and iOS keyboard extension capabilities. Haptics are supported in keyboard extensions (native keyboard uses them).

### Tertiary (LOW confidence)
- Haptic bug diagnosis -- requires on-device testing to determine root cause. Multiple hypotheses listed but none verified.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new libraries, all existing code
- Architecture: HIGH -- patterns already established in the project, just extending them
- Pitfalls: MEDIUM -- haptic bug diagnosis is uncertain; UserDefaults default values well-understood
- Code examples: HIGH -- based on reading actual project source code

**Research date:** 2026-03-07
**Valid until:** 2026-04-07 (stable -- no external dependencies changing)
