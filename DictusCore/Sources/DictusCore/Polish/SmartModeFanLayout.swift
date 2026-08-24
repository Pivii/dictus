// DictusCore/Sources/DictusCore/Polish/SmartModeFanLayout.swift
// Geometry and hit-testing for the keyboard's long-press Smart Mode fan (issue #79).
import CoreGraphics
import Foundation

/// One row of the long-press fan.
///
/// Normal is a row rather than an implied default because releasing back on the mic
/// **aborts** the gesture — no mode change, no recording — so it is not the way to
/// clear a sticky mode. A user who armed "→ EN" last week needs somewhere to press
/// to get their plain dictation back.
public enum SmartModeFanEntry: Equatable, Sendable, Identifiable {

    /// The free polish, and the default state. Selecting it disarms.
    case normal

    /// A pinned Smart Mode.
    case mode(SmartMode)

    public var id: String {
        switch self {
        case .normal: return "normal"
        case .mode(let mode): return mode.id
        }
    }

    /// The armed mode this row selects, or nil for Normal.
    public var smartMode: SmartMode? {
        guard case .mode(let mode) = self else { return nil }
        return mode
    }

    /// SF Symbol for the row.
    ///
    /// Normal borrows the mic rather than an abstract "off" glyph: the row means
    /// "dictate the way you always did", and the mic is what the user associates
    /// with that.
    public var icon: String {
        switch self {
        case .normal: return "mic.fill"
        case .mode(let mode): return mode.icon
        }
    }
}

/// Where the fan's rows are, and which one a finger is on.
///
/// Lives in DictusCore rather than beside the view for the reason `KeyboardAreaMode`
/// does: the keyboard extension target has no test bundle, and the arithmetic below
/// is the whole of the decision that settled #79's fan-capacity contradiction. A
/// SwiftUI view can be wrong on a screen nobody is looking at; this cannot.
public enum SmartModeFanLayout {

    /// Rows the fan can draw, Normal included.
    ///
    /// Four, and the reasoning is `SmartModeCatalogue.maximumPinnedModes`'. Derived
    /// from it rather than written twice so the two cannot disagree — the cap the
    /// app enforces when pinning IS the cap the fan can draw.
    public static var maximumEntries: Int { SmartModeCatalogue.maximumPinnedModes + 1 }

    /// Apple's minimum touch target, and the bar the four-entry decision cleared.
    ///
    /// Not enforced at runtime: the rows divide whatever height the keyboard area
    /// actually has, and a device narrower than anything shipped today should still
    /// get a usable fan rather than a clipped one. It is here as the number the
    /// tests assert against for the two real device classes.
    public static let minimumRowHeight: CGFloat = 44

    /// Height reserved for the unavailability line under the rows.
    ///
    /// Only subtracted when there is a reason to show, so the ordinary fan — the one
    /// a user with Apple Intelligence sees every time — pays nothing for it. When it
    /// is showing, the rows it squeezes are disabled anyway: nothing in that state is
    /// a target except Normal.
    public static let reasonHeight: CGFloat = 24

    /// The rows, in order, for a pinned list.
    ///
    /// Normal first because the fan deploys downward from the mic and the thumb
    /// travels away from the palm: the nearest row is the cheapest to reach, and
    /// "put it back to normal" is the one selection a user makes under mild
    /// frustration.
    ///
    /// The pinned list is capped defensively as well as at the store, because this
    /// is the side that cannot draw more.
    public static func entries(pinned: [SmartMode]) -> [SmartModeFanEntry] {
        [.normal] + pinned.prefix(SmartModeCatalogue.maximumPinnedModes).map(SmartModeFanEntry.mode)
    }

    /// Height of one row, given the space below the toolbar.
    ///
    /// Rows divide the area evenly and completely: there is deliberately no dead
    /// space between or below them, because every point of it would be a place to
    /// release and get nothing. Measured against the real `KeyMetrics` values —
    /// 205 pt on a standard iPhone, 187 pt on an iPhone SE — four entries give
    /// 51.2 pt and 46.7 pt.
    public static func rowHeight(availableHeight: CGFloat,
                                 entryCount: Int,
                                 showsReason: Bool) -> CGFloat {
        guard entryCount > 0 else { return 0 }
        let usable = max(0, availableHeight - (showsReason ? reasonHeight : 0))
        return usable / CGFloat(entryCount)
    }

    /// Which row a finger at `y` is on, or nil when it is on none.
    ///
    /// `y` is measured from the top of the fan area — the point directly below the
    /// toolbar — so a negative value is the finger back up on the mic, which is the
    /// documented abort. A value past the last row is the reason strip, and aborts
    /// for the same reason: the user is not pointing at a choice.
    public static func entryIndex(atY y: CGFloat,
                                  availableHeight: CGFloat,
                                  entryCount: Int,
                                  showsReason: Bool) -> Int? {
        guard entryCount > 0, y >= 0 else { return nil }
        let height = rowHeight(
            availableHeight: availableHeight, entryCount: entryCount, showsReason: showsReason
        )
        guard height > 0 else { return nil }
        let index = Int(y / height)
        guard index < entryCount else { return nil }
        return index
    }
}
