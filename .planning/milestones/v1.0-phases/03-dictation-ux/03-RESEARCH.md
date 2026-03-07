# Phase 3: Dictation UX - Research

**Researched:** 2026-03-06
**Domain:** iOS Keyboard Extension UX, Cross-Process Audio, SwiftUI Animations
**Confidence:** HIGH

## Summary

Phase 3 transforms the keyboard from a typing tool into a Wispr Flow-inspired dictation experience. The core challenge is architectural: iOS keyboard extensions **cannot record audio directly** (Apple explicitly prohibits microphone access in extensions regardless of RequestsOpenAccess). The existing two-process architecture (keyboard triggers DictusApp via URL scheme, DictusApp records and transcribes, results flow back via Darwin notifications + App Group) remains the correct foundation. What changes is the UX: the keyboard replaces its letter layout with a recording UI that mirrors DictusApp's recording state in real time.

The implementation involves five major areas: (1) redesigning the keyboard to show a toolbar with mic button + recording overlay that replaces the letter keys, (2) wiring auto-insert of transcription via `textDocumentProxy.insertText()`, (3) adding QWERTY as an alternative layout with accented character long-press on AZERTY, (4) haptic feedback via `UIImpactFeedbackGenerator` (iOS 16 compatible), and (5) an in-app test dictation screen.

**Primary recommendation:** Keep all audio recording in DictusApp. The keyboard's recording UI is a state mirror driven by Darwin notifications -- it shows waveform data, timer, and controls that signal back to DictusApp via App Group + Darwin notifications. The keyboard never touches AVAudioSession.

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- Dictation flow is Wispr Flow-inspired: tap mic -> DictusApp opens briefly for mic activation -> auto-return -> keyboard shows recording UI
- Recording UI replaces keyboard letters entirely during recording (waveform center, timer below, X cancel top-left, checkmark stop top-right)
- Text auto-inserts via `textDocumentProxy.insertText()` -- no preview bar, no confirmation step
- After insertion: keyboard snaps back to normal letter layout immediately -- no confirmation message
- No dedicated undo button -- DUX-02 dropped by user decision
- Toolbar row above keyboard: app/settings shortcut (left), mic button (right)
- Mic button states: subtle/muted idle, animated recording (keyboard transforms), shimmer/spinner transcribing
- AZERTY (default) + QWERTY switchable from Settings only (no in-keyboard toggle)
- QWERTY: no accented characters; AZERTY: add long-press accented character popups
- Layout preference persisted in App Group UserDefaults

### Claude's Discretion
- Exact toolbar dimensions and mic button sizing
- Waveform animation style during recording (bar count, colors, animation speed)
- Processing/transcribing state animation in keyboard
- Haptic feedback intensity and generator types
- Test dictation screen layout and integration point
- Accented character popup positioning and available characters per key
- How the toolbar left button (app/settings shortcut) works technically from a keyboard extension

### Deferred Ideas (OUT OF SCOPE)
- Logo and brand identity (Direction Artistique) -- Phase 4
- App navigation structure (TabBar) -- Phase 4
- Full design system pass (Liquid Glass, SF Pro, Dynamic Type) -- Phase 4

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DUX-01 | Transcribed text auto-inserted into active text field via textDocumentProxy | `textDocumentProxy.insertText()` pattern verified; auto-insert on `transcriptionReady` Darwin notification |
| DUX-02 | Undo last transcription insertion | **DROPPED by user decision** -- no undo button, manual select+delete instead |
| DUX-03 | Haptic feedback on recording start, stop, and text insertion | `UIImpactFeedbackGenerator` compatible with iOS 16+ and keyboard extensions |
| DUX-04 | Animated waveform during active recording | Existing `WaveformView` pattern reusable; energy data forwarded via App Group from AudioRecorder |
| KBD-02 | Full AZERTY keyboard layout | Already delivered in Phase 1 Plan 1.3; Phase 3 adds long-press accented characters |
| KBD-03 | QWERTY layout available as alternative | New `KeyboardLayout` static property with QWERTY rows; layout selection via App Group UserDefaults |
| KBD-05 | Mic button with clear visual states (idle, recording, transcribing) | Toolbar mic button with state-driven appearance; states tracked via `KeyboardState.dictationStatus` |
| APP-04 | In-app test dictation screen | New view in DictusApp with `TextEditor` + record button using existing `DictationCoordinator` |

