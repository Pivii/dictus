// DictusKeyboard/KeyboardSmartModeFan.swift
// The long-press fan's state, in the process that owns the gesture (issue #79).
import Foundation
import SwiftUI
import DictusCore

/// What the fan is showing, as one value.
///
/// Grouped rather than three published properties because they are only ever read
/// together and only ever written together: a fan that is open with no entries, or
/// highlighting row 2 of a list that has one, is not a state anything should be able
/// to express.
struct SmartModeFanState: Equatable {

    /// The rows, Normal first.
    let entries: [SmartModeFanEntry]

    /// Which row the finger is on, or nil when it is on none — back up on the mic,
    /// or down in the reason strip. Nil is the abort.
    var highlightedIndex: Int?

    /// The sentence under the rows, or nil when there is none.
    ///
    /// Nil in the non-subscriber's fan even though modes are refused there: the
    /// `Dictus Pro` row *is* the message, and a strip repeating it would say the same
    /// thing twice and take height from four rows that need it (#404). It is what
    /// decides the geometry — `SmartModeFanLayout.rowHeight(showsReason:)` — so it
    /// must not be repurposed as "are the modes disabled". That is `modesAreArmable`.
    let unavailableReason: String?

    /// What the toolbar says when a release lands on a mode row that cannot be armed.
    ///
    /// Separate from `unavailableReason` for one case: in the non-subscriber's fan
    /// there is no strip, and a release on a greyed `Liste` still has to be answered
    /// with something. Everywhere else the two are the same string.
    let refusalMessage: String?

    /// Whether a mode row may be armed at all.
    ///
    /// Was inferred from `unavailableReason != nil` until #404, which is where the two
    /// stopped meaning the same thing: the Pro fan refuses every mode and shows no
    /// sentence. Leaving it inferred would have made those rows armable.
    let modesAreArmable: Bool

    /// The row the stored armed mode corresponds to, or nil for Normal.
    ///
    /// Drawn as a marker, so the user can see their choice survived (#423). Separate
    /// from `effectiveEntryID` below because the two disagree exactly when this issue
    /// bites: the mode is armed, and Normal is what will run.
    let armedEntryID: String?

    /// The row a dictation started right now would actually run.
    ///
    /// `"normal"` whenever the armed mode will not be honoured, because that is the
    /// truth — greying the mode row says "you cannot pick this", not "the thing you
    /// already picked will not happen", and only the second is the case.
    let effectiveEntryID: String

    /// Whether the fan is the non-subscriber's, i.e. whether its mode rows are behind
    /// Dictus Pro.
    ///
    /// Derived from the rows rather than stored beside them, so the tag and the row it
    /// sits on cannot disagree.
    var offersProUpgrade: Bool { entries.contains(.pro) }

    /// What `entry` carries beside its name, if anything.
    func tag(for entry: SmartModeFanEntry) -> SmartModeFanRowTag? {
        SmartModeFanLayout.tag(
            for: entry,
            armedIdentifier: armedEntryID,
            effectiveIdentifier: effectiveEntryID,
            modesRequirePro: offersProUpgrade
        )
    }

    /// Whether a release on the highlighted row would do anything.
    var canCommitHighlighted: Bool {
        guard let highlightedIndex, entries.indices.contains(highlightedIndex) else { return false }
        switch entries[highlightedIndex] {
        // Normal is always selectable: it is the free polish, it is how a sticky mode
        // is cleared on a device that has since lost Apple Intelligence, and in the
        // non-subscriber's fan it is the only row that records at all (#404).
        case .normal: return true
        // The Pro row leads to the paywall. Nothing about it is conditional.
        case .pro: return true
        case .mode: return modesAreArmable
        }
    }
}

