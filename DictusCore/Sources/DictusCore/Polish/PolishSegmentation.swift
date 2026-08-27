// DictusCore/Sources/DictusCore/Polish/PolishSegmentation.swift
// Cutting an output into the units a guardrail can judge one at a time (#413, #414).
import Foundation

/// Splits a polish output into the pieces a guardrail inspects individually.
///
/// ### Why this exists at all
///
/// Both guardrail holes #393 found are the same shape: a check that reads the whole
/// output as one blob cannot see a defect confined to one item of a list. #413's
/// language check reads an output of five English bullets and one French one as
/// French, because the aggregate is what `NLLanguageRecognizer` answers about.
/// #414's grounding check needs the same cut for a different reason — `NLTagger`'s
/// recall is context-sensitive, and it finds a name on a bullet standing alone that
/// it misses inside the block.
///
/// ### A segment is a line
///
/// After `PolishPostpass.decodeNewlines` every dictated and every model-emitted
/// break is a single `\n`, so one bullet is one line — this splits on the text the
/// post-pass already produced and changes nothing about how breaks are encoded,
/// decoded or emitted (#437 owns that).
///
/// Sentence-level segmentation was considered and is not what ships. A sentence is
/// short enough that the recogniser is unreliable on it, so the check would spend
/// its confidence floor on noise; and the failure #413 measured is per *item*, not
/// per sentence. Measured on the #393 corpus: lines clear every pre-registered bar
/// with room, and sentences buy nothing — see
/// `docs/research/413-414-guardrail-resolution.md` §6.
public enum PolishSegmentation {

    /// The output's lines, trimmed, with any leading list marker removed and blanks
    /// dropped.
    ///
    /// The marker goes because it is not text: leaving `- ` on would inflate every
    /// segment's character count by two, and the minimum-length threshold is
    /// measured in characters of actual language.
    public static func segments(of text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { stripLeadingMarker(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// Bullet, dash, asterisk or an ordinal like `1.` / `2)`, plus the whitespace
    /// after it. Only ONE marker is stripped: a second one is content.
    private static func stripLeadingMarker(_ line: String) -> String {
        var rest = Substring(line).drop(while: \.isWhitespace)
        if let first = rest.first, "-–—*•·".contains(first) {
            rest = rest.dropFirst()
        } else {
            let digits = rest.prefix(while: \.isNumber)
            if !digits.isEmpty, digits.count <= 3,
               let separator = rest.dropFirst(digits.count).first, ".)".contains(separator) {
                rest = rest.dropFirst(digits.count + 1)
            }
        }
        return String(rest.drop(while: \.isWhitespace))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
