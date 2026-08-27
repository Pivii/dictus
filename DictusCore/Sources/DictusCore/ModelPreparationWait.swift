// DictusCore/Sources/DictusCore/ModelPreparationWait.swift
// Turns a measured first-preparation duration into the shape of the sentence the
// preparation screen shows about it. Issue #432.
import Foundation

/// How long the preparation screen should tell the user to expect to be there.
///
/// WHY a bucket and not just the number:
/// `ModelInfo.firstPreparationSeconds` is a measurement, and a measurement is not a
/// promise. Something has to decide whether to round 236 seconds up or down, whether
/// a 32-second wait deserves a figure at all, and what to say for a model nobody has
/// ever timed. Those decisions are the same wherever they are asked, they are the
/// part of this issue with a right and a wrong answer, and none of them can be tested
/// from inside a SwiftUI view. Making them here leaves the view with a `switch` it
/// cannot get wrong and leaves the reasoning somewhere a test can hold it still.
public enum ModelPreparationWait: Equatable, Sendable {

    /// Measured, and short enough that naming a number would be noise rather than
    /// reassurance. Medium's 32s.
    case brief

    /// Measured in minutes, rounded up. The associated value is never below
    /// `minimumNamedMinutes`.
    case minutes(Int)

    /// Nobody has timed this model's first preparation on a device, or the catalogue
    /// does not know this identifier at all — which is exactly what a model left over
    /// from an older build looks like. The screen still says the wait happens once. It
    /// invents no duration.
    case unmeasured

    /// Under this, a first preparation is `.brief` and the copy names no figure.
    ///
    /// A minute rather than something rounder because that is where the sentence has
    /// to change: below it "under a minute" is both true and calming, above it the
    /// user wants the number.
    public static let briefThresholdSeconds = 60

    /// The smallest figure the copy will ever print.
    ///
    /// WHY a floor of two: the English source sentence reads "about %lld minutes" and
    /// the String Catalog carries no plural rule for it, so a 1 would ship "about 1
    /// minutes" into a screen the user is already staring at. Nothing in the catalogue
    /// is anywhere near that seam today — the two measured values are 32s and 236s —
    /// so the floor is here to stop a 70-second model added later from introducing the
    /// bug quietly. It costs at most a minute of overstatement, in the safe direction.
    public static let minimumNamedMinutes = 2

    /// The wait to announce for `identifier`.
    public static func forModel(_ identifier: String) -> ModelPreparationWait {
        forMeasuredSeconds(ModelInfo.forIdentifier(identifier)?.firstPreparationSeconds)
    }

    /// WHY this rounds UP, always:
    /// the person reading the screen is deciding whether to keep waiting or force
    /// quit. Issue #432 is that decision, taken by the maintainer, on a screen that
    /// named no duration at all. A wait that ends sooner than announced costs nothing;
    /// one that runs past the announced figure re-creates the exact doubt the sentence
    /// was written to remove, and now with the app's own words as evidence.
    ///
    /// A non-positive reading is treated as no reading. Zero seconds is not a
    /// measurement of a Core ML compile, it is a bug in whoever wrote it down.
    public static func forMeasuredSeconds(_ seconds: Int?) -> ModelPreparationWait {
        guard let seconds, seconds > 0 else { return .unmeasured }
        guard seconds >= briefThresholdSeconds else { return .brief }
        // Integer ceiling. `(n + 59) / 60` rather than `ceil` on a Double so the
        // boundary cases are exact rather than nearly exact.
        let roundedUpMinutes = (seconds + 59) / 60
        return .minutes(max(minimumNamedMinutes, roundedUpMinutes))
    }
}