</phase_requirements>

## Standard Stack

### Core (Already in Project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftUI | iOS 16+ | All keyboard and app UI | Project standard, already in use |
| UIKit | iOS 16+ | `UIInputViewController`, `textDocumentProxy`, haptics | Required for keyboard extension APIs |
| DictusCore | local SPM | Shared types, App Group, Darwin notifications | Project's cross-process framework |
| WhisperKit | latest via SPM | Audio recording + transcription (DictusApp only) | Already integrated in Phase 2 |

### Supporting (New for Phase 3)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| UIImpactFeedbackGenerator | iOS 10+ | Haptic feedback | Recording start/stop, text insertion |
| AVAudioSession | iOS 16+ | Audio session (DictusApp only) | Already used by AudioRecorder |

### No New Dependencies Required
Phase 3 uses only existing frameworks. No new SPM packages needed.

## Architecture Patterns

### Critical Constraint: Keyboard Extensions Cannot Record Audio

**Confidence: HIGH** (Apple official documentation)

Apple's Custom Keyboard documentation explicitly states: "Custom keyboards have no access to the device microphone, so dictation input is not possible." This applies regardless of `RequestsOpenAccess` setting. The existing two-process architecture is the only viable approach:

```
Keyboard (tap mic)
  -> Link(destination: "dictus://dictate") opens DictusApp
  -> DictusApp records audio via WhisperKit AudioProcessor
  -> DictusApp transcribes via WhisperKit
  -> DictusApp writes result to App Group UserDefaults
  -> DictusApp posts Darwin notification
  -> Keyboard receives notification, reads result
  -> Keyboard auto-inserts via textDocumentProxy.insertText()
```

### Architecture Change: Recording Control from Keyboard UI

The CONTEXT.md says "recording controlled from keyboard UI." This means:

1. **Start recording**: Keyboard taps mic -> opens DictusApp (same as Phase 1)
2. **Stop recording**: Keyboard writes a "stop" signal to App Group + posts Darwin notification -> DictusApp observes and calls `stopDictation()`
3. **Cancel recording**: Same pattern, keyboard writes "cancel" signal -> DictusApp discards audio

This requires **new Darwin notification names** for keyboard-to-app signaling (currently only app-to-keyboard exists):
- `com.pivi.dictus.stopRecording` (keyboard -> app)
- `com.pivi.dictus.cancelRecording` (keyboard -> app)

And **new DictationStatus cases** or SharedKeys for waveform data forwarding:
- `SharedKeys.waveformEnergy` -- serialized `[Float]` array written by DictusApp during recording
- DictusApp writes energy data to App Group on each audio buffer callback
- Keyboard reads on each `statusChanged` notification (or a dedicated `waveformUpdate` notification)

### Recommended Project Structure Changes

