// DictusKeyboard/Views/ToolbarView.swift
import SwiftUI
import DictusCore

/// Toolbar displayed above the keyboard with app shortcut and AnimatedMicButton.
/// Inspired by Wispr Flow -- the mic button is the primary dictation trigger.
///
/// WHY AnimatedMicButton replaces inline micIcon:
/// AnimatedMicButton provides 4 visual states (idle glow, recording pulse,
/// transcribing shimmer, success flash) that give the user clear feedback
/// about the dictation lifecycle. The inline micIcon only had basic color changes.
///
/// The bar has two presentations (#241) and keeps its 52 pt in both, so opening
/// the panel is a content swap and not a resize. In an area that has produced four
/// layout regressions (#166 and family), that property matters more than anything
/// else in the design:
///
///     closed:  [☰]  ← centre slot →  [🎤 pill]
///     open:    [✕]                   [Dictus Pro] [⚙]
///
/// There is deliberately no mic while the panel is open: the panel is not a
/// surface anyone dictates from, and the mic's absence is what makes the state
/// unambiguous.
struct ToolbarView: View {
    let hasFullAccess: Bool
    let dictationStatus: DictationStatus
    var onMicTap: () -> Void

    // Suggestion bar integration parameters (default to idle/empty)
    var statusMessage: String?

    /// Identity carried purely so the status message's rendering can be attributed
    /// to a view and a controller in the exported log (#261). Defaulted, so a call
    /// site that does not care is unaffected; both current call sites supply them.
    var messageProbeRootViewID: String = "unknown"
    var messageProbeControllerID: String = "unknown"

    /// Whether polish has stopped calling its engine for the rest of DictusApp's
    /// process (#315). Declared next to `statusMessage` because it is the bar's
    /// other way of saying something went wrong, and the opposite kind of thing:
    /// a state, not a message. It carries no timer, is not dismissed, and goes
    /// away only when a fresh app process clears it.
    var showsPolishUnavailable: Bool = false

    var suggestions: [String] = []
    var suggestionMode: SuggestionMode = .idle
    var onSuggestionTap: ((Int) -> Void)?

    /// Whether the last dictation insertion can still be undone (#266).
    /// Transient by construction: it is set for a few seconds after an insertion
    /// and only while the inserted text is verifiably still the tail of the field.
    var showsDictationUndo: Bool = false

    /// Removes the last dictation insertion. Re-checks the field before deleting.
    var onDictationUndoTap: (() -> Void)?

    /// Whether the hamburger panel currently fills the keyboard area (#241).
    /// Drives which of the two presentations above the bar renders.
    var isPanelOpen: Bool = false

    /// Opens the panel from the hamburger, closes it from the ✕. Same callback:
    /// both are the same control in the same 32 pt slot, just labelled by state.
    var onPanelToggle: (() -> Void)?

    /// Gear, panel presentation only. Opens DictusApp.
    var onSettingsTap: (() -> Void)?

    /// Hides the Pro entry. Read once when the panel opens rather than observed:
    /// a subscription cannot change while the keyboard is the frontmost surface.
    var isProActive: Bool = false

    /// Pro entry, panel presentation only. Non-subscribers only.
    var onProTap: (() -> Void)?

    /// The armed Smart Mode, or nil for Normal (#79). Drives the centre slot's
    /// priority-4 occupant and the mic pill's corner badge.
    var armedSmartMode: SmartMode?

    /// Whether the "long-press for Smart Modes" hint is still worth showing. The
    /// policy is `SmartModeDiscovery`'s; this is only the answer.
    var offersSmartModeHint: Bool = false

    /// Opens the long-press fan. Returns whether it opened — a refusal (a dictation
    /// in flight, nothing pinned) leaves the gesture inert rather than arming on a
    /// menu the user never saw.
    var onSmartModeFanOpen: (() -> Bool)?

    /// Reports the finger's position while the fan is open, in points below the
    /// toolbar. Negative means back up on the mic.
    var onSmartModeFanDrag: ((CGFloat) -> Void)?

    /// Release: arm what is highlighted and start recording, or abort.
    var onSmartModeFanRelease: (() -> Void)?

