// DictusCore/Sources/DictusCore/ModelCleanupPolicy.swift
// Extracted decision rule for whether a failed model preparation may delete the
// files it downloaded. Testable in isolation -- no file system, no engine.

import Foundation

/// Decides whether a failed download/prewarm is allowed to wipe the model files
/// already on disk.
///
/// WHY extracted from `ModelManager` (issue #405):
/// `ModelManager` is `@MainActor`, owns live WhisperKit/FluidAudio pipelines and
/// lives in the DictusApp target, so none of it can be exercised from a unit
/// test. The rule itself is pure -- it reads two facts and returns a Bool -- and
/// it is exactly where #405's defect lived: the prewarm branch cleaned up
/// unconditionally, so a Turbo compile that merely ran out of clock cost the user
/// a 1.05 GB re-download. Same pattern as `IdleReleasePolicy`.
///
/// WHY an enum with statics (not a struct): there is no state to carry. The
/// caller owns the facts; this type only combines them.
public enum ModelCleanupPolicy {

    /// Whether the files a failed preparation left behind must be removed.
    ///
    /// Three cases, and only one of them deletes anything:
    ///
    /// - **Download-phase failure** (`downloadPhaseCompleted == false`): keep.
    ///   The downloader moves each file into place atomically, so everything on
    ///   disk is a complete file and a retry skips it and resumes where it left
    ///   off (issue #210, the policy the Parakeet path has always had).
    /// - **Prewarm timeout** (issue #405): keep. The payload downloaded fine and
    ///   only the Core ML compilation ran out of clock -- on a slow device, on a
    ///   thermally throttled one, or because the budget itself is too tight
    ///   (issue #406). The bytes are still good, so a retry must be able to
    ///   resume at the compile step instead of repaying the download.
    /// - **Any other prewarm failure**: delete. ANE compilation failures ("Must
    ///   re-compile the E5 bundle", issue #104) leave behind an unusable Core ML
    ///   cache that makes every retry fail identically until it is cleared.
    ///
    /// - Parameters:
    ///   - downloadPhaseCompleted: the payload finished downloading, so the
    ///     failure belongs to the prewarm phase.
    ///   - isPrewarmTimeout: the failure is the deadline guard firing, not the
    ///     compilation itself reporting an error.
    /// - Returns: true when the caller should remove the model's files.
    public static func shouldCleanUpFiles(
        downloadPhaseCompleted: Bool,
        isPrewarmTimeout: Bool
    ) -> Bool {
        downloadPhaseCompleted && !isPrewarmTimeout
    }
}
