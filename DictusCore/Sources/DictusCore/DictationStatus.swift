// DictusCore/Sources/DictusCore/DictationStatus.swift
import Foundation

/// Represents the current state of a dictation round-trip.
/// Written to App Group UserDefaults so both processes can track progress.
///
/// WHY `.transcribing` and `.processing` are two states and not one (#267): they
/// are two waits of different natures. Transcription is fast and bounded by the
/// audio's length; the LLM stage that follows is 3-6 s today and scales with the
/// output it generates. Rendering the second under the first's animation and
/// label told the user "transcribing" for six seconds, which reads as a hang and
/// invites the desperation tap on cancel. Both stages own the keyboard area and
/// both are judged live by the same heartbeat cadence -- what differs is what
/// the user is told.
///
/// WHY `CaseIterable`: the tests that sweep every status (idempotence of the
/// keyboard-area transition, liveness of every state) used to spell the list out,
/// so a new case joined the enum without joining the sweep. `allCases` makes the
/// sweep grow on its own.
///
/// WHY `Sendable`: the stage watchdog in `DictationCoordinator` hands the status it
/// was armed for to a `Timer` closure, and a plain `String`-raw enum crossing that
/// boundary is safe by construction. Without the conformance the compiler can only
/// warn about it.
public enum DictationStatus: String, Codable, CaseIterable, Sendable {
    case idle         // No dictation in progress
    case requested    // Keyboard triggered dictus://dictate
    case recording    // Main app is recording audio
    case transcribing // Main app is running transcription
    case processing   // Main app is running the LLM stage on the transcript
    case ready        // Transcription result available in shared storage
    case failed       // Something went wrong
}
