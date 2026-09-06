// DictusKeyboard/KeyboardCallGuard.swift
// The keyboard's own answer to "is a call holding the microphone" (#483).
import Foundation
import DictusCore

/// Why the keyboard asks this at all, rather than letting DictusApp find out.
///
/// Before #483 the mic tap always handed off, and the call was only detected once the app
/// had cold-started. Measured on device 2026-09-03, `rev b290af2`, iPhone16,2, iOS 26.6.1,
/// during a real call held on the iPhone's earpiece:
///
/// ```
/// 08:24:23  <KBD> extensionURLFallback
/// 08:24:23  <APP> coldStartURLReceived isColdStart=true
/// 08:24:24  <APP> dictationFailed …
/// ```
///
/// The user was thrown out of the app they were typing in, watched Dictus launch, and had
/// to swipe back to be told a call was holding the microphone — by which time the message
/// had been counting down its three seconds from a screen it was not visible on (#482).
/// `CXCallObserver` is readable from an app extension, which is what makes declining in
/// place possible at all.
///
/// This lives beside `KeyboardState` rather than inside it because that file is already at
/// SwiftLint's `file_length` and `type_body_length` ceilings.
extension KeyboardState {

    /// Build the process's call observer, and write down what it cost.
    ///
    /// The `footprintKB` bracket is the answer to the question #483 made a precondition:
    /// the extension has ~50 MB, and "CallKit is small" is a claim that needed a number.
    /// It is kept rather than removed after the probe because the number that matters is
    /// the one from a device, and this is what will carry it (#255 — the log's reader is
    /// an agent).
    ///
    /// - Parameter instanceID: the owner's id, so the two lines sit with the rest of its
    ///   trail. Passed in because this runs before `KeyboardState` is fully initialised.
    static func makeCallObserver(instanceID: String) -> SystemCallObserver {
        let footprintBeforeKB = MemoryFootprint.residentKB()
        let observer = SystemCallObserver()
        let footprintAfterKB = MemoryFootprint.residentKB()

        // `residentKB()` returns -1 when the Mach task info read fails, and subtracting
        // that would print a number like `-50001` or, worse, a plausible `0` — a reading
        // that is not a measurement, in the one line the device test list asks a human to
        // read. This repo has already spent a false alarm on a log that said something it
        // did not mean (#455), so the failure is named rather than arithmetically hidden.
        let deltaKB: String
        if footprintBeforeKB >= 0 && footprintAfterKB >= 0 {
            deltaKB = "\(footprintAfterKB - footprintBeforeKB)"
        } else {
            deltaKB = "unavailable"
        }

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardState",
            instanceID: instanceID,
            action: "callObserverReady",
            details: "\(observer.snapshot())"
                + " footprintKB=\(footprintBeforeKB)->\(footprintAfterKB)"
                + " deltaKB=\(deltaKB)"
        ))
        return observer
    }

    /// Decline the mic tap when a call holds the microphone, and say so in place.
    ///
    /// The sentence is #313's — the one DictusApp would have shown after the handoff. It is
    /// spelled out again here rather than shared because the app and the keyboard have
    /// separate string catalogs; `DictationErrorCopyTests` pins the two copies to the same
    /// key and the same French translation, so this cannot drift into a second message.
    ///
    /// - Returns: `true` when the tap was refused and the caller must stop.
    func refuseMicTapIfACallHoldsTheMicrophone() -> Bool {
        guard case .callHoldsMicrophone(let evidence) = callObserver.decide() else {
            return false
        }

        logProbe(
            "micTapRejectedDuringCall",
            details: "evidence=\(evidence.rawValue) \(callObserver.snapshot()) \(sessionDetails())"
        )
        HapticFeedback.actionRefused()
        presentStatusMessage(
            String(localized: "The microphone is busy on a call. Try again once the call ends."),
            reason: "call-holds-microphone",
            timeoutReason: "call-holds-microphone-timeout"
        )
        return true
    }
}