```
DictusKeyboard/
├── KeyboardRootView.swift      # Updated: conditional render normal vs recording UI
├── KeyboardState.swift         # Updated: new stop/cancel methods, waveform data
├── KeyboardViewController.swift # Minor: pass controller ref for textDocumentProxy
├── Models/
│   ├── KeyDefinition.swift     # Updated: accented characters data
│   ├── KeyboardLayer.swift     # Unchanged
│   └── KeyboardLayout.swift    # Updated: add QWERTY layout + layout selection logic
├── Views/
│   ├── KeyboardView.swift      # Updated: remove MicKey from bottom row, add toolbar
│   ├── KeyButton.swift         # Updated: add long-press for accented characters
│   ├── KeyRow.swift            # Minor updates for new key types
│   ├── SpecialKeyButton.swift  # Unchanged
│   ├── FullAccessBanner.swift  # Unchanged
│   ├── MicButtonDisabled.swift # May be removed/refactored
│   ├── ToolbarView.swift       # NEW: toolbar with app shortcut + mic button
│   ├── RecordingOverlay.swift  # NEW: full recording UI replacing keyboard
│   └── AccentPopup.swift       # NEW: long-press accented character picker
├── InputView.swift             # Unchanged
DictusApp/
├── DictationCoordinator.swift  # Updated: observe stop/cancel from keyboard
├── ContentView.swift           # Updated: add test dictation navigation
├── Views/
│   ├── RecordingView.swift     # Unchanged (DictusApp's recording UI)
│   └── TestDictationView.swift # NEW: in-app test dictation screen (APP-04)
DictusCore/
├── SharedKeys.swift            # Updated: new keys for layout, waveform, stop signal
├── DarwinNotifications.swift   # Updated: new notification names
├── DictationStatus.swift       # Possibly updated with new states
```

### Pattern: Keyboard Recording UI as State Mirror

The keyboard's recording overlay is a **read-only mirror** of DictusApp's state. It does NOT record audio. It:
1. Observes `DictationStatus` changes via Darwin notifications
2. Reads waveform energy data from App Group UserDefaults
3. Displays waveform visualization using the same `WaveformView` pattern from RecordingView
4. Writes stop/cancel signals back to App Group and posts notifications

```swift
// KeyboardState.swift -- new methods for Phase 3
func requestStop() {
    defaults.set(true, forKey: SharedKeys.stopRequested)
    defaults.synchronize()
    DarwinNotificationCenter.post(DarwinNotificationName.stopRecording)
}

func requestCancel() {
    defaults.set(true, forKey: SharedKeys.cancelRequested)
    defaults.synchronize()
    DarwinNotificationCenter.post(DarwinNotificationName.cancelRecording)
}
```

```swift
// DictationCoordinator.swift -- observe stop/cancel from keyboard
init() {
    // ... existing setup ...
    DarwinNotificationCenter.addObserver(
        for: DarwinNotificationName.stopRecording
    ) { [weak self] in
        DispatchQueue.main.async {
            self?.stopDictation()
        }
    }
    DarwinNotificationCenter.addObserver(
        for: DarwinNotificationName.cancelRecording
    ) { [weak self] in
        DispatchQueue.main.async {
            self?.cancelDictation()
        }
    }
}
```

### Pattern: Auto-Insert Transcription

```swift
// In KeyboardState.handleTranscriptionReady()
// Instead of storing lastTranscription for display, insert directly
private func handleTranscriptionReady() {
    refreshFromDefaults()
    if let transcription = defaults.string(forKey: SharedKeys.lastTranscription) {
        // Auto-insert via textDocumentProxy
        controller?.textDocumentProxy.insertText(transcription)
        // Fire haptic
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        // Reset to idle
        dictationStatus = .idle
        statusMessage = nil
    }
}
```

**Key issue:** `KeyboardState` needs a reference to the `UIInputViewController` (or its `textDocumentProxy`) to insert text. Currently it doesn't have one. Options:
- Pass `controller` reference into `KeyboardState` at init
- Use a callback/closure pattern
- Post a local notification that `KeyboardRootView` observes

**Recommendation:** Pass the controller reference. It's the simplest approach and matches the existing pattern where `KeyboardRootView` already receives `controller`.

### Pattern: Waveform Data Forwarding

Waveform energy data must flow from DictusApp's AudioRecorder to the keyboard extension. Two approaches:

**Option A: App Group UserDefaults (Recommended)**
- DictusApp writes energy array to UserDefaults on each buffer callback (~10Hz)
- Posts `waveformUpdate` Darwin notification after write
- Keyboard reads and displays
- Pros: Uses existing infrastructure
- Cons: ~10Hz update rate may feel slightly laggy; UserDefaults serialization overhead

