// DictusCore/Sources/DictusCore/SharedKeys.swift
import Foundation

/// Centralized UserDefaults keys for App Group shared storage.
/// Using an enum with static properties prevents typo-based bugs.
public enum SharedKeys {
    public static let dictationStatus = "dictus.dictationStatus"
    public static let lastTranscription = "dictus.lastTranscription"
    public static let lastTranscriptionTimestamp = "dictus.lastTranscriptionTimestamp"
    public static let lastError = "dictus.lastError"

    // Model management keys (added for Plan 2.3 transcription pipeline)
    public static let activeModel = "dictus.activeModel"
    public static let modelReady = "dictus.modelReady"
    public static let downloadedModels = "dictus.downloadedModels"
    /// Tri-state model lifecycle: "idle" / "loading" / "ready".
    /// "idle" = no active load in flight, but `modelReady` may still be true.
    /// "loading" = WhisperKit/Parakeet is being loaded into RAM (or compiling/downloading).
    /// "ready" = active model is loaded in RAM and `transcribe()` calls will succeed.
    /// The keyboard reads this to refuse mic taps during load (issue #144).
    public static let modelLoadState = "dictus.modelLoadState"

    // Keyboard-App cross-process contracts (added for Plan 3.1)
    /// Legacy single global keyboard layout, stored as String ("azerty"/"qwerty"/"qwertz").
    /// Since #272 the layout is per dictionary language — see `keyboardLayoutsByLanguage`.
    /// This key is now only *read* by the one-time migration, and kept up to date as a
    /// mirror of the active language's layout so a rollback to a build without #272 finds
    /// the shape the user is on. Nothing else should read or write it.
    public static let keyboardLayout = "dictus.keyboardLayout"
    /// Keyboard layout per dictionary language (#272): `[SupportedLanguage.rawValue: LayoutType.rawValue]`.
    /// An entry means the user explicitly chose that layout for that language; a missing
    /// entry means the language still inherits `SupportedLanguage.defaultLayout` and keeps
    /// tracking it. The presence of the dictionary itself — even empty — is the marker that
    /// the migration from `keyboardLayout` has run. Read and written only through
    /// `KeyboardLayoutPreference`.
    public static let keyboardLayoutsByLanguage = "dictus.keyboardLayoutsByLanguage"
    /// Bool: whether the keyboard draws a persistent digit row above the letter rows (#331).
    /// Default false — absent means off, which is `UserDefaults.bool`'s natural default, so no
    /// migration and no registration is needed and every existing install keeps its geometry.
    /// One global value, not per language: a number row is a hardware habit, not a language one.
    /// Read and written only through `NumberRowPreference`, except for the Settings toggle's
    /// @AppStorage binding — the same split every other preference on that screen uses.
    public static let numberRowEnabled = "dictus.numberRowEnabled"
    /// JSON-encoded [Float] waveform energy data written by app during recording
    public static let waveformEnergy = "dictus.waveformEnergy"
    /// Bool flag set by keyboard to request recording stop
    public static let stopRequested = "dictus.stopRequested"
    /// Bool flag set by keyboard to request recording cancellation
    public static let cancelRequested = "dictus.cancelRequested"
    /// Double: elapsed recording seconds, updated at ~5Hz during recording
    public static let recordingElapsedSeconds = "dictus.recordingElapsedSeconds"

    // Keyboard mode preference (added for Phase 09 keyboard modes)
    /// Current keyboard mode stored as String ("micro", "emojiMicro", "full")
    @available(*, deprecated, message: "Use defaultKeyboardLayer instead. Kept for migration only.")
    public static let keyboardMode = "dictus.keyboardMode"

    /// Default keyboard layer: "letters" or "numbers". Replaces keyboardMode.
    public static let defaultKeyboardLayer = "dictus.defaultKeyboardLayer"

    // User preferences (added for Plan 4.1 onboarding + settings)
    /// Keyboard language code ("fr"/"en"/"es"/"de"), default "fr".
    /// Drives the keyboard layout, key labels, and autocorrect/prediction.
    /// Since issue #226 this is NO longer the STT language by itself — see
    /// `transcriptionLanguage` below. STT only follows this key when the
    /// transcription language mode is "follow" (the default).
    public static let language = "dictus.language"

