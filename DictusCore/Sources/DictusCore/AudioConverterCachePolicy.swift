// DictusCore/Sources/DictusCore/AudioConverterCachePolicy.swift
// What an audio tap should do with the converter it is holding when a buffer arrives.
import Foundation

/// What a tap callback should do with the sample-rate converter it currently holds.
public enum AudioConverterCacheDecision: Equatable, Sendable {
    /// The held converter already reads the format this buffer is in. Convert with it.
    case reuse
    /// There is no converter for this format yet. Build one from the buffer's own format.
    case build
    /// This exact format already failed to produce a converter. Drop the buffer without
    /// trying again — see `AudioConverterCachePolicy` for why the memo exists.
    case skipUnconvertibleFormat
}

/// Decides whether an audio tap must rebuild its converter for an incoming buffer (issue #417).
///
/// ### Why this is in DictusCore and not next to the engine
///
/// Same reason as `AudioInputFormatPolicy` and `IdleReleasePolicy`: `UnifiedAudioEngine` is
/// `@MainActor`, owns a live `AVAudioEngine` and lives in the DictusApp target, so nothing
/// on its capture path can be exercised from a test. This decision is pure — it compares a
/// format to two remembered ones — and it is what makes the fix correct, so it is the part
/// that has to be assertable.
///
/// ### The bug this encodes
///
/// `startEngine()` used to read the input node's format, then sixty lines later hand that
/// same format to `installTap`. Measured on device six times (2026-09-02 and 2026-09-03,
/// iPhone16,2 / iOS 26.6.1): while a native call or Siri holds the session, the input node
/// renegotiates inside that window and `installTap` raises
/// `Failed to create tap due to format mismatch, <AVAudioFormat 1 ch, 48000 Hz, Float32>` —
/// a format that is individually valid, and that every pre-flight guard therefore accepts.
///
/// The tap now installs with `format: nil`, so the bus supplies its own format and a mismatch
/// is impossible by construction. The consequence is that the converter can no longer be built
/// ahead of time from a format we merely read: the authoritative format is the one on the first
/// buffer. That also fixes a second, quieter failure — a mid-recording route change, where the
/// converter used to keep converting from a format the hardware had stopped producing.
///
/// ### Why the unconvertible-format memo
///
/// The tap callback runs on a real-time audio thread and `.build` allocates. A format that
/// `AVAudioConverter(from:to:)` refuses would otherwise be retried on every single buffer —
/// roughly a hundred allocation attempts a second, on that thread, for as long as the route
/// lasts. Remembering the one format that failed bounds it to a single attempt, while leaving
/// any *other* format free to be tried: the failure is a property of the format, not of the tap.
public enum AudioConverterCachePolicy {

    /// - Parameters:
    ///   - heldInputFormat: `AVAudioConverter.inputFormat` of the converter the tap is
    ///     holding, or nil if it holds none.
    ///   - lastUnconvertibleFormat: the last format `AVAudioConverter(from:to:)` refused,
    ///     or nil if none has been refused since the tap was installed.
    ///   - bufferFormat: `AVAudioPCMBuffer.format` of the buffer that just arrived.
    /// - Returns: what to do with the held converter.
    ///
    /// Generic over the format type rather than typed to `AVAudioFormat` so the call site
    /// keeps AVFoundation's own equality — `AVAudioFormat.isEqual` compares the sample rate,
    /// the channel count, the common format, interleaving *and* the channel layout, and
    /// re-implementing that here would only test the re-implementation.
    public static func decide<Format: Equatable>(
        heldInputFormat: Format?,
        lastUnconvertibleFormat: Format?,
        bufferFormat: Format
    ) -> AudioConverterCacheDecision {
        // Reuse first: a held converter for this format settles the question, and no
        // sequence can produce both a held converter and a failure memo for one format.
        if let heldInputFormat, heldInputFormat == bufferFormat {
            return .reuse
        }
        if let lastUnconvertibleFormat, lastUnconvertibleFormat == bufferFormat {
            return .skipUnconvertibleFormat
        }
        return .build
    }
}
