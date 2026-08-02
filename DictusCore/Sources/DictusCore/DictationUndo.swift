// DictusCore/Sources/DictusCore/DictationUndo.swift
// Safety check for undoing the last dictation insertion (issue #266).
//
// WHAT THIS PROTECTS AGAINST:
// The undo control deletes text the user cannot see being counted. If the
// keyboard deletes `insertedText.count` characters without first proving that
// those characters are still the ones sitting at the caret, it eats whatever
// the user typed, pasted or moved the caret in front of instead. Deleting the
// wrong text from someone's message is worse than offering no undo at all, so
// the check below is the feature rather than a guard on it.
//
// THE INVARIANT:
// Before the control is shown, and again immediately before it acts, the caller
// re-reads the LIVE `documentContextBeforeInput` and this function confirms the
// inserted string is still the tail of the field. Any doubt fails closed.
//
// THE BOUNDED WINDOW:
// `documentContextBeforeInput` returns a bounded amount of text, and some hosts
// return only as far back as the last line break. A two-minute dictation is
// therefore routinely longer than anything the proxy will show. Refusing to undo
// in that case would disable the feature exactly where holding backspace hurts
// most, so a truncated window is accepted on a weaker guarantee: the whole
// visible window must be a suffix of what was inserted. The result says which
// of the two guarantees was obtained, so a partial verification is never
// silently mistaken for a full one.
//
// WHAT THE TRUNCATED BRANCH DOES NOT PROVE:
// It says the tail of the field is the tail of the insertion. It says nothing
// about the characters further back, which are exactly the ones a `deleteCount`
// of the full insertion goes on to delete.
//
// The first design answered that by re-proving the remainder between deletion
// chunks, on the assumption that the proxy's window slides back over the
// document as the deletion consumes it. Three device captures in Notes
// (2026-08-02) disproved the assumption arithmetically: the window measured
// 491, 496 and 490 graphemes when each burst started and 11, 16 and 10 when it
// stopped — the starting window minus the 480 removed, exactly. That host
// serves one cached window and trims it; it never refetches, and a caret round
// trip did not make it. So the requirement was unmeetable there, and its price
// was the feature: a 4752-grapheme undo removed 480 and left 4272 behind.
//
// The caller now stops only on a refusal that PROVES the field changed
// (`suffix-mismatch`, `truncated-mismatch`) and continues through refusals that
// merely mean the document could not be read (`no-context`, `window-too-short`).
// The residual exposure is a host that silently accepted less text than it was
// handed — a length-limited field — where the recorded count reaches past what
// actually arrived.
//
// The hard bound is the count itself: it is the length of the string the
// keyboard handed to `insertText`, so a burst cannot remove more than one
// dictation put there, whatever the window did or did not show.

import Foundation

public enum DictationUndo {

    /// Result of validating a pending dictation undo against the live context.
    public enum CheckResult: Equatable {
        /// Safe to undo: issue exactly `deleteCount` `deleteBackward()` calls
        /// (one per grapheme cluster).
        ///
        /// - `verifiedCount`: how many trailing graphemes were actually matched
        ///   against the document. Equal to `deleteCount` on a full match, lower
        ///   when the proxy's window was too small to show the whole insertion.
        /// - `windowTruncated`: true when the document context ran out before the
        ///   insertion did, i.e. `verifiedCount < deleteCount`.
        case ok(deleteCount: Int, verifiedCount: Int, windowTruncated: Bool)

        /// Unsafe: show nothing, delete nothing. `reason` is a machine-readable
        /// slug for device logs ("empty-insertion", "no-context",
        /// "suffix-mismatch", "window-too-short", "truncated-mismatch").
        case failed(reason: String)
    }

    /// How much of a truncated window must match before a partial verification is
    /// accepted.
    ///
    /// WHY a floor at all: a short window is cheap to match by accident. A field
    /// ending in ". " matches the tail of half the transcriptions this app
    /// produces. Two dozen graphemes of running text is not something a different
    /// field coincidentally ends with.
    ///
    /// This only ever applies to the truncated branch. A full match of a
    /// three-character insertion is still a full match.
    public static let minimumTruncatedMatch = 24

    /// Whether a `.failed` reason is evidence that the field stopped being ours, as
    /// opposed to evidence that it could not be read.
    ///
    /// `suffix-mismatch` and `truncated-mismatch` are proof: the document was
    /// legible and what it holds is not what we inserted. `no-context` and
    /// `window-too-short` are absence of proof — a detached or unsettled proxy, a
    /// secure field, a host whose cached window has run dry mid-deletion.
    ///
    /// Callers that are deciding whether to STOP something already in flight — the
    /// deletion burst, the offer on screen — must branch on this rather than on
    /// `.failed` alone. Callers deciding whether to START deleting must not: there,
    /// anything short of a pass fails closed.
    public static func provesTheFieldChanged(_ reason: String) -> Bool {
        reason == "suffix-mismatch" || reason == "truncated-mismatch"
    }

    /// Validates that `insertedText` is still the tail of the field.
    ///
    /// - Parameters:
    ///   - context: the LIVE `documentContextBeforeInput`, re-read at the moment
    ///     of the check — never a value captured when the text was inserted.
    ///   - insertedText: the exact string handed to `insertText`, separator
    ///     included. `DictationCoordinator` appends the separator before writing
    ///     to the App Group, so this is the whole of what reached the field.
    public static func verify(
        context: String?,
        insertedText: String,
        minimumTruncatedMatch: Int = minimumTruncatedMatch
    ) -> CheckResult {
        guard !insertedText.isEmpty else {
            return .failed(reason: "empty-insertion")
        }
        // No context means no proof. Secure fields report nothing at all, and a
        // host that reports nothing is exactly the host whose text must not be
        // deleted on a guess.
        guard let context = context, !context.isEmpty else {
            return .failed(reason: "no-context")
        }

        let insertedCount = insertedText.count

        // The window shows at least as much as we inserted: full verification.
        // String comparison uses canonical equivalence, so a host reporting
        // decomposed accents still matches a precomposed insertion — and both
        // normalisations have the same grapheme count, which is what
        // deleteBackward() consumes.
        if context.count >= insertedCount {
            guard context.hasSuffix(insertedText) else {
                return .failed(reason: "suffix-mismatch")
            }
            return .ok(deleteCount: insertedCount, verifiedCount: insertedCount, windowTruncated: false)
        }

        // The window ran out first. Everything it does show has to be the tail of
        // what we inserted; anything else means the field is no longer ours.
        guard context.count >= minimumTruncatedMatch else {
            return .failed(reason: "window-too-short")
        }
        guard insertedText.hasSuffix(context) else {
            return .failed(reason: "truncated-mismatch")
        }
        // The delete count is still the full insertion. Deleting only the verified
        // part would leave the head of the transcription stranded in the field,
        // which is not an undo.
        return .ok(deleteCount: insertedCount, verifiedCount: context.count, windowTruncated: true)
    }
}