    /// Whether the fan is on screen right now.
    ///
    /// Guards re-entry into `onSmartModeFanOpen`, and it is deliberately the *state*
    /// rather than `fanGestureDidOpen`: the fan's idle backstop can close it while
    /// the finger is still down, and a guard on the flag would leave the long press
    /// inert from then on.
    var isSmartModeFanOpen: Bool = false

    /// Coordinate space the fan gesture reports in. Declared here and named by
    /// `KeyboardRootView`, which owns the view it is attached to: the drag has to be
    /// measured against the whole keyboard area, not against the 52 pt bar the
    /// gesture starts in.
    static let fanCoordinateSpace = "dictusKeyboardArea"

    /// Set the moment the long-press succeeds, cleared as soon as anything has had a
    /// chance to consume it.
    ///
    /// WHY it exists: the fan gesture is attached with `simultaneousGesture`, so the
    /// underlying mic `Button` is still live and fires its action on a release inside
    /// its bounds — which is exactly the abort. Without this, pulling back to the mic
    /// to cancel would start the plain recording the user just cancelled.
    ///
    /// It is set ~0.35 s before any release, so it is always true by the time the
    /// button action could run, whichever order SwiftUI delivers the two in.
    @State private var fanGestureDidOpen = false

    /// Drives the discovery hint's float: 0 at rest, 3 at the far end of the breath.
    /// One value for the offset and the opacity, so the two cannot drift apart.
    @State private var hintDrift: CGFloat = 0

    var body: some View {
        // WHY ZStack: ensures the banner text is centered horizontally across the
        // full toolbar width, independent of the mic pill position on the right.
        // Both layers are vertically centered by the ZStack's default alignment.
        ZStack {
            if !hasFullAccess {
                fullAccessBar
            } else if isPanelOpen {
                panelBar
            } else {
                dictationBar
            }
        }
        .padding(.horizontal, 12)
        // Push content down so the mic ring/glow doesn't get clipped by the
        // iOS keyboard container's native top border (~2pt separator).
        .padding(.top, 4)
        // WHY 52pt: The AnimatedMicButton pill (36pt tall) has ring/glow effects
        // extending to 46pt. With 4pt top padding, 52pt total provides enough
        // breathing room above and below the pill without clipping.
        .frame(height: Self.toolbarHeight)
    }

    /// The bar's height, in both presentations. Named rather than inlined because the
    /// fan gesture subtracts it to turn a root-space drag into a fan-space one, and a
    /// second literal 52 would be a silent one-notch offset on every row boundary.
    /// `KeyboardRootView` and `KeyboardViewController` hold their own copies for
    /// their own layout; this one belongs to the bar itself.
    static let toolbarHeight: CGFloat = 52

    // MARK: - Presentations

    /// The dictation cockpit: hamburger left (when idle), suggestion bar (when
    /// typing), mic right.
    ///
    /// WHY the hamburger yields to suggestions:
    /// The suggestion bar needs horizontal space to display 3 slots legibly. The
    /// hamburger inherits that arbitration from the language switcher it replaced,
    /// at the same 32 pt cost. Accepted consequence (#241): the keyboard language
    /// cannot be changed mid-word.
    ///
    /// WHY undo sits between the error message and the suggestions (#266):
    /// an error means the dictation failed, so there is nothing to undo and the
    /// error wins. Suggestions lose because immediately after an insertion the user
    /// has typed nothing, so whatever the bar is showing was predicted from text
    /// that was just dictated — worth little, and worth less than a control that
    /// expires in seconds and is the only alternative to holding backspace.
    ///
    /// WHY the polish-unavailable notice sits LAST, beside the hamburger rather
    /// than instead of anything (#315): it is the only occupant of this bar that
    /// can last the whole app process. Above the suggestions it would suppress
    /// completions and corrections for that entire time, which is the keyboard's
    /// core job; in place of the hamburger it would make the panel unreachable
    /// for the same duration. Sharing the slot costs visibility while the user is
    /// mid-word, and that is the cheapest of the three prices.
    private var dictationBar: some View {
        HStack {
            if !centreSlot.evictsHamburger {
                hamburgerButton
            }

            centreSlotContent

            micPill
        }
    }

