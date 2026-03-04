# Pitfalls Research

*Research date: 2026-03-04*

---

## Critical Pitfalls

These are show-stoppers that can kill the project if not addressed early.

---

### 1. Microphone Access Is Blocked in Keyboard Extensions by Default

**The pitfall:** iOS keyboard extensions cannot access the microphone by default. The restriction has been in place since iOS 8. Even with `RequestsOpenAccess = true` in `Info.plist` and the user granting Full Access in Settings, audio recording via `AVAudioEngine` or `AVAudioRecorder` frequently fails with error code `561145187` (`kAudioSessionIncompatibleCategory`). Apple's documentation is misleading — it lists microphone as a capability unlocked by Full Access, but the sandbox enforcement at the OS level is inconsistent and device-dependent.

**Evidence:** Multiple Apple Developer Forums threads confirm that enabling `RequestsOpenAccess` is necessary but not sufficient. Developers report that `AVAudioSession.sharedInstance().requestRecordPermission` succeeds (returns `true`) but then `AVAudioEngine.start()` still fails. The error is `com.apple.coreaudio.avfaudio Code=561145187` with the call failing at `kAUStartIO`.

**Warning signs:**
- Testing only in the Simulator (audio always works there; the Simulator does not enforce extension sandboxing)
- Assuming Full Access == microphone access because Apple's docs imply it
- No error handling around `AVAudioEngine.start()`

**Prevention strategy:**
- Treat microphone recording as a privileged feature that may fail even when permissions appear granted
- Wrap all audio session setup in `do/catch` and display a clear degraded-mode UI
- Test exclusively on physical devices from day one, not the Simulator
- Architecture: record audio in the containing app (main app target), not the extension. The keyboard extension triggers a deep link or IPC message to the main app, which records the audio and writes the result to the App Group shared container. The extension then reads the transcript. This is the only fully reliable pattern.
- If in-extension recording is attempted: configure `AVAudioSession` with `.record` category before calling `requestRecordPermission`, and add `NSMicrophoneUsageDescription` in **both** the main app `Info.plist` and the extension's `Info.plist`

**Phase:** Architecture (Phase 0 / Sprint 0). Choosing between in-extension and main-app recording is a foundational architectural decision that cannot be changed cheaply later.

---

### 2. Memory Limit Is ~30MB, Not 50MB — WhisperKit's Tiny Model May Not Fit

**The pitfall:** The PROJECT.md states the memory limit is "~50MB." Empirical evidence from developer forums and crash reports puts the actual jetsam kill threshold for keyboard extensions at **~30MB on most devices**, not 50MB. The limit is not publicly documented by Apple and varies by device RAM and OS version. It is enforced by jetsam (the iOS OOM killer) and the extension process is terminated without warning when it is exceeded.

WhisperKit's models (even the smallest) carry significant memory overhead when loaded:
- `openai_whisper-tiny`: ~40–60MB resident memory once loaded into Core ML (the on-disk `.mlmodelc` package is smaller, but Core ML expands it in memory during compilation and inference)
- `openai_whisper-small`: well above the limit for any extension
- Core ML model compilation at first launch adds a **temporary spike** of 1.5–2x the model's resident size

Loading even the tiny model inside the keyboard extension process is likely to cause a jetsam termination on devices with 3–4GB RAM or less.

**Warning signs:**
- The app works fine in the Simulator but crashes silently on device
- Crashes appear in device logs as `jetsam` events with no stack trace
- Memory profiling shows a spike when WhisperKit loads that exceeds 30MB
- First launch after install always crashes (Core ML compilation spike)

**Prevention strategy:**
- Do not instantiate `WhisperKit` inside the keyboard extension process at all
- Run all inference in the containing app (main app target) and share results via App Group
- If in-extension inference is non-negotiable: use `ModelComputeOptions` to restrict to Neural Engine only (smallest memory footprint), lazy-load the model only when dictation is explicitly requested, and release it immediately after transcription (`whisperKit = nil`)
- Pre-compile Core ML models in the main app on first launch so the extension never incurs compilation overhead
- Track memory with Xcode Instruments `Allocations` and `VM Tracker` on an iPhone 12 (4GB RAM) — the lowest-end A14 target
- Set a conservative internal budget of 25MB total extension memory (all code, heap, stack, assets)

**Phase:** Architecture (Phase 0). Determines whether inference runs in-extension or via IPC to main app.

