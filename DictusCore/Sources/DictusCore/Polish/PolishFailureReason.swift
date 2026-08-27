// DictusCore/Sources/DictusCore/Polish/PolishFailureReason.swift
import Foundation

/// Why a polish engine call failed (#315).
///
/// WHY this exists: `PolishMetrics.Outcome.engineFailed` is one opaque bucket.
/// The field export from 1.8.0 (25) showed 25 failures out of 242 events, many
/// returning in 4-24 ms — far too fast for the model to have run — while
/// availability stayed `available` throughout. The error value was caught and
/// dropped on the floor, so nothing in the metrics, the export or the log could
/// say what those failures were. This type is the missing word.
///
/// WHY a string slug rather than an enum: the set is open. Nine of the values
/// below mirror `LanguageModelSession.GenerationError`'s cases, but any error
/// can reach the catch block, and an unforeseen one must still be identifiable
/// rather than collapsing into "other". `other(_:)` carries the error's type
/// name for exactly that.
///
/// WHY nothing but the slug: a failure reason is diagnostic data that ends up in
/// a shared export and in the persistent log. `GenerationError.Context.debugDescription`
/// and `localizedDescription` can quote the prompt — which is the user's
/// dictation — so neither is ever read here. The reason stays low-cardinality by
/// construction, which is also what makes a per-reason count meaningful.
public struct PolishFailureReason: Sendable, Hashable, Codable, CustomStringConvertible {

    /// Stable identifier, e.g. "rateLimited" or "other:URLError". Stable means
    /// it is a wire value: it lands in the debug export and in the persistent
    /// log, and reports written against one build get compared to the next.
    public let slug: String

    public init(slug: String) {
        self.slug = slug
    }

    public var description: String { slug }

    // MARK: - Apple Foundation Models

    // The nine `LanguageModelSession.GenerationError` cases, one slug each. The
    // names match Apple's case names deliberately: the reason in an export can
    // be searched straight against Apple's documentation.

    public static let exceededContextWindowSize = PolishFailureReason(slug: "exceededContextWindowSize")
    public static let assetsUnavailable = PolishFailureReason(slug: "assetsUnavailable")
    public static let guardrailViolation = PolishFailureReason(slug: "guardrailViolation")
    public static let unsupportedGuide = PolishFailureReason(slug: "unsupportedGuide")
    public static let unsupportedLanguageOrLocale = PolishFailureReason(slug: "unsupportedLanguageOrLocale")
    public static let decodingFailure = PolishFailureReason(slug: "decodingFailure")
    public static let rateLimited = PolishFailureReason(slug: "rateLimited")
    public static let concurrentRequests = PolishFailureReason(slug: "concurrentRequests")
    public static let refusal = PolishFailureReason(slug: "refusal")

    // MARK: - Catch-all

    /// The reason for an error no engine recognised, carrying the error's Swift
    /// type name (`other:URLError`). An engine that never classifies anything —
    /// every backend but Apple FM today — reports every failure this way, which
    /// is still enough to tell two unforeseen failures apart in an export.
    public static func other(_ error: Error) -> PolishFailureReason {
        PolishFailureReason(slug: "other:\(String(describing: type(of: error)))")
    }

    // MARK: - Codable

    // Encoded as a bare string, not as `{"slug": "..."}`. `PolishMetrics` is
    // persisted one JSON object per line in the 7-day debug ring and read back
    // by a human as often as by the decoder; a nested object for a single
    // string would earn nothing.

    public init(from decoder: Decoder) throws {
        slug = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(slug)
    }
}
