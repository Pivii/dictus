// DictusApp/Audio/UnifiedAudioEngine.swift
// Single audio engine for all recording paths — replaces both AudioRecorder and RawAudioCapture.
// Uses native AVAudioEngine (no WhisperKit dependency). Captured samples are passed to
// transcribe(audioArray:) which accepts any [Float] 16kHz mono array.
import Foundation
@preconcurrency import AVFoundation
import DictusCore

extension Notification.Name {
    /// In-process signal that the AVAudioSession was interrupted or the media
    /// services stack was reset. Consumers (LiveActivityManager, DictationCoordinator)
    /// must treat the audio engine as dead until a successful `warmUp()` returns.
    /// Mirrors the cross-process Darwin notification of the same name (issue #106).
    static let dictusAudioSessionInterrupted = Notification.Name("DictusAudioSessionInterrupted")

    /// In-process signal that the warm-state engine was released after the idle
    /// timeout. Consumers should dismiss the Dynamic Island standby indicator —
    /// the next dictation will be a cold start (issue #106 Phase B).
    static let dictusWarmStateReleased = Notification.Name("DictusWarmStateReleased")
}

/// Which of the two Objective-C calls in `startEngine()` raised an NSException.
///
/// The raw values are the tokens already written to the persistent log
/// (`installTap NSException:` / `engine.start NSException:`), so a log an agent greps
/// and an error payload it reads spell the same fact the same way (#255, #417).
enum ObjCAudioStartCall: String {
    case installTap
    case engineStart = "engine.start"
}

/// Errors that can occur during audio engine operations.
enum AudioEngineError: Error, DiagnosableError {
    case permissionDenied
    case permissionUndetermined

    /// A call holds the microphone. The payload names which of the two signals said so —
    /// a telephony input route, or a bluetooth headset route during an interruption
    /// (#459). Diagnostic only: a log that says nothing but "a call" cannot tell a
    /// handset call from an AirPods one, and those are two different fixes if this
    /// detection is ever wrong again.
    case phoneCallActive(evidence: String)

    /// The input node reported a format nothing can be recorded from, and it reported
    /// it again from a node that had just been built (#123). The payload names which
    /// half of the format was missing — `AudioInputFormatFailure.rawValue` — and is
    /// diagnostic only, for the same reason `phoneCallActive` carries evidence: the
    /// two ways to reach this are indistinguishable in a log that only says "the
    /// hardware is unavailable".
    case audioHardwareUnavailable(reason: String)

    /// `installTap` or `engine.start` raised an Objective-C exception. `reason` is the
    /// exception's own text — an AVFoundation sentence naming formats and sample rates —
    /// and `call` names which of the two raised it.
    ///
    /// WHY `call` is carried (#417): AVAudioEngine defers tap creation on a stopped engine
    /// until `start()`, so the same exception text can come from either site, and the two
    /// mean different things — a tap that could not be installed, versus a format that
    /// drifted after it was. Only the persistent log told them apart, and that distinction
    /// is what made #417 diagnosable at all. Diagnostic only, like `phoneCallActive`'s
    /// evidence: both cases show the user the same sentence, because from their side they
    /// are the same event.
    case installTapFailed(call: ObjCAudioStartCall, reason: String)

    /// User-facing text. Written to `DictationErrorChannel` and displayed by whichever
    /// surface the user is on — the keyboard's toolbar, the app's failure screen, or both.
    var errorDescription: String? {
        switch self {
        case .permissionDenied, .permissionUndetermined:
            return DictationFailureMessage.microphonePermissionDenied
        case .phoneCallActive:
            return String(localized: "The microphone is busy on a call. Try again once the call ends.",
                          comment: "Shown when a dictation cannot start because a phone call holds the microphone (issue #313).")
        case .audioHardwareUnavailable:
            return String(localized: "The microphone is not available right now. Try again in a moment.",
                          comment: "Shown when the audio hardware reports no usable input format (issue #313).")
        case .installTapFailed:
            // WHY the same sentence #311 wrote for a stranded cold start: from the user's
            // side this is the same event, a dictation that did not start, and the same
            // action fixes it. It deliberately names no cause — the message it replaces
            // said the microphone was unavailable, and the tester in #417 correctly
            // answered that nothing else was holding their microphone.
            return String(localized: "Dictation could not start. Tap the microphone again.")
        }
    }

    /// English technical detail for the log. Never shown to the user.
    var diagnosticDescription: String {
        switch self {
        case .permissionDenied:
            return "microphone permission denied"
        case .permissionUndetermined:
            return "microphone permission not yet requested"
        case .phoneCallActive(let evidence):
            return "a call holds the microphone — \(evidence)"
        case .audioHardwareUnavailable(let reason):
            return "input node reports an unusable format after the engine rebuild — \(reason)"
        case .installTapFailed(let call, let reason):
            return "\(call.rawValue) raised: \(reason)"
        }
    }
}

/// Unified audio engine for recording dictation audio.
///
/// WHY this replaces AudioRecorder + RawAudioCapture:
/// Both classes did the same job (capture 16kHz mono Float32 audio). AudioRecorder wrapped
/// WhisperKit's AudioProcessor (tight coupling, manual isEngineRunning bool = bug #38).
/// RawAudioCapture used native AVAudioEngine (zero WhisperKit dependency, computed
/// isEngineRunning = always correct). Since transcribe(audioArray:) accepts any [Float],
/// we don't need WhisperKit's AudioProcessor for capture. One engine, one code path.
///
/// KEY DESIGN: Sample gating via isRecording flag.
/// The engine runs continuously (keeps app alive via UIBackgroundModes:audio) but only
/// accumulates audio samples when isRecording is true. When idle, the engine still processes
/// buffers for heartbeat/energy (background survival) but discards the actual audio data.
/// This eliminates the 64M idle sample accumulation bug (#38).
@MainActor
// WHY the exemption (#417): this class body was at 648 of the 650-line budget before the
// converter rebuild was added, so any fix landing in it trips the rule. The threshold's own
// rationale in .swiftlint.yml is that it exists "to catch a NEW type or function ballooning"
// and explicitly not to police the large classes that already exist — raising the global
// number to fit this one would weaken it everywhere for a class it was never aimed at, and
// carving the audio-thread half into an extension is a restructuring of the file that the
// same rationale calls the highest-risk change available. Scoped here, and only here.
// swiftlint:disable:next type_body_length
class UnifiedAudioEngine: ObservableObject {
    // MARK: - Published State

    /// Whether the user is actively recording (samples being accumulated).
    @Published var isRecording = false

    /// Energy levels (0.0-1.0) for waveform visualization.
    @Published var bufferEnergy: [Float] = []

    /// Elapsed recording time in seconds.
    @Published var bufferSeconds: Double = 0

    // MARK: - Engine State

    /// Whether the underlying AVAudioEngine is currently running.
    /// COMPUTED from engine.isRunning — always accurate, fixes #38.
    var isEngineRunning: Bool { engine.isRunning }

    /// Whether the engine is in a healthy state for warm-start recording.
    ///
    /// WHY both gates: `engine.isRunning` returns true even after an interruption
    /// began, until we explicitly stop it. `isInterrupted` reflects whether the
    /// AVAudioSession is actually usable. The Live Activity layer queries this to
    /// avoid showing "ready to dictate" while the audio system is dead (issue #106).
    var isHealthy: Bool { engine.isRunning && !isInterrupted }

    /// Current accumulated sample count (for zombie engine health check).
    var currentSampleCount: Int { audioSamples.count }

    /// What AVAudioSession actually reports for the system-haptics allowance.
    ///
    /// WHY this is read rather than tracked: `setAllowHapticsAndSystemSoundsDuringRecording`
    /// is a request, not an assignment — the session is free to report something
    /// else, and the SDK documents the default as NO. When this is false while we
    /// hold an active session, iOS mutes system haptics device-wide: every
    /// keyboard including Apple's stops tapping, in every app, for as long as the
    /// session lives (issue #293).
    var allowsHapticsDuringRecording: Bool {
        AVAudioSession.sharedInstance().allowHapticsAndSystemSoundsDuringRecording
    }

    // MARK: - Private

    private var engine = AVAudioEngine()

    /// Accumulated audio samples in 16kHz mono Float32 (WhisperKit/Parakeet expected format).
    private var audioSamples: [Float] = []

