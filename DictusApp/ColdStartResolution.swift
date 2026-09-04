// DictusApp/ColdStartResolution.swift
// What happens to a cold-start dictation parked waiting for the app to become
// active, when the app leaves the foreground instead (issue #311).
import Foundation
import UIKit
import DictusCore

/// The exit a parked cold start is guaranteed to get.
///
/// WHY this lives beside `ColdStartLaunch` rather than inside `DictationCoordinator`:
/// it is one concern with one entry point, and the coordinator is already the largest
/// type in the app -- adding this to it put the file past both of SwiftLint's length
/// limits, which is the linter making the same point. The decision these methods act
/// on is `ColdStartResolutionPolicy` in DictusCore; this is the half that needs UIKit
/// and the App Group.
///
/// WHY three members of the coordinator are not `private`: Swift scopes `private` to
/// the file, so `pendingColdStartDictation`, `coldStartAssertion` and
/// `reportStrandedColdStart()` have to be visible from here. Each is narrow and has
/// exactly one writer. `handleError` is the one that deliberately stayed private, which
/// is why `reportStrandedColdStart()` did not move over with the rest: a purpose-built
/// method crossing the line is a much smaller door than the general failure path.
extension DictationCoordinator {
    /// Give a parked cold start its last chance, at the moment the app leaves the
    /// foreground (issue #311).
    ///
    /// The invariant this restores: **a parked start is never abandoned silently.**
    /// Either the dictation runs, or the keyboard is told it failed. What it must
    /// never do again is stay parked: the overlay held "Démarrage…" indefinitely,
    /// the Dynamic Island sat in standby, and the only recovery was opening DictusApp
    /// by hand — which fired `didBecomeActive` and started recording 22 seconds late,
    /// long after the user had given up.
    ///
    /// WHY here and not from `willEnterForeground`, which the issue's brief proposed:
    /// the deferral logs `appState=1`, i.e. the app was *already* `.inactive` when the
    /// URL arrived, so the background-to-foreground transition had completed and
    /// `willEnterForeground` had already fired. An observer for it would never see the
    /// flag set. Between the parking and the background transition, no lifecycle event
    /// arrives at all — this is the first one, and therefore the only one.
    ///
    /// WHY it attempts the start rather than reporting straight away: `.active` is not
    /// coming, so the alternative is a guaranteed failure. The attempt may hit the #73
    /// `AUIOClient_StartIO` failure from a non-active state, in which case
    /// `startDictation`'s own catch reports it through `handleError` — the same terminal
    /// state, and no raw CoreAudio error reaching the user. It cannot regress a healthy
    /// dictation: this runs only when `didBecomeActive` never came, which is a path that
    /// strands 100% of the time today.
    ///
    /// WHY it calls `startDictation` rather than starting the engine itself, which is
    /// load-bearing and not a convenience: a success here has to be a *complete* start,
    /// or it is the same bug with a different cause. Going through the shared path is
    /// what guarantees that — `allowInactiveStart` suppresses the defer and nothing
    /// else, so the cold-start task still writes `.recording` to the App Group (which
    /// posts `statusChanged` and flips the keyboard off "Démarrage…" on its own), still
    /// calls `transitionToRecording()`, still logs `audioEngineStarted`, still runs the
    /// zombie-engine check, and the audio thread still streams waveform energy across.
    /// Recording on into the background is the warm path's normal behaviour under
    /// `UIBackgroundModes: audio`, so a success is genuinely usable and not a special case.
    ///
    /// - Returns: whether a dictation was started. The caller needs it because the two
    ///   decisions it makes next — clearing `coldStartActive` and starting a standby
    ///   Live Activity — both assume no recording is beginning, and `status` has not
    ///   moved yet when this returns (the start runs in a Task).
    ///
    /// Deliberately not `@discardableResult`: a caller that ignores the answer would
    /// clear `coldStartActive` and start a standby activity against a recording that
    /// is beginning, which is the pair of mistakes the comments at the call site warn
    /// about. The compiler should ask.
    func resolvePendingColdStartOnBackground() -> Bool {
        let storedRaw = AppGroup.defaults.string(forKey: SharedKeys.dictationStatus)
        let resolution = ColdStartResolutionPolicy.resolution(
            isPending: pendingColdStartDictation,
            storedStatus: storedRaw.flatMap(DictationStatus.init(rawValue:)),
            coordinatorStatus: status
        )
        guard resolution != .none else { return false }

        // Taken before anything else runs: from here on there is a request only this
        // process can resolve, and it must not be suspended mid-resolution. It covers
        // the log writes too, which are async and are the evidence the device
        // validation greps for.
        beginColdStartAssertion()

        // Cleared before acting, not after: every branch below is terminal for this
        // parked request, and leaving the flag set would let a later `didBecomeActive`
        // start a second dictation for a request already resolved.
        pendingColdStartDictation = false
        PersistentLog.log(.coldStartStranded(
            keyboardStatus: storedRaw ?? "nil",
            action: resolution.rawValue
        ))

        switch resolution {
        case .none:
            // Unreachable behind the guard above. Spelled out rather than folded into
            // a `default` so a case added to `ColdStartResolution` later stops the
            // compiler here instead of silently doing nothing.
            endColdStartAssertion(reason: "no-op")
            return false
        case .dropped:
            // The keyboard has already stopped waiting — its watchdog reset the status,
            // or a cancel wrote `.idle`. Raising an error banner now would speak for a
            // request the user has moved on from.
            endColdStartAssertion(reason: "dropped")
            return false
        case .report:
            // Every write `handleError` makes to the App Group is synchronous, so the
            // user-facing outcome is already safe on this branch. The assertion is here
            // so the log lines that prove it survive the suspension too.
            reportStrandedColdStart()
            endColdStartAssertion(reason: "reported")
            return false
        case .retry:
            // The assertion stays held. `startDictation` does its work inside a Task,
            // and that task releases it: `engine-started` once the engine is capturing
            // and `UIBackgroundModes: audio` takes over, or `failure-reported` once the
            // keyboard has been told. Its `defer` catches every other exit.
            startDictation(fromURL: true, allowInactiveStart: true, origin: .keyboard)

            // Except when there is no task at all. `startDictation` can also fail
            // synchronously and return before creating one -- "no model downloaded" is
            // that path -- and it reports through `handleError` like any other failure.
            // Nothing would then release the assertion until it expired. The App Group
            // separates the two cases: still `requested` means the start is in flight
            // inside the task, anything else means the outcome already landed right here.
            let started = AppGroup.defaults.string(forKey: SharedKeys.dictationStatus)
                == DictationStatus.requested.rawValue
            if !started {
                endColdStartAssertion(reason: "resolved-synchronously")
            }
            return started
        }
    }

