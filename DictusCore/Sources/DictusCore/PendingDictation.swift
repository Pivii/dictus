// DictusCore/Sources/DictusCore/PendingDictation.swift
// The raw transcription, durable in the App Group while the keyboard polishes it (#361).
import Foundation

/// A transcription the keyboard has claimed and not yet typed.
///
/// ### The principle this exists for
///
/// **The raw transcription must be durable before any generation starts.** Polish
/// runs in the keyboard extension since #361, and the extension is a process iOS
/// may stop running at any moment. Writing the raw down first, and treating polish
/// as an enrichment applied on top, keeps the old worst case — the dictation
/// degrades to raw insertion — as the new worst case, rather than opening a new
/// class of loss.
///
/// ### And the failure it turned out to guard against
///
/// The measurement on 2026-08-23 (#361, #357 Q4) found the extension is not torn
/// down mid-generation. It is *suspended*, and that is worse: a generation dismissed
/// off-screen resumed and completed forty-four minutes later, and under a design
/// where the keyboard owns insertion it would have typed into whatever document held
/// focus at that moment. So `documentIdentifier` is not a nicety that saves a
/// dictation during iOS's routine controller churn — it is the primary guard against
/// a resurrected write. The question it answers is not "can this raw be recovered"
/// but "may this generation still be inserted".
///
/// Both readings need the same two facts, which is why they are on the same record.
public struct PendingDictation: Codable, Equatable, Sendable {

    /// The raw STT output, exactly as DictusApp wrote it. Not the polished text and
    /// not the deterministic floor: this is the value that must survive.
    public let raw: String

    /// The per-dictation language policy snapshot (#226), travelling with the text.
    ///
    /// WHY it travels instead of being re-read: without it each stage re-reads App
    /// Group state, and a language change from the keyboard toolbar during
    /// transcription would transcribe in one language and polish in another. The
    /// process boundary makes this sharper rather than softer — the keyboard is the
    /// process whose toolbar can change the language.
    public let policy: TranscriptionLanguagePolicy

    /// The Smart Mode armed when this dictation started, or nil for Normal (#79).
    ///
    /// Travels for the same reason `policy` does, and the reason is sharper here.
    /// The mode is armed by long-pressing the mic on the keyboard, so the process
    /// that would re-read it is the process whose UI changes it — and a mode changed
    /// between "stop speaking" and "the generation runs" would transform a dictation
    /// the user started under a different instruction. The whole record travels
    /// rather than its identifier so a custom mode (#269) needs no lookup table on
    /// the far side.
    ///
    /// Optional, and decoded as absent on records written before it existed: a
    /// keyboard that upgrades mid-dictation finds a record with no mode and runs the
    /// free polish, which is what that dictation was started under anyway.
    public let smartMode: SmartMode?

    /// The mode that was armed and **did not** run, when the dictation was resolved
    /// down to Normal (#423), or nil when nothing was skipped.
    ///
    /// The mirror of `smartMode` above and mutually exclusive with it: a mode that
    /// ran was not skipped. It travels on this record rather than in a field of the
    /// coordinator because the sentence is shown *after* the insertion — a message
    /// raised before it is wiped by `KeyboardState.insertDictation` on its way to
    /// idle — and by then a newer dictation may already own the slot. This record is
    /// the thing that is superseded correctly.
    ///
    /// Optional and decoded as absent on records written before it existed, like
    /// `smartMode`: the worst case is a lost transient notice.
    public let skippedSmartMode: SmartModeSkipNotice?

    /// How long the user spoke. Feeds the polish duration gate (#141), which is
    /// otherwise unanswerable in the extension: it never saw the audio.
    public let recordingDuration: TimeInterval

