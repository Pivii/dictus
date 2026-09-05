// DictusCore/Sources/DictusCore/PolishedTextChannel.swift
// What the keyboard produced, and whether the document received it (#495).

import Foundation

/// The end of a keyboard dictation, as the keyboard writes it and DictusApp reads it.
///
/// WHY THIS EXISTS: until #495 the App Group carried one value — the polished text —
/// and its absence meant two different things. "The keyboard typed nothing" and "the
/// keyboard produced nothing" are not the same event, and conflating them threw away a
/// generation that had already succeeded. Measured on device 2026-09-05: `outcome:
/// success` with 181 characters of English in the polish debug, and
/// `polishHandoff step=finished outcome=not-inserted chars=0` in the log at the same
/// second, because the insertion was refused (#391) and `finish` deleted the text on
/// its way out. The user's document received nothing, so the home card was their only
/// copy of that dictation, and it held the French they had armed a translation away
/// from.
///
/// WHY A TYPE AND NOT A SECOND KEY WRITTEN BESIDE THE FIRST: the flag is only useful
/// while it is never left behind. A stale `true` from a previous dictation claims an
/// insertion that did not happen, and two keys touched by four call sites in two
/// targets is exactly the shape where one site updates one key. Writing and clearing
/// them together, behind one type, makes that unrepresentable — the same argument
/// `DictationErrorChannel` makes about its own read, and `PendingDictationChannel`
/// about who may clear a pending record.
///
/// The rule, in one line: **the text alone decides whether anything was produced; the
/// flag only ever says where it went.** `read` returns `.nothing` when there is no
/// text, whatever the flag says, so a flag that somehow survived on its own cannot
/// invent an insertion.
public enum PolishedTextChannel {

    /// How the dictation ended.
    public enum Ending: Equatable, Sendable {
        /// The keyboard produced text and typed it into the user's document.
        case inserted(String)
        /// The keyboard produced text and refused to type it — the user had left the
        /// field, dismissed the keyboard, or the host would not name the document
        /// (#391). The refusal is correct; the text is still the dictation's only
        /// copy, and DictusApp is where the user recovers it (#495).
        case refused(String)
        /// The keyboard produced nothing: an armed mode that failed, a generation that
        /// returned empty, a watchdog that cancelled one. The raw DictusApp already
        /// holds is the honest outcome here.
        case nothing

        /// The text this dictation produced, typed or not. Nil only for `.nothing`.
        public var text: String? {
            switch self {
            case .inserted(let text), .refused(let text):
                return text
            case .nothing:
                return nil
            }
        }

        /// The `outcome` field of the `polishHandoff step=finished` log line.
        ///
        /// Three values since #495, and the two that existed before keep exactly the
        /// meaning they had: `inserted` is a dictation the document received, and it
        /// must never appear for one nothing typed — that field is the instrument that
        /// diagnosed #467, and a fix that made it lie would cost more than the bug.
        ///
        /// WHY `refused-with-text` and not something shorter: the label has to survive
        /// the greps already used on these captures, so it deliberately contains
        /// neither `not-inserted` nor `inserted` as a substring. Grepping either of the
        /// old labels still returns exactly the lines it used to.
        public var logOutcome: String {
            switch self {
            case .inserted:
                return "inserted"
            case .refused:
                return "refused-with-text"
            case .nothing:
                return "not-inserted"
            }
        }
    }

    /// Write what this dictation produced and where it went.
    ///
    /// Called from the keyboard, immediately before `polishDidFinish` is posted: a bare
    /// Darwin notification says only "some polish finished", and the app decides on what
    /// it reads next.
    public static func record(_ ending: Ending, in defaults: UserDefaults = AppGroup.defaults) {
        guard let text = ending.text else {
            clear(in: defaults)
            return
        }
        defaults.set(text, forKey: SharedKeys.lastPolishedTranscription)
        defaults.set(ending == .inserted(text), forKey: SharedKeys.lastPolishedWasInserted)
        defaults.synchronize()
    }

    /// Drop both halves. Called wherever the polished text was already being dropped —
    /// DictusApp clearing the previous dictation's answer as it hands a new one over,
    /// and the launch sweep — because a flag outliving the text it describes is the one
    /// way this channel can lie.
    public static func clear(in defaults: UserDefaults = AppGroup.defaults) {
        defaults.removeObject(forKey: SharedKeys.lastPolishedTranscription)
        defaults.removeObject(forKey: SharedKeys.lastPolishedWasInserted)
        defaults.synchronize()
    }

    /// What the keyboard left behind.
    ///
    /// Answering `.nothing` for a missing text is what makes the flag unable to speak on
    /// its own. Callers still have to establish that the answer belongs to *their*
    /// hand-off — `SharedKeys.lastPolishedHandoffToken` is what says so.
    public static func read(from defaults: UserDefaults = AppGroup.defaults) -> Ending {
        guard let text = defaults.string(forKey: SharedKeys.lastPolishedTranscription) else {
            return .nothing
        }
        return defaults.bool(forKey: SharedKeys.lastPolishedWasInserted)
            ? .inserted(text)
            : .refused(text)
    }
}
