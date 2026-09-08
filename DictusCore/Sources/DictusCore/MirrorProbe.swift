// DictusCore/Sources/DictusCore/MirrorProbe.swift
// DEBUG-only instrument: measures when the proxy's mirror diverges from the
// document, and whether anything ever reconverges them (issue #530).
//
// WHY AN INSTRUMENT AND NOT A FIX:
// A keyboard extension can never observe the document. `documentContextBeforeInput`
// is a local mirror, it is the only reader an extension has, and #266 measured that
// it cannot be forced to refetch. So logging the mirror alone shows nothing — that
// is exactly why #530's second capture could show the chain but not the damage.
//
// THE COMPARAND:
// The keyboard's own edit history. It knows every insertText and deleteBackward IT
// issued, so it can predict what the tail should be. It does NOT know host-side
// edits, but it is told one happened. So: keep a shadow of the tail built purely
// from our own operations, and compare it to the mirror at every event.
//
// On #530's capture the keyboard deleted one character and inserted one, predicting
// a net-unchanged "ton", while the mirror reported "tonn". That +1 is the phantom,
// and the event it first appears after is what this instrument exists to name.
//
// WHAT THE TWO OUTCOMES MEAN:
// - The offset appears after one of OUR operations => the mirror failed to reflect
//   an edit we made. The keyboard can detect that itself, at the moment it happens,
//   with no ground truth. A suppression flag becomes possible AND releasable.
// - The offset never appears, yet the text is destroyed => the divergence was
//   already inside the mirror when we baselined on it, i.e. it originates entirely
//   host-side at the selection delete. Nothing in the extension can see it, and
//   #530's criterion 5 has no observable to release on.
//
// The whole file is #if DEBUG: none of it exists in a release binary.

import Foundation

#if DEBUG
/// Tracks a keyboard-side prediction of the document tail and compares it to what
/// the proxy reports, so a divergence has a timestamp and an event name.
///
/// Not thread-safe and not meant to be: every call site is the main thread, which
/// is where UITextDocumentProxy is legal anyway.
public final class MirrorProbe {

    /// Shared because the probe points span the bridge, the SwiftUI root view and
    /// the input view controller. Several keyboard instances can exist in one
    /// process (~9 is normal here), but only the visible one receives key events
    /// and host callbacks. `seq` on every line makes any interleaving visible
    /// rather than silent.
    public static let shared = MirrorProbe()

    /// A document mutation the keyboard itself issued.
    public enum Op: Equatable {
        case insert(String)
        case deleteBackward
        /// A replacement: `deleted` deleteBackward() calls, then `inserted`.
        case replace(deleted: Int, inserted: String)
    }

    /// One comparison of the shadow against the mirror.
    public struct Reading: Equatable {
        public let event: String
        public let mirrorTail: String
        public let mirrorLength: Int
        public let shadowTail: String
        public let shadowLength: Int
        /// How many characters the mirror holds that the shadow does not.
        /// +1 is #530's phantom. Negative means the mirror is behind the shadow.
        /// nil means no alignment was found within ±6 — the shadow is no longer a
        /// usable baseline, which is what a host-side edit looks like.
        public let offset: Int?
        /// True when the mirror and the shadow do not describe the same tail.
        public var diverged: Bool { offset != 0 }
    }

    /// How much of a tail is logged, and how much is compared.
    private static let tailWidth = 24
    /// The shadow never needs more than this; the mirror is a window anyway (#266).
    private static let shadowCap = 200
    /// Alignments beyond this are not a phantom, they are a different document.
    private static let maxAlignment = 6

    /// The predicted tail, built from our own operations since the last baseline.
    private var shadow: String?
    /// The event name of the previous probe, so a reconvergence can name what
    /// preceded it.
    private var previousEvent: String?
    /// The previous probe's offset, to detect a return to zero.
    private var previousOffset: Int?
    /// Monotonic line counter — orders the log unambiguously.
    private var sequence = 0

    public init() {}

    // MARK: - Recording our own edits

    /// Declares a mutation the keyboard just issued, so the prediction follows it.
    /// Call this at the mutation site, never from a host callback: the whole point
    /// is that the shadow contains only what WE did.
    public func record(_ op: Op) {
        guard var predicted = shadow else { return }
        switch op {
        case .insert(let text):
            predicted += text
        case .deleteBackward:
            if !predicted.isEmpty { predicted.removeLast() }
        case .replace(let deleted, let inserted):
            predicted = String(predicted.dropLast(deleted)) + inserted
        }
        shadow = String(predicted.suffix(Self.shadowCap))
    }

