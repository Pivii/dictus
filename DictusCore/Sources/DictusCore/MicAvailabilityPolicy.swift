// DictusCore/Sources/DictusCore/MicAvailabilityPolicy.swift
import Foundation

/// How the keyboard's mic button should present itself with respect to the
/// shared model load state (issue #250).
///
/// This is presentation only. It never replaces the mic-tap guard in
/// `KeyboardState.startRecording()` — the guard stays authoritative and keeps
/// refusing taps while `ModelLoadState == .loading`, whatever this returns.
public enum MicAvailability: String, Equatable, Sendable {
    /// Normal mic button.
    case available
    /// Dimmed "not ready" mic. Still tappable — the tap explains the wait and
    /// names the resolving action instead of silently doing nothing.
    case modelLoading
}

/// Decides whether a model load in flight is worth showing on the mic button.
///
/// Pure and time-injectable so the two edge cases that make this feature risky
/// can be unit-tested without a device:
///
/// 1. **Flicker.** `ModelLoadState` flips to `.loading` on every cold start,
///    including fast ones (Parakeet, warm app) that resolve in a few hundred
///    milliseconds. Greying the button out for that long reads as instability,
///    not as feedback, so a load must last at least `surfaceDelay` before it is
///    allowed to change the button.
///
/// 2. **Permanently dead button.** `ModelLoadState` is written by DictusApp. If
///    the app is force-quit part-way through a load, `loading` stays in the App
///    Group with no process left to move it on. Binding the button naively to
///    that value would disable it forever — far worse than the pre-#250
///    behaviour. `staleLoadCutoff` bounds how long a `loading` value is
///    trusted; past it the button goes back to normal and the user simply gets
///    the pre-tap-free behaviour we had before (tap → refusal message).
public enum MicAvailabilityPolicy {

    /// How long a load must already have been running before the not-ready
    /// state is shown.
    ///
    /// WHY 0.6s: it has to be long enough to swallow the fast paths — Parakeet
    /// and a warm app resolve well inside it, and it also absorbs the few
    /// milliseconds of cross-process UserDefaults propagation lag — while
    /// staying under the ~1s threshold at which a wait stops feeling
    /// instantaneous. A load that resolves faster than this never needed
    /// announcing; a load that outlasts it (whisper-medium was ~10s in the
    /// #250 capture) is surfaced essentially as soon as the user looks at the
    /// keyboard.
    public static let surfaceDelay: TimeInterval = 0.6

    /// How long a `loading` value is trusted before the button reverts to
    /// normal.
    ///
    /// WHY 30s: the slowest load observed on this path in #250 was ~10s
    /// (whisper-medium, cold), so this leaves 3x margin for a genuine load.
    /// Past it we assume nobody is going to move the state on and stop
    /// dimming the button. The cost of being wrong is small and bounded: a
    /// genuinely slower load (a first-run turbo compile can take minutes) just
    /// loses the pre-tap hint and behaves exactly as it did before #250 — the
    /// tap is still refused and still explains itself.
    public static let staleLoadCutoff: TimeInterval = 30

    /// - Parameters:
    ///   - state: the value read from `SharedKeys.modelLoadState`.
    ///   - loadStartedAt: when that `loading` value was written, or the first
    ///     time this process observed it when the writer left no timestamp.
    ///     `nil` means the age is unknown, which is treated as untrustworthy.
    ///   - now: current time, injected for tests.
    public static func availability(
        state: ModelLoadState,
        loadStartedAt: Date?,
        now: Date
    ) -> MicAvailability {
        guard state == .loading, let loadStartedAt else { return .available }

        let elapsed = now.timeIntervalSince(loadStartedAt)
        // A negative elapsed means the device clock moved between the write and
        // this read. Failing the lower bound is the safe direction: we show the
        // normal button rather than dimming it on data we cannot age.
        guard elapsed >= surfaceDelay, elapsed < staleLoadCutoff else { return .available }

        return .modelLoading
    }

    /// Whether the presentation can still change on its own for this load.
    ///
    /// Used by the keyboard to stop its re-evaluation timer once a `loading`
    /// value has gone stale, so the timer's lifetime is bounded by
    /// `staleLoadCutoff` instead of running for as long as the keyboard is up.
    public static func needsReevaluation(
        state: ModelLoadState,
        loadStartedAt: Date?,
        now: Date
    ) -> Bool {
        guard state == .loading, let loadStartedAt else { return false }
        return now.timeIntervalSince(loadStartedAt) < staleLoadCutoff
    }
}