**Option B: Shared file in App Group container**
- DictusApp writes binary Float array to a shared file
- Faster read/write than UserDefaults for binary data
- Pros: Lower overhead for frequent updates
- Cons: File I/O complexity, cleanup needed

**Recommendation:** Start with Option A (UserDefaults). The waveform is decorative -- slight lag is acceptable. If performance is poor on device, upgrade to Option B. The waveform update frequency can be throttled to ~5Hz to reduce cross-process overhead.

### Pattern: AZERTY Long-Press Accented Characters

```swift
// Accented character mapping for AZERTY
static let accentedCharacters: [String: [String]] = [
    "e": ["e", "e", "e", "e", "e"],  // e, e, e, e, ë
    "a": ["a", "a", "a"],              // a, a, a
    "u": ["u", "u", "u"],              // u, u, u
    "i": ["i", "i"],                    // i, i
    "o": ["o", "o"],                    // o, o
    "c": ["c"],                         // c
    "y": ["y"],                         // y
    "n": ["n"],                         // n (tilde)
]
```

**Implementation:** Long-press on a character key shows a horizontal popup above the key with accented variants. User slides finger to select. This matches native iOS keyboard behavior.

**Note:** The actual Unicode characters should be used (e, e, e, etc. are placeholders above -- the implementation must use proper Unicode: e -> [e, e, e, e, e]).

### Anti-Patterns to Avoid

- **Recording audio in the keyboard extension**: Impossible per Apple docs. Don't attempt AVAudioSession in the extension.
- **High-frequency UserDefaults writes**: Don't update waveform data at 60fps. Throttle to 5-10Hz.
- **Timer.scheduledTimer in keyboard extension**: Use `Task.sleep` instead (established pattern from Phase 1).
- **UIApplication.shared in keyboard extension**: Not available. Use `Link(destination:)` for URL scheme opening.
- **Blocking main thread for App Group reads**: Keep UserDefaults reads synchronous but small. Don't deserialize large objects on main.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Haptic feedback | Custom vibration patterns | `UIImpactFeedbackGenerator` | Standard API, 3 lines of code |
| Waveform visualization | Custom Core Graphics drawing | `WaveformView` (existing) | Already built in Phase 2, proven pattern |
| Cross-process signaling | Custom IPC mechanism | Darwin notifications + App Group | Established in Phase 1, working on device |
| Keyboard layout data | Runtime-computed layouts | Static `KeyboardLayout` data | Existing pattern, data-driven, easy to add QWERTY |
| Long-press gesture | Custom touch tracking | SwiftUI `LongPressGesture` + `DragGesture` | Built-in, composable |

## Common Pitfalls

### Pitfall 1: Waveform Data Race Condition
**What goes wrong:** Keyboard reads waveform energy from UserDefaults before DictusApp finishes writing it, showing stale or corrupted data.
**Why it happens:** Darwin notifications are "fire and forget" -- they arrive before UserDefaults propagation completes (same issue solved with 100ms retry in Phase 1).
**How to avoid:** Apply the same 100ms retry pattern for waveform reads. Alternatively, accept slight staleness since waveform is decorative.
**Warning signs:** Waveform bars freeze or jump erratically.

### Pitfall 2: Keyboard Memory Pressure
**What goes wrong:** Adding waveform animation + recording UI + accented popups pushes keyboard extension over ~50MB limit, causing iOS to terminate it.
**Why it happens:** Keyboard extensions have strict memory limits. Complex SwiftUI views with animations consume memory.
**How to avoid:** Keep waveform bar count reasonable (30-50 bars, not 100+). Don't load images. Don't cache large data structures. Profile with Instruments.
**Warning signs:** Keyboard disappears unexpectedly during recording or when showing accented popups.

