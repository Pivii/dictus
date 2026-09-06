// DictusCore/Sources/DictusCore/SystemCallObserver.swift
// The one place CallKit is imported: a retained CXCallObserver, reduced to a decision.
import Foundation

#if os(iOS)
import CallKit

/// Reads the system's current calls and answers `ActiveCallPolicy`'s question (issue #483).
///
/// ### Why the observer is a stored property and never a local
///
/// `CXCallObserver` must be **retained**, and its `calls` array is not guaranteed to be
/// populated the instant after `init()` — the header describes the property as "blocking on
/// initial state retrieval if necessary", which is the giveaway that the state arrives from
/// another process. An observer created at mic-tap time and read on the next line would
/// answer "no call" during a real call, and it would do it intermittently, which is worse
/// than doing it always.
///
/// So each owner builds one when it starts and holds it for its whole life:
/// `UnifiedAudioEngine` at app launch, `KeyboardState` at keyboard launch. By the time
/// anyone asks, the connection is up and the answer is a local read.
///
/// ### Why an instance and not a singleton
///
/// Both owners already live exactly once per process and outlive every question asked of
/// them, so a shared global would add process-wide mutable state and buy nothing.
///
/// ### Why it is in DictusCore
///
/// The app and the keyboard have to answer this identically — since #483 the keyboard
/// refuses the mic tap on the same evidence the app would have refused it on, ten seconds
/// and one cold start later. One type, one import, one rule.
public final class SystemCallObserver {

    private let observer: CXCallObserver

    /// Build and retain the observer. Do this once, when the process starts.
    public init() {
        observer = CXCallObserver()
    }

    /// Whether a call holds the microphone right now.
    public func decide() -> ActiveCallDecision {
        ActiveCallPolicy.decide(calls: observer.calls.map {
            ObservedCall(hasConnected: $0.hasConnected, hasEnded: $0.hasEnded)
        })
    }

    /// What CallKit is reporting, as one log token.
    ///
    /// It carries `onHold` and `outgoing` even though `ActiveCallPolicy` does not read them:
    /// the rule treats every live call the same, and the first field capture that argues it
    /// should not has to be readable off the log rather than reproduced (#255).
    ///
    /// Shape: `calls=2[connected+outgoing,pending+onHold]`, or `calls=0[]`.
    public func snapshot() -> String {
        let calls = observer.calls
        let described = calls.map { call -> String in
            var flags = [call.hasEnded ? "ended" : (call.hasConnected ? "connected" : "pending")]
            if call.isOnHold { flags.append("onHold") }
            if call.isOutgoing { flags.append("outgoing") }
            return flags.joined(separator: "+")
        }
        return "calls=\(calls.count)[\(described.joined(separator: ","))]"
    }
}
#endif
