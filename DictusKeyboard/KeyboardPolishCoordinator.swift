// DictusKeyboard/KeyboardPolishCoordinator.swift
import Foundation
import UIKit
import DictusCore

/// The tail of a keyboard dictation, in the process that runs it (#361).
///
/// DictusApp transcribes and writes the raw text; from `transcriptionReady` onwards
/// everything happens here: polish, the trailing separator, and the insertion.
///
/// ### Why the call moved
///
/// Apple refuses `LanguageModelSession` generations to backgrounded processes, and
/// DictusApp is backgrounded for every keyboard dictation by design — measured at
/// ~10% failure over a spread-out day and 45% during a dense working session,
/// latching for twelve minutes at a time (#315). The keyboard extension is in the
/// foreground at exactly the moment polish runs: the user has stopped speaking and
/// is waiting for text. Twenty consecutive generations from here, fired while the
/// app was visibly being refused, all succeeded with no degradation (#361,
/// 2026-08-23). Moving the call does not work around the limit; it stops meeting it.
///
/// ### The two rules this type exists to hold
///
/// **The raw is durable before any generation starts.** `PendingDictation` is written
/// the moment the raw is claimed, so the worst case stays what it already was — the
/// dictation degrades to raw insertion — rather than becoming a new class of loss.
///
/// **A generation may only be typed into the field it came from.** The extension is
/// not torn down mid-generation, it is suspended, and one measured generation resumed
/// forty-four minutes later. `documentIdentifier` is what stops that landing in
/// somebody else's document.
@MainActor
final class KeyboardPolishCoordinator {

    static let shared = KeyboardPolishCoordinator()

    private let service: PolishService
    private let defaults = AppGroup.defaults

    /// The dictation this process is polishing, if any.
    ///
    /// Identity rather than a bool, because a generation can outlive the dictation
    /// that started it: #357 Q4 measured one resuming forty-four minutes later. When
    /// that one comes back it has to be able to tell that the slot is no longer its
    /// own — a bool would let it clear a newer dictation's claim on the way out, and
    /// take that dictation's overlay and Live Activity down with it.
    private var activePolish: PendingDictation?

    /// Whether a generation is on its way back. Read by the recovery path, which must
    /// not insert a raw whose polish is still coming — that would type it twice.
    var isPolishing: Bool { activePolish != nil }

    private init() {
        self.service = PolishService(sink: AppendOnlyPolishEventSink()) {
            // The #315 notice describes this process's gate since #361. Written to the
            // App Group as well as published in memory, so a controller rebuilt while
            // the state holds still finds it.
            PolishAvailabilityChannel.markUnavailable()
            KeyboardState.shared.refreshPolishAvailability()
        }
    }

    // MARK: - Entry point