    /// `UITextDocumentProxy.documentIdentifier` of the field this dictation belongs
    /// to, as a string, or nil when the host would not name one.
    ///
    /// Nil is not a wildcard — see `mayInsert(into:)`.
    ///
    /// ### Measured scope, 2026-08-23 on `c5c226c`
    ///
    /// **It identifies an input session, not a document.** It is stable across the
    /// in-place controller churn decision 7 was written around — the ~9 rebuilds per
    /// dictation (#281) — which is why ordinary dictations insert normally. But
    /// dismissing the keyboard and re-presenting it mints a new one, *even in the same
    /// field of the same app*: three runs in that capture returned
    /// `different-document` (a non-nil identifier that did not match) at 4,860,
    /// 8,356 and 7,406 ms, after the maintainer left Notes and came straight back to
    /// the same note.
    ///
    /// So half of decision 7's stated reasoning is falsified. It does not separate
    /// "the user left the field" from "iOS rebuilt the controller while the user did
    /// not move" — it separates them only *within* one input session, and reads
    /// "left" across any dismissal whether or not the user came back.
    ///
    /// The half that matters survives intact: it is a sound guard against typing a
    /// resurrected generation into a document the user did not choose, which is the
    /// forty-three-minute case #357 Q4 measured. The maintainer tested the resulting
    /// behaviour deliberately and accepted it — the raw is on DictusApp's result card
    /// either way, and a user who leaves mid-polish can reasonably expect no text.
    ///
    /// **Do not replace this with something looser.** Anything that matched more
    /// readily would reintroduce exactly the risk the check exists to prevent.
    public let documentIdentifier: String?

    /// When the keyboard claimed the raw, seconds since 1970.
    public let claimedAt: TimeInterval

    /// How long after `claimedAt` a *recovery* may still insert the raw.
    ///
    /// This bounds only the degraded path — a keyboard that comes back to find a
    /// record nobody is polishing. It does not bound the generation itself:
    /// decision 15 rejected inventing a second temporal threshold, and the identity
    /// check is what decides whether a late generation may be typed.
    ///
    /// WHY 30 s: the window has to exceed the legitimate length of the thing it
    /// covers, and the field p90 of a polish generation is 4,842 ms with a maximum
    /// of 12,528 ms over 196 successes (#315 export). 30 s clears that with margin
    /// while staying far under the five-minute App Group sweep that is the outer
    /// bound. A judgement call, not a measurement.
    ///
    /// **And it has never been reached.** `mayRecover` needs the identity check to
    /// pass first, and the scope finding recorded on `documentIdentifier` above means
    /// it cannot: a process that died before its generation resolved was necessarily
    /// dismissed and re-presented, which mints a new identifier. `step=recovered`
    /// appears in none of the four device sessions on this branch. The number is kept
    /// as it is rather than tuned, because tuning it would imply it decides something.
    public static let recoveryWindow: TimeInterval = 30

    public init(raw: String,
                policy: TranscriptionLanguagePolicy,
                smartMode: SmartMode? = nil,
                skippedSmartMode: SmartModeSkipNotice? = nil,
                recordingDuration: TimeInterval,
                documentIdentifier: String?,
                claimedAt: TimeInterval = Date().timeIntervalSince1970) {
        self.raw = raw
        self.policy = policy
        self.smartMode = smartMode
        self.skippedSmartMode = skippedSmartMode
        self.recordingDuration = recordingDuration
        self.documentIdentifier = documentIdentifier
        self.claimedAt = claimedAt
    }

    // MARK: - The two questions

    /// Whether a finished generation may be typed into the field currently in front
    /// of the user.
    ///
    /// Two deaths look identical in a log and are nothing alike for the user. If the
    /// user switched app or dismissed the keyboard, they left the field, and
    /// inserting later would be typing into a document they did not choose — which
    /// this product refuses everywhere else. But iOS recreates
    /// `KeyboardViewController` constantly while the user does not move, on the
    /// order of nine instances per dictation (#281), and there the field is still
    /// present and the user is still waiting.
    ///
    /// The identifier separates those two **only within one input session**, which
    /// covers the churn above and nothing beyond it. A user who dismisses the keyboard
    /// and comes back to the very same field reads as "left", and their dictation is
    /// refused. That is measured, accepted, and recorded on `documentIdentifier`.
    ///
    /// **Nil fails closed on either side.** A host that names no document cannot
    /// prove the field is the same one, and "we could not tell" must not read as
    /// "yes" on the path that types into somebody's message.
    ///
    /// This is identity alone, deliberately. It is what the *stage* rule asks — see
    /// `KeyboardHandoffStage` — and the stage is decided from `viewWillAppear`, before
    /// the view is reliably in a window. Folding window attachment in here would drop
    /// the overlay on every ordinary controller rebuild. The insertion gate below adds
    /// it; the stage does not.
    public func addressesSameDocument(as currentIdentifier: String?) -> Bool {
        guard let documentIdentifier, let currentIdentifier else { return false }
        return documentIdentifier == currentIdentifier
    }

