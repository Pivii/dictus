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

    /// How long the user spoke. Feeds the polish duration gate (#141), which is
    /// otherwise unanswerable in the extension: it never saw the audio.
    public let recordingDuration: TimeInterval

    /// `UITextDocumentProxy.documentIdentifier` of the field this dictation belongs
    /// to, as a string, or nil when the host would not name one.
    ///
    /// Nil is not a wildcard — see `mayInsert(into:)`.
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
    public static let recoveryWindow: TimeInterval = 30

    public init(raw: String,
                policy: TranscriptionLanguagePolicy,
                recordingDuration: TimeInterval,
                documentIdentifier: String?,
                claimedAt: TimeInterval = Date().timeIntervalSince1970) {
        self.raw = raw
        self.policy = policy
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
    /// **Nil fails closed on either side.** A host that names no document cannot
    /// prove the field is the same one, and "we could not tell" must not read as
    /// "yes" on the path that types into somebody's message.
    public func mayInsert(into currentIdentifier: String?) -> Bool {
        guard let documentIdentifier, let currentIdentifier else { return false }
        return documentIdentifier == currentIdentifier
    }

    /// Whether a keyboard that found this record lying around may insert the raw.
    ///
    /// Same identity rule, plus the window: a record older than that belongs to a
    /// dictation the user has stopped waiting for, and the honest outcome there is
    /// that it is lost.
    public func mayRecover(into currentIdentifier: String?,
                           now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard mayInsert(into: currentIdentifier) else { return false }
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
/// this record for its whole life.** It writes it the moment it claims the raw, and
/// it is the only thing that clears it, on exactly three outcomes: the text was
/// inserted, the insertion was refused, or the record expired. DictusApp's launch
/// sweep is a backstop for a keyboard process that died between two of those.
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