### Pitfall 3: textDocumentProxy.insertText() Timing
**What goes wrong:** Auto-insert fires but text doesn't appear in the host app's text field.
**Why it happens:** The keyboard extension may not be the first responder when the transcription arrives, especially if DictusApp was just in the foreground.
**How to avoid:** Ensure insertion happens only after the keyboard is visible and has focus. Check that `textDocumentProxy` is responsive before inserting.
**Warning signs:** Transcription completes but text doesn't appear; no error thrown.

### Pitfall 4: Stop Signal Not Received by DictusApp
**What goes wrong:** User taps checkmark (stop) in keyboard recording UI, but DictusApp doesn't stop recording.
**Why it happens:** DictusApp may be suspended in background. Darwin notifications can be delayed or dropped for suspended apps.
**How to avoid:** DictusApp must declare `audio` background mode to stay active during recording. Verify background audio session keeps the app alive.
**Warning signs:** Tapping stop does nothing; recording continues indefinitely.

### Pitfall 5: DictusApp Not Auto-Returning to Previous App
**What goes wrong:** After tapping mic, DictusApp opens but doesn't return the user to their previous app.
**Why it happens:** iOS has no API to programmatically return to the previous app. The user must tap the "< Back" chevron.
**How to avoid:** This is a known limitation (documented in STATE.md). DictusApp should minimize its visible time -- start recording immediately and present minimal UI. The user can tap back to their app using the iOS status bar chevron.
**Warning signs:** User confusion about how to get back to their typing app.

### Pitfall 6: Accented Character Popup Clipping
**What goes wrong:** Long-press popup for accented characters gets clipped by the keyboard extension's bounds.
**Why it happens:** Apple's docs note that keyboard extensions cannot draw above their top edge. Popups that extend above the keyboard view area will be clipped.
**How to avoid:** Position accented character popups to stay within the keyboard's frame. For top-row keys, consider showing the popup beside or below the key instead of above.
**Warning signs:** Popup appears cut off for top-row letter keys (A, Z, E, R, etc.).

## Code Examples

### Haptic Feedback Helper

```swift
// Source: UIKit UIFeedbackGenerator documentation
enum HapticFeedback {
    static func recordingStarted() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    static func recordingStopped() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    static func textInserted() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}
```