    // Transcription language decoupling (issue #226)
    /// Transcription (STT) language mode, decoupled from the keyboard language.
    /// Values: "follow" (default — STT follows `language` above, today's behavior),
    /// "auto" (Whisper language auto-detection, unlocks the long tail incl. zh),
    /// or an explicit code "fr"/"en"/"es"/"de".
    /// A missing or unrecognized value behaves as "follow" so fresh and upgraded
    /// installs keep the exact pre-#226 behavior without any migration.
    /// Written ONLY by the app's Settings — the keyboard toolbar language
    /// switcher keeps writing `language`/`keyboardLayout` and can therefore
    /// never override an explicit or auto transcription choice.
    public static let transcriptionLanguage = "dictus.transcriptionLanguage"
    /// Whether haptic feedback is enabled, default true
    public static let hapticsEnabled = "dictus.hapticsEnabled"
    /// Whether the user has completed onboarding, default false
    public static let hasCompletedOnboarding = "dictus.hasCompletedOnboarding"
    /// Current onboarding step index (0-5). Persisted to UserDefaults so the user
    /// resumes at the right step even after iOS TCC-triggered terminations
    /// (e.g., when "Allow Full Access" is toggled during keyboard setup).
    public static let onboardingCurrentPage = "dictus.onboardingCurrentPage"

    // Text prediction preferences (added for Phase 08)
    /// Whether autocorrect is enabled, default true
    public static let autocorrectEnabled = "dictus.autocorrectEnabled"

    // Autocorrect debug logging (DEBUG builds only - see AutocorrectDebugLog).
    /// Bool: when true, logs autocorrect decisions with the typed word + correction
    /// to the App Group persistent log for debugging. CONTAINS USER TEXT — never
    /// active in Release builds (code is compile-time excluded via #if DEBUG).
    public static let autocorrectDebugLogging = "dictus.autocorrectDebugLogging"

    #if DEBUG
    // Forced Pro entitlement (DEBUG builds only - see PremiumFlags.debugProEntitlementForced).
    /// Bool: when true, `ProStatusManager.isProActiveStatic` reports Pro active whatever
    /// StoreKit says, so the Smart Mode surface #460 hides can still be tested on device.
    ///
    /// WHY the key itself is inside the conditional, unlike `autocorrectDebugLogging`
    /// above: #460 asks for a Release binary in which *nothing* names the force path, and
    /// a `static let` outside it would leave the string in the binary for a `strings` pass
    /// to find. Every reader is `#if DEBUG` too, so the constant has no Release caller to
    /// lose.
    public static let debugProEntitlementForced = "dictus.debugProEntitlementForced"
    #endif

    // Live Activity preference
    /// Whether Live Activity (Dynamic Island + Lock Screen) is enabled, default true
    public static let liveActivityEnabled = "dictus.liveActivityEnabled"

    // Post-STT polish (issue #141)
    /// Whether the polish layer runs between STT final output and App Group write, default false.
    /// Off by default — round 1 is opt-in measurement. See ADR 0002.
    public static let polishEnabled = "dictus.polishEnabled"
    /// Bool: whether polish has stopped calling its engine for the rest of this app
    /// process (#315). Written only by DictusApp, read by whichever surface has to
    /// say so — the keyboard toolbar today. Absent reads false, which is the
    /// available state, so no registration and no migration are needed.
    ///
    /// Read and written only through `PolishAvailabilityChannel`, which is where
    /// the rule about clearing it lives.
    public static let polishUnavailable = "dictus.polishUnavailable"

