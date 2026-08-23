// DictusCore/Sources/DictusCore/Polish/PolishTimeBudget.swift
// How long a polish generation may legitimately take, given its input (#361).
import Foundation

/// The longest a polish call may run before whatever is waiting on it gives up.
///
/// ### Why this is not a constant
///
/// Decision 14 put the Live Activity watchdog at a flat 10 s, calibrated from a field
/// p90 of 4,842 ms and a max of 12,528 ms, and said in terms that it should be
/// recalibrated from real extension-side timings: *"If a single one exceeds it, raise
/// it."* The timings that existed then all came from the probe, which only ever ran a
/// fixed 462-character fixture — so the distribution it measured had no length axis at
/// all.
///
/// Real ones now exist and they are longer:
///
/// ```text
///   462 chars   4,292 - 5,067 ms   (probe burst, 2026-08-23)
///   391 chars      12,002 ms       (device, 2026-08-23)
/// 1,015 chars      21,182 ms       (device, 2026-08-23, outcome success)
/// ```
///
/// Both of the real ones exceed 10 s. The 1,015-character dictation was lost from the
/// user's field because of it: the watchdog fired at 10 s, wrote `dictationStatus =
/// idle`, and the keyboard's overlay came down eleven seconds before the generation
/// returned.
///
/// ### Why a fixed timeout is the wrong shape
///
/// The input length is known before the call starts — DictusApp has the raw text in
/// hand when it hands it over. Spending that knowledge is free, and a flat number
/// cannot be right at both ends: it is either far too generous for the 50-character
/// dictations that dominate real use, or too tight for the long ones, and the long
/// ones are exactly where the cost of being wrong is highest because the user has
/// invested minutes of speech in them.
///
/// ### The numbers, and how much they are worth
///
/// Per-character cost across the three points above is 10.2, 30.7 and 20.9 ms/char.
/// That is not a tight fit — the 391-character case took longer than the
/// 462-character one — so length explains a lot and not everything, and the rest
/// (thermal state, contention, what else the device is doing) is not observable here.
///
/// A watchdog has to exceed the *legitimate* duration of the thing it watches, so
/// this is an upper envelope rather than a fit: **40 ms per character**, about 30%
/// above the worst rate observed, on a **15 s floor** that keeps every short dictation
/// covered by more than an order of magnitude and stays above the old flat number so
/// nothing that worked before regresses.
///
/// There is no explicit ceiling because there is already a real one: #270's context
/// guard refuses input beyond roughly 4,160 characters for the French Natural prompt,
/// so the engine is never handed more than that. At the rate above that is the
/// worst case this can produce, for a dictation of about four and a half minutes of
/// speech. Long, and the honest answer for a wait that is genuinely still running.
///
/// **Firing early is no longer benign**, which is what changed. Decision 14 reasoned
/// that a false positive only cost an Island returning to standby a second early,
/// because the keyboard types its text regardless. That is no longer true on either
/// half: the watchdog also clears `dictationStatus`, which takes the keyboard's
/// overlay down, and since this round it also withdraws the dictation's right to be
/// typed. So the envelope is deliberately generous.
public enum PolishTimeBudget {

    /// Shortest budget, whatever the input. Above decision 14's flat 10 s so no
    /// dictation that completed under the old number can fail under this one.
    static let floor: TimeInterval = 15

    /// Upper envelope of the per-character cost, in seconds. ~30% above the worst
    /// rate measured on device.
    static let perCharacter: TimeInterval = 0.040

    /// How long a generation over `characters` of input may run before the process
    /// that owns the overlay concludes it is stuck.
    public static func generationCeiling(forCharacters characters: Int) -> TimeInterval {
        max(floor, Double(max(0, characters)) * perCharacter)
    }

    /// How long DictusApp waits for `polishDidFinish` before concluding the dictation
    /// on its own.
    ///
    /// Deliberately longer than `generationCeiling`. Both processes watch the same
    /// call, and it matters which one wins: the keyboard's expiry posts
    /// `polishDidFinish`, which ends the dictation cleanly on both sides, while the
    /// app's is the blunt one — it clears shared state for a keyboard that never
    /// reported. The margin makes the clean path the normal one and leaves the app's
    /// timer as what it is meant to be, the net under a keyboard that has stopped
    /// running.
    public static func handoffCeiling(forCharacters characters: Int) -> TimeInterval {
        generationCeiling(forCharacters: characters) + margin
    }

    /// How much longer the app waits than the keyboard.
    static let margin: TimeInterval = 5
}
