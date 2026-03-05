---
status: investigating
trigger: "Cross-process transcription stub text is not received by the keyboard after dictation completes in DictusApp"
created: 2026-03-05T00:00:00Z
updated: 2026-03-05T00:00:00Z
---

## Current Focus

hypothesis: Multiple root causes identified — see Resolution
test: Code trace complete
expecting: N/A — research-only mode
next_action: Report findings

## Symptoms

expected: After dictation completes in DictusApp (stub reaches "ready" state), switching back to the keyboard should show the stub transcription text inserted into the text field.
actual: Status bar shows "transcription ready" with spinner but text not inserted into text field.
errors: None reported (no crash)
reproduction: Trigger dictation from keyboard, let stub complete in DictusApp, switch back to keyboard
started: Phase 1 implementation

## Eliminated

(none — all hypotheses confirmed or partially confirmed)

## Evidence

- timestamp: 2026-03-05T00:01:00Z
  checked: DictationCoordinator.startDictation() write sequence
  found: writeTranscription() is called BEFORE updateStatus(.ready). This means the transcriptionReady Darwin notification fires before the statusChanged(.ready) notification.
  implication: The keyboard receives transcriptionReady first, reads lastTranscription (good), but the status may still be .transcribing at that point.

- timestamp: 2026-03-05T00:02:00Z
  checked: KeyboardState.handleTranscriptionReady()
  found: This method DOES read lastTranscription from UserDefaults and sets self.lastTranscription. The data flow works correctly — lastTranscription gets populated.
  implication: The transcription text IS being read from UserDefaults into KeyboardState.lastTranscription.

- timestamp: 2026-03-05T00:03:00Z
  checked: KeyboardRootView TranscriptionStub display condition
  found: TranscriptionStub is shown ONLY when BOTH conditions are true: (1) state.lastTranscription != nil AND (2) state.dictationStatus == .ready. This is the critical gate.
  implication: Even if lastTranscription is populated, the stub won't show unless dictationStatus is exactly .ready.

- timestamp: 2026-03-05T00:04:00Z
  checked: Race condition in DictationCoordinator between writeTranscription and updateStatus
  found: writeTranscription() posts transcriptionReady notification. Then updateStatus(.ready) posts statusChanged notification. These are TWO separate Darwin notifications. KeyboardState handles them in two separate callbacks.
  implication: When handleTranscriptionReady fires, it calls refreshFromDefaults() which reads status — but at this point status may already be .ready because writeTranscription runs synchronously before updateStatus on the same MainActor. However, UserDefaults cross-process sync is NOT instantaneous.

- timestamp: 2026-03-05T00:05:00Z
  checked: KeyboardState.handleTranscriptionReady() status handling
  found: handleTranscriptionReady() calls refreshFromDefaults() first, which reads dictationStatus. If .ready has been written by then, dictationStatus will be .ready. But the refreshFromDefaults triggered by handleTranscriptionReady may read status as .transcribing (not yet .ready) because the statusChanged notification hasn't fired yet.
  implication: TIMING BUG — when transcriptionReady fires, the status written to UserDefaults may still be .transcribing because updateStatus(.ready) hasn't executed yet from DictationCoordinator's perspective.

- timestamp: 2026-03-05T00:06:00Z
  checked: DictationCoordinator line 55-56 execution order
  found: Line 55 writeTranscription(stubResult) and line 56 updateStatus(.ready) run sequentially on MainActor. writeTranscription writes lastTranscription + posts transcriptionReady. Then updateStatus writes .ready + posts statusChanged. Since both are synchronous on the same actor, by the time keyboard's Darwin callback fires (asynchronous, cross-process), BOTH writes should already be committed to UserDefaults.
  implication: The cross-process UserDefaults race is mitigated by the fact that Darwin notifications are delivered asynchronously. By the time the keyboard process receives the notification, both values should be written. BUT .synchronize() propagation across processes is not guaranteed to be instant.

- timestamp: 2026-03-05T00:07:00Z
  checked: Text insertion mechanism
  found: TranscriptionStub has an "Inserer" BUTTON that calls controller.textDocumentProxy.insertText(text). Text is NOT auto-inserted — the user must manually tap the button.
  implication: ROOT CAUSE 1 — Text insertion is manual (button tap), not automatic. The user may expect auto-insertion but the Phase 1 design requires a manual tap on "Inserer".