    // Polish in the keyboard extension (issue #361)
    /// Data: the JSON-encoded `TranscriptionLanguagePolicy` snapshot for the
    /// transcription sitting in `lastTranscription`. Written by DictusApp beside the
    /// raw text, read by the keyboard, which polishes with it instead of re-reading
    /// the live settings — see `PendingDictation.policy` for why that distinction is
    /// the whole point.
    ///
    /// **Its presence is also the marker that says the text is a hand-off.** DictusApp
    /// posts `transcriptionReady` for its own dictations too, and has since long
    /// before #361; those carry finished text and clear this key, so the keyboard
    /// types them without running the pipeline a second time.
    public static let lastTranscriptionPolicy = "dictus.lastTranscriptionPolicy"
    /// Double: how many seconds of audio produced `lastTranscription`. The keyboard
    /// cannot measure this — it never saw the audio — and the polish duration gate
    /// (#141) is decided on it.
    public static let lastTranscriptionDuration = "dictus.lastTranscriptionDuration"
    /// Data: the JSON-encoded `PendingDictation` the keyboard has claimed and not
    /// yet typed. Read and written only through `PendingDictationChannel`, which is
    /// where the rule about who clears it lives.
    public static let pendingDictation = "dictus.pendingDictation"
    /// String: the final text the keyboard typed, written back just before the
    /// insertion so DictusApp can show the polished version rather than the raw one
    /// in its Live Activity preview and its last-transcription card (#361 decision 6).
    public static let lastPolishedTranscription = "dictus.lastPolishedTranscription"
    /// String: a fresh identifier DictusApp writes with each hand-off, which the
    /// keyboard carries and echoes back on `polishDidFinish`.
    ///
    /// Darwin notifications carry no payload, so a bare post says only "some polish
    /// finished". The keyboard is allowed to post more than once for one dictation —
    /// early when the answer is known, again when the generation returns — and since
    /// the app's watchdog started withdrawing dictations, accepting a post from the
    /// wrong one can end a *live* dictation. The token is what makes the post name
    /// which hand-off it belongs to.
    public static let handoffToken = "dictus.handoffToken"
    /// String: the token the keyboard echoes beside `lastPolishedTranscription`.
    public static let lastPolishedHandoffToken = "dictus.lastPolishedHandoffToken"

    // MARK: - Smart Modes (issue #79)
    /// String: identifier of the armed Smart Mode, or absent for Normal. Sticky —
    /// it survives keyboard and app restarts, like the keyboard language, and is
    /// cleared by selecting Normal.
    ///
    /// An identifier rather than a record, so a built-in's prompt is never frozen at
    /// the version that was current when the user armed it. Read and written only
    /// through `SmartModeStore`, which is where the rule about when a read may
    /// disarm lives.
    ///
    /// Distinct from `smartModeEnabled` below, which is the per-feature Pro toggle:
    /// that one says whether the feature is switched on at all, this one says which
    /// mode the next dictation runs.
    public static let smartModeArmed = "dictus.smartModeArmed"
    /// [String]: identifiers of the modes pinned to the keyboard's long-press fan,
    /// in the user's own order. Absent means they have never chosen, which seeds
    /// from `SmartModeCatalogue.defaultPinnedIdentifiers`; an empty array is a real
    /// choice and is honoured.
    public static let smartModePinned = "dictus.smartModePinned"
    /// Bool: whether the user has ever completed the long-press fan gesture.
    ///
    /// The only thing it does is retire the discovery hint from the toolbar's centre
    /// slot. Set once and never cleared — a user who has performed the gesture knows
    /// it exists, and re-teaching them is what makes a hint into noise. See
    /// `SmartModeDiscovery`.
    public static let smartModeGestureUsed = "dictus.smartModeGestureUsed"
    /// Data: the JSON-encoded `SmartMode` armed for the transcription sitting in
    /// `lastTranscription`, or absent when the dictation runs Normal.
    ///
    /// Written by DictusApp beside the raw text and the language policy, read by the
    /// keyboard, which applies it. The whole record travels rather than the
    /// identifier for the same reason `lastTranscriptionPolicy` carries values
    /// instead of keys: re-resolving on the far side would let a mode change made
    /// while transcription was running reach a dictation that was started under a
    /// different one — and the keyboard is exactly where the mode is armed.
    public static let lastTranscriptionSmartMode = "dictus.lastTranscriptionSmartMode"
    /// Data: the JSON-encoded `SmartModeSkipNotice` for a dictation whose armed mode
    /// was resolved away, or absent when nothing was skipped (#423).
    ///
    /// The mirror image of the key above, and it exists because the two ends of the
    /// fact are in different processes: DictusApp resolves the armed mode at
    /// transcription start and decides it will not run; the toolbar that has to say
    /// so belongs to the keyboard. Without this the fallback is silent — text is
    /// inserted, the outcome is an ordinary success, and the only trace is a WARNING
    /// in a log the user never reads.
    ///
    /// Written and cleared beside `lastTranscriptionSmartMode`, so the two can never
    /// both be set: a mode that ran was not skipped.
    public static let lastTranscriptionSmartModeSkipped = "dictus.lastTranscriptionSmartModeSkipped"
    /// String: the `identifier|reason` of the last skip the user was actually told
    /// about, or absent when there is nothing outstanding (#423).
    ///
    /// What makes the notice fire **once, the first time it happens after the state
    /// changes** rather than on every dictation forever. Cleared by arming, by
    /// disarming, and by any resolve that succeeds — each of those is the state
    /// changing. Written only by the surface that showed the sentence, never by the
    /// resolve, so an in-app dictation cannot burn the token with nobody told.
    public static let smartModeSkipAnnounced = "dictus.smartModeSkipAnnounced"