    /// Converter from the hardware format (typically 48kHz mono) to 16kHz mono.
    ///
    /// WHY nonisolated(unsafe): `startEngine()` pre-builds one from the format the input
    /// node reported, and from then on `processBuffer()` owns it — it rebuilds from the
    /// buffer's own format whenever the two disagree (#417). Main writes it again only to
    /// clear it, in the two places that bump `engineGeneration` and remove the tap first,
    /// so an in-flight callback bails out before it can observe the nil.
    ///
    /// WHY the pre-build survived the move to the tap: it is what keeps the audio thread
    /// allocation-free in the normal case. The format the node reports is the right one
    /// almost always; when it is not, the tap pays a single build and says so.
    private nonisolated(unsafe) var converter: AVAudioConverter?

    /// The last buffer format `AVAudioConverter(from:to:)` refused, if any.
    ///
    /// WHY it is remembered (#417): the tap runs on a real-time thread and buffers arrive
    /// at roughly 100 Hz. Without the memo, a format nothing can convert would be retried
    /// — allocating — on every one of them, for as long as that route lasts. Cleared
    /// wherever `converter` is, so a fresh engine inherits no verdict from the dead one.
    /// `AudioConverterCachePolicy` holds the rule.
    private nonisolated(unsafe) var lastUnconvertibleInputFormat: AVAudioFormat?