- timestamp: 2026-03-05T00:08:00Z
  checked: StatusBar spinner behavior
  found: StatusBar ALWAYS shows a ProgressView spinner alongside the message. When status is .ready, statusMessage = "Transcription ready" and the spinner still shows because StatusBar unconditionally renders ProgressView().
  implication: ROOT CAUSE 2 — The spinner showing alongside "Transcription ready" is a UI bug. The spinner should stop when status is .ready, but StatusBar has no conditional logic for spinner visibility.

- timestamp: 2026-03-05T00:09:00Z
  checked: Status message lifecycle for .ready
  found: When statusChanged fires with .ready, updateStatusMessage sets statusMessage = "Transcription ready". This message persists indefinitely (no auto-clear timer for .ready). Meanwhile, handleTranscriptionReady sets statusMessage = "Transcription received" and clears it after 3 seconds. But these two compete depending on notification ordering.
  implication: The statusMessage may flicker between "Transcription ready" and "Transcription received", or one may overwrite the other depending on which Darwin notification arrives first.

- timestamp: 2026-03-05T00:10:00Z
  checked: Whether TranscriptionStub disappears after statusMessage clears
  found: TranscriptionStub visibility depends on dictationStatus == .ready, NOT on statusMessage. If dictationStatus stays .ready, TranscriptionStub remains visible even after statusMessage clears. However, if something resets dictationStatus to .idle, TranscriptionStub disappears.
  implication: TranscriptionStub should remain visible as long as dictationStatus == .ready. This is correct behavior.

- timestamp: 2026-03-05T00:11:00Z
  checked: Whether handleTranscriptionReady could set lastTranscription but dictationStatus still be .transcribing
  found: handleTranscriptionReady calls refreshFromDefaults() which reads whatever status is in UserDefaults at that moment. In DictationCoordinator, writeTranscription runs before updateStatus(.ready). Both call .synchronize(). The keyboard's Darwin callback is async cross-process. The question is: does the second .synchronize() (for .ready status) propagate before the keyboard reads it?
  implication: POTENTIAL ISSUE — If the keyboard receives transcriptionReady notification and reads UserDefaults before updateStatus(.ready)'s synchronize propagates, dictationStatus will be .transcribing and TranscriptionStub won't show (because the view requires dictationStatus == .ready).

- timestamp: 2026-03-05T00:12:00Z
  checked: Second Darwin notification (statusChanged with .ready)
  found: After writeTranscription, updateStatus(.ready) fires statusChanged notification. KeyboardState.refreshFromDefaults() handles this and reads dictationStatus = .ready. It updates dictationStatus but does NOT read lastTranscription.
  implication: When statusChanged fires with .ready, dictationStatus becomes .ready and lastTranscription was already set by handleTranscriptionReady. BOTH conditions for TranscriptionStub should now be met. Unless handleTranscriptionReady's refreshFromDefaults() read .ready and set dictationStatus to .ready, followed by handleTranscriptionReady setting statusMessage = "Transcription received" which clears after 3s, overwriting the "Transcription ready" from statusChanged.

## Resolution

root_cause: |
  THREE issues identified:

  **ISSUE 1 (PRIMARY — likely the reported bug): TranscriptionStub requires manual button tap**
  The TranscriptionStub view shows the transcription text but requires the user to tap "Inserer" button to insert it via textDocumentProxy.insertText(). There is NO auto-insertion. If the user expects the text to appear automatically in the text field, this is the root cause. The text IS displayed in the TranscriptionStub UI bar, but NOT inserted into the active text field without user action.

  **ISSUE 2 (UI confusion): StatusBar spinner never stops**
  StatusBar unconditionally renders a ProgressView() spinner alongside every message, including "Transcription ready". This gives the impression that something is still loading/processing when the transcription is actually complete. This is misleading and contributes to the user perception that "it's not working."

  **ISSUE 3 (Potential race): Cross-process notification ordering**
  DictationCoordinator calls writeTranscription() then updateStatus(.ready) sequentially. Two separate Darwin notifications fire. If the keyboard's handleTranscriptionReady fires and reads UserDefaults before .ready is committed, the TranscriptionStub won't show (requires dictationStatus == .ready). However, the second statusChanged notification should eventually fix this. In practice, this race is unlikely to be the primary issue because both writes happen synchronously before either Darwin callback is processed by the keyboard (different process, async delivery).

fix: (research only — no changes made)
verification: (research only)
files_changed: []