/// Everything the keyboard knows about Smart Modes: the armed mode's name, whether
/// the toolbar still teaches the gesture, and the fan while it is open.
///
/// ### Why a separate object rather than four properties on `KeyboardState`
///
/// The same argument `KeyboardPolishStage.swift` makes and one more. `KeyboardState`
/// sits at SwiftLint's `type_body_length` budget with a single line of headroom, so
/// four new stored properties do not fit — and unlike the polish stage, none of this
/// has to live over there: the fan is opened, drawn and released entirely within the
/// keyboard's own UI, and the only thing it needs from the dictation state machine is
/// `startRecording()`. `KeyboardWaveformDriver.shared` is the existing precedent for
/// a second observed object beside `KeyboardState` in `KeyboardRootView`.
@MainActor
final class KeyboardSmartModeState: ObservableObject {

    static let shared = KeyboardSmartModeState()

    private init() {}

    /// The fan, or nil when it is closed.
    @Published private(set) var fan: SmartModeFanState?

    /// The armed Smart Mode, or nil for Normal.
    ///
    /// A published copy of `SmartModeStore.armedMode`, so the toolbar's centre slot,
    /// the mic pill's badge and the recording overlay redraw when it changes.
    /// Refreshed by `refresh(status:)` rather than read per body evaluation:
    /// iOS keeps ~9 root views alive, and each would otherwise hit `UserDefaults` on
    /// every layout pass.
    ///
    /// The whole record rather than the two or three fields the views want: those
    /// fields have already gone from one to three in this issue alone (name, then
    /// icon, then badge), and three parallel published properties written in one
    /// statement is a struct with extra steps.
    @Published private(set) var armedMode: SmartMode?

    /// The armed mode **when a dictation starting now would actually run it**, and
    /// nil otherwise (#423).
    ///
    /// The surfaces that claim a mode is in force read this one, not `armedMode`
    /// above: the mic pill's corner badge and the recording overlay's capsule. Both
    /// are assertions about what the next dictation does, and drawing them from the
    /// stored value made them lie whenever the dictation had already decided to skip
    /// it — a badge saying EN over a dictation that returns French.
    ///
    /// `armedMode` stays beside it and is still drawn, greyed, by the toolbar's
    /// centre slot: the user's choice survived and hiding it would be a different
    /// lie. Armed and effective are two facts, so they are two properties.
    ///
    /// Resolved through `SmartModeAvailability.forDictation`, which is the same
    /// expression `SmartModeStore.resolveArmedMode()` consults. That is the point:
    /// the two cannot disagree.
    @Published private(set) var effectiveMode: SmartMode?

    /// Whether the toolbar's centre slot still teaches the long-press gesture.
    ///
    /// Cached for a harder reason than `armedName`: `SmartModeDiscovery.offersHint`
    /// reaches `SystemLanguageModel.default.availability`, and a body-time read would
    /// put that on the main thread nine times per layout pass — for a line of text
    /// that changes about twice in a device's lifetime.
    @Published private(set) var offersHint = false

    /// Height of the area the fan draws into, i.e. everything below the toolbar.
    ///
    /// Written by `KeyboardViewController.applyLayout` in the same synchronous turn
    /// that grows the hosting constraint, so it is correct before the first drag
    /// update arrives. Not published and not read by any view: it exists so the
    /// y-to-row mapping can be done against the height the *layout* actually used
    /// rather than one SwiftUI has measured — during the frame the fan opens those
    /// are not yet the same number, and a row chosen against the stale one would be
    /// the wrong row.
    var areaHeight: CGFloat = 0

    /// Closes a fan whose gesture never ended.
    ///
    /// The fan hides the keys, so a fan that outlives its finger is a keyboard the
    /// user cannot type on — the worst failure available to a menu. SwiftUI does not
    /// call `onEnded` on a *cancelled* touch, only on a released one, and a keyboard
    /// extension is somewhere touches get cancelled: the host app can present a
    /// sheet, iOS can hand the keyboard to another controller mid-press.
    ///
    /// Eight seconds because a long-press-and-choose is over in about two, and
    /// reading four rows does not take four times that. If it fires under a finger
    /// that is still down, the release lands on a nil fan and does nothing — the
    /// gesture is abandoned, not misread.
    private var idleTimer: Timer?
    private static let idleTimeout: TimeInterval = 8