    /// Take ownership of the raw transcription DictusApp just wrote, polish it, and
    /// type it.
    ///
    /// `raw` has already been removed from the App Group by the caller — that removal
    /// is what stops a redelivered Darwin notification from running this twice — so
    /// this method's first act is to write it back down under its own key, where it
    /// stays until the dictation is either typed or refused.
    func handle(raw: String) {
        let policy = storedPolicy()
        let duration = defaults.double(forKey: SharedKeys.lastTranscriptionDuration)
        let pending = PendingDictation(
            raw: raw,
            policy: policy,
            recordingDuration: duration,
            documentIdentifier: currentDocumentIdentifier()
        )
        PendingDictationChannel.store(pending)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionPolicy)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionDuration)
        PersistentLog.log(.polishHandoff(step: "claimed", outcome: "pending", chars: raw.count))

        activePolish = pending
        Task { await run(pending) }
    }

    /// Give up on the previous dictation because a new one is starting
    /// (decision 15: N+1 cancels N and takes its place).
    ///
    /// Everything belonging to N goes at once — the engine call, the claim, the
    /// pending record and the stage — because the alternative is worse than losing
    /// it. A cancelled call resolves to the deterministic floor and would happily
    /// type it, but by then N+1 is recording: the insertion would drive this
    /// keyboard back to `.idle` under a live recording overlay, and leave an undo
    /// offer pointing at text from a dictation that is over.
    ///
    /// This is what the app already did before the move, arrived at from the other
    /// side: its session-generation gate dropped the previous result rather than
    /// writing it.
    ///
    /// The stage is released here rather than when the cancelled call resumes,
    /// because Apple FM does not promise to return promptly — #357 Q4 measured a
    /// generation coming back forty-four minutes later — and a stage still held then
    /// would freeze this keyboard's overlay for the whole of the next dictation.
    func cancelForNewDictation() {
        service.cancelInflight()
        guard let abandoned = activePolish else { return }
        activePolish = nil
        PendingDictationChannel.clear()
        KeyboardState.shared.endLocalProcessingStage()
        PersistentLog.log(.polishHandoff(
            step: "abandoned",
            outcome: "new-dictation",
            chars: abandoned.raw.count
        ))
    }

    /// Insert a raw a previous keyboard never got to type (#361 decision 7).
    ///
    /// Called when a keyboard appears and finds a pending record nobody is working
    /// on. Same identity rule as the insertion path, plus the recovery window: past
    /// it, the user has stopped waiting and the honest outcome is that the dictation
    /// is lost.
    ///
    /// Does nothing while this process is polishing — the generation is still coming
    /// back, and inserting here would type the dictation twice.
    func recoverPendingIfNeeded() {
        guard !isPolishing, let pending = PendingDictationChannel.current else { return }
        let current = currentDocumentIdentifier()
        guard pending.mayRecover(into: current) else {
            guard pending.isExpired() else { return }
            PendingDictationChannel.clear()
            PersistentLog.log(.polishHandoff(step: "recovered", outcome: "expired", chars: pending.raw.count))
            return
        }
        PendingDictationChannel.clear()
        PersistentLog.log(.polishHandoff(step: "recovered", outcome: "raw", chars: pending.raw.count))
        finish(text: DictationTail.apply(pending.raw, policy: pending.policy), insert: true)
    }

    // MARK: - The run

    private func run(_ pending: PendingDictation) async {
        let polished = await service.polish(
            raw: pending.raw,
            languagePolicy: pending.policy,
            recordingDuration: pending.recordingDuration,
            onEngineWillRun: { [weak self] in
                self?.announceProcessingStage()
            }
        )

        // A newer dictation claimed the slot while this generation was in flight
        // (decision 15). It owns the pending record, the stage and the app's
        // Live Activity now, so this one leaves without touching any of them —
        // posting `polishDidFinish` here would end the newer dictation early.
        guard activePolish == pending else {
            PersistentLog.log(.polishInsertionRefused(reason: "superseded", ageMs: pending.ageMs))
            return
        }
        activePolish = nil

        // Or the record went while nothing replaced it: the recovery path typed the
        // raw, or DictusApp's launch sweep found it expired. Either way the dictation
        // has already been concluded by whoever cleared it, including the Darwin post.
        guard PendingDictationChannel.current == pending else {
            PersistentLog.log(.polishInsertionRefused(reason: "record-gone", ageMs: pending.ageMs))
            KeyboardState.shared.endLocalProcessingStage()
            return
        }
        PendingDictationChannel.clear()

        let current = currentDocumentIdentifier()
        guard pending.mayInsert(into: current) else {
            // Not a lost dictation so much as a refused one. The user left the field —
            // switched app, dismissed the keyboard — or the host will not name the
            // document, and typing into a document they did not choose is the thing
            // this product refuses everywhere else.
            PersistentLog.log(.polishInsertionRefused(
                reason: current == nil ? "no-identifier" : "different-document",
                ageMs: pending.ageMs
            ))
            finish(text: nil, insert: false)
            return
        }

        finish(text: DictationTail.apply(polished, policy: pending.policy), insert: true)
    }

    /// Move the keyboard's own overlay to the LLM stage, and tell DictusApp to move
    /// the Live Activity with it (#361 decision 6).
    ///
    /// The stage is set locally rather than requested over the App Group: this process
    /// draws the overlay, so there is nobody to ask. That is faster than before the
    /// move, not slower. The Darwin post carries only the Live Activity, which is
    /// app-owned and cannot be reached from here.
    private func announceProcessingStage() {
        KeyboardState.shared.beginLocalProcessingStage()
        DarwinNotificationCenter.post(DarwinNotificationName.polishWillRun)
    }

    /// End the dictation: hand the final text back to DictusApp, tell it we are done,
    /// and type — in that order, so the app's Live Activity preview is the text the
    /// user is about to see rather than the raw it handed over.
    private func finish(text: String?, insert: Bool) {
        if let text, insert {
            defaults.set(text, forKey: SharedKeys.lastPolishedTranscription)
        } else {
            defaults.removeObject(forKey: SharedKeys.lastPolishedTranscription)
        }
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.polishDidFinish)

        guard let text, insert else {
            KeyboardState.shared.endLocalProcessingStage()
            return
        }
        KeyboardState.shared.insertDictation(text)
    }

    // MARK: - Reading what travelled

    /// The policy snapshot DictusApp wrote beside the raw text.
    ///
    /// Falls back to a fresh snapshot only when the app wrote none, which it does not
    /// do. The fallback exists because the alternative — refusing to polish — would
    /// lose the dictation over a missing side-channel, and a snapshot taken here is
    /// exactly the behaviour that predates #226. The log line is what makes the
    /// difference visible if it ever happens, because a silent fallback here is the
    /// transcribe-in-one-language-polish-in-another bug returning by the back door.
    private func storedPolicy() -> TranscriptionLanguagePolicy {
        guard let data = defaults.data(forKey: SharedKeys.lastTranscriptionPolicy),
              let policy = try? JSONDecoder().decode(TranscriptionLanguagePolicy.self, from: data) else {
            PersistentLog.log(.polishHandoff(step: "claimed", outcome: "policy-missing", chars: 0))
            return TranscriptionLanguagePolicy.snapshot()
        }
        return policy
    }

    /// The document the keyboard is editing right now, as a string, or nil.
    ///
    /// Goes through the ObjC shim: `documentIdentifier` imports into Swift as a
    /// non-optional `UUID` while the host is free to return nil, and reading it
    /// directly traps before the input session exists. See `TextProxyIdentity.m`.
    private func currentDocumentIdentifier() -> String? {
        guard let proxy = KeyboardState.shared.controller?.textDocumentProxy else { return nil }
        return DictusTextProxyIdentity.documentIdentifier(of: proxy)?.uuidString
    }
}

private extension PendingDictation {
    /// How long ago this dictation was claimed, in milliseconds. The number that says
    /// whether a refused insertion was routine controller churn or the forty-four
    /// minute resurrection #357 Q4 measured.
    var ageMs: Int {
        Int((Date().timeIntervalSince1970 - claimedAt) * 1000)
    }
}