    /// The one occupant of the centre slot, resolved by the priority table in
    /// DictusCore (#79). The view renders whatever it is handed; the ordering is
    /// tested over there, because this target has no test bundle.
    private var centreSlot: ToolbarCentreSlot {
        ToolbarCentreSlot.resolve(
            isChoosingMode: isSmartModeFanOpen,
            errorMessage: statusMessage,
            offersDictationUndo: showsDictationUndo,
            hasSuggestions: !suggestions.isEmpty,
            polishUnavailable: showsPolishUnavailable,
            armedModeName: armedSmartMode?.displayName,
            offersDiscoveryHint: offersSmartModeHint
        )
    }

    @ViewBuilder
    private var centreSlotContent: some View {
        switch centreSlot {
        case .choosingMode:
            fanTitle
        case .error(let message):
            errorMessage(message)
        case .dictationUndo:
            dictationUndoButton
            Spacer()
        case .suggestions:
            SuggestionBarView(
                suggestions: suggestions,
                mode: suggestionMode,
                onTap: { index in onSuggestionTap?(index) }
            )
        case .polishUnavailable:
            polishUnavailableNotice
        case .armedMode(let name):
            armedModeLabel(name)
        case .discoveryHint:
            discoveryHint
        case .empty:
            Spacer()
        }
    }

    /// WHY not red (#313, decided 2026-08-25): red is the recording overlay's colour in
    /// this keyboard, and a message in that same red one second after the overlay in that
    /// red disappears reads as an alarm. Half of what lands here is not an alarm at all —
    /// "No words detected" is the user having stopped the mic a beat early — and the other
    /// half is not helped by shouting. Grey, the treatment the bar already gives
    /// `polishUnavailableNotice`, says the same thing without claiming the app is broken.
    private func errorMessage(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            // Instrumentation only (#261). "The message was assigned" and
            // "a live view put it on screen" are different facts, and only
            // the first was observable — iOS keeps several controllers
            // alive, so a message can be set and rendered into a tree the
            // user is not looking at. This is the second fact, reported
            // from the one place that can actually attest to it.
            .onAppear {
                KeyboardState.shared.noteStatusMessageDisplayed(
                    rootView: messageProbeRootViewID,
                    controller: messageProbeControllerID
                )
            }
            .onDisappear {
                KeyboardState.shared.noteStatusMessageHidden(
                    rootView: messageProbeRootViewID,
                    controller: messageProbeControllerID
                )
            }
    }

    /// The mic, carrying the fan gesture.
    ///
    /// `simultaneousGesture` rather than `highPriorityGesture`: the plain tap is
    /// still the overwhelmingly common way to dictate, and it must not pay a
    /// long-press delay. See `fanGestureDidOpen` for how the two are kept from
    /// firing on the same release.
    private var micPill: some View {
        AnimatedMicButton(
            status: dictationStatus,
            isPill: true,
            badge: armedSmartMode?.badge,
            onTap: {
                guard !fanGestureDidOpen else {
                    fanGestureDidOpen = false
                    return
                }
                onMicTap()
            }
        )
        .simultaneousGesture(fanGesture)
    }