    // MARK: - Refreshing

    /// Re-read the armed mode and the hint policy, and drop a fan a dictation has
    /// taken the area from.
    ///
    /// Called from `KeyboardState.refreshFromDefaults`, deliberately *before* its
    /// reconcile guard can return early: the armed mode is a sticky setting the app
    /// can change — block C's mode list unpins and repins — and it has nothing to do
    /// with whether this dictation was abandoned.
    ///
    /// A plain read (`armedMode`), never `resolveArmedMode()`: this draws a surface,
    /// and the resolve is allowed to disarm. That distinction is `SmartModeStore`'s
    /// stated contract and this is the call site it was written for.
    ///
    /// Dropping the fan here is not cosmetic. It is a live gesture, and one that
    /// survived into a recording would still hold a highlighted row when the overlay
    /// came down — a release then would arm a mode chosen before the dictation the
    /// user has since finished.
    func refresh(status: DictationStatus) {
        let armed = SmartModeStore.armedMode
        armedMode = armed
        // One availability read per refresh, beside the one `offersHint` already
        // pays for, and for the same reason it is cached there: nine live root views
        // would otherwise hit `SystemLanguageModel.availability` on every layout pass.
        let dictation = SmartModeAvailability.forDictation
        effectiveMode = dictation.isArmable ? armed : nil
        // The hint teaches the long press, so it goes when the long press stops opening
        // anything (#460). Resolved from the read above rather than from a third
        // availability check: the two differ only in the #315 latch, which cannot make a
        // fan reachable or unreachable.
        offersHint = SmartModeDiscovery.offersHint(
            deviceCanRunModes: SmartModeAvailability.deviceCanRunModes,
            fanIsReachable: SmartModeSurface.fanEntryPoint(
                reason: dictation.reason, paywallVisible: PremiumFlags.paywallVisible
            ) != .hidden
        )
        // Through `close()` rather than by clearing the value, so the backstop timer
        // goes with it. `presentAreaMode` refuses while a dictation owns the area,
        // which is the correct no-op here — the overlay already has the area.
        if status.ownsKeyboardArea { close() }
    }

    // MARK: - Opening