    /// Target format: 16kHz mono Float32 — what WhisperKit and Parakeet expect.
    ///
    /// WHY the force unwrap cannot trap: this initializer only returns nil for a
    /// format/rate/channel combination Core Audio cannot represent. All four
    /// arguments are compile-time constants, and 16 kHz mono non-interleaved
    /// Float32 is a canonical PCM format supported on every device iOS 17 runs on.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
        // swiftlint:disable:next force_unwrapping
    )!

    /// Whether the audio session has been configured at least once.
    /// WHY: iOS forbids changing AVAudioSession category from background.
    /// We configure once and keep the category set forever.
    ///
    /// WHY `private(set)` rather than `private` (#293): the `engineStateSnapshot`
    /// diagnostic used to pass a hardcoded `true` for this field, so every
    /// `sessionConfigured=true` in a device log was a literal, not a measurement.
    /// The snapshot now reads the real value.
    private(set) var sessionConfigured = false

    /// True when an AVAudioSession interruption is currently in flight.
    ///
    /// WHY tracked separately from `engine.isRunning`: When an interruption begins,
    /// iOS deactivates the session under us; the engine may still report `isRunning`
    /// momentarily, but the next `installTap`/`start` will fail. Routing decisions
    /// (Live Activity, transitionToRecording guard) need a fast in-process flag to
    /// know the audio layer is degraded (issue #106).
    private var isInterrupted = false

    /// Re-entry guard for the interruption handler. Prevents a second `.began` /
    /// `.ended` arriving while we're still mutating engine state from a previous
    /// event (Siri → ringing call back-to-back), which would leave a dangling tap.
    private var isHandlingInterruption = false

    /// Generation counter for the underlying AVAudioEngine instance. Bumped on
    /// `handleMediaServicesReset` when we replace the engine. The audio tap closure
    /// captures the generation it was installed under — if a buffer arrives after
    /// the engine has been replaced, the closure bails out instead of writing into
    /// shared `nonisolated(unsafe)` state and racing with the new engine's tap.
    private nonisolated(unsafe) var engineGeneration: UInt64 = 0

    /// Tokens for the AVAudioSession lifecycle observers, retained so we can
    /// remove them in `deinit` and avoid leaking notifications across hot reloads
    /// or future re-instantiation.
    private var notificationObservers: [NSObjectProtocol] = []

    /// Pending idle-release work item (issue #106 Phase B). Armed whenever the
    /// engine *enters* the warm-idle state — end of a recording (`collectSamples`)
    /// or a successful `warmUp()` — and cancelled at the start of any new
    /// recording. If it ever fires, `releaseWarmState()` tears down the engine +
    /// session so the device stops paying for `UIBackgroundModes:audio`.
    private var idleReleaseWorkItem: DispatchWorkItem?

    /// Time at which the engine entered the warm-idle state: a recording ended
    /// (`collectSamples` / `cancelDictation`) or a warm-up completed with nobody
    /// recording. Used to compute how long the engine sat idle before being
    /// released — emitted in the `warmStateReleased(idleSeconds:)` log event for
    /// tuning the timeout — and as the anchor for the wall-clock backstop.
    /// Nil means "not warm-idle": either never armed, or a recording is running.
    private var lastIdleStartTime: Date?

    /// The interval the currently-armed release was scheduled with. Kept so the
    /// wall-clock backstop measures against the same window the timer used,
    /// rather than assuming the post-dictation one.
    private var armedIdleReleaseInterval: TimeInterval = UnifiedAudioEngine.idleReleaseInterval

    /// Idle window after which the warm engine + session are released, when the
    /// warm state followed a real dictation. Hardcoded for this iteration; a
    /// user-facing setting will land as a follow-up (issue #106 out-of-scope).
    /// 10 minutes balances UX (warm starts feel instant within a normal
    /// "back-and-forth dictation session") against battery drain (3.3%/h
    /// baseline drops to ~0%/h after release).
    private static let idleReleaseInterval: TimeInterval = 10 * 60

    /// Idle window applied when the engine was warmed WITHOUT a preceding
    /// dictation: launch pre-load, `didBecomeActive` re-warm, explicit `warmUp()`.
    ///
    /// WHY a separate constant that currently holds the same value: #256 leaves
    /// open whether a user who merely opened the app deserves a shorter window
    /// than one who just dictated. That is a product call, not an implementation
    /// one, so this ships with the conservative answer (identical windows) and a
    /// single line to change if the maintainer decides otherwise.
    private static let warmUpIdleReleaseInterval: TimeInterval = idleReleaseInterval

    /// Sample gating flag read from the audio thread.
    /// WHY nonisolated(unsafe): Read from audio callback thread (single reader pattern).
    /// Written from main thread via startRecording()/collectSamples()/stopEngine().
    /// The flag is a simple Bool — partial reads are impossible on ARM64.
    private nonisolated(unsafe) var isRecordingFlag = false

    /// Timestamp of last heartbeat write to App Group.
    /// Throttled to ~1Hz to avoid excessive UserDefaults writes from the audio thread.
    /// WHY nonisolated(unsafe): Written only from the audio callback thread (single writer).
    private nonisolated(unsafe) var lastHeartbeatWrite: TimeInterval = 0

    /// Timestamp of last waveform write to App Group from the audio thread.
    /// Throttled to ~5Hz (every 200ms) — same rate as keyboard waveform display.
    /// WHY from audio thread: In background, iOS throttles DispatchQueue.main.async delivery.
    /// Writing directly from the audio thread bypasses this throttling.
    private nonisolated(unsafe) var lastWaveformWrite: TimeInterval = 0

    /// Timestamp of the last waveform-shape diagnostic emitted from the audio thread.
    private nonisolated(unsafe) var lastWaveformDiagnosticsWrite: TimeInterval = 0

    /// Rolling energy buffer maintained on the audio thread for direct App Group writes.
    /// Separate from @Published bufferEnergy (which is main-thread-only for SwiftUI).
    /// WHY nonisolated(unsafe): Single writer (audio callback thread).
    private nonisolated(unsafe) var audioThreadEnergy: [Float] = []

    /// Rolling per-bucket waveform shape used by the keyboard/App Group snapshot.
    /// Unlike audioThreadEnergy (one RMS value per callback), this keeps a short envelope
    /// history with enough local variation to render an actual waveform silhouette.
    private nonisolated(unsafe) var audioThreadWaveformBins: [Float] = []

    /// Accumulated sample count on the audio thread for elapsed time calculation.
    /// WHY nonisolated(unsafe): Single writer (audio callback thread).
    private nonisolated(unsafe) var audioThreadSampleCount: Int = 0

    private let waveformBarCount = 30

    // MARK: - Init / Deinit

    init() {
        registerInterruptionObservers()
    }

    deinit {
        idleReleaseWorkItem?.cancel()
        for token in notificationObservers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Register observers for AVAudioSession lifecycle events that can break the
    /// engine without our knowledge — phone calls, Siri, route loss, media services
    /// reset (issue #106).
    ///
    /// WHY in init (not after first start): Apple delivers the .began interruption
    /// notification immediately when the OS interrupts us, even if we haven't yet
    /// activated the session. Registering early means we never miss one. Observers
    /// are cheap when the session isn't active.
    ///
    /// WHY no `queue: .main` + `Task { @MainActor }` double hop: each Task adds a
    /// runloop tick of latency between AVAudioSession posting the notification and
    /// us mutating `isInterrupted`. Since this class is @MainActor, dispatching
    /// the closure to MainActor.assumeIsolated handles isolation directly.
    private func registerInterruptionObservers() {
        let center = NotificationCenter.default

        let interruptionToken = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleInterruption(note) }
        }

        let routeChangeToken = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleRouteChange(note) }
        }

        let mediaResetToken = center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMediaServicesReset() }
        }

        notificationObservers = [interruptionToken, routeChangeToken, mediaResetToken]
    }

    /// AVAudioSession interruption handler.
    ///
    /// On `.began`: tear down the engine and mark the session unhealthy. The Live
    /// Activity must dismiss because a dead session means the next dictation will
    /// be a cold start, not a warm start (issue #106).
    ///
    /// On `.ended` with `.shouldResume`: try to reactivate and re-warm. If recovery
    /// fails (rare — usually means the OS still holds the audio resource), we leave
    /// the engine cold and accept that the next dictation pays the cold-start cost.
    private func handleInterruption(_ note: Notification) {
        // Re-entry guard: a second interruption arriving before we finish handling
        // the previous one (Siri → ringing call back-to-back) would leave a dangling
        // tap. The MainActor isolation already serialises calls, so the flag only
        // needs to cover async work inside this method (warmUp on .ended).
        guard !isHandlingInterruption else {
            PersistentLog.log(.engineWarmUpFailed(
                context: "interruption",
                error: "reentrant interruption ignored"
            ))
            return
        }
        isHandlingInterruption = true
        defer { isHandlingInterruption = false }

        guard let userInfo = note.userInfo,
              let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }

        switch type {
        case .began:
            let reason = userInfo[AVAudioSessionInterruptionReasonKey].flatMap { value -> String in
                if let raw = value as? UInt,
                   let parsed = AVAudioSession.InterruptionReason(rawValue: raw) {
                    return "\(parsed)"
                }
                return "\(value)"
            } ?? "unknown"

            isInterrupted = true
            isRecording = false
            isRecordingFlag = false
            cancelIdleRelease()

            // Stop the engine so the next start() reinstalls the tap with a fresh
            // hardware format. Don't deactivate the session — iOS will do that for us
            // and re-asks ownership when the interruption ends.
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()

            PersistentLog.log(.audioInterruptionBegan(reason: reason))
            logHapticsAllowance(context: "interruptionBegan")

            // Notify in-process listeners (LiveActivityManager, DictationCoordinator)
            // immediately. Darwin notification mirrors for cross-process consumers
            // (keyboard ext) so they can stop trusting the warm-state contract.
            NotificationCenter.default.post(name: .dictusAudioSessionInterrupted, object: nil)
            DarwinNotificationCenter.post(DarwinNotificationName.audioSessionInterrupted)

        case .ended:
            let optionsRaw = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            let shouldResume = options.contains(.shouldResume)

            // We deliberately do NOT auto-resume here even when shouldResume is true.
            //
            // WHY: the user just finished a phone call (or whatever interruption);
            // they have not asked to dictate. Eagerly re-warming the engine
            // re-activates AVAudioSession, which iOS surfaces as the orange mic
            // indicator in its Dynamic Island — but our Live Activity is already
            // dismissed (Phase A correctly tears it down on .began). The combination
            // is the worst of both: audio resources held + no Dictus UX visible.
            //
            // Instead, leave the engine cold and rely on the natural re-warm paths:
            //  - if user reopens the app, DictationCoordinator's didBecomeActive
            //    observer calls warmUp.
            //  - if user taps the keyboard mic, the cold-start dictation path
            //    starts the engine fresh.
            // The interruption is over, so the flag that says one is in flight must say
            // so — that is its documented meaning, and until #459 nothing here cleared
            // it. The only clear was at the end of a successful `startEngine`, which was
            // harmless while nothing read the flag before a start could finish.
            //
            // WHY it stopped being harmless (#459 review): the call guard now reads this
            // flag *before* the engine starts, and refuses the start when it is raised.
            // A flag that only a successful start can clear, gating a start, is a latch:
            // guard refuses → the start never reaches the clear → the next tap refuses
            // again, with nothing the user can do about it. Today iOS drops the HFP route
            // when the call ends, so the other half of the guard's conjunction falls and
            // the latch never closes — but that is iOS saving us, not us being correct.
            //
            // Clearing here does NOT resume anything: the engine stays cold on purpose,
            // for the reason above. It says the audio layer is no longer degraded, which
            // is true, and lets the next mic tap try. The clear in `startEngine` stays —
            // it answers a different question (this start succeeded, so we are healthy)
            // and covers the interruptions that never deliver an `.ended` at all.
            isInterrupted = false

            // Either way, the warm-state contract matches reality and the orange
            // mic only appears when the user actually wants to record (issue #106).
            PersistentLog.log(.audioInterruptionEnded(shouldResume: shouldResume, restored: false))

        @unknown default:
            return
        }
    }

    /// Audio route change handler. Logs only — most route changes (headphones
    /// plugged/unplugged) are handled transparently by AVAudioEngine. We do NOT
    /// tear down the engine here; that path is reserved for explicit interruptions.
    /// If the input route disappears entirely, the next recording attempt fails
    /// gracefully via the hwFormat guards in `startEngine()`.
    /// - Note on what this line carries (issue #123): this handler describes the
    ///   moment the dead-input-node fault is *created*, so it is the one line in the
    ///   file a reader reaches for first, and it used to say almost nothing.
    ///   `reason` printed raw (`AVAudioSessionRouteChangeReason(rawValue: 0)`), which
    ///   sends the reader to a lookup table for the only genuinely diagnostic part of
    ///   the field. `inputs=none` said what the route had become and never what it had
    ///   been, which is exactly the question — what disappeared? And without
    ///   `availableInputs`, "no input, nothing connected" and "no input while the
    ///   built-in mic sits right there" read identically, though they are two
    ///   different faults.
    private func handleRouteChange(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let raw = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt else {
            return
        }

        // WHY the previous route comes from `userInfo` and not from a field we kept:
        // AVAudioSession hands it to us in the notification and it is the only place
        // it exists. Tracking it ourselves would mean holding a copy that is wrong for
        // every route change that happens while the app is suspended.
        let previous = (userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)
            .map { portList($0.inputs) } ?? "unknown"

        PersistentLog.log(.audioRouteChanged(
            reason: Self.routeChangeReasonName(raw),
            details: "previous=\(previous) \(routeStateDescription())"
        ))
    }

    /// The name of a route-change reason, with its raw value kept alongside.
    ///
    /// WHY both (issue #123): the eight case names are the whole diagnostic value of
    /// the field, and the raw value is what survives a reason iOS adds after this
    /// build shipped — an unmapped one now logs `unmapped(9)` instead of what the old
    /// `guard let` did, which was to drop the line entirely and leave a route change
    /// with no trace at all.
    private static func routeChangeReasonName(_ raw: UInt) -> String {
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else {
            return "unmapped(\(raw))"
        }

        let name: String
        switch reason {
        case .unknown: name = "unknown"
        case .newDeviceAvailable: name = "newDeviceAvailable"
        case .oldDeviceUnavailable: name = "oldDeviceUnavailable"
        case .categoryChange: name = "categoryChange"
        case .override: name = "override"
        case .wakeFromSleep: name = "wakeFromSleep"
        case .noSuitableRouteForCategory: name = "noSuitableRouteForCategory"
        case .routeConfigurationChange: name = "routeConfigurationChange"
        @unknown default: name = "unmapped"
        }
        return "\(name)(\(raw))"
    }

    /// AVAudioSession.mediaServicesWereReset handler. This is rare but brutal:
    /// the entire audio stack is reset by the OS and ALL existing AVAudioEngine
    /// instances are invalid. We must allocate a fresh engine and reconfigure
    /// before any future start() call.
    private func handleMediaServicesReset() {
        PersistentLog.log(.audioMediaServicesReset)
        logHapticsAllowance(context: "mediaServicesReset")

        cancelIdleRelease()
        replaceEngine()
        sessionConfigured = false
        isInterrupted = true
        isRecording = false
        isRecordingFlag = false

        NotificationCenter.default.post(name: .dictusAudioSessionInterrupted, object: nil)
        DarwinNotificationCenter.post(DarwinNotificationName.audioSessionInterrupted)
    }

    /// Throw the current `AVAudioEngine` away and put a fresh one in its place.
    ///
    /// This is the only operation in the class that discards the input node, and
    /// therefore the only one that can clear a format the node has latched. Extracted
    /// from `handleMediaServicesReset()` for #123, where a dead input format needs
    /// exactly this and nothing else.
    ///
    /// WHY the two callers are not the same call: the reset handler additionally tears
    /// down `sessionConfigured`, raises `isInterrupted`, clears the recording flags and
    /// posts both interruption notifications. None of that may happen inside
    /// `startEngine()` — the flags in particular, because `forceRestart()` reaches
    /// `startEngine()` in the middle of a live recording and clearing them there would
    /// silently stop accumulating samples.
    ///
    /// The generation bump stays welded to the replacement: it must happen BEFORE the
    /// new engine exists so any in-flight tap callback from the old one sees a stale
    /// generation and bails out, instead of writing into shared audio-thread state and
    /// racing the new engine's tap.
    private func replaceEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engineGeneration &+= 1
        engine = AVAudioEngine()
        converter = nil
        lastUnconvertibleInputFormat = nil
    }

    // MARK: - Session & Permissions (ported from AudioRecorder)

    /// Configure the audio session. Must be called from foreground.
    ///
    /// WHY .allowBluetoothA2DP (not .allowBluetooth) — fix #85:
    /// .allowBluetooth enables HFP (Hands-Free Profile) which hijacks AirPods AVRCP
    /// controls — single-tap play/pause stops working for Music app during recording.
    /// .allowBluetoothA2DP keeps A2DP output on AirPods without activating HFP:
    /// built-in mic is used for recording, AirPods controls stay with media apps.
    /// Confirmed via WhisperFlow reverse-engineering (same NoBluetooth approach).
    ///
    /// WHY .duckOthers:
    /// Automatically lowers other apps' volume (~60%) while Dictus's engine is active.
    /// The AirPods hijack was caused by HFP (.allowBluetooth), not ducking.
    ///
    /// WHY .defaultToSpeaker:
    /// Without it, .playAndRecord routes output to the earpiece by default — nearly
    /// inaudible without headphones. .defaultToSpeaker sends audio to the loudspeaker.
    ///
    /// WHY setActive every time (no sessionConfigured guard for setActive):
    /// iOS interrupts the audio session when the app goes to background. Even if the
    /// category was set, setActive(true) must be called again on foreground return.
    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        if !sessionConfigured {
            try session.setCategory(.playAndRecord, options: [.allowBluetoothA2DP, .defaultToSpeaker, .duckOthers])
        }
        try session.setActive(true)
        sessionConfigured = true

        PersistentLog.log(.audioSessionConfigured(category: "playAndRecord"))
        applyHapticsAllowance(context: "configureAudioSession")
    }

    // MARK: - System Haptics Allowance (issue #293)

    /// Ask the session to keep system haptics and system sounds alive while we
    /// hold audio input, then log what it actually reports back.
    ///
    /// WHY this is called from every activation path rather than once in
    /// `configureAudioSession()`: the allowance defaults to NO and belongs to the
    /// session, not to us. Any path that reaches an active session without
    /// passing through `configureAudioSession()` — `warmUp()` short-circuiting on
    /// an already-running engine, `startRecording()` on a warm engine, a
    /// `startEngine()` that implicitly reactivated the session — would leave it
    /// unset, and a single such path is enough to mute the whole device.
    /// Re-asserting is one setter call; not re-asserting is a device-wide bug the
    /// user cannot attribute to us.
    ///
    /// WHY the throw is logged instead of `try?`: before #293 this was a bare
    /// `try?`, which made a failed call and a successful one produce exactly the
    /// same (empty) evidence. Three investigations ran blind on that.
    private func applyHapticsAllowance(context: String) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        } catch {
            PersistentLog.log(.audioHapticsAllowanceFailed(
                context: context,
                error: error.localizedDescription
            ))
        }
        logHapticsAllowance(context: context)
    }

    /// Log the session's current haptics allowance without touching it. Used on
    /// the teardown paths, where re-asserting would be meaningless — but where
    /// the value still matters, because "haptics came back" is the observation
    /// the user reports and this is the line that dates it.
    private func logHapticsAllowance(context: String) {
        PersistentLog.log(.audioHapticsAllowance(
            context: context,
            allowed: AVAudioSession.sharedInstance().allowHapticsAndSystemSoundsDuringRecording
        ))
    }

    /// Check and request microphone permission if needed.
    /// Returns true if permission is granted, false otherwise.
    func ensureMicrophonePermission() async throws -> Bool {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            return true
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            return granted
        case .denied:
            throw AudioEngineError.permissionDenied
        @unknown default:
            return false
        }
    }

    // MARK: - Engine Lifecycle

    /// Start the engine in idle mode (running but not recording).
    /// Keeps the app alive in background via UIBackgroundModes:audio.
    ///
    /// WHY this arms the idle release (issue #256): warming up puts the engine
    /// into exactly the state the release is meant to bound — running, holding
    /// the audio session, and nobody recording. Before #256 only `collectSamples`
    /// armed it, so the three non-dictation doors into that state (launch
    /// pre-load, `didBecomeActive` re-warm, and this call) left the engine
    /// unbounded. A device log showed 8h18m of continuous engine time with no
    /// dictation in the window. Arm on *entering the state*, not on the one event
    /// that happened to precede it in the original design.
    func warmUp() throws {
        // Cancel any pending idle release — we're explicitly going back warm.
        cancelIdleRelease()

        guard !engine.isRunning else {
            PersistentLog.log(.engineWarmUpSuccess(context: "already running"))
            // This short circuit never reaches `startEngine()`, so it is one of
            // the paths that would otherwise leave the allowance untouched
            // (issue #293).
            applyHapticsAllowance(context: "warmUp-alreadyRunning")
            // Re-arm before returning. `cancelIdleRelease()` above dropped
            // whatever was pending, and leaving without re-arming is how the
            // engine used to end up warm forever.
            scheduleIdleRelease(after: Self.warmUpIdleReleaseInterval)
            return
        }
        try startEngine(context: "warmUp")
        PersistentLog.log(.engineWarmUpSuccess(context: "unifiedEngine-warmUp"))

        // NOT in a `defer`: on a `startEngine()` throw we are not warm, and
        // arming a release for an engine that never started would only produce a
        // misleading `warmStateReleased` ten minutes later.
        scheduleIdleRelease(after: Self.warmUpIdleReleaseInterval)
    }

    /// Begin recording: purge idle audio and start accumulating samples.
    /// If the engine isn't running yet, starts it first (<100ms).
    func startRecording() throws {
        // Cancel any pending idle release — recording activity resets the timer.
        cancelIdleRelease()

        if !engine.isRunning {
            try startEngine(context: "startRecording")
        }
        purgeState()
        isRecording = true
        isRecordingFlag = true

        PersistentLog.log(.audioEngineStarted)

        // A warm engine skips `startEngine()` entirely, so this is the second
        // path that would otherwise never re-assert the allowance — and it is the
        // one that matters most, because it is the moment iOS starts treating us
        // as actively recording (issue #293).
        applyHapticsAllowance(context: "startRecording")
    }

    /// Collect recorded samples WITHOUT stopping the engine.
    /// Keeps the engine alive for subsequent recordings (no cold start needed).
    ///
    /// WHY keep engine running: iOS requires an active audio engine to keep
    /// the app alive in background (UIBackgroundModes:audio). Stopping the engine
    /// causes iOS to suspend the app, breaking Darwin notification reception.
    ///
    /// - Returns: Audio samples ready for transcription. Engine keeps running.
    func collectSamples() -> [Float] {
        isRecording = false
        isRecordingFlag = false

        let samples = audioSamples
        audioSamples = []

        PersistentLog.log(.engineCollectResult(sampleCount: samples.count, engineRunning: engine.isRunning))

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("UnifiedAudioEngine collectSamples. Samples: \(samples.count, privacy: .public), Duration: \(String(format: "%.1f", Double(samples.count) / 16000.0), privacy: .public)s, engine still running")
        }

        // Reset published state but keep engine running
        bufferEnergy = []
        bufferSeconds = 0

        // Arm the idle-release timer (issue #106 Phase B). If the user starts a
        // new recording or warms up before the timer fires, it gets cancelled.
        scheduleIdleRelease(after: Self.idleReleaseInterval)

        return samples
    }

    /// Stop the engine completely and return all accumulated samples.
    /// After this, the next recording requires warmUp() or startRecording().
    ///
    /// - Returns: Audio samples ready for transcription.
    func stopEngine() -> [Float] {
        cancelIdleRelease()
        isRecording = false
        isRecordingFlag = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let samples = audioSamples
        audioSamples = []

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("UnifiedAudioEngine stopped. Samples: \(samples.count, privacy: .public), Duration: \(String(format: "%.1f", Double(samples.count) / 16000.0), privacy: .public)s")
        }

        bufferEnergy = []
        bufferSeconds = 0

        return samples
    }

    /// Fully deactivate audio: stop engine + deactivate AVAudioSession.
    /// Call when user explicitly stops all audio (e.g., Power button in Dynamic Island).
    func deactivateSession() {
        cancelIdleRelease()
        isRecording = false
        isRecordingFlag = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioSamples = []
        PersistentLog.log(.audioEngineStopped)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionConfigured = false
        logHapticsAllowance(context: "deactivateSession")

        bufferEnergy = []
        bufferSeconds = 0
    }

    /// Force restart the engine (stop + removeTap + reconfigure + start).
    /// Used to recover from zombie engine state where isRunning == true but tap receives no buffers.
    func forceRestart() {
        cancelIdleRelease()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        sessionConfigured = false
        PersistentLog.log(.audioEngineStopped)

        do {
            try configureAudioSession()
            try startEngine(context: "forceRestart")
            PersistentLog.log(.engineWarmUpSuccess(context: "forceRestart"))
        } catch {
            PersistentLog.log(.engineWarmUpFailed(context: "forceRestart", error: DictationFailureMessage.diagnostic(for: error)))
        }
    }

    // MARK: - Idle Release (issue #106 Phase B)

    /// Arm the idle-release work item. Idempotent by construction: it cancels any
    /// prior timer first, so the extra call sites added for #256 can never stack
    /// timers — the last caller to arm always owns the only pending work item.
    /// The work runs on the main queue after `interval` elapses with no recording
    /// activity. Must be called from MainActor context.
    ///
    /// - Parameter interval: how long the engine may sit warm and idle. Callers
    ///   pass `idleReleaseInterval` after a dictation and
    ///   `warmUpIdleReleaseInterval` when the warm state was entered without one.
    private func scheduleIdleRelease(after interval: TimeInterval) {
        cancelIdleRelease()
        lastIdleStartTime = Date()
        armedIdleReleaseInterval = interval

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.releaseWarmState(reason: "idleTimeout")
            }
        }
        idleReleaseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
    }

    /// Cancel a pending idle release. Safe to call when none is armed.
    ///
    /// WHY it also clears `lastIdleStartTime`: the anchor is only meaningful while
    /// a release is armed. Every caller here (`startRecording`, `stopEngine`,
    /// `deactivateSession`, `forceRestart`, interruption and media-services-reset
    /// handling) is leaving the warm-idle state, so keeping the old timestamp let
    /// the wall-clock backstop measure an idle age that had already ended — most
    /// dangerously during an active recording, where the next `didBecomeActive`
    /// could have released the engine mid-sentence (issue #256).
    private func cancelIdleRelease() {
        idleReleaseWorkItem?.cancel()
        idleReleaseWorkItem = nil
        lastIdleStartTime = nil
    }

    /// Wall-clock backstop for the asyncAfter timer. If iOS suspended the main
    /// queue while we were backgrounded, `scheduleIdleRelease`'s `asyncAfter`
    /// can fire late or get coalesced. The DictationCoordinator's
    /// `didBecomeActive` handler calls this to verify: if we have been idle
    /// past the threshold without the timer firing, release now (the engine is
    /// burning battery for nothing). Issue #106 Phase B.
    ///
    /// The decision itself lives in `IdleReleasePolicy` so it can be unit-tested
    /// without an `AVAudioEngine` — including the `isRecording` clause, which was
    /// missing here before #256.
    func enforceIdleReleaseIfDue() {
        guard IdleReleasePolicy.shouldRelease(
            isWarm: engine.isRunning || sessionConfigured,
            isRecording: isRecording,
            idleSince: lastIdleStartTime,
            now: Date(),
            interval: armedIdleReleaseInterval
        ) else { return }
        releaseWarmState(reason: "wallClockBackstop")
    }

    /// Tear down the warm-state engine and deactivate the AVAudioSession.
    ///
    /// Called by the idle timer (`scheduleIdleRelease`). Public so the
    /// scenePhase.active path can call it explicitly if needed (currently
    /// unused — re-warm goes through `warmUp` which trumps the timer). After
    /// release, the next dictation will pay the cold-start cost (~100ms engine
    /// boot + cached WhisperKit init).
    ///
    /// Posts both an in-process notification (Live Activity dismisses) and a
    /// Darwin notification (cross-process consumers can react). Issue #106.
    func releaseWarmState(reason: String) {
        // No-op if already released (prevents double-deactivation logs and
        // redundant Darwin posts when called from multiple paths), and never
        // release under an active recording.
        //
        // WHY the recording clause is here as well as in `enforceIdleReleaseIfDue`:
        // the timer path does not go through the backstop. `startRecording()`
        // cancels the pending work item, so in practice the timer cannot fire
        // mid-recording — but that is a cancellation race away from being false,
        // and this is the single funnel every teardown goes through.
        guard IdleReleasePolicy.canRelease(
            isWarm: engine.isRunning || sessionConfigured,
            isRecording: isRecording
        ) else { return }

        let idleSeconds: Int = {
            guard let started = lastIdleStartTime else { return 0 }
            return Int(Date().timeIntervalSince(started))
        }()

        isRecording = false
        isRecordingFlag = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // Bump generation so any in-flight tap callback bails out before mutating
        // shared audio-thread state (matches the mediaServicesWereReset pattern).
        engineGeneration &+= 1

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        sessionConfigured = false
        converter = nil
        lastUnconvertibleInputFormat = nil
        lastIdleStartTime = nil
        idleReleaseWorkItem = nil

        PersistentLog.log(.warmStateReleased(idleSeconds: idleSeconds))

        // The user-visible claim of #293 is "haptics came back on their own about
        // ten minutes later". This line is what dates the other end of that
        // window against the release that supposedly caused it.
        logHapticsAllowance(context: "releaseWarmState-\(reason)")
        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Warm state released after \(idleSeconds, privacy: .public)s idle (reason: \(reason, privacy: .public))")
        }

        NotificationCenter.default.post(name: .dictusWarmStateReleased, object: nil)
        DarwinNotificationCenter.post(DarwinNotificationName.warmStateReleased)
    }

    // MARK: - Private Helpers

    /// Start the AVAudioEngine with a tap on the input node.
    ///
    /// - Parameter context: names the path that started the engine, so the
    ///   haptics-allowance line emitted on success says which one it came from
    ///   (issue #293).
    private func startEngine(context: String) throws {
        audioSamples = []
        audioThreadEnergy = []
        audioThreadWaveformBins = []
        audioThreadSampleCount = 0
        lastHeartbeatWrite = 0
        lastWaveformWrite = 0
        lastWaveformDiagnosticsWrite = 0

        // WHY this runs BEFORE the format is resolved (issue #459):
        // it used to run thirty lines below, and that is why the AirPods case never
        // reached it. A call takes the input hardware away, so the input node reports a
        // dead format, so `resolveUsableInputFormat` threw `audioHardwareUnavailable`
        // and returned — the call guard was never evaluated at all. Measured on device
        // 2026-08-31: `engineRebuiltOnDeadFormat … route=BluetoothHFP` then
        // `invalid hwFormat after engine rebuild`, and no phone-call line anywhere.
        //
        // Asking "is a call holding this?" first is also the cheaper order: rebuilding
        // a whole AVAudioEngine to chase a format a call is holding cannot succeed.
        // Nothing about the #457 rebuild itself changes — only when it is reached.
        try refuseIfACallHoldsTheMicrophone()

        let (inputNode, hwFormat) = try resolveUsableInputFormat(context: context)

        // Pre-build the converter from the format the node just reported, to 16kHz mono.
        //
        // WHY this is best effort and no longer throws (#417): since the tap installs with
        // `format: nil`, `hwFormat` is advisory. The format that matters is the one on the
        // first buffer, and `processBuffer` rebuilds from it when the two disagree. Refusing
        // to start here would refuse a dictation the bus was about to serve correctly.
        //
        // The pre-build stays because it is what keeps the audio thread allocation-free in
        // the normal case: the node's format is the bus's format almost always, so the first
        // recording buffer finds a converter that already matches and builds nothing.
        //
        // The log line stays for the reason #123 put it there: a start that produces no
        // converter used to leave no trace at all, and the format is the only thing that
        // would explain it. It is a diagnostic now, not a failure — the tap gets the last word.
        converter = AVAudioConverter(from: hwFormat, to: targetFormat)
        lastUnconvertibleInputFormat = nil
        if converter == nil {
            PersistentLog.log(.diagnosticProbe(
                component: "UnifiedAudioEngine",
                instanceID: context,
                action: "converterPrebuildFailed",
                details: "no converter from sr=\(hwFormat.sampleRate) ch=\(hwFormat.channelCount) to 16kHz mono"
            ))
        }

        // Remove any stale tap before installing a new one.
        // WHY: If a previous startEngine() installed a tap but engine.start() threw
        // (e.g., app in background → AUIOClient_StartIO error), the tap remains
        // but the engine isn't running. The next call crashes on installTap.
        inputNode.removeTap(onBus: 0)

        // Wrap installTap in an Objective-C @try/@catch. AVFoundation raises an
        // NSException (uncatchable in Swift) when the format is invalid in ways
        // our pre-flight guards don't cover (#71, #102). Without this shim the
        // process aborts with SIGABRT. Swift imports the Objective-C
        // `tryBlock:error:` as a throwing method.
        // Capture the engine generation at install time. Buffers arriving after a
        // mediaServicesWereReset has bumped the generation (and replaced the engine)
        // belong to the dead engine and must be discarded — otherwise they race
        // with the new engine's tap on shared `nonisolated(unsafe)` audio-thread
        // state (issue #106 review).
        //
        // WHY `format: nil` rather than `hwFormat` (#417): nil means "use the bus's own
        // format", so the value can no longer be stale and a mismatch is impossible by
        // construction. `hwFormat` was read by `resolveUsableInputFormat` sixty lines up,
        // and an interruption — a native call, or Siri — renegotiates the input node inside
        // that window. Measured six times on device (2026-09-02 with Siri listening,
        // 2026-09-03 during a call): `installTap NSException: Failed to create tap due to
        // format mismatch, <AVAudioFormat 1 ch, 48000 Hz, Float32>`, on a format that is
        // individually valid and that every pre-flight guard therefore accepts.
        let installedGeneration = engineGeneration
        do {
            try ObjCExceptionCatcher.catchException {
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
                    guard let self else { return }
                    guard installedGeneration == self.engineGeneration else { return }
                    self.processBuffer(buffer)
                }
            }
        } catch {
            let reason = (error as NSError).localizedDescription
            PersistentLog.log(.dictationFailed(error: "installTap NSException: \(reason)"))
            throw AudioEngineError.installTapFailed(call: .installTap, reason: reason)
        }

        // engine.start() can throw both Swift errors (AUIOClient_StartIO) and
        // Objective-C NSExceptions. Wrap in both ObjCExceptionCatcher AND Swift do/catch.
        var swiftStartError: Error?
        do {
            try ObjCExceptionCatcher.catchException {
                do {
                    try self.engine.start()
                } catch {
                    swiftStartError = error
                }
            }
        } catch {
            inputNode.removeTap(onBus: 0)
            let reason = (error as NSError).localizedDescription
            PersistentLog.log(.dictationFailed(error: "engine.start NSException: \(reason)"))
            throw AudioEngineError.installTapFailed(call: .engineStart, reason: reason)
        }
        if let swiftStartError {
            inputNode.removeTap(onBus: 0)
            // The last silent throw in this function before #123. AUIOClient_StartIO
            // failures land here and left nothing in the log to date them by.
            PersistentLog.log(.dictationFailed(
                error: "engine.start failed: \((swiftStartError as NSError).localizedDescription)"
            ))
            throw swiftStartError
        }

        // Engine is healthy again — clear any interruption flag set by a previous
        // .began handler. Centralising the clear here means every successful start
        // path (warmUp, startRecording, didBecomeActive recovery, forceRestart,
        // .ended interruption resume) ends up healthy without each caller having
        // to remember to flip the flag.
        isInterrupted = false

        // Re-assert the system-haptics allowance now that the session is truly
        // carrying input. `configureAudioSession()` sets it before the engine
        // exists, and `startEngine()` is reachable without it — after a
        // `releaseWarmState()` deactivation, or when `engine.start()` reactivates
        // the session implicitly. This is the funnel every start path goes
        // through (issue #293).
        applyHapticsAllowance(context: "startEngine-\(context)")

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("UnifiedAudioEngine started (hw: \(hwFormat.sampleRate, privacy: .public)Hz -> 16kHz)")
        }
    }

    /// Get an input node whose format can actually be recorded from, rebuilding the
    /// engine once if the one we have reports a dead format.
    ///
    /// ### The bug (issue #123, three device captures)
    ///
    /// The audio session momentarily reports no input at all
    /// (`audioRouteChanged details=inputs=none`). The input node, read in that window,
    /// latches `sr=0.0 ch=2` — what `outputFormat(forBus:)` returns with no input
    /// present. The route comes back a second later; the node keeps the dead format
    /// for the life of the process. Every dictation after that failed, and the only
    /// thing that ever cleared it was the user force-quitting the app.
    ///
    /// The old code answered `sr == 0` with a 50 ms sleep and a re-read of **the same
    /// node**, which cannot work: the node is what is latched. `engine` was created
    /// once and replaced in exactly one place — `handleMediaServicesReset()`, which
    /// never fired in any of the three captures (`audioMediaServicesReset` count 0).
    ///
    /// So a dead format means "this engine is unusable", and the answer is a new one.
    /// `replaceEngine()` is the media-services-reset rebuild, extracted; the 50 ms
    /// settle stays because it is the separate #102 fix, for a node that has not
    /// finished negotiating its format after a wake-from-URL-scheme `setActive(true)`.
    /// A fresh node deserves that window just as much as the old one did.
    ///
    /// ### Why the loop terminates
    ///
    /// `AudioInputFormatPolicy.decide` returns `.rebuildEngine` only while
    /// `hasRebuiltEngine` is false, and the only branch that does not return or throw
    /// sets it to true. Pinned by `testAtMostOneRebuildIsEverAsked` in DictusCore.
    ///
    /// - Returns: the node the tap must be installed on — which is NOT necessarily
    ///   `engine.inputNode` as read by the caller before this ran — and its format.
    private func resolveUsableInputFormat(context: String) throws -> (AVAudioInputNode, AVAudioFormat) {
        var node = engine.inputNode
        var format = node.outputFormat(forBus: 0)
        var hasRebuiltEngine = false

        while true {
            let decision = AudioInputFormatPolicy.decide(
                channelCount: format.channelCount,
                sampleRate: format.sampleRate,
                hasRebuiltEngine: hasRebuiltEngine
            )

            switch decision {
            case .proceed:
                return (node, format)

            case .rebuildEngine:
                let before = "sr=\(format.sampleRate) ch=\(format.channelCount)"
                replaceEngine()
                hasRebuiltEngine = true
                usleep(50_000)
                node = engine.inputNode
                format = node.outputFormat(forBus: 0)

                // The trigger is sporadic and has no identified cause, so the next
                // field occurrence has to be able to tell its own story: this line is
                // what will say whether the rebuild is what unblocked the user.
                PersistentLog.log(.diagnosticProbe(
                    component: "UnifiedAudioEngine",
                    instanceID: context,
                    action: "engineRebuiltOnDeadFormat",
                    details: "before=\(before) after=sr=\(format.sampleRate) ch=\(format.channelCount) \(routeStateDescription())"
                ))

            case .fail(let reason):
                // A fresh node reporting a dead format is not a latch, it is an
                // absence — the hardware is not there. `reason` names which half was
                // missing; the user-facing sentence is the same either way (#313).
                PersistentLog.log(.dictationFailed(
                    error: "invalid hwFormat after engine rebuild: sr=\(format.sampleRate) ch=\(format.channelCount) reason=\(reason.rawValue) \(routeStateDescription())"
                ))
                throw AudioEngineError.audioHardwareUnavailable(reason: reason.rawValue)
            }
        }
    }

    /// Refuse the start when a call holds the microphone, and say that it is a call.
    ///
    /// ### What was wrong (issue #459)
    ///
    /// The guard used to be one `contains("telephony")` on the input ports. **A call
    /// carried over AirPods or any bluetooth headset does not present as `telephony`.
    /// It presents as `BluetoothHFP`** — so for most people, on the majority of their
    /// calls, the guard never fired. Until #457 that miss was hidden: a zero-channel
    /// format threw `phoneCallActive` too, so the AirPods case reached the user with
    /// the right message for the wrong reason. #457 corrected the mislabel, which left
    /// this case telling the user the microphone is unavailable without saying that a
    /// call is holding it — the one situation the user can actually act on.
    ///
    /// ### WHY only the inputs, and not `builtInReceiver` on the outputs
    ///
    /// Unchanged from the original guard: without `.defaultToSpeaker`, iOS routes
    /// output to `builtInReceiver` by default. That is normal operation, not a call.
    ///
    /// The rule itself is `CallRoutePolicy` in DictusCore, because this method cannot
    /// be tested — `@MainActor`, a live `AVAudioEngine`, and a simulator that has
    /// neither a telephony route nor bluetooth audio. Since #123 this is the only site
    /// in the file that produces the phone-call message.
    private func refuseIfACallHoldsTheMicrophone() throws {
        let session = AVAudioSession.sharedInstance()
        let decision = CallRoutePolicy.decide(
            inputPortTypes: session.currentRoute.inputs.map { $0.portType.rawValue },
            isInterrupted: isInterrupted,
            builtInMicrophoneIsAvailable: (session.availableInputs ?? [])
                .contains { $0.portType == .builtInMic }
        )

        guard case .callHoldsMicrophone(let evidence) = decision else { return }

        PersistentLog.log(.dictationFailed(
            error: "a call holds the microphone: \(evidence.rawValue) — \(routeStateDescription())"
        ))
        throw AudioEngineError.phoneCallActive(evidence: Self.evidenceSentence(for: evidence))
    }

    /// The English fragment `AudioEngineError.phoneCallActive` carries into the log.
    ///
    /// Diagnostic only — never shown to anyone. It exists because the two signals are
    /// indistinguishable in a log that only says "a call", and the reader of that log
    /// is an agent (#255).
    private static func evidenceSentence(for evidence: CallRouteEvidence) -> String {
        switch evidence {
        case .telephonyInputRoute:
            return "a telephony input route is active"
        case .headsetRouteDuringInterruption:
            return "a bluetooth headset is the input route while the session is interrupted"
        }
    }

    /// What the audio session says about its inputs right now, for a log line.
    ///
    /// WHY all three fields (issue #123): the failure this file spent months not
    /// explaining was a route that went empty and came back. `route` alone would have
    /// shown the built-in mic by the time the guard ran and told the reader nothing;
    /// `available` and `preferred` are what separate "nothing is connected" from "we
    /// asked for a device that is gone".
    private func routeStateDescription() -> String {
        let session = AVAudioSession.sharedInstance()
        return "route=\(portList(session.currentRoute.inputs))"
            + " available=\(portList(session.availableInputs ?? []))"
            + " preferred=\(session.preferredInput.map { $0.portType.rawValue } ?? "none")"
    }

    /// Port types as one comma-separated token, or `none` for an empty list.
    ///
    /// Shared by `routeStateDescription()` and the route-change handler so the same
    /// fact never gets two spellings in the log an agent has to scan (#255).
    private func portList(_ ports: [AVAudioSessionPortDescription]) -> String {
        let names = ports.map { $0.portType.rawValue }.joined(separator: ",")
        return names.isEmpty ? "none" : names
    }

    /// Reset recording state without stopping the engine.
    private func purgeState() {
        audioSamples = []
        bufferEnergy = []
        bufferSeconds = 0
        audioThreadEnergy = []
        audioThreadWaveformBins = []
        audioThreadSampleCount = 0
        lastWaveformWrite = 0
        lastWaveformDiagnosticsWrite = 0
    }

    /// Process incoming audio buffer: convert to 16kHz and compute energy for waveform.
    ///
    /// WHY nonisolated: This callback fires on the audio thread. We do the CPU-intensive
    /// conversion here, then dispatch UI updates and sample accumulation to main thread.
    ///
    /// SAMPLE GATING: Samples only accumulate when isRecordingFlag is true. When idle,
    /// the engine still processes buffers for heartbeat + waveform (keeps background alive)
    /// but discards audio data. This prevents the 64M idle sample accumulation bug (#38).
    ///
    /// IDLE FAST PATH (issue #106 Phase C): When `isRecordingFlag` is false, we skip the
    /// converter, waveform compute, energy buffer maintenance, and the main-thread
    /// dispatch — none of those outputs are consumed when no one is dictating. We only
    /// emit a sparse heartbeat (every 3s instead of 1s) so the keyboard's watchdog
    /// can still see the app is alive when a future dictation starts.
    ///
    /// WHY 3s (not 10s): `isRecordingFlag` is false during `.transcribing` too —
    /// `collectSamples()` flips it to false before transcription begins. The keyboard
    /// watchdog falls back to the heartbeat with a 5s threshold during active dictation.
    /// A 10s throttle let transcriptions longer than 5s falsely trip the watchdog.
    /// 3s keeps us safely below the threshold; the per-buffer drain reduction comes
    /// from skipping conversion + waveform compute, not from the heartbeat cadence.
    private nonisolated func processBuffer(_ buffer: AVAudioPCMBuffer) {
        let now = Date().timeIntervalSince1970

        // Idle fast path — sparse heartbeat only.
        if !isRecordingFlag {
            let idleHeartbeatThrottle: TimeInterval = 3.0
            if now - lastHeartbeatWrite >= idleHeartbeatThrottle {
                lastHeartbeatWrite = now
                AppGroup.defaults.set(now, forKey: SharedKeys.recordingHeartbeat)
            }
            return
        }

        guard let converter = converterMatching(buffer.format) else { return }

        // Calculate output frame count: input frames * (target rate / source rate) + 1
        let ratio = 16000.0 / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        // Convert from hardware format to 16kHz mono
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            if #available(iOS 14.0, *) {
                DictusLogger.app.warning("Audio conversion error: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        // Extract Float32 samples from the converted buffer
        guard let channelData = outputBuffer.floatChannelData else { return }
        let frameLength = Int(outputBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // Compute RMS energy for this buffer (0.0-1.0 range)
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
        // Scale RMS to waveform range. 15x scaling maps: quiet speech (0.01) → 0.15,
        // normal (0.05) → 0.75, loud (0.07+) → 1.0 capped.
        let energy = min(rms * 15.0, 1.0)

        // === Audio thread writes (bypass main thread throttling in background) ===

        // Update audio-thread energy buffer (rolling window of last 30 values)
        audioThreadEnergy.append(energy)
        if audioThreadEnergy.count > 30 {
            audioThreadEnergy.removeFirst(audioThreadEnergy.count - 30)
        }

        // Build a short-lived waveform silhouette from local buckets inside the current buffer.
        // WHY: A single RMS value per callback tends to produce a flat line that only moves
        // vertically. Splitting the converted buffer into several peak+RMS buckets preserves
        // intra-utterance shape, which makes the keyboard waveform feel alive even after app
        // switches or when speech loudness is relatively stable.
        let waveformBuckets = makeWaveformBuckets(from: samples)
        audioThreadWaveformBins.append(contentsOf: waveformBuckets)
        if audioThreadWaveformBins.count > waveformBarCount {
            audioThreadWaveformBins.removeFirst(audioThreadWaveformBins.count - waveformBarCount)
        }

        // Write heartbeat (~1Hz) during recording
        if now - lastHeartbeatWrite >= 1.0 {
            lastHeartbeatWrite = now
            AppGroup.defaults.set(now, forKey: SharedKeys.recordingHeartbeat)
        }

        // Write waveform data + elapsed time to App Group (~5Hz)
        if now - lastWaveformWrite >= 0.2 {
            lastWaveformWrite = now
            audioThreadSampleCount += 0 // count is updated in main thread dispatch below
            let snapshot = makeWaveformSnapshot()
            if let data = try? JSONEncoder().encode(snapshot) {
                AppGroup.defaults.set(data, forKey: SharedKeys.waveformEnergy)
            }
            AppGroup.defaults.set(Double(audioThreadSampleCount) / 16000.0, forKey: SharedKeys.recordingElapsedSeconds)
            AppGroup.defaults.synchronize()
            DarwinNotificationCenter.post(DarwinNotificationName.waveformUpdate)

            if now - lastWaveformDiagnosticsWrite >= 1.0 {
                lastWaveformDiagnosticsWrite = now
                PersistentLog.log(.diagnosticProbe(
                    component: "UnifiedAudioEngine",
                    instanceID: "shared",
                    action: "waveformSnapshot",
                    details: waveformStatsDetails(snapshot)
                ))
            }
        }

        // Track sample count on audio thread (needed for elapsed time in App Group writes)
        audioThreadSampleCount += samples.count

        // === Main thread dispatch (for in-app UI: RecordingView, SwiftUI) ===

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // SAMPLE GATE: only accumulate when recording
            guard self.isRecording else { return }
            self.audioSamples.append(contentsOf: samples)
            self.bufferSeconds = Double(self.audioSamples.count) / 16000.0

            // Maintain a rolling window of energy values (last 30 = matches barCount in BrandWaveform)
            self.bufferEnergy = self.makeWaveformSnapshot()
        }
    }

    /// The converter for this buffer, built or rebuilt when the one we hold reads a
    /// different format. Nil means the buffer cannot be converted and must be dropped.
    ///
    /// ### Why the format comes from the buffer (#417)
    ///
    /// The tap installs with `format: nil`, so the bus decides what it delivers and nothing
    /// we read beforehand is authoritative. `startEngine()` still pre-builds a converter from
    /// the format the node reported, which is the same format in every ordinary start — so
    /// the ordinary path lands on `.reuse` and allocates nothing.
    ///
    /// It also closes a second, quieter failure the issue named: before this, a route change
    /// mid-recording left the converter reading a format the hardware had stopped producing,
    /// and it went on converting from it without a word.
    ///
    /// ### Why allocating on the audio thread is acceptable here
    ///
    /// This runs on a real-time thread, and `AVAudioConverter(from:to:)` allocates. It is
    /// bounded to one build per distinct format — a start, or a route renegotiation — and
    /// `AudioConverterCachePolicy` is what bounds it: without the failure memo, a format
    /// nothing can convert would allocate on every buffer at roughly 100 Hz.
    ///
    /// The same callback already encodes JSON at 5 Hz and writes the persistent log at 1 Hz,
    /// so a build at route-change frequency is strictly cheaper than what runs here anyway.
    /// The alternative — hop to main and drop buffers until it answers — would lose audio at
    /// the start of the recording, which is the worst place to lose it.
    private nonisolated func converterMatching(_ bufferFormat: AVAudioFormat) -> AVAudioConverter? {
        switch AudioConverterCachePolicy.decide(
            heldInputFormat: converter?.inputFormat,
            lastUnconvertibleFormat: lastUnconvertibleInputFormat,
            bufferFormat: bufferFormat
        ) {
        case .reuse:
            return converter

        case .skipUnconvertibleFormat:
            return nil

        case .build:
            let previous = converter?.inputFormat
            guard let rebuilt = AVAudioConverter(from: bufferFormat, to: targetFormat) else {
                // This is the case that silently loses the recording: no converter means no
                // samples accumulate, and the user gets an empty transcription with nothing
                // to explain it. Logged as a failure for that reason, once per format —
                // `lastUnconvertibleInputFormat` is what keeps it from repeating at 100 Hz.
                converter = nil
                lastUnconvertibleInputFormat = bufferFormat
                PersistentLog.log(.dictationFailed(
                    error: "no converter from the bus format sr=\(bufferFormat.sampleRate)"
                        + " ch=\(bufferFormat.channelCount) to 16kHz mono"
                ))
                return nil
            }
            converter = rebuilt
            lastUnconvertibleInputFormat = nil

            // The whole point of #417 is that the format we read and the format the bus
            // delivers can differ, and we had no way to see it. This line is that evidence.
            PersistentLog.log(.diagnosticProbe(
                component: "UnifiedAudioEngine",
                instanceID: "shared",
                action: "converterBuiltFromBusFormat",
                details: "from=\(previous.map { "sr=\($0.sampleRate) ch=\($0.channelCount)" } ?? "none")"
                    + " to=sr=\(bufferFormat.sampleRate) ch=\(bufferFormat.channelCount)"
            ))
            return rebuilt
        }
    }

    private nonisolated func makeWaveformBuckets(from samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }

        let bucketCount = max(3, min(6, samples.count / 160))
        let bucketSize = max(samples.count / bucketCount, 1)
        var buckets: [Float] = []
        buckets.reserveCapacity(bucketCount)

        var start = 0
        while start < samples.count {
            let end = min(start + bucketSize, samples.count)
            let slice = samples[start..<end]

            var sumSquares: Float = 0
            var peak: Float = 0
            for sample in slice {
                let magnitude = abs(sample)
                sumSquares += magnitude * magnitude
                peak = max(peak, magnitude)
            }

            let rms = sqrt(sumSquares / Float(max(slice.count, 1)))
            let shaped = min(max((peak * 0.65) + (rms * 6.5), 0), 1)
            buckets.append(shaped)
            start = end
        }

        return buckets
    }

    private nonisolated func makeWaveformSnapshot() -> [Float] {
        let source = audioThreadWaveformBins.isEmpty ? audioThreadEnergy : audioThreadWaveformBins
        let resampled = resampleWaveform(source, targetCount: waveformBarCount)
        return enhanceWaveformContrast(resampled)
    }

    private nonisolated func resampleWaveform(_ source: [Float], targetCount: Int) -> [Float] {
        guard targetCount > 0 else { return [] }
        guard !source.isEmpty else { return Array(repeating: 0, count: targetCount) }
        guard source.count != targetCount else { return source }

        var result: [Float] = []
        result.reserveCapacity(targetCount)

        for index in 0..<targetCount {
            let position = Float(index) / Float(max(targetCount - 1, 1))
            let arrayIndex = position * Float(source.count - 1)
            let lower = Int(arrayIndex)
            let upper = min(lower + 1, source.count - 1)
            let fraction = arrayIndex - Float(lower)
            let value = source[lower] * (1 - fraction) + source[upper] * fraction
            result.append(min(max(value, 0), 1))
        }

        return result
    }

    private nonisolated func enhanceWaveformContrast(_ values: [Float]) -> [Float] {
        guard !values.isEmpty else { return [] }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let spread = maxValue - minValue

        guard maxValue > 0.06 else { return values }

        if spread < 0.12 {
            let centerBias = stride(from: 0, to: values.count, by: 1).map { index -> Float in
                let normalized = Float(index) / Float(max(values.count - 1, 1))
                let distance = abs(normalized - 0.5)
                return 1.0 - (distance * 0.18)
            }

            return values.enumerated().map { index, value in
                let normalized: Float
                if spread > 0.0001 {
                    normalized = (value - minValue) / spread
                } else {
                    normalized = 0.5
                }

                let floor = min(maxValue * 0.28, 0.16)
                let stretched = floor + normalized * (1 - floor)
                return min(max(stretched * centerBias[index], 0), 1)
            }
        }

        return values
    }

    private nonisolated func waveformStatsDetails(_ values: [Float]) -> String {
        guard !values.isEmpty else { return "count=0" }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let spread = maxValue - minValue
        let first = values.first ?? 0
        let middle = values[values.count / 2]
        let last = values.last ?? 0
        return String(
            format: "count=%d min=%.3f max=%.3f spread=%.3f first=%.3f mid=%.3f last=%.3f",
            values.count,
            minValue,
            maxValue,
            spread,
            first,
            middle,
            last
        )
    }
}