    // MARK: - Background execution assertion

    /// Take the background assertion described on `coldStartAssertion`. Idempotent.
    func beginColdStartAssertion() {
        guard coldStartAssertion == .invalid else { return }
        coldStartAssertion = UIApplication.shared.beginBackgroundTask(
            withName: "dictus.coldStartLastChance"
        ) { [weak self] in
            self?.handleColdStartAssertionExpiryFromAnyThread()
        }
    }

    /// Release the assertion, after making sure the lines it was protecting are on
    /// disk. Idempotent, so every exit can call it without checking first.
    func endColdStartAssertion(reason: String) {
        guard coldStartAssertion != .invalid else { return }
        PersistentLog.log(.diagnosticProbe(
            component: "coldStart", instanceID: "0",
            action: "assertionEnded",
            details: "reason=\(reason)"
        ))
        // Drain before letting go, not after: `PersistentLog.log` appends on a
        // `.utility` queue, and releasing the assertion is precisely the moment the
        // process becomes suspendable again.
        PersistentLog.flush()
        UIApplication.shared.endBackgroundTask(coldStartAssertion)
        coldStartAssertion = .invalid
    }

    /// Bridge from UIKit's expiration handler onto the main actor.
    ///
    /// WHY the thread check rather than a bare `MainActor.assumeIsolated`: UIKit
    /// documents this handler as running on the main thread, but a wrong assumption
    /// here traps and takes the app down, and the branch costs nothing. WHY not
    /// `Task { @MainActor in }`: that defers the work to a later turn, and the whole
    /// premise of an expiring assertion is that there may not be one.
    nonisolated func handleColdStartAssertionExpiryFromAnyThread() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { self.handleColdStartAssertionExpiry() }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { self.handleColdStartAssertionExpiry() }
            }
        }
    }

    /// The assertion ran out before either outcome landed.
    ///
    /// An expiry with the request still unresolved is itself a stranded start, and it
    /// has to be reported rather than expiring quietly -- otherwise the guarantee has
    /// a hole exactly where the system is under most pressure.
    ///
    /// WHY the App Group status is what decides, rather than a flag of our own: it is
    /// the same value the keyboard is reading, so one read answers both ways this can
    /// already be resolved. `recording` means the start succeeded and the audio mode
    /// has taken over; anything else that is not `requested` means the keyboard
    /// stopped waiting on its own.
    func handleColdStartAssertionExpiry() {
        guard coldStartAssertion != .invalid else { return }
        let stored = AppGroup.defaults.string(forKey: SharedKeys.dictationStatus)
        guard stored == DictationStatus.requested.rawValue else {
            endColdStartAssertion(reason: "expired-resolved")
            return
        }
        PersistentLog.log(.coldStartStranded(
            keyboardStatus: DictationStatus.requested.rawValue,
            action: "expired"
        ))
        reportStrandedColdStart()
        endColdStartAssertion(reason: "expired-reported")
    }
}