---

### 3. The Extension Cannot Use `UIApplication.shared` — Crashes at Runtime

**The pitfall:** `UIApplication.shared` is unavailable in app extensions and calling it crashes the process with `EXC_BAD_INSTRUCTION`. This is enforced at the linker/runtime level. Many SwiftUI and UIKit APIs call into `UIApplication.shared` internally, including:
- `UIApplication.shared.open(_:)` (deep links)
- `UIPasteboard.general` (when not in an extension context)
- Some `UIScene` APIs
- Haptic feedback APIs (`UIImpactFeedbackGenerator` sometimes works, sometimes not)

Third-party dependencies (analytics SDKs, crash reporters, logging frameworks) often call `UIApplication.shared` and will crash the extension.

**Warning signs:**
- Any SPM dependency that is not explicitly extension-safe
- Using `UIApplication.shared.open()` to redirect users to Settings or the main app
- Initializing analytics/tracking in the extension target

**Prevention strategy:**
- Enable `EXTENSION_SAFE_API_ONLY = YES` in the extension target's build settings — Xcode will emit a compile-time error for forbidden APIs
- Audit every SPM dependency: check if it declares `APPLICATION_EXTENSION_API_ONLY` support or explicitly states extension compatibility
- To open URLs from the extension (e.g., to navigate to Settings), use `self.extensionContext?.open(url, completionHandler: nil)` — not `UIApplication.shared.open()`
- Do not link analytics, crash reporters, or logging SDKs into the keyboard extension target

**Phase:** Project setup (Sprint 1). Enable `EXTENSION_SAFE_API_ONLY` before writing any extension code.

---

### 4. Full Access Is Not Granted by Default — Users Must Manually Enable It

**The pitfall:** After installing the keyboard and enabling it in Settings > General > Keyboard > Keyboards, the user must *separately* navigate to Settings > General > Keyboard > Keyboards > Dictus > Allow Full Access and toggle it on. Most users will not do this. Without Full Access:
- No network access from the extension
- No App Group shared container writes (reads still work)
- Microphone access is unavailable
- The keyboard cannot communicate results back to the main app via shared UserDefaults

A keyboard that silently fails because Full Access is off will confuse users and generate negative reviews.

**Warning signs:**
- Testing with a development provisioning profile (Full Access is easier to grant during dev)
- Not detecting Full Access state in the extension
- UI that shows the dictation button even when Full Access is off

**Prevention strategy:**
- Detect Full Access state using `UIPasteboard` access as a proxy: `UIPasteboard.general.hasStrings` will throw if Full Access is not granted
- Alternatively, check App Group container accessibility: attempt to read from `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` — returns `nil` without Full Access
- Show a prominent non-dismissible banner when Full Access is off: "Dictation requires Full Access. Tap here to enable it." with a deep link to the Settings page
- Include a dedicated onboarding step in the main app for Full Access setup with visual instructions
- The dictation button must be visually disabled (greyed out) when Full Access is off, not silently non-functional

**Phase:** Onboarding flow (Sprint 2).

---

## Common Mistakes

Frequent errors that waste significant development time.

---

### 5. SwiftUI in Keyboard Extensions: Height and Layout Failures

**The pitfall:** Keyboard extensions must set their own height via constraints on `inputView` or `inputViewController.view`. SwiftUI's `UIHostingController` does not automatically communicate its `intrinsicContentSize` to the hosting UIKit layer in all iOS versions. The keyboard can appear with 0 height, incorrect height, or flicker between heights.

Specific issues:
- `UIHostingController` does not update its view's intrinsic content size automatically when the SwiftUI view's content changes (fixed in iOS 16 with `.intrinsicContentSize` sizing option, but requires explicit opt-in)
- SwiftUI's `ignoresSafeArea(.keyboard)` modifier interacts badly inside an extension because the extension IS the keyboard — safe area semantics are inverted
- Using `@State` with large state objects can trigger excessive re-renders that cause layout thrashing

**Warning signs:**
- The keyboard view appears blank or too tall/short after the first render
- Layout constraint conflict warnings in the console
- SwiftUI preview works but the extension does not render correctly on device

