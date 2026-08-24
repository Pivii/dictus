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

    /// Why no mode may be armed, or nil when they all may. When set, every mode row
    /// draws disabled and this sentence sits under them; Normal stays live.
    let unavailableReason: String?

    /// Whether a release on the highlighted row would arm anything.
    var canCommitHighlighted: Bool {
        guard let highlightedIndex, entries.indices.contains(highlightedIndex) else { return false }
        // Normal is always selectable: it is the free polish, and it is how a sticky
        // mode is cleared on a device that has since lost Apple Intelligence.
        guard entries[highlightedIndex].smartMode != nil else { return true }
        return unavailableReason == nil
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

    /// Display name of the armed Smart Mode, or nil for Normal.
    ///
    /// A denormalised copy of `SmartModeStore.armedMode?.displayName`, published so
    /// the toolbar's centre slot and the recording overlay redraw when it changes.
    /// Refreshed by `refresh(status:)` rather than read per body evaluation:
    /// iOS keeps ~9 root views alive, and each would otherwise hit `UserDefaults` on
    /// every layout pass.
    @Published private(set) var armedName: String?

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
        armedName = SmartModeStore.armedMode?.displayName
        offersHint = SmartModeDiscovery.offersHint
        if status.ownsKeyboardArea { fan = nil }
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
    /// **Nothing is pinned.** A fan holding only Normal is a menu with one item and
    /// no way to learn what the others are. The user is told where the list lives
    /// instead. Only reachable by unpinning everything in the app — a fresh install
    /// seeds two (`SmartModeCatalogue.defaultPinnedIdentifiers`).
    @discardableResult
    func open() -> Bool {
        let keyboard = KeyboardState.shared
        guard !keyboard.dictationStatus.ownsKeyboardArea else {
            keyboard.logProbe("smartModeFanRefused", details: "reason=dictation-in-flight")
            return false
        }
        let pinned = SmartModeCatalogue.pinnedModes
        guard !pinned.isEmpty else {
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
        // Read once, at open. The armability of a mode cannot change between the
        // long-press and the release a second later, and re-reading it per drag
        // update would put a `SystemLanguageModel` availability check on the main
        // thread inside a gesture.
        let armability = SmartModeAvailability.current
        fan = SmartModeFanState(
            entries: SmartModeFanLayout.entries(pinned: pinned),
            highlightedIndex: nil,
            unavailableReason: armability.reason.map(Self.localizedReason)
        )
        keyboard.presentAreaMode(.smartModeFan)
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
        current.highlightedIndex = index
        fan = current
        HapticFeedback.keyTapped()
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
            if let reason = current.unavailableReason, current.highlightedIndex != nil {
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
        if let mode = entry.smartMode {
            SmartModeStore.arm(mode)
        } else {
            SmartModeStore.disarm()
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
    static func localizedReason(_ reason: SmartModeUnavailableReason) -> String {
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
        case .other:
            return String(
                localized: "Smart Modes are unavailable right now.",
                comment: "Shown in the Smart Mode fan for an unavailability reason this build does not recognise."
            )
        }
    }
}
