// DictusCore/Sources/DictusCore/FillerWordFilter.swift
import Foundation

/// Removes filler words (French + English) from transcription output.
/// Uses word-boundary matching to avoid corrupting valid words that
/// contain filler substrings (e.g., "humain", "errer", "bénévole").
public struct FillerWordFilter {

    // Locked word list from CONTEXT.md — do NOT add more without updating tests.
    private static let fillers = ["euh", "hm", "bah", "ben", "voila", "um", "uh", "er"]

    // Pattern uses lookahead/lookbehind for word boundaries instead of \b,
    // because \b treats apostrophes as boundaries in French (e.g., "l'humain").
    // (?<=\s|^) = preceded by whitespace or start of string
    // (?=\s|$|[,.!?;:]) = followed by whitespace, end, or punctuation
    private static let pattern: String = {
        let escaped = fillers.map { NSRegularExpression.escapedPattern(for: $0) }
        return "(?<=\\s|^)(" + escaped.joined(separator: "|") + ")(?=\\s|$|[,.!?;:])"
    }()

    /// Removes filler words from the given text and cleans up resulting whitespace/punctuation.
    public static func clean(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // Remove filler words (case-insensitive, whole-word only)
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // Remove orphaned punctuation left after filler removal (e.g., " , " -> " ")
        result = result.replacingOccurrences(
            of: "(?<=\\s|^)[,.](?=\\s|$)",
            with: "",
            options: .regularExpression
        )

        // Collapse multiple spaces into one
        result = result.replacingOccurrences(
            of: "  +",
            with: " ",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespaces)
    }
}