    /// Open the fan, unless there is nothing to open it onto.
    ///
    /// Called from the mic's long-press, before any drag. Returns whether the fan
    /// opened, so the gesture can decide not to arm itself on a refusal.
    ///
    /// ### The two refusals
    ///
    /// **A dictation is in flight.** `presentAreaMode` already refuses to displace
    /// the recording overlay, but the gesture has to know: opening a fan that never
    /// appears and then arming a mode on release would change a setting the user
    /// never saw a menu for.
    ///
    /// **Nothing is pinned, and nothing is armed.** A fan holding only Normal is a
    /// menu with one item, no way to learn what the others are, and nothing to
    /// undo. The user is told where the list lives instead. Only reachable by
    /// unpinning everything in the app — a fresh install seeds two
    /// (`SmartModeCatalogue.defaultPinnedIdentifiers`).
    ///
    /// Both halves of that condition matter, and #402 is the bill for checking only
    /// the first: with a mode armed, the Normal row is the one surface that clears
    /// it, so the fan opens on it alone. `SmartModeFanLayout.entries` owns the rule
    /// and states it at length; an empty result is the refusal.
    ///
    /// **Nothing is on sale.** With `PremiumFlags.paywallVisible` down and no
    /// subscription, the whole surface is absent rather than locked — the rule
    /// `HistoryAvailability` already applies to the transcription history (#460).
    /// Nobody loses a feature: no subscription can be bought while the flag is down,
    /// so nobody is entitled, so nothing is being taken from someone who paid. This
    /// refusal is silent — not even the "pick your modes" line below, which would
    /// point at a screen the app does not offer either.
    ///
    /// All three refusals return **before** `presentAreaMode`, which is what keeps
    /// them out of the keyboard's declared height constraint (#166): the area mode
    /// never becomes `.smartModeFan`, so no layout pass is asked for.
    @discardableResult
    func open() -> Bool {
        let keyboard = KeyboardState.shared
        guard !keyboard.dictationStatus.ownsKeyboardArea else {
            keyboard.logProbe("smartModeFanRefused", details: "reason=dictation-in-flight")
            return false
        }
        // Read once, at open. The armability of a mode cannot change between the
        // long-press and the release a second later, and re-reading it per drag
        // update would put a `SystemLanguageModel` availability check on the main
        // thread inside a gesture.
        let armability = SmartModeAvailability.current
        let entryPoint = SmartModeSurface.fanEntryPoint(
            reason: armability.reason, paywallVisible: PremiumFlags.paywallVisible
        )
        guard entryPoint != .hidden else {
            keyboard.logProbe("smartModeFanRefused", details: "reason=paywall-hidden")
            return false
        }
        // The store rather than the published `armedMode` beside it: that copy is a
        // cache for view bodies and can be one `refreshFromDefaults` behind the app,
        // and the app unpinning everything is exactly the moment it would be. One
        // read per long-press is not the cost that cache exists to avoid.
        let armed = SmartModeStore.armedMode
        // The row and the sentence answer the same question — is Dictus Pro on sale to
        // this user today — so they read it from the same expression (#460). Splitting
        // them is what let the flag remove the row and leave the sentence.
        let offersPro = SmartModeSurface.sellsPro(
            reason: armability.reason, paywallVisible: PremiumFlags.paywallVisible
        )
        let entries = SmartModeFanLayout.entries(
            pinned: SmartModeCatalogue.pinnedModes, armed: armed, offersProUpgrade: offersPro
        )
        guard !entries.isEmpty else {
            keyboard.logProbe("smartModeFanRefused", details: "reason=nothing-pinned")
            keyboard.presentStatusMessage(
                String(
                    localized: "Pick your Smart Modes in Dictus.",
                    comment: "Shown when the long-press fan is opened with no modes pinned."
                ),
                reason: "smartModeFan-empty",
                timeoutReason: "smartModeFan-empty-timeout"
            )
            return false
        }
        let reason = armability.reason.map { Self.localizedReason($0, sellsPro: offersPro) }
        fan = SmartModeFanState(
            entries: entries,
            highlightedIndex: nil,
            // The Dictus Pro row carries the message in the non-subscriber's fan, so
            // the strip would say the same thing twice and take height from four rows
            // that need it (#404).
            unavailableReason: offersPro ? nil : reason,
            refusalMessage: reason,
            modesAreArmable: armability.isArmable,
            armedEntryID: armed?.id,
            // What will run, not what is set. With no entitlement that is Normal
            // whatever is armed, which is the fact #423 says nothing was telling
            // the user.
            effectiveEntryID: SmartModeAvailability.forDictation.isArmable
                ? (armed?.id ?? SmartModeFanEntry.normal.id)
                : SmartModeFanEntry.normal.id
        )
        keyboard.presentAreaMode(.smartModeFan)
        armIdleTimer()
        HapticFeedback.keyTapped()
        keyboard.logProbe(
            "smartModeFanOpened",
            details: "entries=\(fan?.entries.count ?? 0) reason=\(armability.reason?.slug ?? "-")"
        )
        return true
    }

    // MARK: - Dragging

    /// Track the finger, in the fan area's own coordinates.
    ///
    /// `y` is measured from the top of the fan — the point directly below the
    /// toolbar — so a negative value is the finger back up on the mic. That is the
    /// documented abort, and it arrives here as a nil highlight rather than as a
    /// special case: everywhere that is not a row means the same thing.
    func track(y: CGFloat) {
        guard let fan else { return }
        highlight(SmartModeFanLayout.entryIndex(
            atY: y,
            availableHeight: areaHeight,
            entryCount: fan.entries.count,
            showsReason: fan.unavailableReason != nil
        ))
    }

