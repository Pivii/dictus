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
    /// Double (timeIntervalSince1970): when `modelLoadState` last changed value.
    /// Written by DictusApp in the same breath as the state itself.
    /// The keyboard uses it to age a `loading` value (issue #250): a stale one
    /// left behind by a force-quit mid-load is recognised as old and never
    /// dims the mic button. Absent or 0 means "age unknown" — consumers must
    /// fall back to their own first-observation time, never to "just started".
    public static let modelLoadStateChangedAt = "dictus.modelLoadStateChangedAt"

    // Keyboard-App cross-process contracts (added for Plan 3.1)
    /// Current keyboard layout type stored as String ("azerty" or "qwerty")
    public static let keyboardLayout = "dictus.keyboardLayout"
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

    // Live Activity preference
    /// Whether Live Activity (Dynamic Island + Lock Screen) is enabled, default true
    public static let liveActivityEnabled = "dictus.liveActivityEnabled"

    // Post-STT polish (issue #141)
    /// Whether the polish layer runs between STT final output and App Group write, default false.
    /// Off by default — round 1 is opt-in measurement. See ADR 0002.
    public static let polishEnabled = "dictus.polishEnabled"

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
    /// Bool: per-feature toggle for Smart Mode, default true (registered by ProStatusManager)
    public static let smartModeEnabled = "dictus.smartModeEnabled"
    /// Bool: per-feature toggle for History, default true (registered by ProStatusManager)
    public static let historyEnabled = "dictus.historyEnabled"
    /// Bool: per-feature toggle for Vocabulary, default true (registered by ProStatusManager)
    public static let vocabularyEnabled = "dictus.vocabularyEnabled"
}