    // MARK: - Probing

    /// Compares the shadow to the live mirror, logs the result, and returns it.
    ///
    /// Re-baselines ONLY when there is no shadow yet or when no alignment exists
    /// within ±6 — the signature of an edit the keyboard did not make. A small
    /// offset is deliberately NOT adopted away: whether it persists or clears is
    /// the question this instrument was built to answer.
    @discardableResult
    public func probe(event: String, mirror: String?) -> Reading {
        sequence += 1
        let mirrorText = mirror ?? ""

        guard let shadowText = shadow else {
            adopt(mirror: mirrorText, event: event, reason: "no-baseline")
            let reading = Reading(
                event: event,
                mirrorTail: Self.tail(mirrorText),
                mirrorLength: mirrorText.count,
                shadowTail: Self.tail(mirrorText),
                shadowLength: mirrorText.count,
                offset: 0
            )
            log(reading)
            previousEvent = event
            previousOffset = 0
            return reading
        }

        let offset = Self.alignment(shadow: shadowText, mirror: mirrorText)
        let reading = Reading(
            event: event,
            mirrorTail: Self.tail(mirrorText),
            mirrorLength: mirrorText.count,
            shadowTail: Self.tail(shadowText),
            shadowLength: shadowText.count,
            offset: offset
        )
        log(reading)

        if offset == 0, let previous = previousOffset, previous != 0 {
            AutocorrectDebugLog.mirrorReconverged(
                seq: sequence,
                previousOffset: previous,
                previousEvent: previousEvent ?? "?",
                event: event
            )
        }

        if offset == nil {
            // The shadow no longer describes this document: an edit landed that the
            // keyboard did not make. Re-baseline, loudly — the line above this one
            // is the last moment the prediction was trustworthy.
            adopt(mirror: mirrorText, event: event, reason: "unaligned")
            previousOffset = 0
        } else {
            previousOffset = offset
        }
        previousEvent = event
        return reading
    }

    /// Resets the prediction to what the mirror currently says.
    public func adopt(mirror: String, event: String, reason: String) {
        shadow = String(mirror.suffix(Self.shadowCap))
        AutocorrectDebugLog.mirrorAdopted(
            seq: sequence,
            event: event,
            reason: reason,
            tail: Self.tail(mirror),
            length: mirror.count
        )
    }

    /// Drops the baseline entirely — used when the keyboard appears and the field
    /// it is attached to is unknown.
    public func reset() {
        shadow = nil
        previousEvent = nil
        previousOffset = nil
    }

    private func log(_ reading: Reading) {
        AutocorrectDebugLog.mirrorProbe(
            seq: sequence,
            event: reading.event,
            mirror: (tail: reading.mirrorTail, length: reading.mirrorLength),
            shadow: (tail: reading.shadowTail, length: reading.shadowLength),
            offset: reading.offset
        )
    }

    // MARK: - Comparison

    /// The last `tailWidth` characters, for the log.
    static func tail(_ text: String) -> String {
        String(text.suffix(tailWidth))
    }

    /// How many characters the mirror holds that the shadow does not.
    ///
    /// Tries the smallest offsets first, so an exact match wins over a coincidental
    /// one. Returns nil when nothing within ±6 lines the two tails up — that is not
    /// a desync, that is a different document.
    ///
    /// WHY tails and not whole strings: the mirror is a window the host trims (#266),
    /// so the shadow can legitimately be longer. Only the end is comparable.
    static func alignment(shadow: String, mirror: String) -> Int? {
        let candidates = (0...maxAlignment).flatMap { $0 == 0 ? [0] : [$0, -$0] }
        for offset in candidates {
            // offset > 0: the mirror carries surplus characters, drop them to compare.
            // offset < 0: the shadow carries surplus characters, drop those instead.
            let mirrorSide = offset > 0 ? String(mirror.dropLast(offset)) : mirror
            let shadowSide = offset < 0 ? String(shadow.dropLast(-offset)) : shadow
            let width = min(mirrorSide.count, shadowSide.count, tailWidth)
            // Too short to be evidence: a 1-character coincidence is not an alignment.
            // Both sides empty is a genuine match (an emptied field).
            if width == 0 {
                if mirrorSide.isEmpty && shadowSide.isEmpty { return offset }
                continue
            }
            if width < 3 && !(mirrorSide.count == width && shadowSide.count == width) {
                continue
            }
            if mirrorSide.suffix(width) == shadowSide.suffix(width) { return offset }
        }
        return nil
    }
}
#endif