**Prevention strategy:**
- Set keyboard height explicitly via a `NSLayoutConstraint` on `inputViewController.view.heightAnchor` in `viewDidAppear`, not `viewDidLoad`
- On iOS 16+, use `UIHostingController(rootView:)` followed by `hostingController.sizingOptions = .intrinsicContentSize`
- On iOS 15, manually call `hostingController.view.invalidateIntrinsicContentSize()` whenever SwiftUI content changes
- Use a thin `UIKit` wrapper (`KeyboardViewController`) as the root and host SwiftUI views as children — do not attempt to make `UIInputViewController` itself a pure SwiftUI entry point
- Avoid `ignoresSafeArea` modifiers in keyboard views; set height explicitly instead

**Phase:** Sprint 1 (keyboard scaffold setup).

---

### 6. `textDocumentProxy` Is Unreliable for Reading Context

**The pitfall:** `textDocumentProxy.documentContextBeforeInput` returns at most ~300 characters before the cursor. It returns `nil` in:
- Password fields
- Secure text entry fields
- Some web views (`WKWebView`)
- Immediately after `insertText()` (proxy state is stale for one run loop cycle)

After calling `insertText()` to place a transcription, the proxy's context does not update synchronously. Reading it immediately after insertion gives you the pre-insertion text.

Additionally, `adjustTextPosition(byCharacterOffset:)` can move the cursor unexpectedly in some editors.

**Warning signs:**
- Assuming the context always reflects the current document state
- Reading `documentContextBeforeInput` immediately after `insertText()`
- Testing only in `UITextField` (which is the most reliable host — real apps use `UITextView`, `WKWebView`, etc.)

**Prevention strategy:**
- Always guard for `nil` on `documentContextBeforeInput` and `documentContextAfterInput`
- After `insertText()`, wait one run loop (`DispatchQueue.main.async`) before reading context again
- Test with: UITextField, UITextView, Safari web view, Notes, Messages, Mail, WhatsApp — they each have different proxy behaviors
- Never attempt to "read back" inserted text via the proxy to confirm success — use your own state instead
- For the undo feature: track what was inserted in a local variable; do not rely on the proxy to tell you what to delete

**Phase:** Sprint 2 (text insertion and dictation flow).

---

### 7. WhisperKit First-Load Cold Start and Core ML Compilation

**The pitfall:** When WhisperKit loads a model for the first time on a new device or after an OS update, Core ML must compile the `.mlpackage` → `.mlmodelc` on the device. This takes **10–60 seconds** on older A-series chips and consumes significantly more memory during compilation than during inference. If this happens inside the extension, the jetsam killer will terminate the process.

