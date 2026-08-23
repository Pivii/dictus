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
        let text = await PolishCoordinator.shared.polish(
            raw: rawText,
            languagePolicy: languagePolicy,
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
            withTimeInterval: Self.polishHandoffTimeout,
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.polishHandoffTimedOut() }
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
        if let reason {
            PersistentLog.log(.polishHandoff(step: "abandoned", outcome: reason, chars: 0))
        }
    }

    /// The keyboard says the dictation is over — polished or not, typed or refused.
    func polishHandoffFinished() {
        guard let session = polishHandoffSession,
              mayReport(session, "polish handoff completion") else { return }
        let typed = defaults.string(forKey: SharedKeys.lastPolishedTranscription)
        endPolishHandoff(abandonedAs: nil)
        // `typed` is nil when the keyboard refused to insert (decision 7). The
        // dictation still ended, so the Island still comes home — it just comes home
        // on the raw preview, because nothing was typed to preview.
        if let typed {
            lastResult = typed
        }
        PersistentLog.log(.polishHandoff(
            step: "finished",
            outcome: typed == nil ? "not-inserted" : "inserted",
            chars: typed?.count ?? 0
        ))
        LiveActivityManager.shared.endWithResult(preview: typed ?? lastResult)
    }

    /// The keyboard never got back to us.
    ///
    /// WHY 10 seconds (decision 14): a watchdog has to exceed the legitimate duration
    /// of the thing it watches, and the field p90 of a polish generation is 4,842 ms
    /// with a maximum of 12,528 ms over 196 successes (#315). The twenty-call
    /// extension burst measured on 2026-08-23 ran 4,292 to 5,067 ms, flat, which is
    /// what settled the number rather than an arbitration.
    ///
    /// The house style is more aggressive than this — the recording watchdog is at
    /// 2 s — and the asymmetry is what allows it: the keyboard owns insertion now, so
    /// it types its text whether or not this fires. A false positive costs a Dynamic
    /// Island that returned to standby a second early. Compare #60, where a stuck
    /// Island was visible and costly. Without it, the measurement on #357 Q4 says the
    /// wait would be forty-four minutes.
    func polishHandoffTimedOut() {
        guard let session = polishHandoffSession,
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
    }

    /// How long the app waits for `polishDidFinish` before bringing the Live Activity
    /// home by itself. Provisional by construction — see `polishHandoffTimedOut`.
    static var polishHandoffTimeout: TimeInterval { 10 }
}
