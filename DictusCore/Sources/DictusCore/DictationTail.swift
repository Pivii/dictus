// DictusCore/Sources/DictusCore/DictationTail.swift
// The trailing separator a finished dictation carries into the host field.
import Foundation

/// What gets appended to a dictation before it is typed.
///
/// WHY this is a type of its own since #361: the separator used to be four lines
/// inline in `DictationCoordinator`, immediately before the App Group write. Polish
/// and insertion moved into the keyboard extension, and the tail moves with them —
/// but in-app dictations still finish in DictusApp, so the rule now has two callers
/// in two processes. A rule with two callers is a rule that drifts, and this one
/// silently corrupts Chinese text when it does.
public enum DictationTail {

    /// Append the trailing separator so chained dictations don't stick together.
    ///
    /// Whisper Auto-detect mode (#226) inserts the transcription as-is: the output
    /// language is unknown, and coercing Western punctuation/spacing onto e.g.
    /// Chinese ("你好。" + ". ") would corrupt the text. Follow and explicit modes —
    /// and Parakeet in every mode — keep the historical separator behavior.
    public static func apply(_ text: String, policy: TranscriptionLanguagePolicy) -> String {
        guard !policy.insertsTranscriptionAsIs else { return text }
        if let last = text.last, ".!?…".contains(last) {
            return text + " "
        }
        return text + ". "
    }
}
