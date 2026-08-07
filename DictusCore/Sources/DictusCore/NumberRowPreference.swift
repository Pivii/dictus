// DictusCore/Sources/DictusCore/NumberRowPreference.swift
// Whether the keyboard draws a persistent digit row above the letter rows (#331).
import Foundation

/// The opt-in persistent number row: `1234567890` always reachable without switching to
/// the symbols page.
///
/// WHY this lives in DictusCore rather than in either target:
/// DictusApp's Settings writes it and the keyboard extension reads it at grid-build time,
/// so it crosses the App Group and belongs where both can see it — the same reasoning that
/// put `KeyboardLayoutPreference` here.
///
/// WHY one global value and not one per language (#331 triage):
/// a number row is a hardware habit, not a language one. Someone who wants digits on the
/// keyboard wants them on every keyboard they type on, and per-language state here would be
/// state to explain with nothing asking for it.
///
/// WHY the absence of the key means off:
/// `UserDefaults.bool` returns false for a missing key, so an install that has never seen
/// this feature reads exactly what it read before it existed. No migration, no registration,
/// and nobody's keyboard changes shape on update.
///
/// Note that this flag alone does **not** say whether the row is drawn. Landscape never draws
/// it regardless (the keyboard would eat 72% of the screen — see the measurement in #331), and
/// that check lives with the geometry in the keyboard target, which is the only place that can
/// see the device orientation.
public enum NumberRowPreference {

    /// Whether the user asked for the digit row.
    public static var isEnabled: Bool {
        AppGroup.defaults.bool(forKey: SharedKeys.numberRowEnabled)
    }

    /// Records the user's choice.
    ///
    /// DictusApp's Settings toggle writes the key through @AppStorage instead, the way every
    /// other toggle on that screen does. This is the programmatic writer: the tests, and any
    /// future surface outside SwiftUI (the keyboard's own hamburger panel is the candidate
    /// named in #331).
    public static func setEnabled(_ enabled: Bool) {
        AppGroup.defaults.set(enabled, forKey: SharedKeys.numberRowEnabled)
    }
}
