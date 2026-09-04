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

    /// The way out of a non-subscriber's fan: the last of its four rows (#404).
    ///
    /// Not a button: `SmartModeFanView` is `allowsHitTesting(false)` by construction,
    /// because the finger went down on the mic pill and one gesture tracks it to the
    /// release. As a *row* it is selected by that same drag and committed by the same
    /// release — `commit()` opens the app **on the paywall** instead of arming
    /// anything. That is what makes it reachable at all.
    ///
    /// It costs a slot, which is why the fan shows two mode rows rather than three:
    /// four entries is the ceiling `SmartModeCatalogue.maximumPinnedModes` measured,
    /// and five would put an iPhone SE row at 37.4 pt against Apple's 44 pt minimum.
    case pro

    public var id: String {
        switch self {
        case .normal: return "normal"
        case .mode(let mode): return mode.id
        case .pro: return "pro"
        }
    }

    /// The armed mode this row selects, or nil for Normal **and for the Pro row**.
    ///
    /// Nil for two rows that mean different things, which is why nothing decides
    /// what a release does from this property alone — `SmartModeFanState` and
    /// `KeyboardSmartModeState.commit()` switch over the case. Reading nil as
    /// "disarm" would make the Pro row silently clear the user's mode on the way to
    /// the paywall.
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
        case .pro: return "sparkles"
        }
    }
}

/// What a fan row carries beside its name (#404, #423).
///
/// Three states and never two at once, because a row that said two things at once would
/// be saying neither. `SmartModeFanLayout.tag(for:...)` owns the precedence.
public enum SmartModeFanRowTag: String, Equatable, Sendable {

    /// This is what the next dictation runs. A check, and the honest answer to the
    /// question the fan is actually being asked.
    case effective

    /// Armed, and it will not run (#423). The user's choice survived a condition it
    /// cannot run under, and the marker says so without claiming it is active.
    case inactive

    /// Behind Dictus Pro (#404). Named rather than merely greyed, because greying says
    /// "you cannot pick this" and the row is here to say what the subscription buys.
    case pro
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

    /// The rows, in order, for a pinned list and the mode currently armed — or no
    /// rows at all, which is this type's way of saying the fan should not open.
    ///
    /// Normal first because the fan deploys downward from the mic and the thumb
    /// travels away from the palm: the nearest row is the cheapest to reach, and
    /// "put it back to normal" is the one selection a user makes under mild
    /// frustration.
    ///
    /// The pinned list is capped defensively as well as at the store, because this
    /// is the side that cannot draw more.
    ///
    /// ### Why the armed mode is an input to a list it never appears in
    ///
    /// It decides whether a Normal-only fan is worth opening, and #402 is what
    /// happens when that question is answered somewhere else. With nothing pinned
    /// and nothing armed, a one-row fan is a menu with one item, no way to learn
    /// what the others are, and nothing to undo — the user is better served by
    /// being told where the mode list lives. With nothing pinned but a mode
    /// **armed**, that same one row is the only surface in the product that clears
    /// it: releasing back on the mic aborts, so the mic is not the way out. A user
    /// who unpins everything while "→ DE" is armed otherwise dictates German
    /// forever, which is the bug as Pierre hit it on device.
    ///
    /// ### Why an empty array rather than a second return type
    ///
    /// A fan with no rows is not a state `SmartModeFanState` is allowed to hold —
    /// its own doc comment says so — so "no rows" already means "do not open" for
    /// everything downstream, and `rowHeight` and `entryIndex` already answer 0 and
    /// nil for it. Wrapping that in an enum would name the same thing twice.
    ///
    /// `armed` is the resolved record, not the stored identifier: an identifier this
    /// build cannot resolve reads as nil, and refusing on it is right — that user is
    /// already getting Normal, so there is nothing to escape from.
    ///
    /// ### The non-subscriber's fan keeps the shape everyone else's has (#404)
    ///
    /// `Normal`, the default-pinned modes, and a `Dictus Pro` row — **four rows, the
    /// same four slots a subscriber sees**. A single full-height Dictus Pro row was
    /// built first, from #392's thread, and re-decided on device on 2026-08-29 for
    /// three reasons, of which the aesthetic one was the smallest:
    ///
    /// - **It removed the only way to dictate.** With one row there is no `Normal`,
    ///   so a non-subscriber who opened the fan could not start a recording from it
    ///   at all: releasing on the Pro row leaves for the app, releasing back on the
    ///   mic is the documented abort. A lost function, not a style preference.
    /// - **"Dictus Pro" advertises nothing.** `Liste` and `→ EN` greyed under their
    ///   real names say what the subscription buys; the product's own name does not.
    /// - **It was two different screens for one object.** Subscribing should
    ///   *un-grey* this fan, not replace it with a surface the user has to learn
    ///   twice.
    ///
    /// **It opens whatever is pinned or armed**, which is the decision #404 left open
    /// about #403's armed-mode-alone fan, and it is safe for the same reason it was
    /// when this was one row: a user without entitlement is *already* getting Normal,
    /// because `resolveArmedMode()` refuses to honour a mode without it (#395).
    /// #402's stranding needs a mode that is actually applying. The armed value
    /// survives untouched and comes back with the subscription — and now, unlike in
    /// the one-row shape, the `Normal` row is there to release on regardless.
    ///
    /// The no-dead-space rule below is untouched: rows still divide the area evenly
    /// and completely. It never required *one* row, only that the rows fill the area.
    ///
    /// The caller decides whether the offer is on, because it also owes the #236
    /// gate: while the paywall is hidden there is nothing to sell and a row leading
    /// to it is a dead end.
    public static func entries(pinned: [SmartMode],
                               armed: SmartMode?,
                               offersProUpgrade: Bool = false) -> [SmartModeFanEntry] {
        if offersProUpgrade {
            // Normal and Dictus Pro take one slot each; whatever is left goes to modes.
            let modeSlots = max(0, maximumEntries - 2)
            return [.normal]
                + SmartModeCatalogue.defaultPinnedModes.prefix(modeSlots).map(SmartModeFanEntry.mode)
                + [.pro]
        }
        guard !pinned.isEmpty || armed != nil else { return [] }
        return [.normal] + pinned.prefix(SmartModeCatalogue.maximumPinnedModes).map(SmartModeFanEntry.mode)
    }

    /// What `entry` is tagged with, or nil when it carries nothing.
    ///
    /// The precedence is the whole of this function and each step is a decision:
    ///
    /// 1. **The Dictus Pro row carries no tag.** It is not a mode and nothing about it
    ///    is conditional; its own chevron says what it does.
    /// 2. **What will run wins.** In the non-subscriber's fan that is `Normal`, and it
    ///    must still read as the current selection — the row is releasable and starts a
    ///    recording like anyone else's.
    /// 3. **`PRO` beats `INACTIF`.** Both would be true of an armed mode belonging to
    ///    someone who never subscribed, and only one of them tells them anything they
    ///    can act on. #404 states it as the rule: `INACTIF` for a subscriber who
    ///    switched Smart Modes off, `PRO` for someone who has not subscribed.
    /// 4. **`INACTIF` last**, for the armed mode that survived a condition it cannot run
    ///    under (#423).
    public static func tag(for entry: SmartModeFanEntry,
                           armedIdentifier: String?,
                           effectiveIdentifier: String,
                           modesRequirePro: Bool) -> SmartModeFanRowTag? {
        if case .pro = entry { return nil }
        if entry.id == effectiveIdentifier { return .effective }
        if modesRequirePro, entry.smartMode != nil { return .pro }
        if entry.id == armedIdentifier { return .inactive }
        return nil
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
