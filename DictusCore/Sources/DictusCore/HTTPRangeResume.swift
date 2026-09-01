// DictusCore/Sources/DictusCore/HTTPRangeResume.swift
// The decision a ranged model download makes when the server answers.
import Foundation

/// The `Content-Range` a `206 Partial Content` response carries.
///
/// Only the `bytes` unit is accepted. A server answering in any other unit is not
/// answering the question we asked, and treating it as bytes would append the wrong
/// payload to a half-written model file.
public struct HTTPContentRange: Equatable, Sendable {
    /// First byte of the returned span, inclusive.
    public let start: Int64
    /// Last byte of the returned span, inclusive.
    public let end: Int64
    /// Total size of the whole resource, or `nil` when the server sent `*`.
    public let total: Int64?

    public init(start: Int64, end: Int64, total: Int64?) {
        self.start = start
        self.end = end
        self.total = total
    }

    /// Number of bytes this span covers.
    public var length: Int64 { end - start + 1 }
}

/// What a caller must do with the body of a ranged response.
public enum RangeResumeDecision: Equatable, Sendable {
    /// The server honoured the range: append the body at this offset.
    case appendFrom(Int64)
    /// The body covers the whole requested span, but the response header describes only
    /// its final leg, which began further in.
    ///
    /// This is what a background `URLSession` looks like when it resumes a task by
    /// itself. Measured on device 2026-09-01: a chunk asked for at 201326592 was
    /// interrupted 2 996 625 bytes in when iOS suspended the app; the system re-issued
    /// the request from 204323217, stitched the two legs together, and handed
    /// `didFinishDownloadingTo` the complete chunk — with a `Content-Range` describing
    /// the second leg alone. Reading that header as the body's start refused a perfectly
    /// good chunk, which was the one case this whole mechanism exists for.
    ///
    /// The header cannot vouch for the body here, so the caller must check the assembled
    /// file's LENGTH against the span it asked for. Carries the leg's start, for the log.
    case appendResumedSpan(lastLegStart: Int64)
    /// The server ignored the range and sent the whole resource (`200`). The partial
    /// on disk is worthless — drop it and write this body from byte 0. Carries the
    /// reason so the debug log can say why a resume did not happen.
    case restartFromZero(reason: String)
    /// The response cannot be used at all. Carries the reason for the log.
    case reject(reason: String)
}

/// Decides whether a ranged response may be appended to a partially downloaded file.
///
/// WHY this is a type of its own (issue #449): it is the one piece of the background
/// downloader that is pure — a status code, two headers and an expected offset in,
/// a decision out — and it is also the piece where a wrong answer is silent. Appending
/// a `200` body to a half-written file produces a file of exactly the right length made
/// of the wrong bytes, which no existence check downstream can catch. `ModelManager`
/// and the background `URLSession` delegate cannot be reached from a test; this can.
///
/// The rules come from the maintainer's Hugging Face reading on issue #449:
///
/// - resume with `Range: bytes=<offset>-` and `If-Range: <ETag>`
/// - require `206 Partial Content` **and** an exact `Content-Range` start before
///   appending
/// - if the server returns `200`, replace/restart cleanly rather than appending
///
/// See https://huggingface.co/docs/huggingface_hub/guides/download.
public enum HTTPRangeResume {

    /// The `Range` header value for the remainder of a file from `start`.
    public static func rangeHeaderValue(start: Int64) -> String {
        "bytes=\(start)-"
    }

    /// The `Range` header value for one closed span, both bounds inclusive.
    public static func rangeHeaderValue(start: Int64, end: Int64) -> String {
        "bytes=\(start)-\(end)"
    }

    /// Parses a `Content-Range` response header.
    ///
    /// Accepts `bytes <start>-<end>/<total>` and `bytes <start>-<end>/*`. Returns nil
    /// for any other unit, for the unsatisfied form `bytes */<total>`, and for anything
    /// malformed — all of which mean "do not append".
    public static func parseContentRange(_ header: String) -> HTTPContentRange? {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        // Split "bytes 0-1/2" into the unit and the span, tolerating repeated spaces.
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bytes" else { return nil }

        let span = parts[1].split(separator: "/", omittingEmptySubsequences: false)
        guard span.count == 2 else { return nil }

        let bounds = span[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2,
              let start = Int64(bounds[0]),
              let end = Int64(bounds[1]),
              start >= 0,
              end >= start else {
            return nil
        }

        let totalField = span[1]
        let total: Int64?
        if totalField == "*" {
            total = nil
        } else if let parsed = Int64(totalField), parsed > end {
            total = parsed
        } else {
            // A total that does not cover the span it describes is a contradiction.
            return nil
        }

        return HTTPContentRange(start: start, end: end, total: total)
    }

    /// Whether a ranged response may be appended at `expectedStart`.
    ///
    /// - Parameters:
    ///   - statusCode: HTTP status of the response the body came with.
    ///   - contentRangeHeader: raw `Content-Range` header, or nil when absent.
    ///   - expectedStart: the offset the caller asked for and holds on disk.
    ///   - expectedEnd: the last byte the caller asked for, or nil for an open-ended
    ///     request. A `Content-Range` starting anywhere inside this span belongs to a
    ///     transfer the client resumed itself — see `appendResumedSpan`.
    ///   - expectedTotal: the file size the repository listing promised, or nil when
    ///     the listing did not know it.
    public static func decide(
        statusCode: Int,
        contentRangeHeader: String?,
        expectedStart: Int64,
        expectedEnd: Int64?,
        expectedTotal: Int64?
    ) -> RangeResumeDecision {
        switch statusCode {
        case 200:
            // The server ignored the range — either it does not support ranges, or the
            // `If-Range` validator no longer matches and it is serving the current
            // resource in full. Both mean the partial on disk is stale.
            return .restartFromZero(reason: "http200-range-ignored")

        case 206:
            guard let contentRangeHeader else {
                return .reject(reason: "206-without-content-range")
            }
            guard let range = parseContentRange(contentRangeHeader) else {
                return .reject(reason: "206-unparsable-content-range")
            }
            if range.start != expectedStart {
                // Inside the span we asked for: the client resumed its own transfer and
                // this header describes the tail of it. Outside it: the response has
                // nothing to do with what was requested.
                let withinRequestedSpan = range.start > expectedStart
                    && (expectedEnd.map { range.start <= $0 } ?? true)
                guard withinRequestedSpan else {
                    return .reject(reason: "206-start-\(range.start)-expected-\(expectedStart)")
                }
                if let expectedTotal, let total = range.total, total != expectedTotal {
                    return .restartFromZero(
                        reason: "206-total-\(total)-expected-\(expectedTotal)"
                    )
                }
                return .appendResumedSpan(lastLegStart: range.start)
            }
            if let expectedTotal, let total = range.total, total != expectedTotal {
                // The resource changed size under us. Nothing on disk can be trusted,
                // and appending would produce a file of the right length and the wrong
                // content — the one failure no completeness check downstream can see.
                return .restartFromZero(reason: "206-total-\(total)-expected-\(expectedTotal)")
            }
            return .appendFrom(range.start)

        case 416:
            // Requested Range Not Satisfiable: our offset is past the end of the
            // resource, so the partial is longer than what the server has.
            return .restartFromZero(reason: "http416-range-not-satisfiable")

        default:
            return .reject(reason: "http\(statusCode)")
        }
    }
}