    // Audio heartbeat (added for background waveform reliability)
    /// Double (timeIntervalSince1970): written directly from the audio thread at ~1Hz
    /// during active recording. The keyboard watchdog reads this as a fallback
    /// when Darwin waveform notifications don't arrive (iOS main thread throttling
    /// in background). If the heartbeat is fresh (< 5s), the app is still recording.
    public static let recordingHeartbeat = "dictus.recordingHeartbeat"

    // Cold start detection keys (added for Phase 13)
    /// Bool flag: true when the app was opened from the keyboard for cold start dictation.
    /// Set by handleIncomingURL when source=keyboard query parameter is present.
    /// Cleared when the app enters background.
    public static let coldStartActive = "dictus.coldStartActive"
    /// String: URL scheme of the source app (e.g., "whatsapp") or "unknown".
    /// Used by auto-return logic to navigate back to the correct app after dictation.
    public static let sourceAppScheme = "dictus.sourceAppScheme"

    // Keyboard teardown diagnostics (issue #281)
    /// String: DictusApp's last reported scene phase, one of `AppScenePhaseMarker`.
    /// Written by the app on every scene phase change, read by the keyboard extension
    /// when its controllers are torn down. Observation only — nothing branches on it.
    public static let appScenePhase = "dictus.appScenePhase"
    /// Double (timeIntervalSince1970): when `appScenePhase` was written. The pair is
    /// only meaningful together: the keys outlive the app process, so the age is what
    /// separates "the app is in the background right now" from a stale leftover.
    public static let appScenePhaseTimestamp = "dictus.appScenePhaseTimestamp"

    // MARK: - Sound Feedback
    /// Whether sound feedback is enabled for recording events, default true
    public static let soundFeedbackEnabled = "dictus.soundFeedbackEnabled"
    /// Name of the WAV file (without extension) to play when recording starts
    public static let recordStartSoundName = "dictus.recordStartSoundName"
    /// Name of the WAV file (without extension) to play when recording stops
    public static let recordStopSoundName = "dictus.recordStopSoundName"
    /// Name of the WAV file (without extension) to play when recording is cancelled
    public static let recordCancelSoundName = "dictus.recordCancelSoundName"
    /// Sound volume from 0.0 to 1.0, default 0.5
    public static let soundVolume = "dictus.soundVolume"

    // MARK: - Pro / Subscription
    /// Bool: true when the user has an active Pro subscription.
    /// Written by SubscriptionManager (DictusApp), read by the keyboard extension.
    public static let proActive = "dictus.proActive"
    /// Bool: per-feature toggle for Smart Mode. Seeded to true, once, by
    /// `ProStatusManager.seedFeatureTogglesIfNeeded()`; written afterwards only by the
    /// Settings toggle. Stored, never merely registered -- the keyboard extension reads
    /// these and a registered default would not reach it (#401).
    public static let smartModeEnabled = "dictus.smartModeEnabled"
    /// Bool: per-feature toggle for History. Seeded like `smartModeEnabled` above.
    public static let historyEnabled = "dictus.historyEnabled"
    /// Bool: per-feature toggle for Vocabulary. Seeded like `smartModeEnabled` above.
    public static let vocabularyEnabled = "dictus.vocabularyEnabled"

    // MARK: - Retired keys
    /// The #357 probe's arming flag, removed with the probe in #361. Kept as a
    /// literal, and only here, so DictusApp can delete it from the App Group on
    /// devices that armed it once — the flag defaults to false, but a device where
    /// the toggle was left on would carry a `true` no code reads any more.
    ///
    /// Drop this and its one caller once a release has shipped with the cleanup.
    static let retiredAppleFMExtensionProbeArmed = "dictus.debug.appleFMExtensionProbeArmed"

    /// Every key no live code reads, cleared once per app launch.
    static let retiredKeys = [retiredAppleFMExtensionProbeArmed]

    /// Remove the retired keys above. Called from DictusApp's launch, which is the
    /// only process that owns hygiene over shared state.
    public static func clearRetiredKeys() {
        let defaults = AppGroup.defaults
        for key in retiredKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }
}
