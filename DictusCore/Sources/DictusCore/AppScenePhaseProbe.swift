// DictusCore/Sources/DictusCore/AppScenePhaseProbe.swift
import Foundation

/// Which of its lifecycle states DictusApp last reported.
///
/// Mirrors SwiftUI's `ScenePhase` without depending on SwiftUI, so the keyboard
/// extension can read the value without linking a UI framework it has no use for.
/// `unknown` is what the keyboard sees when the app has never published a phase in
/// this install — not a state the app ever writes.
public enum AppScenePhaseMarker: String {
    case active
    case inactive
    case background
    case unknown
}

/// Publishes DictusApp's scene phase to the App Group, and renders it for the
/// keyboard extension's log lines.
///
/// WHY this exists (#281). After a cold-start dictation the extension can lose every
/// live `KeyboardViewController` and get none back for 10 s or more. The surviving
/// hypothesis is that the teardown happens when the swipe-back lands *before* iOS has
/// rotated in a successor controller — that is, that the app handing the foreground
/// back and the controllers being destroyed are ordered, not merely adjacent.
///
/// The debug log cannot settle that today. It has one-second resolution and interleaves
/// two processes whose writes lag relative to each other, so `<APP> appDidEnterBackground`
/// and `<KBD> viewDidDisappear` landing in the same second says nothing about which
/// happened first (see PR #282 §1). Reading the phase from the App Group at the moment
/// of teardown puts the answer on the keyboard's own line, in the keyboard's own clock,
/// where no cross-process comparison is needed.
///
/// No new IPC path: this is the App Group's shared `UserDefaults`, the same channel
/// every other cross-process value in this app travels on.
///
/// Observation only. Nothing reads these keys to make a decision.
public enum AppScenePhaseProbe {

    /// Publishes `marker` as DictusApp's current phase. Called from the app only.
    ///
    /// The timestamp is stored alongside so the keyboard can report how old the value
    /// is. Age is what makes the reading trustworthy: the keys survive the app being
    /// killed, so a phase with no timestamp near it is a leftover from an earlier run
    /// rather than a statement about now.
    ///
    /// `synchronize()` because the reader is another process that may look microseconds
    /// later — the same reason the cold-start flag is synchronized on this path.
    public static func record(
        _ marker: AppScenePhaseMarker,
        at date: Date = Date(),
        into defaults: UserDefaults = AppGroup.defaults
    ) {
        defaults.set(marker.rawValue, forKey: SharedKeys.appScenePhase)
        defaults.set(date.timeIntervalSince1970, forKey: SharedKeys.appScenePhaseTimestamp)
        defaults.synchronize()
    }

    /// The app's phase, its age in milliseconds, and the cold-start flag, in the
    /// shared key=value format. Called from the keyboard only.
    ///
    /// `appPhaseAgeMs=-1` means no phase has ever been published, in which case
    /// `appPhase` reads `unknown`; the two always agree, so a negative age is never
    /// ambiguous with a real measurement.
    ///
    /// `coldStart` rides along because the #281 window only ever opens during a
    /// cold-start handoff, and reading it here costs one more lookup on `defaults`
    /// the caller has already paid to open.
    public static func describe(
        at date: Date = Date(),
        from defaults: UserDefaults = AppGroup.defaults
    ) -> String {
        let stored = defaults.string(forKey: SharedKeys.appScenePhase)
        let writtenAt = defaults.object(forKey: SharedKeys.appScenePhaseTimestamp) as? Double
        guard let stored, let marker = AppScenePhaseMarker(rawValue: stored), let writtenAt else {
            return "appPhase=\(AppScenePhaseMarker.unknown.rawValue) appPhaseAgeMs=-1"
                + " coldStart=\(defaults.bool(forKey: SharedKeys.coldStartActive))"
        }
        let ageMs = Int((date.timeIntervalSince1970 - writtenAt) * 1000)
        return "appPhase=\(marker.rawValue) appPhaseAgeMs=\(ageMs)"
            + " coldStart=\(defaults.bool(forKey: SharedKeys.coldStartActive))"
    }
}