    /// Whether a finished generation may actually be typed **now**.
    ///
    /// Identity is necessary and was assumed sufficient until 2026-08-23 on
    /// `fe8223c`, where a 1,015-character dictation was typed into a keyboard that
    /// had already gone:
    ///
    /// ```text
    /// 19:02:39  keyboardDidDisappear
    /// 19:02:41  keyboardTextInserted                       <-- no refusal logged
    /// 19:02:44  dictationUndoInvalidated reason=revalidate-truncated-mismatch
    /// ```
    ///
    /// `viewDidDisappear` fired at :39 and `deinit` only at :43, and in between the
    /// proxy went on answering with the same `documentIdentifier` while no longer
    /// being able to receive text. The undo revalidation two seconds later looked for
    /// the inserted string in the document and did not find it — the insertion went
    /// nowhere.
    ///
    /// So the identifier says *which* field, and nothing about whether this keyboard
    /// is still in front of it. `keyboardIsAttached` is the second half, and it has to
    /// come from UIKit window attachment rather than from bookkeeping — the same
    /// ground truth #260 settled on, and for the same reason: the bookkeeping is what
    /// is wrong in exactly these cases.
    public func mayInsert(into currentIdentifier: String?, keyboardIsAttached: Bool) -> Bool {
        guard keyboardIsAttached else { return false }
        return addressesSameDocument(as: currentIdentifier)
    }

    /// Whether a keyboard that found this record lying around may insert the raw.
    ///
    /// Same identity rule, plus the window: a record older than that belongs to a
    /// dictation the user has stopped waiting for, and the honest outcome there is
    /// that it is lost.
    ///
    /// Measured as unreachable — see `recoveryWindow` and `documentIdentifier`. Kept
    /// because the case it covers is one no capture has produced rather than one that
    /// is impossible, and because the alternative is a raw with no path back at all.
    public func mayRecover(into currentIdentifier: String?,
                           keyboardIsAttached: Bool,
                           now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard mayInsert(into: currentIdentifier, keyboardIsAttached: keyboardIsAttached) else {
            return false
        }
        return now - claimedAt <= Self.recoveryWindow
    }

    /// Whether the record is old enough that nothing will ever act on it again, so
    /// whoever notices should drop it.
    public func isExpired(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        now - claimedAt > Self.recoveryWindow
    }
}

/// Read and write the pending record in the App Group.
///
/// WHY a named contract rather than three `UserDefaults` calls, the same argument
/// `DictationErrorChannel` and `PolishAvailabilityChannel` make: the rule is not in
/// the key, it is in who clears it and when. Stated once here — **the keyboard owns
/// this record for its whole life.** It writes it the moment it claims the raw, and it
/// normally clears it, on exactly three outcomes: the text was inserted, the insertion
/// was refused, or the record expired.
///
/// DictusApp clears it in two places, and both are the app concluding something the
/// keyboard did not: the launch sweep, for a keyboard process that died mid-dictation,
/// and the hand-off watchdog, which has just told the user the dictation is over and
/// must therefore also withdraw its right to be typed.
public enum PendingDictationChannel {

    public static var current: PendingDictation? {
        guard let data = AppGroup.defaults.data(forKey: SharedKeys.pendingDictation) else { return nil }
        return try? JSONDecoder().decode(PendingDictation.self, from: data)
    }

    public static func store(_ pending: PendingDictation) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        let defaults = AppGroup.defaults
        defaults.set(data, forKey: SharedKeys.pendingDictation)
        defaults.synchronize()
    }

    public static func clear() {
        let defaults = AppGroup.defaults
        defaults.removeObject(forKey: SharedKeys.pendingDictation)
        defaults.synchronize()
    }
}
