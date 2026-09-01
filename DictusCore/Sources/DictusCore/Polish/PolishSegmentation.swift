// DictusCore/Sources/DictusCore/Polish/PolishSegmentation.swift
// Cutting text into the units a language question can be asked about one at a time
// (#413, #414 on an output; #456 on an input).
import Foundation
import NaturalLanguage

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
/// Sentence-level segmentation was considered for that check and is not what ships
/// there. A sentence is short enough that the recogniser is unreliable on it, so the
/// check would spend its confidence floor on noise; and the failure #413 measured is
/// per *item*, not per sentence. Measured on the #393 corpus: lines clear every
/// pre-registered bar with room, and sentences buy nothing — see
/// `docs/research/413-414-guardrail-resolution.md` §6.
///
/// ### An input is cut by sentence, and that is not a contradiction (#456)
///
/// `sentences(of:)` below exists because the *input* asks a different question. A raw
/// STT transcript has no lines at all — Parakeet emits one continuous blob — so the
/// line cut returns a single segment there and measures nothing. And the question is
/// not "does any unit disagree", which is a refusal, but "how much of the text is in
/// each language", which is a count: a sentence that reads weakly contributes nothing
/// to the count instead of vetoing the whole text, so the unreliability that rules
/// sentences out of a guardrail is affordable in a proportion. See
/// `PolishLanguageMix`.
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


    /// The text's sentences, trimmed, with blanks dropped.
    ///
    /// `NLTokenizer(unit: .sentence)` rather than a split on `.` — it is the same
    /// framework the recogniser comes from, it does not cut on the period of an
    /// abbreviation or a decimal, and it handles scripts with no Western sentence
    /// punctuation at all. The list marker is NOT stripped here: an input has no
    /// markers to strip, and the tokenizer already leaves punctuation attached to the
    /// sentence it belongs to.
    public static func sentences(of text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { result.append(sentence) }
            return true
        }
        return result
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
