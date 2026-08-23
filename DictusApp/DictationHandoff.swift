// DictusApp/DictationHandoff.swift
// The tail of a dictation: what happens between a finished transcription and a
// finished dictation, split by which process runs it (issue #361).
import Foundation
import UIKit
import DictusCore

/// The tail of a dictation, split by which process runs it.
///
/// WHY this is a file of its own rather than part of `DictationCoordinator`: the
/// coordinator is already the largest type in the app and adding this to it put the
/// file past SwiftLint's length limit, which is the linter making the point the
/// header of `ColdStartResolution.swift` makes in prose. Same device, same reason.
///
/// WHY six members of the coordinator are not `private`: Swift scopes `private` to
/// the file, so `defaults`, `mayReport`, `updateStatus` and the three
/// `polishHandoff*` properties have to be visible from here. Each carries a note at
/// its declaration. `updateStatus` is the one worth watching — it is the single
/// funnel every status write goes through, and it stays that.
@MainActor
extension DictationCoordinator {

    /// A dictation started inside DictusApp: polish here, exactly as every dictation
    /// did before #361, and show the result in the app.
    func finishInApp(rawText: String,
                     languagePolicy: TranscriptionLanguagePolicy,
                     smartMode: SmartMode?,
                     audioDuration: TimeInterval,
                     session: Int) async {
        // Polish layer (#141) — passes raw through when toggle off, when language
        // detection skips, when the engine throws/cancels, or when the guardrail rejects.
        //
        // The status moves to `.processing` from inside the call rather than
        // before it (#267): every one of those pass-through paths returns in
        // about a millisecond, and announcing a stage for them would flash a
        // label and a new animation for a single frame. `onEngineWillRun`
        // fires only once an engine worth waiting for is about to run.
        let outcome = await PolishCoordinator.shared.polish(
            raw: rawText,
            languagePolicy: languagePolicy,
            smartMode: smartMode,
            recordingDuration: audioDuration,
            // Gated like every other write this task makes: the callback
            // fires from inside `polish`, which a cancel does not interrupt,
            // so an abandoned dictation would otherwise reopen the keyboard
            // overlay on "Traitement..." and drive the Live Activity into a
            // stage it had already left (#267).
            onEngineWillRun: { [weak self] in
                guard let self, self.mayReport(session, "processing stage") else { return }
                self.updateStatus(.processing)
                LiveActivityManager.shared.transitionToProcessing()
            }
        )

        // An armed Smart Mode that produced nothing insertable ends the dictation as
        // a failure rather than as a quieter version of itself (#79). Inserting the
        // untransformed text would be the worst outcome available — the user asked
        // for bullets, or for English, and would get neither without being told.
        guard let text = outcome.text else {
            guard mayReport(session, "smart mode failure") else { return }
            let name = outcome.smartModeFailure?.modeDisplayName ?? "Smart Mode"
            handleError("\(name) n'a pas pu transformer ce texte. Réessayez.")
            return
        }

        let finalText = DictationTail.apply(text, policy: languagePolicy)

        // Same gate the keyboard path applies before its own write, and for the same
        // reason: everything below is irreversible from the user's point of view.
        guard mayReport(session, "transcription result") else { return }

        lastResult = finalText
        status = .ready
        defaults.set(finalText, forKey: SharedKeys.lastTranscription)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.set(DictationStatus.ready.rawValue, forKey: SharedKeys.dictationStatus)
        // Not a hand-off, and the absence of the policy blob is what says so.
        //
        // This path still posts `transcriptionReady`, as it has since long before
        // #361 — a keyboard that happens to be on screen types the app's result. But
        // the text is already finished, and a keyboard that re-polished it would put
        // an app-origin event into the `<KBD>` half of the debug ring, which is the
        // one thing the writer marker exists to keep clean. Cleared rather than
        // merely not written, because the previous dictation's blob could still be
        // lying here if no keyboard ever claimed it.
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionPolicy)
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionDuration)
        // Same reasoning one key up: cleared rather than merely not written, because
        // a previous hand-off's mode could still be lying here if no keyboard ever
        // claimed it — and a keyboard that typed this app-origin text under it would
        // transform a dictation that has already been transformed (#79).
        defaults.removeObject(forKey: SharedKeys.lastTranscriptionSmartMode)
        defaults.synchronize()

        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
        DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)
        LiveActivityManager.shared.endWithResult(preview: finalText)

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Transcription complete: \(finalText, privacy: .private)")
        }
    }

    /// A dictation the keyboard asked for: write the RAW text down and stop.
    ///
    /// **The raw transcription is durable before any generation starts.** That is the
    /// principle the whole relocation hangs on: the keyboard polishes in a process iOS
    /// may stop running at any moment, and writing the raw first — exactly as this
    /// method has always written the final text — keeps the old worst case, a
    /// dictation degrading to raw insertion, as the new worst case.
    ///
    /// The policy snapshot travels with the text. Without it the keyboard would re-read
    /// the live settings, and a language change from its own toolbar during
    /// transcription would transcribe in one language and polish in another (#226).
    /// The duration travels for a smaller reason with no workaround: the keyboard never
    /// saw the audio, and the polish duration gate is decided on it.
    func handOffToKeyboard(rawText: String,
                           languagePolicy: TranscriptionLanguagePolicy,
                           smartMode: SmartMode?,
                           audioDuration: TimeInterval,
                           session: Int) {
        // The last transcription the user sees in the app, until the keyboard reports
        // what it actually typed. Raw rather than nothing: if the keyboard never gets
        // back to us, the card should still show the dictation that happened.
        lastResult = rawText
        status = .ready
        defaults.set(rawText, forKey: SharedKeys.lastTranscription)
        if let policyData = try? JSONEncoder().encode(languagePolicy) {
            defaults.set(policyData, forKey: SharedKeys.lastTranscriptionPolicy)
        } else {
            // Unreachable — the policy encodes four strings. If it ever happened, the
            // keyboard reads the absent blob as "not a hand-off" and types the raw
            // text unpolished, which is the honest degradation: the alternative would
            // be polishing against re-read live settings, and transcribing in one
            // language while polishing in another is the bug the snapshot exists to
            // prevent.
            defaults.removeObject(forKey: SharedKeys.lastTranscriptionPolicy)
            PersistentLog.log(.dictationFailed(error: "language policy did not encode for hand-off"))
        }
        defaults.set(audioDuration, forKey: SharedKeys.lastTranscriptionDuration)
        // The armed Smart Mode travels beside the policy, or the key is cleared so
        // the keyboard reads Normal (#79). Written from the same snapshot the
        // transcription used, never re-read on the far side — the keyboard toolbar
        // is where the mode is armed, so re-reading it there is the mid-dictation
        // change #226's snapshot exists to prevent, in its sharpest form.
        if let smartMode, let modeData = try? JSONEncoder().encode(smartMode) {
            defaults.set(modeData, forKey: SharedKeys.lastTranscriptionSmartMode)
        } else {
            // Either no mode was armed, or — unreachable — the record did not
            // encode. Both degrade to Normal, which is the free polish: the honest
            // fallback, and the one the keyboard already knows how to run.
            defaults.removeObject(forKey: SharedKeys.lastTranscriptionSmartMode)
            if smartMode != nil {
                PersistentLog.log(.dictationFailed(error: "smart mode did not encode for hand-off"))
            }
        }
        let token = UUID().uuidString
        polishHandoffToken = token
        defaults.set(token, forKey: SharedKeys.handoffToken)
        defaults.set(Date().timeIntervalSince1970, forKey: SharedKeys.lastTranscriptionTimestamp)
        defaults.set(DictationStatus.ready.rawValue, forKey: SharedKeys.dictationStatus)
        // The previous dictation's polished text, if the keyboard left one behind.
        // Cleared here so `polishDidFinish` cannot be answered with a stale string.
        defaults.removeObject(forKey: SharedKeys.lastPolishedTranscription)
        defaults.synchronize()

        DarwinNotificationCenter.post(DarwinNotificationName.statusChanged)
        DarwinNotificationCenter.post(DarwinNotificationName.transcriptionReady)
        PersistentLog.log(.polishHandoff(step: "handedOff", outcome: "raw", chars: rawText.count))

        if #available(iOS 14.0, *) {
            DictusLogger.app.info("Transcription handed to keyboard: \(rawText, privacy: .private)")
        }

        beginPolishHandoff(session: session, preview: rawText)
    }

    // MARK: The Live Activity, waiting on the other process (decision 6)

    /// Start waiting for the keyboard to finish the dictation.
    ///
    /// The Live Activity is app-owned and the stage that paces it now happens over
    /// there, so `endWithResult` is deferred until `polishDidFinish` arrives rather
    /// than fired on the App Group write. That is what keeps the Dynamic Island
    /// describing the dictation instead of the hand-off.
    func beginPolishHandoff(session: Int, preview: String) {
        polishHandoffSession = session
        polishHandoffPreview = preview
        polishHandoffWatchdog?.invalidate()
        polishHandoffWatchdog = Timer.scheduledTimer(
            withTimeInterval: PolishTimeBudget.handoffCeiling(forCharacters: preview.count),
            repeats: false
        ) { [weak self] _ in
            // The session is captured, not read at execution time. `invalidate()` does
            // not unschedule a block already enqueued on the main queue, so a timer
            // cancelled a hair too late would otherwise time out whichever hand-off is
            // current when it runs — which, after round 7, withdraws that dictation.
            // Same device as the stage watchdog in `DictationCoordinator`, which
            // captures the status it was armed for.
            DispatchQueue.main.async { self?.polishHandoffTimedOut(armedFor: session) }
        }
    }

    /// Stop waiting. Idempotent.
    ///
    /// `abandonedAs` names what cut the wait short, and is nil on the two paths that
    /// conclude it properly — the keyboard reporting in, and the watchdog — because
    /// each of those writes its own line. A wait that ends without one of those lines
    /// is the case worth being able to find.
    func endPolishHandoff(abandonedAs reason: String?) {
        guard polishHandoffSession != nil else { return }
        polishHandoffWatchdog?.invalidate()
        polishHandoffWatchdog = nil
        polishHandoffSession = nil
        polishHandoffPreview = nil
        polishHandoffToken = nil
        if let reason {
            PersistentLog.log(.polishHandoff(step: "abandoned", outcome: reason, chars: 0))
        }
    }

    /// The keyboard says the dictation is over — polished or not, typed or refused.
    ///
    /// **Called at most once per dictation, and safe to call more than once.** The
    /// keyboard sends `polishDidFinish` when the tail completes, and also earlier when
    /// it knows the result can no longer be inserted anywhere: a generation still
    /// running for a document the user has left has no outcome to wait for, and the
    /// Live Activity was announcing "processing" for up to seven seconds after the
    /// keyboard had gone back to a normal keyboard (measured on `c5c226c`). The
    /// generation is still running and will still post when it returns; the guard
    /// below is what makes that second post a no-op rather than a second
    /// `endWithResult` on an Island that has moved on.
    func polishHandoffFinished() {
        guard let session = polishHandoffSession,
              mayReport(session, "polish handoff completion") else { return }
        // Which hand-off is this post about? The keyboard may legitimately post twice
        // for one dictation, and a post from a dictation that is over must not end the
        // one that replaced it — since round 7 that would also withdraw it.
        let posted = defaults.string(forKey: SharedKeys.lastPolishedHandoffToken)
        guard posted == polishHandoffToken else {
            PersistentLog.log(.polishHandoff(step: "finished", outcome: "stale-token", chars: 0))
            return
        }
        let typed = defaults.string(forKey: SharedKeys.lastPolishedTranscription)
        // Captured before `endPolishHandoff` clears it. On the early path there is no
        // typed text and there never will be, so the raw this dictation handed over is
        // the only honest preview.
        let raw = polishHandoffPreview
        endPolishHandoff(abandonedAs: nil)
        // `typed` is nil when the keyboard refused to insert (decision 7), or when it
        // has not tried yet. The dictation still ended for display purposes, so the
        // Island still comes home — on the raw, because nothing was typed to preview.
        if let typed {
            lastResult = typed
        }
        PersistentLog.log(.polishHandoff(
            step: "finished",
            outcome: typed == nil ? "not-inserted" : "inserted",
            chars: typed?.count ?? 0
        ))
        LiveActivityManager.shared.endWithResult(preview: typed ?? raw ?? lastResult)
    }

    /// The keyboard never got back to us.
    ///
    /// Decision 14 put this at a flat 10 s and said to recalibrate it once real
    /// extension-side timings existed. They do, they are longer, and the number now
    /// comes from `PolishTimeBudget` — see there for the measurements and why a fixed
    /// timeout is the wrong shape when the input length is known before the call.
    ///
    /// **Firing early is not benign, which is what decision 14 got wrong.** Its
    /// reasoning was that a false positive costs an Island returning to standby a
    /// second early, because the keyboard types its text regardless. Both halves of
    /// that are false: this also clears `dictationStatus`, which takes the keyboard's
    /// overlay down, and since this round it withdraws the dictation's right to be
    /// typed at all. On device (`fe8223c`) a 1,015-character dictation was lost
    /// exactly this way — the watchdog fired at 10 s, the overlay came down, the user
    /// left the field, and the generation returned eleven seconds later.
    func polishHandoffTimedOut(armedFor session: Int) {
        guard polishHandoffSession == session,
              mayReport(session, "polish handoff watchdog") else { return }
        let preview = polishHandoffPreview
        endPolishHandoff(abandonedAs: nil)
        PersistentLog.log(.polishHandoff(
            step: "watchdog",
            outcome: "timeout",
            chars: preview?.count ?? 0
        ))
        LiveActivityManager.shared.endWithResult(preview: preview)
        // It cleans `dictationStatus` too, not only the Island (decision 14). A
        // `ready` nobody consumed is what the next keyboard appearance would restore
        // its state from, and this process has stopped believing anything is in
        // flight.
        if status == .ready {
            updateStatus(.idle)
        }
        // And it withdraws the dictation, which is the half that was missing. Telling
        // the user it is over and then typing into their field a few seconds later is
        // a resurrection, and decision 7's principle covers it: a result nobody is
        // waiting for any more may not be inserted. Clearing the record is how that
        // reaches the keyboard — its own run sees the record gone and stops, with no
        // new IPC and no second source of truth.
        //
        // This is the second app-side writer of a record the keyboard otherwise owns;
        // the other is the launch sweep. Both are the app concluding something the
        // keyboard did not.
        if let pending = PendingDictationChannel.current {
            PendingDictationChannel.clear()
            PersistentLog.log(.polishHandoff(
                step: "watchdog", outcome: "withdrawn", chars: pending.raw.count
            ))
        }
    }
}