**Note:** `UIImpactFeedbackGenerator` works in keyboard extensions (it doesn't require UIApplication.shared). iOS 16+ compatible. The `.prepare()` call reduces latency by pre-spinning the Taptic Engine.

### QWERTY Layout Data

```swift
// KeyboardLayout.swift addition
static let qwertyLettersRows: [[KeyDefinition]] = [
    ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"].map {
        KeyDefinition($0, output: $0.lowercased())
    },
    ["A", "S", "D", "F", "G", "H", "J", "K", "L"].map {
        KeyDefinition($0, output: $0.lowercased())
    },
    [
        KeyDefinition("shift", type: .shift, width: 1.5),
        KeyDefinition("Z", output: "z"),
        KeyDefinition("X", output: "x"),
        KeyDefinition("C", output: "c"),
        KeyDefinition("V", output: "v"),
        KeyDefinition("B", output: "b"),
        KeyDefinition("N", output: "n"),
        KeyDefinition("M", output: "m"),
        KeyDefinition("delete", type: .delete, width: 1.5),
    ],
    // Row 4: same bottom row as AZERTY
    [
        KeyDefinition("globe", type: .globe, width: 1.2),
        KeyDefinition("123", type: .layerSwitch, width: 1.2),
        KeyDefinition("mic", type: .mic, width: 1.0),
        KeyDefinition("space", output: " ", type: .space, width: 3.5),
        KeyDefinition("return", type: .returnKey, width: 1.8),
    ],
]
```

### Layout Selection from App Group

```swift
// SharedKeys addition
public static let keyboardLayout = "dictus.keyboardLayout"

// KeyboardLayout selection
enum LayoutType: String {
    case azerty = "azerty"
    case qwerty = "qwerty"
}

static var activeLayout: LayoutType {
    let raw = AppGroup.defaults.string(forKey: SharedKeys.keyboardLayout) ?? "azerty"
    return LayoutType(rawValue: raw) ?? .azerty
}

static var currentLettersRows: [[KeyDefinition]] {
    switch activeLayout {
    case .azerty: return lettersRows
    case .qwerty: return qwertyLettersRows
    }
}
```

### Recording Overlay Structure

```swift
// RecordingOverlay.swift -- replaces keyboard during recording
struct RecordingOverlay: View {
    let onCancel: () -> Void
    let onStop: () -> Void
    let waveformEnergy: [Float]
    let elapsedSeconds: Double

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: X (cancel) ... checkmark (stop)
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Button(action: onStop) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            // Center: waveform
            WaveformView(energyLevels: waveformEnergy)
                .frame(height: 60)
                .padding(.horizontal, 24)

            // Timer below waveform
            Text(formatTime(elapsedSeconds))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(.top, 8)

            Spacer()
        }
        .background(Color.black.opacity(0.95))
    }
}
```

### Toolbar with Mic Button

```swift
// ToolbarView.swift -- sits above keyboard letters
struct ToolbarView: View {
    let hasFullAccess: Bool
    let dictationStatus: DictationStatus
    let onMicTap: () -> Void

    var body: some View {
        HStack {
            // Left: app shortcut (opens DictusApp settings)
            if hasFullAccess {
                Link(destination: URL(string: "dictus://settings")!) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Right: mic button with state-driven appearance
            MicToolbarButton(
                status: dictationStatus,
                hasFullAccess: hasFullAccess
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Preview bar + confirm/dismiss | Auto-insert directly | Phase 3 (user decision) | Simpler UX, fewer components |
| Mic button in bottom keyboard row | Mic in toolbar above keyboard | Phase 3 (user decision) | Toolbar pattern like Wispr Flow |
| Recording UI in DictusApp only | Recording UI mirrored in keyboard | Phase 3 (user decision) | Immersive recording experience |
| No accented characters | Long-press popups on AZERTY | Phase 3 delivery | Better French typing |

## Open Questions

1. **Waveform data forwarding performance**
   - What we know: UserDefaults works for single values; waveform needs ~30-50 floats at 5-10Hz
   - What's unclear: Whether serializing `[Float]` to UserDefaults at 5-10Hz causes UI jank in either process
   - Recommendation: Start with UserDefaults + JSON encoding. Profile on device. Fall back to shared file if laggy.

2. **DictusApp background mode for recording**
   - What we know: DictusApp records audio when opened via URL scheme. User returns to their app while recording continues.
   - What's unclear: Whether DictusApp stays alive in background long enough for full dictation. iOS may suspend it.
   - Recommendation: Add `audio` background mode to DictusApp's Info.plist. The active AVAudioSession with `.record` category should keep it alive. Test on device with recordings >30 seconds.

3. **Left toolbar button behavior from keyboard extension**
   - What we know: `Link(destination:)` can open URL schemes from keyboard extensions
   - What's unclear: Whether `dictus://settings` is the best route, or if it should open the main app generally
   - Recommendation: Use `dictus://` (no specific host) to just open the app. Settings-specific routing can be added in Phase 4 when the settings screen exists.

4. **Stop/cancel signal reliability when DictusApp is backgrounded**
   - What we know: Darwin notifications work cross-process. But backgrounded apps may have reduced notification delivery.
   - What's unclear: Whether DictusApp reliably receives Darwin notifications while recording in background
   - Recommendation: Test on device. If unreliable, add a polling fallback where DictusApp checks App Group for stop/cancel flags every 500ms during recording.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (built-in) |
| Config file | DictusCore/Package.swift (test target defined) |
| Quick run command | `xcodebuild test -scheme DictusCore -destination 'platform=iOS Simulator,name=iPhone 16'` |
| Full suite command | `xcodebuild test -scheme DictusCore -destination 'platform=iOS Simulator,name=iPhone 16'` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DUX-01 | Auto-insert text via textDocumentProxy | manual-only | N/A -- requires keyboard extension context | N/A |
| DUX-02 | DROPPED | N/A | N/A | N/A |
| DUX-03 | Haptic feedback triggers | manual-only | N/A -- requires physical device Taptic Engine | N/A |
| DUX-04 | Waveform animation during recording | manual-only | N/A -- visual + cross-process | N/A |
| KBD-02 | AZERTY layout (accented characters added) | unit | `swift test --filter AccentedCharacterTests` | No -- Wave 0 |
| KBD-03 | QWERTY layout available | unit | `swift test --filter QWERTYLayoutTests` | No -- Wave 0 |
| KBD-05 | Mic button visual states | manual-only | N/A -- visual state changes in extension | N/A |
| APP-04 | In-app test dictation screen | manual-only | N/A -- end-to-end with audio | N/A |

**Justification for manual-only tests:** Most Phase 3 requirements involve keyboard extension UI rendering, cross-process communication timing, hardware haptics, and audio recording -- none of which can be unit tested in isolation. The testable units are layout data structures (QWERTY layout correctness, accented character mappings).

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme DictusCore -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
- **Per wave merge:** Full test suite + manual on-device testing of dictation flow
- **Phase gate:** All unit tests green + manual UAT of complete dictation round-trip

### Wave 0 Gaps
- [ ] `DictusCore/Tests/DictusCoreTests/QWERTYLayoutTests.swift` -- covers KBD-03 (QWERTY row counts, key labels)
- [ ] `DictusCore/Tests/DictusCoreTests/AccentedCharacterTests.swift` -- covers KBD-02 (accent mappings for all AZERTY keys)
- [ ] Move `KeyboardLayout` and `KeyDefinition` to DictusCore so they are testable (currently in DictusKeyboard target which has no test target)

*(Note: Most Phase 3 requirements are manual-only. Wave 0 gaps are limited to data model tests.)*

## Sources

### Primary (HIGH confidence)
- [Apple Custom Keyboard Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html) -- keyboard extension capabilities and limitations, microphone access prohibition
- [Apple UITextDocumentProxy documentation](https://developer.apple.com/documentation/uikit/uitextdocumentproxy) -- insertText API for text insertion
- [Apple SensoryFeedback documentation](https://developer.apple.com/documentation/swiftui/sensoryfeedback) -- iOS 17+ only (not usable, project targets iOS 16)
- Existing codebase analysis -- KeyboardState.swift, DictationCoordinator.swift, KeyboardLayout.swift, RecordingView.swift

### Secondary (MEDIUM confidence)
- [Wispr Flow documentation](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone) -- confirmed two-process architecture pattern (keyboard opens main app for recording)
- [9to5Mac Wispr Flow review](https://9to5mac.com/2025/06/30/wispr-flow-is-an-ai-that-transcribes-what-you-say-right-from-the-iphone-keyboard/) -- UX flow reference
- [Hacking with Swift UIFeedbackGenerator](https://www.hackingwithswift.com/example-code/uikit/how-to-generate-haptic-feedback-with-uifeedbackgenerator) -- haptic implementation patterns

### Tertiary (LOW confidence)
- Waveform data forwarding via UserDefaults at 5-10Hz -- untested performance assumption, needs device validation
- DictusApp background recording persistence -- needs device testing to confirm `audio` background mode keeps app alive

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, all existing frameworks
- Architecture: HIGH -- keyboard extension limitations well-documented, two-process pattern proven in Phases 1-2
- Waveform forwarding: MEDIUM -- pattern is sound but cross-process performance at 5-10Hz untested
- Pitfalls: HIGH -- based on established patterns and Apple documentation
- Accented characters: MEDIUM -- implementation pattern clear, popup clipping edge case needs testing

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (stable iOS APIs, no fast-moving dependencies)
