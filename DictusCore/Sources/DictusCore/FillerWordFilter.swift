// DictusCore/Sources/DictusCore/FillerWordFilter.swift
import Foundation

/// Removes filler words (French + English) from transcription output.
/// Uses word-boundary matching to avoid corrupting valid words that
/// contain filler substrings (e.g., "humain", "errer", "bénévole").
public struct FillerWordFilter {

    /// Stub — returns text unchanged. Will be implemented in GREEN phase.
    public static func clean(_ text: String) -> String {
        return text
    }
}
