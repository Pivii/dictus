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

    /// Unfreezes the overlay when a generation never comes back.
    private var stageWatchdog: Timer?

    /// Whether DictusApp has already been told this dictation is over for display
    /// purposes. Reset per claim; see `concludeDisplayForUnreachableDocument`.
    private var hasConcludedDisplay = false

    /// The token DictusApp minted for the hand-off being polished, echoed back on
    /// every `polishDidFinish` so the app can tell which dictation a post is about.
    /// In memory rather than on the record: it only has to outlive the generation, and
    /// if this process dies no post happens at all.
    private var handoffToken: String?

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
            smartMode: storedSmartMode(),
            skippedSmartMode: storedSkippedSmartMode(),
            recordingDuration: duration,
            documentIdentifier: KeyboardState.shared.currentDocumentIdentifier
        )
        PendingDictationChannel.store(pending)
        handoffToken = defaults.string(forKey: SharedKeys.handoffToken)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionPolicy)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionDuration)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionSmartMode)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionSmartModeSkipped)
        defaults.removeObject(forKey: SharedKeys.handoffToken)
        PersistentLog.log(.polishHandoff(step: "claimed", outcome: "pending", chars: raw.count))

        activePolish = pending
        hasConcludedDisplay = false
        // `handoffToken` was read above, from the key this hand-off wrote.
        startStageWatchdog(for: pending)
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
        stopStageWatchdog()
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
    /// back, and inserting here would type the dictation twice. That is also why the
    /// record survives a change of document: this is the path that catches a keyboard
    /// whose *process* died mid-generation, and it can only run if nothing tore the
    /// record down on the way out.
    ///
    /// ### It has never fired, and probably cannot
    ///
    /// Four device sessions on this branch, `step=recovered` zero times. Two measured
    /// facts close it off from both ends. Measurement 3 on #361 found the extension is
    /// *suspended* rather than killed, so the process it exists for usually survives
    /// and the generation resolves normally. And a process that genuinely did die was
    /// necessarily dismissed and re-presented, which mints a new
    /// `documentIdentifier` — see that property — so `mayRecover` would refuse on
    /// identity even if this ran.
    ///
    /// Kept rather than deleted because "no capture has produced it" is not "it cannot
    /// happen", and what it guards is the whole point of writing the raw down first:
    /// a dictation degrades to raw insertion, never to nothing. Do not read its
    /// presence as evidence that the raw is recoverable in practice.
    func recoverPendingIfNeeded() {
        // Two rescues in the order a dictation would have reached them, behind one
        // call because `KeyboardRootView.onAppear` is a SwiftUI closure the type
        // checker already struggles with. First a hand-off whose `transcriptionReady`
        // was dropped and which nobody has claimed; then, below, a claimed one nobody
        // finished. Both return immediately when there is nothing outstanding.
        guard !isPolishing else { return }
        KeyboardState.shared.claimUnclaimedHandoff()

        guard !isPolishing, let pending = PendingDictationChannel.current else { return }
        let current = KeyboardState.shared.currentDocumentIdentifier
        guard pending.mayRecover(
            into: current, keyboardIsAttached: KeyboardState.shared.keyboardIsAttached
        ) else {
            guard pending.isExpired() else { return }
            PendingDictationChannel.clear()
            PersistentLog.log(.polishHandoff(step: "recovered", outcome: "expired", chars: pending.raw.count))
            return
        }
        PendingDictationChannel.clear()

        // The third insertion site, and the one that used to skip the rule the other
        // two enforce (#391). A pending record carrying an armed mode is a dictation
        // whose transformation never ran: typing its raw here would insert French
        // under "→ EN", which is exactly what `PolishTask.isSmart` forbids — and this
        // is the path nobody watches, because it has never fired in any device
        // session. The other two sites are `run(_:)` above and
        // `finish(reporting:inserting:)`.
        if let mode = pending.smartMode {
            PersistentLog.log(.smartModeRefused(
                mode: mode.id, outcome: "recovered", reason: "no-generation"
            ))
            PersistentLog.log(.polishHandoff(step: "recovered", outcome: "smart-refused", chars: pending.raw.count))
            // Nothing to report and nothing to type: no generation ever ran for this
            // record, so the raw DictusApp already holds is all this dictation has
            // (#495 changed only the branch where a result exists).
            finish(reporting: nil, inserting: nil)
            announce(
                SmartModeFailure(
                    modeIdentifier: mode.id,
                    modeDisplayName: mode.displayName,
                    outcome: "recovered",
                    reason: "no-generation"
                ),
                degraded: false
            )
            return
        }

        PersistentLog.log(.polishHandoff(step: "recovered", outcome: "raw", chars: pending.raw.count))
        // Typed, so the app is told the same string the document received — the tailed
        // one, which is what `lastResult` has always carried on the inserted paths.
        let recovered = DictationTail.apply(pending.raw, policy: pending.policy)
        finish(reporting: recovered, inserting: recovered)
        // The dictation this record carries ran Normal because a mode was resolved
        // away, and it is still owed the sentence (#423). After `finish`, for the
        // same reason as in `run(_:)`.
        if let skipped = pending.skippedSmartMode {
            announceSkip(skipped)
        }
    }

    // MARK: - The run

    private func run(_ pending: PendingDictation) async {
        let outcome = await service.polish(
            raw: pending.raw,
            languagePolicy: pending.policy,
            smartMode: pending.smartMode,
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
        stopStageWatchdog()

        // Or the record went while nothing replaced it: the recovery path typed the
        // raw, or DictusApp's launch sweep found it expired. Either way the dictation
        // has already been concluded by whoever cleared it, including the Darwin post.
        guard PendingDictationChannel.current == pending else {
            PersistentLog.log(.polishInsertionRefused(reason: "record-gone", ageMs: pending.ageMs))
            KeyboardState.shared.endLocalProcessingStage()
            return
        }
        PendingDictationChannel.clear()

        let current = KeyboardState.shared.currentDocumentIdentifier
        let attached = KeyboardState.shared.keyboardIsAttached
        guard pending.mayInsert(into: current, keyboardIsAttached: attached) else {
            // Not a lost dictation so much as a refused one. The user left the field —
            // switched app, dismissed the keyboard — or the host will not name the
            // document, and typing into a document they did not choose is the thing
            // this product refuses everywhere else. `off-screen` is the third way and
            // the one that has to be told apart in a log: the field is still named the
            // same, and this keyboard is simply no longer in front of it.
            let reason: String
            if !attached {
                reason = "off-screen"
            } else {
                reason = current == nil ? "no-identifier" : "different-document"
            }
            PersistentLog.log(.polishInsertionRefused(reason: reason, ageMs: pending.ageMs))
            // The refusal is about the document, not about the text (#495). This branch
            // runs *after* the generation returned, so `outcome.text` is usually a
            // finished polish — measured at 2,769 ms and 181 characters of English on
            // the capture that filed the issue — and it used to be deleted here. The
            // document received nothing, which is correct and stays; that makes
            // DictusApp's card the dictation's only copy, and it was showing the raw.
            //
            // No `DictationTail`: the tail is a separator that keeps chained dictations
            // from sticking together in a host field. Nothing was typed, so there is
            // nothing to separate, and the card is a copy surface — a trailing `". "`
            // would be pasted into wherever the user takes the text next.
            finish(reporting: outcome.text, inserting: nil)
            return
        }

        // An armed Smart Mode that produced nothing insertable ends here with an
        // empty hand (#79). The raw is on DictusApp's result card either way, and
        // inserting it would be the worst outcome available: the user asked for
        // bullets, or for English, and would silently get neither.
        //
        // The mode may also come back with the untransformed floor *and* a failure —
        // a context overflow on a mode that declared the floor better than nothing,
        // see `SmartModeOverflowBehaviour`. Then text is inserted and the message
        // still fires: degrading in silence and refusing in silence are the same
        // defect, which is why the message is keyed on the failure and not on
        // whether anything was typed.
        let failure = outcome.smartModeFailure
        let degraded = outcome.isDegraded

        if let polished = outcome.text {
            // The insertion was not refused above, so the app hears the same string the
            // document receives, tail included.
            let tailed = DictationTail.apply(polished, policy: pending.policy)
            finish(reporting: tailed, inserting: tailed)
        } else {
            // A mode that produced nothing insertable. There is no text to report
            // either, so DictusApp stays on the raw — the honest outcome (#79).
            finish(reporting: nil, inserting: nil)
        }

        // After `finish`, never before: a successful insertion clears the toolbar's
        // message on its way to idle (`KeyboardState.insertDictation`), so a message
        // raised first would be wiped by the very insertion it is explaining.
        if let failure {
            announce(failure, degraded: degraded)
        } else if let skipped = pending.skippedSmartMode {
            // Mutually exclusive with the branch above by construction: a mode that
            // was skipped never ran, so it cannot also have failed. `else if` says
            // so rather than relying on it — two sentences in the same slot would
            // leave whichever arrived second, and the user with half the story.
            announceSkip(skipped)
        }
    }

    /// Tell the user their armed mode did not run (#79).
    ///
    /// Four sentences, because four different things happened and only one of them
    /// is "try again":
    ///
    /// - **Too long, text inserted** — the mode declared the floor acceptable. The
    ///   text is in the field; what is missing is the transformation.
    /// - **Too long, nothing inserted** — the mode could not degrade. This one has to
    ///   carry the remedy, because it is the only case where the user has lost
    ///   something and shortening the dictation genuinely fixes it.
    /// - **The dictated language is one the model does not read** (#490) — names that
    ///   language and stops there. It is the one refusal with a knowable cause and no
    ///   remedy: Apple Foundation Models classifies the user turn and refuses before
    ///   generating, so the same words in the same language will be refused again.
    ///   "Try again" would be an instruction to repeat a failure.
    /// - **Anything else** — engine throw, guardrail rejection, cancellation. The
    ///   user can do nothing specific about any of them, so the copy does not pretend
    ///   otherwise; it matches the in-app wording (`DictationHandoff`) word for word,
    ///   so the same failure reads the same on both surfaces.
    ///
    /// The language branch keys on the OUTCOME, never on the
    /// `unsupportedLanguageOrLocale` slug. #518 measured that slug arriving from
    /// plain French, which Apple does read — telling a French speaker their language
    /// is unsupported would be a lie the log would not even contradict. The outcome
    /// is set by our own reading of the transcript and means only what it says.
    ///
    /// The mode name is the catalogue's own label — "→ EN" — so it reads as the
    /// thing the user armed. It goes through `SmartMode.localizedDisplayName` since
    /// the 2026-08-27 rename, because one mode's label is now a word rather than a
    /// symbol and a word has to be said in the user's language.
    ///
    /// WHY the name is a colon-label rather than the sentence's subject: the
    /// translation modes are called "→ EN", so "→ EN could not transform this text"
    /// does not read. `DictationHandoff` flagged that as a known rough edge for this
    /// block; the colon form is the fix, and the app's copy moved to it too so the
    /// same failure reads identically on both surfaces. Renaming the modes was the
    /// alternative and was rejected — `SmartModeCatalogue` picked a language-neutral
    /// label on purpose, and the fan is where that label mostly lives.
    private func announce(_ failure: SmartModeFailure, degraded: Bool) {
        KeyboardState.shared.presentStatusMessage(
            Self.message(for: failure, degraded: degraded),
            reason: "smartModeFailed-\(failure.outcome)",
            timeoutReason: "smartModeFailed-timeout"
        )
    }

    /// The sentence for one refusal. Split out of `announce` so the copy can be read
    /// as a set of four alternatives rather than as a presentation with branches in it.
    private static func message(for failure: SmartModeFailure, degraded: Bool) -> String {
        let name = SmartMode.localizedDisplayName(
            identifier: failure.modeIdentifier, fallback: failure.modeDisplayName
        )
        if failure.outcome == PolishMetrics.Outcome.unsupportedInputLanguage.rawValue,
           let code = failure.detectedLanguage {
            let language = PolishLanguageName.display(for: code)
            return String(
                localized: "\(name): Apple Intelligence does not support the dictated language (\(language)).",
                comment: "Shown when an armed Smart Mode could not run because the language the user dictated is outside the set Apple Intelligence reads. First placeholder is the mode's name, second is the dictated language."
            )
        }
        let overflowed = failure.outcome == PolishMetrics.Outcome.exceededContextBudget.rawValue
        switch (overflowed, degraded) {
        case (true, true):
            return String(
                localized: "\(name): too long, text inserted as dictated.",
                comment: "Shown when a Smart Mode hit the context ceiling and the untransformed text was inserted instead. The placeholder is the mode's name."
            )
        case (true, false):
            return String(
                localized: "\(name): too long. Try a shorter dictation.",
                comment: "Shown when a Smart Mode hit the context ceiling and could not fall back, so nothing was inserted. The placeholder is the mode's name."
            )
        default:
            return String(
                localized: "\(name): could not be applied. Try again.",
                comment: "Shown when an armed Smart Mode fails and nothing is inserted. The placeholder is the mode's name."
            )
        }
    }

    /// Tell the user their armed mode did not run, and that the dictation went in as
    /// Normal (#423).
    ///
    /// ### Why this exists at all
    ///
    /// Because the alternative was silence. With a translation mode armed and Smart Modes
    /// switched off, the dictation ran Normal, the outcome was an ordinary success,
    /// and the only trace was a WARNING in a log the user never reads — French in,
    /// French out, nothing on screen. #79 specifies that an unavailable Smart Mode
    /// fails closed with an explicit message; this path fails *open*, so the message
    /// is the whole of what it owes.
    ///
    /// ### Why it is a notice and not an error
    ///
    /// **Nothing failed.** The user switched the feature off, or their subscription
    /// lapsed, or Apple Intelligence is off — every one of those is a state they are
    /// in, not a fault. The wording says what happened and why, and never "failed",
    /// "error" or "try again". It goes through the same slot as an error and that
    /// slot has been grey since #313, deliberately: red is the recording overlay's
    /// colour and an alarm here would be claiming the app is broken.
    ///
    /// ### Why once
    ///
    /// The state that produced it can last weeks, and a sentence on every dictation
    /// forever is how a notice becomes noise. `SmartModeStore` holds what the user
    /// was last told and forgets it the moment the state changes — arming,
    /// disarming, or a dictation the mode actually runs. The standing signal is the
    /// toolbar's inactive armed-mode label, which does not expire.
    private func announceSkip(_ notice: SmartModeSkipNotice) {
        guard !SmartModeStore.hasAnnouncedSkip(notice) else { return }
        SmartModeStore.noteSkipAnnounced(notice)
        KeyboardState.shared.presentStatusMessage(
            KeyboardSmartModeState.localizedSkipNotice(
                notice,
                // The notice carries the reason it was resolved with, so the gate is
                // asked about that reason and not about the state now (#460).
                sellsPro: SmartModeSurface.sellsPro(
                    reason: notice.reason, paywallVisible: PremiumFlags.paywallVisible
                )
            ),
            reason: "smartModeSkipped-\(notice.reason.slug)",
            timeoutReason: "smartModeSkipped-timeout"
        )
    }

    // MARK: - The backstop this move would otherwise have removed

    /// How long the keyboard draws the LLM stage before declaring it stuck.
    ///
    /// **The timer is not a new threshold.** Before #361 the polish call ran in
    /// DictusApp under `DictationCoordinator.stageWatchdogTimeout(for: .processing)`,
    /// and the keyboard's own overlay was covered by it because the app tore the
    /// session down. Moving the call here made that timer unreachable on the keyboard
    /// path, and left a stuck generation able to hold the overlay for as long as it
    /// ran — #357 Q4 measured forty-three minutes. Same job, now in the process that
    /// owns the stage.
    ///
    /// **The number is `PolishTimeBudget`**, which scales with the input, because a
    /// flat one cannot be right at both ends: a 1,015-character generation measured
    /// 21,182 ms on device and a 50-character one about a second. It is deliberately
    /// shorter than the app's watchdog over the same call, so the clean ending —
    /// this one, which posts `polishDidFinish` — is the one that normally happens.
    ///
    /// Decision 15's "no second timeout" is about queueing N+1 behind N, and is
    /// unaffected: nothing here waits for anything.
    ///
    /// **It also answers the open question the stage rule leaves.** Once the keyboard
    /// is in another document the overlay comes down, but the generation keeps running
    /// on purpose — it may still be typed if the user comes back. Something has to
    /// bound that, or a session sits in a ~50 MB process for as long as the generation
    /// takes.
    ///
    private func startStageWatchdog(for pending: PendingDictation) {
        stopStageWatchdog()
        stageWatchdog = Timer.scheduledTimer(
            withTimeInterval: PolishTimeBudget.generationCeiling(forCharacters: pending.raw.count),
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.stageTimedOut(pending) }
            }
        }
    }

    private func stopStageWatchdog() {
        stageWatchdog?.invalidate()
        stageWatchdog = nil
    }

    /// The generation has not come back. Conclude the dictation: take down the overlay
    /// if one is still up, tell DictusApp, and stop paying for a call whose result
    /// nothing may now use.
    ///
    /// The record goes with it, and that is load-bearing rather than hygiene: while it
    /// exists the stage rule reads the hand-off as outstanding and holds the overlay
    /// up, so releasing the one without the other would leave the keyboard exactly as
    /// stuck as before. On a short dictation the budget can now expire inside the
    /// thirty-second recovery window, so this can destroy a raw that was still
    /// nominally recoverable — nominally, because measurement 4 established that path
    /// cannot fire anyway, and an overlay that never comes down is the worse outcome.
    private func stageTimedOut(_ pending: PendingDictation) {
        guard activePolish == pending else { return }
        PersistentLog.log(.polishHandoff(
            step: "watchdog", outcome: "stage-stuck", chars: pending.raw.count
        ))
        service.cancelInflight()
        activePolish = nil
        stageWatchdog = nil
        PendingDictationChannel.clear()
        // The generation was cancelled a line above, so there is nothing to report and
        // nothing to type. DictusApp concludes on the raw it handed over.
        finish(reporting: nil, inserting: nil)
    }

    /// Tell DictusApp the dictation is over for display purposes, without touching the
    /// generation.
    ///
    /// Called when the keyboard drops the stage because it is in a document this
    /// dictation can no longer reach. The generation keeps running and is still judged
    /// at insertion — that separation is round 3's fix and must not be undone — but the
    /// app was left deferring `endWithResult` on a result nobody will ever see. Measured
    /// on `c5c226c`: the Dynamic Island announced "processing" for **two, six and seven
    /// seconds** after the keyboard had gone back to a normal keyboard. #352 is the
    /// issue that names an Island out of step with the dictation as the failure.
    ///
    /// **This does not weaken decision 6.** The app still defers `endWithResult` until
    /// `polishDidFinish`; what this adds is the moment the keyboard is entitled to send
    /// it — when the answer is known rather than when the call returns, which is the
    /// same principle decision 15 already applies to a superseded call.
    ///
    /// The app ends on the raw it handed over, which is the only text this dictation
    /// will ever have. It tolerates the real `polishDidFinish` arriving later: it has
    /// already forgotten the session by then, so the second post is a no-op.
    ///
    /// Once per claim. `refreshFromDefaults` runs many times per dictation and would
    /// otherwise post on each of them.
    ///
    /// The one case this gets slightly wrong is a document identifier that reads
    /// unavailable transiently and then matches again, where the generation would go on
    /// to insert after the Island had come home. The cost is a raw preview instead of a
    /// polished one, once; the device captures show identifiers readable throughout
    /// ordinary dictations, and decision 14's watchdog would have produced the same
    /// outcome ten seconds later anyway.
    func concludeDisplayForUnreachableDocument() {
        guard let pending = activePolish, !hasConcludedDisplay else { return }
        hasConcludedDisplay = true
        PersistentLog.log(.polishHandoff(
            step: "displayConcluded",
            outcome: "unreachable-document",
            chars: pending.raw.count
        ))
        postDidFinish()
    }

    /// Tell DictusApp the tail is over, naming which hand-off it was.
    ///
    /// The token is written before the post, never after: a bare Darwin notification
    /// says only "some polish finished", and the app decides on what it reads next.
    private func postDidFinish() {
        defaults.set(handoffToken, forKey: SharedKeys.lastPolishedHandoffToken)
        defaults.synchronize()
        DarwinNotificationCenter.post(DarwinNotificationName.polishDidFinish)
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
    ///
    /// **Two decisions, two parameters (#495).** What DictusApp is told and what the
    /// document receives used to travel on one `insert` flag, and that flag deleted the
    /// text on its way past: a generation the user's document was refused was also a
    /// generation the app never heard about, so the home card fell back to the raw and
    /// the dictation's only surviving copy was the version the user had not asked for.
    /// They are the same string on every path that types — the tailed text goes to both
    /// — and they differ only where the insertion is refused with a result in hand.
    ///
    /// - Parameters:
    ///   - reported: what this dictation produced, for DictusApp to show and store.
    ///     Nil when the generation produced nothing, which leaves the app on the raw it
    ///     already holds.
    ///   - inserted: what to type into the host document, or nil to type nothing.
    private func finish(reporting reported: String?, inserting inserted: String?) {
        // Before `postDidFinish`, never after, for the reason `postDidFinish` gives
        // about the token: a bare Darwin notification says only "some polish finished",
        // and the app decides on what it reads next.
        if let reported {
            PolishedTextChannel.record(inserted == nil ? .refused(reported) : .inserted(reported))
        } else {
            PolishedTextChannel.record(.nothing)
        }
        postDidFinish()

        guard let inserted else {
            KeyboardState.shared.endLocalProcessingStage()
            return
        }
        KeyboardState.shared.insertDictation(inserted)
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

    /// The Smart Mode DictusApp wrote beside the raw text, or nil for Normal (#79).
    ///
    /// Unlike `storedPolicy()` there is no fallback to a fresh read, and that is the
    /// point: an absent key legitimately means no mode was armed, and the only other
    /// thing it could mean — the record failed to encode — must degrade to the free
    /// polish rather than to a mode this keyboard resolved for itself. Reading the
    /// armed mode here is exactly the mid-dictation change the snapshot exists to
    /// prevent, because this process's toolbar is where the mode is armed.
    private func storedSmartMode() -> SmartMode? {
        guard let data = defaults.data(forKey: SharedKeys.lastTranscriptionSmartMode) else {
            return nil
        }
        guard let mode = try? JSONDecoder().decode(SmartMode.self, from: data) else {
            PersistentLog.log(.polishHandoff(step: "claimed", outcome: "mode-undecodable", chars: 0))
            return nil
        }
        return mode
    }

    /// The mode DictusApp resolved away for this dictation, or nil when none was
    /// (#423).
    ///
    /// Absent is the ordinary case and means nothing to say. A blob that will not
    /// decode is silently ignored rather than logged loudly: unlike its neighbour it
    /// cannot cost a dictation anything — the worst outcome is a transient sentence
    /// the user does not get, and the skip is in the persistent log either way.
    private func storedSkippedSmartMode() -> SmartModeSkipNotice? {
        guard let data = defaults.data(forKey: SharedKeys.lastTranscriptionSmartModeSkipped) else {
            return nil
        }
        return try? JSONDecoder().decode(SmartModeSkipNotice.self, from: data)
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