    /// Long-press, then drag, then release — one continuous gesture, because that is
    /// what the user performs (#79, Typeless's gesture).
    ///
    /// ### Why the drag is *sequenced* behind the long press and not simultaneous
    ///
    /// Both shapes were measured on the simulator on 2026-08-24, and the difference
    /// is which one keeps tracking once the finger leaves the mic pill — which is
    /// the whole gesture, since every row is below it. Sequenced does: the long
    /// press has already won arbitration, so the drag inherits the touch and follows
    /// it down the fan. A standalone `simultaneousGesture(DragGesture(…))` is
    /// cancelled the moment the finger exits the `Button`'s bounds, and the release
    /// never arrives — three consecutive runs opened the fan and armed nothing.
    ///
    /// `.first(true)` is the long press landing. Opening there rather than on the
    /// first drag update is what makes the fan appear under a *stationary* thumb,
    /// which is the affordance: nothing has moved yet, and the menu is already there
    /// to move onto.
    private var fanGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(Self.fanCoordinateSpace)
            ))
            .onChanged { value in
                // `.second` and NOT `.first(true)`, which is the whole of this
                // gesture's timing (device, 2026-08-24).
                //
                // A `LongPressGesture`'s value means "a press is in progress", not
                // "the press has lasted long enough". `onChanged` therefore delivers
                // `.first(true)` the instant the finger lands, and opening there
                // meant the fan had no delay at all: **21 mic taps out of 21 in one
                // session opened the fan**, and a plain tap could no longer start a
                // dictation. The 0.35 s was written down and never applied.
                //
                // A `SequenceGesture` moves to `.second` only once its first gesture
                // has *succeeded*, so this is the long press completing. The drag
                // value is nil until the finger actually moves, which is what keeps
                // the fan appearing under a stationary thumb.
                guard case .second(true, let drag) = value else { return }
                if !isSmartModeFanOpen {
                    fanGestureDidOpen = onSmartModeFanOpen?() ?? false
                }
                guard fanGestureDidOpen, let drag else { return }
                onSmartModeFanDrag?(drag.location.y - Self.toolbarHeight)
            }
            .onEnded { _ in releaseFan() }
    }

    /// The release that a `SequenceGesture` does not deliver.
    ///
    /// A `SequenceGesture` only calls `onEnded` once its second gesture has been
    /// *recognised*, and a `DragGesture` that never receives a movement update never
    /// is. So a user who held the mic and let go without sliding — the natural way
    /// to peek at the menu, and the exact shape of the documented abort — got no
    /// release at all and the fan stayed over the keys. Measured 2026-08-24:
    /// `smartModeFanOpened` with no `smartModeFanAborted` behind it.
    ///
    /// This covers exactly that case, and only that case: no movement means the
    /// finger never left the pill, so the bounds limitation that rules this shape
    /// out for tracking does not apply. When a real drag happens, whichever of the
    /// two fires first closes the fan and the other finds nothing to do.
    private var releaseSafetyNet: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { _ in releaseFan() }
    }

    /// End the gesture, once, whichever recogniser noticed.
    private func releaseFan() {
        guard fanGestureDidOpen else { return }
        onSmartModeFanRelease?()
        // Cleared a turn later, not here: the mic `Button`'s action may still be
        // about to fire for this same release, and it is the flag that tells it to
        // stand down.
        DispatchQueue.main.async { fanGestureDidOpen = false }
    }

    /// Titles the fan while it is open, priority 0 (#79).
    ///
    /// The header the mock puts above the rows, moved into the bar. Drawn inside the
    /// fan it would have to push the rows down, and the row positions are exactly
    /// what `SmartModeFanLayout` maps the finger's y onto — a header there buys a
    /// line of text and pays for it with the one piece of arithmetic in this block
    /// that was settled on a device. The bar is empty at that moment anyway, and it
    /// sits directly above the first row.
    private var fanTitle: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))

            Text(
                "Choose a Smart Mode",
                comment: "Toolbar title shown while the long-press Smart Mode fan is open."
            )
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
        }
        .foregroundColor(.dictusAccent)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity)
    }

    /// The armed mode's name, priority 4 (#79).
    ///
    /// Accent blue and quiet, wearing the mode's own glyph beside its name. This is
    /// where the badge on the mic is *taught*: the two sit 200 pt apart on the same
    /// bar, so reading "→ EN" here is what makes the EN on the pill mean something
    /// later, when the label has given way to the suggestions.
    ///
    /// It is a statement about a setting, not a message: the user armed this
    /// deliberately, possibly last week, and the reason it is on screen at all is that
    /// a sticky mode with no visible sign is how someone dictates a translation they
    /// did not want.
    private func armedModeLabel(_ name: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: armedSmartMode?.icon ?? "sparkles")
                .font(.system(size: 11, weight: .semibold))

            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(.dictusAccent)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity)
    }

    /// Priority 5, the discovery affordance (#79).
    ///
    /// Secondary and small, in the register of the #315 notice rather than of an
    /// error: nothing is wrong, there is simply something here the user has not
    /// found. `SmartModeDiscovery` retires it once the gesture has been performed.
    ///
    /// ### Why it moves, when nothing else in this bar does
    ///
    /// Every other occupant of the centre slot is a *statement* — an error, a name, a
    /// notice — and a statement that drifts is a distraction. This one is an
    /// invitation, and it is competing for attention with the text the user came here
    /// to write. Static grey caption text in a keyboard toolbar is the most ignorable
    /// object in iOS; it is read once, on the first keyboard the user ever opens, and
    /// after that it is furniture. The drift is what buys the second look.
    ///
    /// The motion is deliberately the mic's own: 2 s, `easeInOut`, `autoreverses`,
    /// the same curve as `AnimatedMicButton`'s idle glow. Two things breathing
    /// together at the same rate read as one thing pointing at the other; two things
    /// breathing at different rates read as a bug.
    ///
    /// The arrow drifts a little further than the text. That difference is the whole
    /// effect — the group is not sliding, it is *reaching* — and it is why this is
    /// two amplitudes on one animation rather than one `offset` on the `HStack`.
    ///
    /// It repeats forever in a keyboard extension, which is the cost. It is the cost
    /// the idle mic glow already pays in the same view, and this one stops existing
    /// the moment the user performs the gesture once.
    private var discoveryHint: some View {
        HStack(spacing: 6) {
            Text(
                "Hold the mic for Smart Modes",
                comment: "Toolbar hint teaching the long-press gesture that opens the Smart Mode fan."
            )
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            // Toward the mic, which is the point of the sentence and sits to the
            // right of it in both presentations of this bar.
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .offset(x: hintDrift * 2.2)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .opacity(0.62 + hintDrift * 0.13)
        .offset(x: hintDrift)
        .padding(.leading, 6)
        .frame(maxWidth: .infinity)
        .onAppear {
            // Assigned inside the animation and never reset: the hint has no other
            // states, so there is nothing here to cancel and stack the way
            // `AnimatedMicButton` has to.
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                hintDrift = 3
            }
        }
    }

    /// The panel header: close left, gear anchored right, Pro entry inserted to
    /// the gear's left for non-subscribers.
    ///
    /// The gear is last in the stack in both subscription states, so it never
    /// moves — a subscriber must not have to look for it somewhere a
    /// non-subscriber does not.
    private var panelBar: some View {
        HStack(spacing: 8) {
            closeButton

            Spacer()

            // Same gate as every other Pro entry point (#236): while the paywall
            // is hidden the product must look like it has no subscription at all,
            // and a pill leading to an unreachable paywall is exactly the kind of
            // dead end that gate exists to prevent.
            if PremiumFlags.paywallVisible && !isProActive {
                proEntry
            }

            settingsButton
        }
    }

    /// No Full Access: centered banner text + disabled mic on the right.
    private var fullAccessBar: some View {
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Full access required")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                AnimatedMicButton(status: .idle, isPill: true, onTap: {})
                    .disabled(true)
                    .opacity(0.4)
            }
        }
    }

    // MARK: - Controls

    /// Bare hamburger, no language code on it (#241): the keyboard already
    /// announces its language through the spacebar label and the key positions,
    /// and a variable-width label jitters the most contested 32 pt of the UI.
    private var hamburgerButton: some View {
        panelToggleButton(
            systemName: "line.3.horizontal",
            label: Text("Keyboard menu")
        )
    }

    /// Removes the dictation that was just inserted (#266).
    ///
    /// WHY it borrows the look of the autocorrect undo chip in `SuggestionBarView`
    /// — accent tint, uturn arrow: the two controls do the same thing to different
    /// text, and they appear in the same strip of the same bar seconds apart. A
    /// user who has learned that a tinted uturn arrow reverts what just happened
    /// should not have to learn it twice.
    ///
    /// It does NOT pulse the way the autocorrect chip does. That pulse exists
    /// because an autocorrection is silent; a dictation insertion is not — the
    /// recording overlay has just closed and the text has just appeared.
    private var dictationUndoButton: some View {
        Button {
            HapticFeedback.keyTapped()
            onDictationUndoTap?()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .semibold))

                Text("Undo")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(.dictusAccent)
            .padding(.horizontal, 14)
            .frame(height: iconDiameter)
            .background(
                Capsule().fill(Color.dictusAccent.opacity(0.12))
            )
            // Same split as `barIcon`: the capsule is what the eye sees, the 44 pt
            // frame is what a finger hits.
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(Text("Undo dictation insertion"))
    }

    /// Polish is not running, and will not run again until DictusApp restarts (#315).
    ///
    /// WHY secondary: nothing failed for the user. The dictation still arrives, as
    /// the deterministic floor it already takes when a guardrail rejects the model's
    /// output — what is missing is the polish on top.
    ///
    /// This used to be the exception, the one message in the bar that was not red.
    /// Since #313 it is the rule: no message in this keyboard is red, and the
    /// argument written here is the one that generalised.
    ///
    /// The copy names the state and stops. No cause, no remedy, no "try again
    /// later": Apple's background rate limit is only refunded by a fresh app
    /// process, so there is no action to offer, and an offer that does not work
    /// is worse than none.
    private var polishUnavailableNotice: some View {
        Text("Polish is temporarily unavailable.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            // The sentence is fixed and must not truncate; on the narrowest
            // supported width it gives up a little size instead. Single line
            // either way, so the bar keeps its 52 pt (#166 and family).
            .minimumScaleFactor(0.75)
            .padding(.leading, 6)
            .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        panelToggleButton(
            systemName: "xmark",
            label: Text("Close menu")
        )
    }

    /// Both states of the left slot, at the identical 32 pt frame the language
    /// label used, so ☰ becomes ✕ in place with no geometry change.
    private func panelToggleButton(systemName: String, label: Text) -> some View {
        Button {
            HapticFeedback.keyTapped()
            onPanelToggle?()
        } label: {
            barIcon(systemName: systemName, size: 17, width: Self.micPillWidth, shape: .capsule)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(label)
    }

    private var settingsButton: some View {
        Button {
            HapticFeedback.keyTapped()
            onSettingsTap?()
        } label: {
            barIcon(systemName: "gearshape", size: 19, width: iconDiameter, shape: .circle)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(Text("Open Dictus"))
    }

    /// Width and height of `AnimatedMicButton`'s pill body, mirrored here so the
    /// panel toggle is the same object as the mic rather than a smaller cousin.
    /// Kept in sync by hand: the mic owns these numbers, this is a deliberate
    /// visual echo of them, not a shared constant to be refactored away.
    private static let micPillWidth: CGFloat = 56

    /// Diameter of the round icon buttons, and the height of every bar control.
    private var iconDiameter: CGFloat { 36 }

    /// Shape of a bar icon's glass backing.
    private enum BarIconShape { case circle, capsule }

    /// Shared geometry for the bar's icon buttons: a 36 pt-tall glass backing
    /// inside a touch target at least 44 pt on each axis.
    ///
    /// WHY the two frames differ (#241 device feedback): the visible control and
    /// the tappable region are not the same thing. The glyph sat in a bare 32 pt
    /// frame, under the 44 pt minimum, and closing the panel measured 10 to 22
    /// seconds per attempt on device — taps aimed at the close control landed on
    /// the 44 pt language rows below it instead. The outer frame is what a finger
    /// hits; the inner one is what the eye sees.
    ///
    /// WHY glass rather than a bare glyph: against the mic's filled pill, an
    /// unbacked icon read as unfinished rather than as a control.
    ///
    /// WHY the panel toggle is a capsule and the gear a circle: the toggle sits
    /// opposite the mic and is the only thing balancing it, so it takes the mic's
    /// pill footprint. The gear never faces the mic — it appears only in the panel
    /// bar, where a second wide pill would compete with the toggle rather than
    /// balance anything.
    private func barIcon(
        systemName: String,
        size: CGFloat,
        width: CGFloat,
        shape: BarIconShape
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .foregroundColor(.dictusPillIconSecondary)
            .frame(width: width, height: iconDiameter)
            .dictusGlass(in: shape == .capsule ? AnyShape(Capsule()) : AnyShape(Circle()))
            .frame(width: max(width, 44), height: 44)
            .contentShape(Rectangle())
    }

    /// White pill, gradient text, in both light and dark appearances (#241).
    ///
    /// Chosen over a gradient-filled pill and over gradient text alone: it carries
    /// the paywall's own gradient, so the Pro signal reads identically across
    /// surfaces, while staying legible against either keyboard background.
    ///
    /// Known and accepted: on the light keyboard a white rounded pill with a
    /// shadow resembles a key. If it reads as a key on device, the recorded
    /// fallback is a gradient-filled pill in light appearance only.
    private var proEntry: some View {
        Button {
            HapticFeedback.keyTapped()
            onProTap?()
        } label: {
            Text(verbatim: "Dictus Pro")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.dictusGradientStart, .dictusGradientEnd],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Capsule().fill(Color.white)
                )
                .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
                // The pill stays 28 pt tall; only the touch target grows to 44.
                // See `barIcon` for why the two are separated.
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityLabel(Text(verbatim: "Dictus Pro"))
    }
}