Additionally, if the model download is interrupted, the resulting `.mlmodelc` file is corrupted. About 20% of WhisperKit users hit this issue (per GitHub Issue #171). The corrupted file causes `prewarmModels()` to throw: `coremldata.bin is not a valid .mlmodelc file`.

**Warning signs:**
- Model download happens inside the extension
- No integrity check on the downloaded model files before loading
- Using `WhisperKit(prewarm: true)` in the extension (will spike memory during compilation)

**Prevention strategy:**
- All model downloading and Core ML compilation must happen in the **main app target**, never in the extension
- After download completes in the main app, call `try await WhisperKit.prewarmModels()` there to trigger compilation, then write a `modelReady: true` flag to the App Group `UserDefaults`
- The extension reads this flag before attempting to use the model
- On load, verify model integrity: check that `audioEncoder.mlmodelc`, `textDecoder.mlmodelc`, and `melspectrogram.mlmodelc` directories are non-empty and contain `model.mil`
- If corruption is detected, delete the model folder and prompt the user to re-download from the main app
- Use `WhisperKitConfig(modelFolder: sharedContainerPath)` to point the extension at the App Group model location

**Phase:** Sprint 3 (model manager and onboarding).

---

### 8. App Group Configuration Mismatch Between Targets

**The pitfall:** Both the main app target and the keyboard extension target must have identical App Group identifiers in their entitlements **and** both must be backed by the same provisioning profile that includes the `com.apple.security.application-groups` capability. If either target's profile is out of sync, the shared container returns `nil` at runtime — no error, just `nil`. This is the most common silent failure in keyboard extension development.

Common triggers:
- Adding the App Group in Xcode for the app target but forgetting to add it to the extension target
- Regenerating provisioning profiles without re-adding the App Group
- Using automatic signing for one target and manual for the other
- Build configurations (Debug vs Release) using different provisioning profiles where only one has the App Group

**Warning signs:**
- `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pivi.dictus")` returns `nil`
- `UserDefaults(suiteName: "group.com.pivi.dictus")` returns a non-nil object but writes do not persist between app and extension (because each target is using its own sandbox)
- Everything works in Simulator but fails on device

**Prevention strategy:**
- On the Apple Developer portal, create the App Group `group.com.pivi.dictus` and explicitly add it to BOTH App IDs (`com.pivi.dictus` and `com.pivi.dictus.keyboard`)
- Download fresh provisioning profiles for both targets after any capability change
- Write a diagnostic function that checks App Group access on launch of both targets: log whether `containerURL` is non-nil
- Use **consistent signing mode** (both automatic or both manual) across targets
- In CI/CD, regenerate profiles after any entitlement change

**Phase:** Sprint 1 (project setup and extension skeleton).

---

### 9. WhisperKit Memory Leak When Re-Instantiating

**The pitfall:** WhisperKit leaks memory when destroyed and re-created (e.g., if the extension tries to load/unload the model between sessions). Issue #265 confirmed this on macOS; the underlying cause is Core ML backend resource retention that the OS does not always reclaim when the Swift object is deallocated. On iOS the behavior is similar — `whisperKit = nil` does not guarantee that Core ML has freed its GPU/ANE buffers.

**Warning signs:**
- Memory grows each time the user activates/deactivates dictation
- Memory does not return to baseline after `whisperKit = nil`

**Prevention strategy:**
- Load the WhisperKit instance **once** and keep it alive for the lifetime of the session
- If memory pressure forces unloading, call `try await whisperKit.unloadModels()` before setting to `nil`
- Use `ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine)` — the Neural Engine path has fewer memory retention issues than GPU
- Profile with Instruments > VM Tracker across multiple dictation cycles before shipping

**Phase:** Sprint 3 (dictation engine integration).

---

## App Store Review Risks

Things that have caused keyboard extensions to be rejected or flagged.

---

### 10. Privacy Usage Descriptions Are Insufficient or Missing

**Risk:** Apple will reject the submission if `NSMicrophoneUsageDescription` is present in `Info.plist` but the description is vague ("This app uses the microphone") or does not clearly explain the specific use case. In 2024–2025, Apple has tightened this requirement significantly.

Required in **both** targets (main app and extension) if microphone is used in either:
- `NSMicrophoneUsageDescription` — must explain dictation purpose in plain user-facing language
- If recording happens in-extension: the extension's `Info.plist` must also have this key

**Prevention strategy:**
- Write descriptions that name the specific feature: "Dictus records your voice only when you tap the microphone button to transcribe speech to text. Your audio is processed entirely on your device and never sent to any server."
- Include this text in the App Store review notes as well
- Do not include `NSMicrophoneUsageDescription` in a target that does not actually request microphone access — reviewers check that declared permissions match actual API usage

---

### 11. Requesting Full Access Without Adequate Justification

**Risk:** Apple's App Review team scrutinizes `RequestsOpenAccess = true` because it gives the keyboard access to the clipboard and (potentially) keystrokes. If the review notes do not explain why Full Access is needed, the app may be rejected under Guideline 5.1.1 (Data Collection and Storage).

**Prevention strategy:**
- In the App Review Information notes field, explicitly state: "Full Access is required to share the transcribed text from the keyboard extension back to the main app via an App Group shared container, and to allow the keyboard to read microphone permission status."
- The App Store description must not claim the app is "secure" or "private" without qualifying: on-device processing should be mentioned but not used as a marketing shield without technical accuracy
- Do not request Full Access if the core keyboard functionality (typing) works without it — only dictation should require it

---

### 12. Network Entitlement Without a Clear Explanation

**Risk:** `RequestsOpenAccess = true` enables network access from the extension. If the extension makes any network requests (e.g., for model download checks, analytics, or telemetry), App Review will scrutinize the privacy policy for whether this is disclosed. An extension that requests open access but makes undisclosed network calls is grounds for rejection under Guideline 5.1.2.

**Prevention strategy:**
- Keep all network access in the main app, not the extension
- The extension should only use the shared container and local file system
- If the extension must check for model updates, do this via the main app on foreground events, not from the extension at keyboard load time

---

### 13. Missing Keyboard Functionality Without Full Access (Guideline 4.5.1)

**Risk:** Apple's Guideline 4.5.1 requires that custom keyboards provide a basic level of functionality (alphanumeric keyboard) without Full Access. A keyboard that shows nothing or is non-functional when Full Access is off will be rejected.

**Prevention strategy:**
- AZERTY typing, delete, space, and return must work regardless of Full Access state
- The microphone button should be visible but clearly disabled with an explanatory tooltip when Full Access is off
- Do not gate basic text insertion on Full Access

---

### 14. Extension Crashes During App Review Testing

**Risk:** App Review tests on a range of devices including older models. A keyboard extension that crashes due to memory pressure on an iPhone 12 (4GB RAM) with other apps open will be rejected as unstable.

**Prevention strategy:**
- Test on the oldest supported device in its worst-case state: multiple apps backgrounded, low storage, background app refresh active
- Add `NSExceptionMaximumBytesForJetsamException` awareness — monitor memory in the extension and gracefully degrade before the OS kills the process
- If WhisperKit is running in-extension, test with the profile attached to catch jetsam events before submission

---

## Prevention Strategies

Consolidated actionable steps organized by development phase.

---

### Phase 0: Architecture Decisions (Before Writing Code)

1. **Decide: in-extension inference vs. main-app inference.** Given the ~30MB memory limit, running WhisperKit in the extension is high-risk. The recommended architecture: extension records audio (if microphone access works) or uses a visual trigger to hand off to the main app, which runs inference and writes the transcript to the App Group shared container.

2. **Decide: in-extension recording vs. main-app recording.** The safest architecture: extension activates the main app (via `extensionContext?.open()` with a custom URL scheme) which presents a recording UI, transcribes, then returns the result. The tradeoff is UX friction (user leaves the keyboard momentarily). Alternatively, attempt in-extension recording with a robust fallback to the main-app pattern.

3. **Define the App Group identifier once:** `group.com.pivi.dictus`. Never hardcode it — put it in a shared `Constants.swift` file compiled into both targets.

### Phase 1: Project Setup (Sprint 1)

4. Enable `EXTENSION_SAFE_API_ONLY = YES` for the keyboard extension target immediately.
5. Set up App Group in Apple Developer portal for both App IDs before writing any code that uses shared storage.
6. Write a `AppGroupDiagnostic.swift` that verifies container access on launch in both targets and logs the result — run this before adding any other feature.
7. Use consistent signing: both targets use automatic signing with the same team, or both use manual.
8. Write a unit test that instantiates `UserDefaults(suiteName: "group.com.pivi.dictus")` and round-trips a value — run this in the extension's unit test target.

### Phase 2: Keyboard UI (Sprint 1–2)

9. Set keyboard height via `NSLayoutConstraint` in `viewDidAppear`, not in a SwiftUI body.
10. Use `UIHostingController` with `sizingOptions = .intrinsicContentSize` (iOS 16+).
11. Test layout on: iPhone 12 mini (small screen), iPhone 15 Pro Max (large screen), landscape orientation.
12. Add full graceful degradation for "Full Access off" state: typing works, dictation button is disabled with an explanation tooltip.

### Phase 3: Dictation (Sprint 2–3)

13. Request microphone permission from the **main app** during onboarding, not from the extension.
14. Add integrity verification for downloaded WhisperKit model files before first use.
15. Run all Core ML model compilation in the main app, write `modelReady` flag to App Group `UserDefaults`.
16. Test dictation on iPhone 12 (A14, 4GB RAM) with 5 other apps in the background.
17. Track memory usage with Instruments > Allocations across 10 consecutive dictation cycles.

### Phase 4: App Store Submission

18. Write specific, accurate `NSMicrophoneUsageDescription` in both `Info.plist` files.
19. Add App Review notes explaining why `RequestsOpenAccess` is needed.
20. Verify that typing (AZERTY layout, delete, space, return) works with Full Access off.
21. Test on the oldest supported device (iPhone 12, iOS 16) with the Simulator off — physical device only.
22. Run the full onboarding flow as a new user to confirm the Full Access setup step is clear and unambiguous.

---

*Sources consulted: Apple Developer Forums (threads 742601, 85478, 105815), WhisperKit GitHub Issues #171 and #265, Medium articles on iOS keyboard extension limitations, KeyboardKit blog, Apple App Extension Programming Guide, Daniel Saidi's App Group blog post.*