    /// Move the highlight, with a selection haptic on every change.
    ///
    /// The haptic is the whole of the feedback while the thumb covers the row it is
    /// choosing — which it does, on a downward drag from a top-right mic — so it
    /// fires on entering *and* on leaving the rows, including into the abort.
    func highlight(_ index: Int?) {
        guard var current = fan, current.highlightedIndex != index else { return }
        armIdleTimer()
        current.highlightedIndex = index
        fan = current
        HapticFeedback.keyTapped()
    }

    /// (Re)start the backstop. Every drag update pushes it out, so it only ever
    /// fires on a gesture that has genuinely stopped reporting.
    private func armIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(
            withTimeInterval: Self.idleTimeout, repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.fan != nil else { return }
                    KeyboardState.shared.logProbe("smartModeFanTimedOut")
                    self.close()
                }
            }
        }
    }

    // MARK: - Releasing

    /// Release: arm what the finger is on and start recording, or abort.
    ///
    /// **The release is the whole commitment**, which is #79's design and Typeless's
    /// gesture: arming and starting are one action, so the common case — arm a mode,
    /// say the thing — costs one gesture rather than a gesture and then a tap.
    ///
    /// Aborting is deliberately silent and total: no mode change, no recording, no
    /// message. The user pulled back, and a keyboard that announced every abandoned
    /// gesture would be unbearable.
    func commit() {
        guard let current = fan else { return }
        let keyboard = KeyboardState.shared
        defer { close() }

        guard current.canCommitHighlighted,
              let index = current.highlightedIndex,
              current.entries.indices.contains(index) else {
            // Includes the release on a disabled mode row, which gets the refusal
            // haptic and the reason: the user did point at something, and was told
            // no. The reason is already on screen under the rows, but the fan is
            // about to close, so it moves to the toolbar.
            if let reason = current.refusalMessage, current.highlightedIndex != nil {
                HapticFeedback.actionRefused()
                keyboard.presentStatusMessage(
                    reason,
                    reason: "smartModeFan-unavailable",
                    timeoutReason: "smartModeFan-unavailable-timeout"
                )
            }
            keyboard.logProbe(
                "smartModeFanAborted",
                details: "highlight=\(current.highlightedIndex.map(String.init) ?? "none")"
            )
            return
        }

        let entry = current.entries[index]
        // Switched over the case rather than over `entry.smartMode`, which is nil for
        // two rows that mean opposite things: reading nil as "disarm" would have the
        // Pro row silently clear the user's mode on its way to the paywall.
        switch entry {
        case .pro:
            // The release leaves the keyboard **for the paywall** instead of arming
            // anything (#404). It landed on the app's home screen until 2026-08-29,
            // which emptied the row of its purpose — the one row in the fan that leads
            // anywhere led somewhere the user then had to search.
            //
            // No `noteGestureUsed`: nothing was armed, and retiring the discovery hint
            // for a user who has still never chosen a mode would take away the only
            // thing pointing them back here. Whether the hint should point a
            // non-subscriber at this gesture at all is #404's own open question,
            // deliberately untouched.
            keyboard.logProbe("smartModeFanProSelected")
            // Put the keys back *before* leaving, which is what `leavePanel` in
            // `KeyboardRootView` does and for the same reason: coming back to a
            // keyboard still showing the menu you left is disorienting, and the task
            // that opened it is over. `close()` is idempotent, so the `defer` above
            // finds nothing to do.
            close()
            keyboard.openDictusApp(intent: .pro)
            return
        case .normal:
            SmartModeStore.disarm()
        case .mode(let mode):
            SmartModeStore.arm(mode)
        }
        SmartModeDiscovery.noteGestureUsed()
        refresh(status: keyboard.dictationStatus)
        keyboard.logProbe("smartModeArmed", details: "mode=\(entry.smartMode?.id ?? "normal")")

        // Recording starts through the same entry point the mic tap uses, debounce
        // and all. A gesture refused there leaves the mode armed and the user taps
        // the mic — the arming is the durable half, and re-doing the long-press to
        // recover a swallowed tap would be the worse outcome.
        keyboard.startRecording()
    }

    /// Put the keys back without arming anything. Also the path a cancelled gesture
    /// and a controller rebuilt mid-gesture both take.
    func close() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard fan != nil else { return }
        fan = nil
        // `presentAreaMode` refuses while a dictation owns the area, which is exactly
        // right here: `commit()` starts one, and the fan must not put the keys back
        // over the recording overlay it just summoned.
        KeyboardState.shared.presentAreaMode(.keys)
    }

    // MARK: - Copy

    /// The user-facing sentence for an unavailability reason.
    ///
    /// `SmartModeUnavailableReason.englishDescription` exists and is deliberately not
    /// used here: DictusCore ships no string catalog, so its copy is the log form and
    /// the fallback. The surface owns its translation, keyed on the case — which is
    /// what that property's own doc comment asks the surface to do.
    ///
    /// - Parameter sellsPro: `SmartModeSurface.sellsPro(reason:paywallVisible:)`.
    ///   No default, which is the point of the parameter: #460 exists because this
    ///   function answered `.notSubscribed` with a sentence naming a product that
    ///   could not be bought, and a default would let the next caller do it again.
    ///   The compiler asks instead.
    static func localizedReason(_ reason: SmartModeUnavailableReason,
                                sellsPro: Bool) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return String(
                localized: "Smart Modes need Apple Intelligence. Turn it on in Settings.",
                comment: "Shown in the Smart Mode fan when Apple Intelligence is switched off."
            )
        case .modelNotReady:
            return String(
                localized: "Apple Intelligence is still downloading. Smart Modes will work once it finishes.",
                comment: "Shown in the Smart Mode fan while the on-device model is downloading."
            )
        case .deviceNotEligible:
            return String(
                localized: "Smart Modes need Apple Intelligence, which this iPhone does not support.",
                comment: "Shown in the Smart Mode fan on hardware that cannot run Apple Foundation Models."
            )
        case .osTooOld:
            return String(
                localized: "Smart Modes need iOS 26 or later.",
                comment: "Shown in the Smart Mode fan when the OS predates Apple Foundation Models."
            )
        case .sdkMissing:
            return String(
                localized: "Smart Modes are not available in this build.",
                comment: "Shown in the Smart Mode fan when the build has no FoundationModels SDK."
            )
        case .engineRefusing:
            return String(
                localized: "Apple Intelligence is busy right now. Smart Modes will come back shortly.",
                comment: "Shown in the Smart Mode fan while the process is rate-limited."
            )
        case .notSubscribed:
            // Nothing is on sale, so nothing may be advertised (#460). Unreachable in
            // practice — with `sellsPro` false the fan does not open at all, so there is
            // no strip and no refusal to answer — and written anyway, because "no caller
            // reaches it" is a property of today's call sites and this is a property of
            // the function. It falls through to the sentence that claims nothing rather
            // than to silence: whatever asked has a line to draw.
            guard sellsPro else { return Self.unavailableNow }
            // The one reason here with a remedy the user can act on today, and the
            // only one that is not about the device. It gets a sentence rather than
            // the control it deserves because the fan handles no touches at all —
            // the Dictus Pro row is the control, and it is a row precisely because a
            // button inside the fan would take the drag from the recogniser (#404).
            return String(
                localized: "Smart Modes are part of Dictus Pro.",
                comment: "Shown in the Smart Mode fan when the device can run Smart Modes but the user has no Pro subscription."
            )
        case .switchedOff:
            // The user did this on purpose, so the sentence names the switch rather
            // than the feature: nothing is broken and nothing is for sale here
            // (#423). Split out of `.notSubscribed`, which used to answer for both
            // and told a paying subscriber their own setting was a paywall.
            return String(
                localized: "Smart Modes are off. Turn them back on in Dictus.",
                comment: "Shown in the Smart Mode fan when a subscriber has switched Smart Modes off in Settings."
            )
        case .other:
            return Self.unavailableNow
        }
    }

    /// The sentence that names no cause: an unavailability the user can neither act on
    /// nor be sold a way out of.
    ///
    /// Shared by `.other` and by `.notSubscribed` while nothing is on sale (#460),
    /// which is not a coincidence — from the user's side those are the same situation,
    /// a feature that is not there and nothing to do about it.
    private static var unavailableNow: String {
        String(
            localized: "Smart Modes are unavailable right now.",
            comment: "Shown in the Smart Mode fan for an unavailability reason this build does not recognise."
        )
    }

    /// The sentence shown after a dictation whose armed mode did not run (#423).
    ///
    /// One per reason the user can be in, because "it went in as Normal" without the
    /// why is only half of what they need — and the wrong why is worse than none:
    /// telling someone who switched the feature off that it "is part of Dictus Pro"
    /// is the exact defect `SmartModeUnavailableReason.switchedOff` was split out to
    /// fix.
    ///
    /// **None of them reads as a failure.** No "failed", no "error", no "try again":
    /// nothing failed, the text is in the field, and the only thing missing is a
    /// transformation the user's own state ruled out. The mode name is the
    /// catalogue's label rather than a description, so it reads as the thing they
    /// armed.
    ///
    /// The definitive reasons are absent on purpose. `resolveArmedMode()` disarms on
    /// those, so the mode is gone and there is no standing setting to explain —
    /// they fall through to the last sentence, which claims nothing about the future.
    ///
    /// - Parameter sellsPro: `SmartModeSurface.sellsPro(reason:paywallVisible:)`, and
    ///   the reason this is the harder of the two copy paths to get right. Unlike the
    ///   fan's reason line, this sentence is **not** made unreachable by the fan
    ///   refusing to open: the notice is resolved in DictusApp and crosses the App
    ///   Group, so a mode armed before the entitlement went away still produces one.
    ///   With nothing on sale it takes the sentence that names no cause (#460).
    static func localizedSkipNotice(_ notice: SmartModeSkipNotice,
                                    sellsPro: Bool) -> String {
        let name = SmartMode.localizedDisplayName(
            identifier: notice.modeIdentifier, fallback: notice.modeDisplayName
        )
        switch notice.reason {
        case .switchedOff:
            return String(
                localized: "Smart Modes are off. \(name) was dictated as Normal.",
                comment: "Shown after a dictation whose armed Smart Mode did not run because the user switched Smart Modes off. The placeholder is the mode's name."
            )
        case .notSubscribed:
            // Same gate as the reason line, and here it is load-bearing rather than
            // defensive (#460): this path survives the fan being hidden.
            guard sellsPro else { return Self.unavailableSkip(name) }
            return String(
                localized: "\(name) needs Dictus Pro. Dictated as Normal.",
                comment: "Shown after a dictation whose armed Smart Mode did not run for lack of a Pro subscription. The placeholder is the mode's name."
            )
        case .appleIntelligenceNotEnabled:
            return String(
                localized: "Apple Intelligence is off. \(name) was dictated as Normal.",
                comment: "Shown after a dictation whose armed Smart Mode did not run because Apple Intelligence is switched off. The placeholder is the mode's name."
            )
        case .modelNotReady:
            return String(
                localized: "Apple Intelligence is still downloading. \(name) was dictated as Normal.",
                comment: "Shown after a dictation whose armed Smart Mode did not run because the on-device model is still downloading. The placeholder is the mode's name."
            )
        case .engineRefusing, .other, .deviceNotEligible, .osTooOld, .sdkMissing:
            return Self.unavailableSkip(name)
        }
    }

    /// The skip sentence that names no cause, for a mode the user can neither run nor
    /// buy their way into. The counterpart of `unavailableNow`, one rung further along:
    /// the dictation has already happened, so it says what went in.
    private static func unavailableSkip(_ name: String) -> String {
        String(
            localized: "\(name) is unavailable. Dictated as Normal.",
            comment: "Shown after a dictation whose armed Smart Mode did not run for a reason the user cannot act on. The placeholder is the mode's name."
        )
    }
}
