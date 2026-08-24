// DictusKeyboard/KeyboardRootView.swift
import SwiftUI
import Combine
import DictusCore

/// Bridge between DictusCore's DefaultKeyboardLayer and DictusKeyboard's KeyboardLayerType.
extension DefaultKeyboardLayer {
    var asLayerType: KeyboardLayerType {
        switch self {
        case .letters: return .letters
        case .numbers: return .numbers
        }
    }
}

/// Root SwiftUI view for the keyboard extension chrome (toolbar + full-area
/// presentations).
///
/// Phase 18 architecture change: The keyboard grid is now a UIKit GiellaKeyboardView
/// added as a direct subview in KeyboardViewController. This SwiftUI view only renders:
/// - ToolbarView (always visible when not recording)
/// - RecordingOverlay (replaces keyboard area during recording)
/// - EmojiPickerView (replaces the key grid, toolbar stays)
///
/// Which of those it renders is decided by a single `KeyboardAreaMode` read from
/// KeyboardState (#271) — the same value KeyboardViewController switches on for
/// the layout, so the two layers cannot drift apart.
///
/// WHY SwiftUI for toolbar/overlay but UIKit for keys:
/// The toolbar and recording overlay are simple SwiftUI layouts that don't need
/// zero-latency touch handling. The key grid needs UICollectionView's proven touch
/// pipeline for zero dead zones. Mixing UIKit keys + SwiftUI chrome gives us both.
struct KeyboardRootView: View {
    let controllerID: String
    @ObservedObject private var state = KeyboardState.shared
    @ObservedObject private var waveformDriver = KeyboardWaveformDriver.shared
    /// Everything Smart Mode: the armed mode's name, the discovery hint, and the
    /// fan while the mic is held. A second observed object beside `KeyboardState`,
    /// exactly as the waveform driver above is — see `KeyboardSmartModeState`.
    @ObservedObject private var smartModes = KeyboardSmartModeState.shared
    @State private var instanceID = String(UUID().uuidString.prefix(8))
    /// Observable state for the suggestion bar, owned by KeyboardViewController.
    /// WHY @ObservedObject (not @StateObject): The controller creates and owns SuggestionState,
    /// injecting the same instance into both this view (for display) and the bridge (for updates).
    /// Using @ObservedObject here means we observe without owning -- the controller is the source of truth.
    @ObservedObject var suggestionState: SuggestionState

    /// Reference to the keyboard bridge for prediction tap handling.
    /// WHY needed: When the user taps a prediction, we need to call
    /// bridge.handlePredictionTap() which inserts the word + space and chains
    /// new predictions. The bridge owns textDocumentProxy access and state management.
    var bridge: DictusKeyboardBridge?

    /// Callback when the user picks a language in the hamburger panel.
    /// The controller uses this to reload the GiellaKeyboardView with the new layout.
    var onLanguageChanged: ((SupportedLanguage) -> Void)?

    /// Callback when the user picks a layout for a language in the panel (#272).
    /// The controller decides whether it has to rebuild — only the active language's
    /// layout is on screen.
    var onLayoutChanged: ((LayoutType, SupportedLanguage) -> Void)?

    /// Whether the Pro entry is hidden from the panel bar.
    ///
    /// WHY @State refreshed on open rather than an observed ProStatusManager:
    /// the extension reads Pro status from the App Group, and a subscription
    /// cannot be bought while the keyboard is the frontmost surface — so a read
    /// each time the panel opens is both sufficient and cheaper than keeping an
    /// ObservableObject alive in a 50 MB process.
    @State private var isProActive = false

    /// WHY @Environment here: openURL is the SwiftUI way to open URLs.
    /// Keyboard extensions cannot access UIApplication.shared, but SwiftUI's
    /// openURL environment action works because it goes through the responder
    /// chain. We capture it here and inject it into KeyboardState via .onAppear.
    @Environment(\.openURL) private var openURL

    /// Fixed toolbar height, matching `KeyboardViewController.toolbarHeight`.
    private let toolbarHeight: CGFloat = 52

    /// What this view presents.
    ///
    /// The mode is owned by KeyboardState; what this adds is the presenter check
    /// on `.recording` only. iOS caches UIInputViewController instances and their
    /// KeyboardRootViews keep receiving updates long after they leave the window
    /// (#128 / #134) — a stale view that rendered the overlay produced the
    /// duplicate grey panel in #116.
    ///
    /// WHY the pickers are deliberately NOT gated the same way, keeping the
    /// pre-#271 split: `.recording` is pushed from another process and can arrive
    /// while no controller owns the keyboard (`activeID=none`, #260), so it needs
    /// an owner to be worth drawing. A picker is opened by a key the user just
    /// touched on the visible keyboard; gating it on ownership would blank the
    /// keyboard area for the whole #260 window instead of merely delaying an
    /// overlay.
    ///
    /// That window is now closed from the other side: an area whose owner was
    /// deallocated is marked reclaimable, and the controller that is actually in a
    /// window claims it on the next status change (#260). This check is what makes
    /// the claim visible — ownership moving to our controllerID is what flips this
    /// from `.keys` to `.recording`.
    ///
    /// The legacy `activeControllerID == nil` fallback that used to mask #128 is
    /// deliberately not reinstated: with #128 fixed, stale controllers are dormant.
    private var presentedMode: KeyboardAreaMode {
        let mode = state.areaMode
        guard mode == .recording else { return mode }
        guard state.activeControllerID == controllerID, state.isKeyboardVisible else {
            return .keys
        }
        // Owning the area is not the same as having checked what to draw (#361). A
        // stage this process set on its own authority outlives the controller that
        // justified it, and a freshly mounted one would otherwise render it before
        // `viewWillAppear` has reconciled anything — a flash of the polish overlay on
        // returning to an app where a dictation was made.
        guard state.mayDrawLocalStage(from: controllerID) else { return .keys }
        return mode
    }

    /// Close the panel, then run whatever takes the user out of the keyboard.
    ///
    /// WHY (#241 device feedback): the panel is a menu, not a place. Both entries
    /// in its bar send the user to DictusApp, and coming back to a keyboard still
    /// showing the menu they left is disorienting — the task that opened it is
    /// over. Resetting before leaving also means the restore in
    /// `KeyboardViewController.viewWillAppear` has nothing to put back.
    private func leavePanel(_ action: @escaping () -> Void) {
        state.presentAreaMode(.keys)
        action()
    }

    /// Open or close the hamburger panel.
    ///
    /// The mode change is the only state involved — `KeyboardState` owns it and
    /// both layers read it (#271), so no flag is duplicated here.
    ///
    /// WHY the mode change itself is deliberately NOT animated: the branches of
    /// the `switch` below are the single child of a VStack, so a transition on
    /// the branch keeps the outgoing and incoming views alive together and the
    /// VStack stacks them — the outgoing bar above the incoming one. Two stacked
    /// bars is the exact artefact this design was reshaped to avoid, and a
    /// transient one is no better. The bar therefore swaps instantly, ☰ to ✕ in
    /// place, and the fade lives inside the panel body where it stacks nothing.
    ///
    /// Nothing here animates geometry either: the hosting height and bottom
    /// anchor move synchronously in UIKit, in the same turn as the mode change,
    /// deliberately (#99, #142).
    private func togglePanel() {
        isProActive = ProStatusManager.isProActiveStatic
        state.togglePanelPresentation()
    }

    /// The 52 pt bar, in whichever of its two presentations the mode calls for.
    ///
    /// The suggestion slots are only filled in `.keys`: every other presentation
    /// hides the key grid, so there is no word being typed to suggest for.
    private var toolbar: some View {
        ToolbarView(
            hasFullAccess: state.controller?.hasFullAccess ?? false,
            dictationStatus: state.dictationStatus,
            onMicTap: { state.startRecording() },
            statusMessage: state.statusMessage,
            messageProbeRootViewID: instanceID,
            messageProbeControllerID: controllerID,
            showsPolishUnavailable: state.polishUnavailable,
            suggestions: presentedMode == .keys ? suggestionState.suggestions : [],
            suggestionMode: presentedMode == .keys ? suggestionState.mode : .idle,
            onSuggestionTap: { index in handleSuggestionTap(index: index) },
            // Undo survives opening the emoji picker (#266): browsing emoji is not
            // typing, and the insertion is still the tail of the field. The panel
            // presentation ignores these — its bar has no centre slot.
            showsDictationUndo: state.dictationUndoAvailable,
            onDictationUndoTap: { state.performDictationUndo() },
            isPanelOpen: presentedMode == .panel,
            onPanelToggle: { togglePanel() },
            onSettingsTap: { leavePanel { state.openDictusApp(intent: "settings") } },
            isProActive: isProActive,
            onProTap: { leavePanel { state.openDictusApp(intent: "pro") } },
            armedSmartMode: smartModes.armedMode,
            offersSmartModeHint: smartModes.offersHint,
            onSmartModeFanOpen: { smartModes.open() },
            onSmartModeFanDrag: { y in smartModes.track(y: y) },
            onSmartModeFanRelease: { smartModes.commit() },
            isSmartModeFanOpen: smartModes.fan != nil
        )
        .frame(height: toolbarHeight)
    }

    /// What fills the keyboard area under the bar. `.keys` puts nothing here — the
    /// grid is UIKit, added directly by `KeyboardViewController`.
    ///
    /// Each `GeometryReader` now measures the area itself rather than the whole
    /// hosting view, so the `- toolbarHeight` subtractions and their clamps are gone
    /// with the reason they existed: a body evaluated before the hosting constraint
    /// landed used to make that subtraction negative.
    @ViewBuilder
    private var areaBelowToolbar: some View {
        switch presentedMode {
        case .emoji:
            // GeometryReader measures the actual space available to SwiftUI.
            // WHY: In keyboard extensions, the hosting controller may not give the
            // full screen width/height to SwiftUI due to safe area or system insets.
            // Passing measured dimensions to EmojiPickerView guarantees it fits.
            GeometryReader { geo in
                EmojiPickerView(
                    onEmojiInsert: { emoji in
                        state.controller?.textDocumentProxy.insertText(emoji)
                        HapticFeedback.keyTapped()
                    },
                    onDelete: {
                        state.controller?.textDocumentProxy.deleteBackward()
                        HapticFeedback.keyTapped()
                    },
                    onDismiss: { state.presentAreaMode(.keys) },
                    availableWidth: geo.size.width,
                    availableHeight: geo.size.height
                )
            }

        case .panel:
            // The hamburger panel (#241). Same layout contract #271 reserved: the bar
            // on top, the panel filling the rest.
            GeometryReader { geo in
                KeyboardPanelView(
                    availableHeight: geo.size.height,
                    // Neither selection closes the panel (#272). A row carries two
                    // independent choices now — language and layout — and closing on
                    // the first one takes the second away. The ✕ in the bar is the
                    // only way out.
                    onLanguageChanged: { language in onLanguageChanged?(language) },
                    onLayoutChanged: { layout, language in onLayoutChanged?(layout, language) }
                )
            }

        case .smartModeFan:
            if let fan = smartModes.fan {
                // The height the *layout* used, not one SwiftUI has measured: the fan
                // appears in the same turn the hosting constraint grows, and the two
                // are not yet the same number. It is also the height the gesture's
                // y-to-row mapping divides, and those two must agree or the row under
                // the finger is not the row that highlights.
                SmartModeFanView(state: fan, availableHeight: smartModes.areaHeight)
            }

        case .keys, .recording:
            EmptyView()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if presentedMode == .recording {
                // Recording overlay fills the full area (toolbar + keyboard space).
                // The UIKit keyboard is hidden by KeyboardViewController when recording.
                RecordingOverlay(
                    dictationStatus: state.displayedDictationStatus,
                    waveformEnergy: state.waveformEnergy,
                    elapsedSeconds: state.recordingElapsed,
                    waveformDriver: waveformDriver,
                    onCancel: { state.requestCancel() },
                    onStop: { state.requestStop() },
                    armedSmartMode: smartModes.armedMode
                )
            } else {
                // ONE toolbar, outside the switch, for every non-recording mode.
                //
                // WHY it was moved out (#79): SwiftUI identity is positional, so a
                // toolbar built inside a `switch` is a *different* view in every
                // branch — and opening the Smart Mode fan changes the branch. The
                // long-press gesture attached to the mic was therefore destroyed and
                // rebuilt at the exact moment it succeeded, so the drag that follows
                // it was delivered to a recogniser that no longer existed. Measured
                // on the simulator 2026-08-24: the fan opened every time and no row
                // ever highlighted, in six consecutive runs.
                //
                // A gesture that spans a mode change needs a view that survives one.
                // Nothing else about the layout changes: the bar is still 52 pt in
                // every presentation, and the area below it is still measured by the
                // same `GeometryReader`s — they now measure only the area, which is
                // what they always wanted.
                toolbar
                areaBelowToolbar
            }
        }
        // The fan's drag is measured against the whole keyboard area, not against the
        // 52 pt bar it starts in: the finger travels from the mic down over rows that
        // are somebody else's view (#79). Named here because this is the view that
        // spans both.
        .coordinateSpace(name: ToolbarView.fanCoordinateSpace)
        // Issue #142: force the body to fill its hosting frame top-aligned.
        // Without this, when the hosting view expands from 52→276pt on mic
        // tap but SwiftUI hasn't yet re-rendered ToolbarView→RecordingOverlay
        // (1-frame async lag), UIHostingController centres the 52pt toolbar
        // intrinsic content inside its 276pt frame — and iOS's keyboard-down
        // animation snapshot freezes that centred-toolbar layout on screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        // Action name kept verbatim (and `isShowing=` with it): #260 and #261 are
        // open and quote this line from device logs. `mode=` is additive.
        //
        // Only the owning view logs (#255). iOS keeps ~9 KeyboardRootView instances
        // alive at once, so an unrestricted emission here reported one mode change
        // ~9 times — a reader taking the file at face value sees a controller
        // lifecycle bug that does not exist. Non-owners present `.keys` by
        // construction, so their transitions carry no information the owner's line
        // does not already have. The owner-less window (#260) stays visible without
        // this line: KeyboardViewController's `dictStatusChange_enter` carries
        // `activeID=none`, and KeyboardState logs `registerControllerDisappearance`
        // and `presentAreaMode` at the source.
        .onChange(of: presentedMode) { _, mode in
            if state.activeControllerID == controllerID {
                PersistentLog.log(.diagnosticProbe(
                    component: "KeyboardRootView",
                    instanceID: instanceID,
                    action: "showsOverlayChanged",
                    details: "isShowing=\(mode == .recording) mode=\(mode.rawValue) status=\(state.dictationStatus.rawValue) visible=\(state.isKeyboardVisible) owner=\(state.activeControllerID ?? "none") controllerID=\(controllerID)"
                ))
            }
            // No emoji dismissal here: `.recording` replaces whatever filled the
            // area, so mutual exclusion is the type's job now, not this callback's.
            syncWaveformDriver()
        }
        // overlayShown/overlayHidden moved to KeyboardState (#255): they describe an
        // app-wide dictation state change, not a per-view event, so they belong
        // where the status is stored rather than in every observer's onChange.
        // The *drawn* stage, not the real one (#309). It is the only thing the driver
        // consumes, and it is the one that still moves when a hold elapses — the real
        // status changed half a second earlier and would fire nothing here.
        .onChange(of: state.displayedDictationStatus) { _, _ in
            syncWaveformDriver()
        }
        .onChange(of: state.waveformEnergy) { _, _ in
            syncWaveformDriver()
        }
        // Only the incoming owner logs (#255). Ownership hand-over is already
        // recorded once per transition at the source, by KeyboardState's
        // registerControllerAppearance / registerControllerDisappearance probes;
        // what this adds is the confirmation that the new owner's view saw it.
        .onChange(of: state.activeControllerID) { _, newOwner in
            if newOwner == controllerID {
                PersistentLog.log(.diagnosticProbe(
                    component: "KeyboardRootView",
                    instanceID: instanceID,
                    action: "activeControllerChanged",
                    details: "newOwner=\(newOwner ?? "none") controllerID=\(controllerID)"
                ))
            }
            syncWaveformDriver()
        }
        .onChange(of: state.isKeyboardVisible) { _, _ in
            syncWaveformDriver()
        }
        .onAppear {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardRootView",
                instanceID: instanceID,
                action: "onAppear",
                details: "status=\(state.dictationStatus.rawValue) visible=\(state.isKeyboardVisible) owner=\(state.activeControllerID ?? "none") controllerID=\(controllerID)"
            ))
            // state.controller is set by KeyboardViewController.viewWillAppear to avoid
            // a strong ref cycle through the hosting view (#134). openURL must stay
            // here — it's a SwiftUI @Environment value, only capturable from a View.
            state.openURL = { url in openURL(url) }

            // Pre-allocate haptic generators so the first key tap has zero latency.
            HapticFeedback.warmUp()

            // Refresh cached haptic enabled state from UserDefaults.
            HapticFeedback.refreshEnabledState()

            // Also read here, not only in togglePanel(): iOS can hand the keyboard
            // to a fresh controller while the panel is open, and viewWillAppear
            // restores `.panel` — that path never goes through the toggle.
            isProActive = ProStatusManager.isProActiveStatic

            // Language is set in KeyboardViewController.viewWillAppear, which fires
            // on every keyboard appearance and picks up any App Group preference changes.

            // A dictation a previous keyboard claimed and never typed (#361 decision
            // 7). Checked on appearance because that is the moment the two facts it
            // needs are both true: the controller is wired, so the document can be
            // identified, and the keyboard is on screen, so the user is here to
            // receive the text. Returns immediately when there is nothing pending,
            // which is every ordinary appearance.
            KeyboardPolishCoordinator.shared.recoverPendingIfNeeded()

            syncWaveformDriver()
        }
        .onDisappear {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardRootView",
                instanceID: instanceID,
                action: "onDisappear",
                details: "status=\(state.dictationStatus.rawValue) controllerID=\(controllerID)"
            ))
            syncWaveformDriver(forceHidden: true)
        }
    }

    /// Push the current presentation at the waveform driver.
    ///
    /// `status:` is the *drawn* stage, not the real one (#309) — the same value the
    /// overlay's label is built from, deliberately. The label and the animation are
    /// two halves of one statement about what the phone is doing; feeding them from
    /// two sources would put the transcription sine under a "Traitement..." label for
    /// the length of a hold, which is a worse artefact than the flash the hold exists
    /// to remove.
    ///
    /// Everything else here still reads the real status through `presentedMode`, so
    /// the overlay itself appears and disappears exactly when it did before.
    private func syncWaveformDriver(forceHidden: Bool = false) {
        waveformDriver.sync(
            presenterID: controllerID,
            status: state.displayedDictationStatus,
            energyLevels: state.waveformEnergy,
            isVisible: !forceHidden && presentedMode == .recording
        )
    }

    // MARK: - Suggestion Handling

    /// Handles a tap on one of the suggestion bar slots.
    ///
    /// Three modes:
    /// - Completion mode: replace partial word with full completion + space.
    /// - Correction mode: standard mobile behavior:
    ///   - Tap index 0 (original word): keep as-is + space, reject future autocorrect
    ///   - Tap index 1 (bold correction): apply correction + space
    ///   - Tap index 2 (alternative, or a learned word when one extends the
    ///     typed prefix — #346): apply it + space. Either way this slot is
    ///     reached only by a tap, which is what keeps a learned word out of L3.
    /// - Accent mode: replace just the vowel without adding a space.
    /// - Undo mode: tap index 0 reverts the autocorrect; slots 1-2 are routed by
    ///   the live document, see applyUndoModeSuggestion.
    private func handleSuggestionTap(index: Int) {
        guard index < suggestionState.suggestions.count else { return }
        let suggestion = suggestionState.suggestions[index]
        guard let proxy = state.controller?.textDocumentProxy else { return }

        // Prediction mode: insert word + trailing space, bypass autocorrect, chain predictions.
        if suggestionState.mode == .predictions {
            bridge?.handlePredictionTap(word: suggestion)
            HapticFeedback.keyTapped()
            return
        }

        // Undo mode: tap index 0 = revert autocorrect, tap 1-2 = accept completion/prediction
        if suggestionState.mode == .undoAvailable {
            if index == 0, let undo = suggestionState.pendingUndo {
                performUndo(undo: undo, proxy: proxy)
                suggestionState.pendingUndo = nil
                suggestionState.clear()
            } else {
                applyUndoModeSuggestion(suggestion, proxy: proxy)
            }
            HapticFeedback.keyTapped()
            return
        }

        if suggestionState.mode == .corrections {
            if index == 0 {
                suggestionState.rejectedWords.insert(suggestion.lowercased())
                proxy.insertText(" ")
            } else {
                replaceCurrentWord(
                    proxy: proxy,
                    currentWord: suggestionState.currentWord,
                    replacement: suggestion,
                    addSpace: true
                )
            }
            suggestionState.pendingUndo = nil
            suggestionState.clear()
            HapticFeedback.keyTapped()
            return
        }

        let addSpace = suggestionState.mode == .completions
        replaceCurrentWord(
            proxy: proxy,
            currentWord: suggestionState.currentWord,
            replacement: suggestion,
            addSpace: addSpace
        )

        suggestionState.pendingUndo = nil
        suggestionState.clear()
        HapticFeedback.keyTapped()
    }

    /// Applies a tap on slot 1-2 of the undo bar (#335).
    ///
    /// WHY this is not a plain prediction tap: `.undoAvailable` only says an undo
    /// chip is showing in slot 0. Slots 1-2 hold predictions when the cursor is
    /// after a space, but completions of the word IN PROGRESS when the user has
    /// started typing again — and inserting one of those glued the suggestion to
    /// the partial word ("concerne" + "concerné" -> "concerneconcerné").
    /// The live document decides, not the mode: see SuggestionTapRouting.
    private func applyUndoModeSuggestion(_ suggestion: String, proxy: UITextDocumentProxy) {
        switch SuggestionTapRouting.decide(
            context: proxy.documentContextBeforeInput,
            currentWord: suggestionState.currentWord
        ) {
        case .insert:
            // Cursor is on a boundary: a prediction lands here, insert + space,
            // and let the bridge chain the next predictions. Unchanged behavior.
            suggestionState.pendingUndo = nil
            bridge?.handlePredictionTap(word: suggestion)

        case .replace(let deleteCount):
            applyReplacement(
                proxy: proxy,
                deleteCount: deleteCount,
                replacement: suggestion,
                addSpace: true
            )
            suggestionState.pendingUndo = nil
            suggestionState.clear()

        case .abort(let reason):
            // Stale `currentWord` mid-word: inserting here would reproduce the
            // very bug this fixes. Swallow the tap — the bar refreshes on the
            // next keystroke (same outcome as replaceCurrentWord, #191).
            logReplacementAborted(proxy: proxy, word: suggestionState.currentWord, reason: reason)
        }
    }

    /// Reverts an autocorrection, preserving any characters typed after the correction.
    private func performUndo(undo: AutocorrectState, proxy: UITextDocumentProxy) {
        guard let context = proxy.documentContextBeforeInput else { return }

        // Try to find the corrected word with trailing space first, then without
        // (user may have deleted the space but the word is still intact).
        let correctedWithSpace = undo.correctedWord + " "
        let range: Range<String.Index>
        let matchedWithSpace: Bool

        if undo.insertedSpace, let r = context.range(of: correctedWithSpace, options: .backwards) {
            range = r
            matchedWithSpace = true
        } else if let r = context.range(of: undo.correctedWord, options: .backwards) {
            range = r
            matchedWithSpace = false
        } else {
            return
        }

        let afterCorrection = String(context[range.upperBound...])
        let matchLength = matchedWithSpace ? correctedWithSpace.count : undo.correctedWord.count
        let deleteCount = matchLength + afterCorrection.count

        for _ in 0..<deleteCount {
            proxy.deleteBackward()
        }

        proxy.insertText(undo.originalWord)
        if matchedWithSpace {
            proxy.insertText(" ")
        }
        proxy.insertText(afterCorrection)

        #if DEBUG
        AutocorrectDebugLog.autocorrectUndone(
            original: undo.originalWord, rejected: undo.correctedWord
        )
        #endif

        suggestionState.rejectedWords.insert(undo.originalWord.lowercased())

        // Learn on this single occurrence (#287 decision 4). `learn` and not
        // `recordUsage`: rejecting a correction is the user saying "no, I meant
        // this word", which is the strongest signal the keyboard ever gets, and
        // it is the trigger Apple documents for its own keyboard dictionary. The
        // repetition counter guards the word-boundary site, where the user has
        // said nothing at all; applying it here would mean rejecting the same
        // correction twice before the keyboard stopped making it.
        UserDictionary.shared.learn(undo.originalWord)
    }

    /// Replaces the word currently being typed with a replacement string.
    ///
    /// Boundary-safe (#191): `currentWord` comes from SuggestionState's async
    /// update and can be stale when the user typed fast between the suggestion
    /// computation and the tap. Deleting a blind `currentWord.count` characters
    /// could then eat into the preceding word. Validate against the live
    /// context first; on mismatch, do nothing destructive — the suggestion bar
    /// refreshes on the next keystroke.
    private func replaceCurrentWord(
        proxy: UITextDocumentProxy,
        currentWord: String,
        replacement: String,
        addSpace: Bool
    ) {
        switch AutocorrectReplacement.check(
            context: proxy.documentContextBeforeInput,
            word: currentWord
        ) {
        case .ok(let deleteCount):
            applyReplacement(
                proxy: proxy,
                deleteCount: deleteCount,
                replacement: replacement,
                addSpace: addSpace
            )
        case .failed(let reason):
            logReplacementAborted(proxy: proxy, word: currentWord, reason: reason)
        }
    }

    /// Executes a validated replacement: deletes exactly `deleteCount` graphemes,
    /// then inserts. Only ever called with a count that a boundary check produced.
    private func applyReplacement(
        proxy: UITextDocumentProxy,
        deleteCount: Int,
        replacement: String,
        addSpace: Bool
    ) {
        for _ in 0..<deleteCount {
            proxy.deleteBackward()
        }
        proxy.insertText(replacement)
        if addSpace {
            proxy.insertText(" ")
        }
    }

    /// Logs a replacement the boundary check refused (#191). Debug builds only.
    private func logReplacementAborted(proxy: UITextDocumentProxy, word: String, reason: String) {
        #if DEBUG
        AutocorrectDebugLog.replacementAborted(
            word: word,
            reason: reason,
            contextTail: DictusKeyboardBridge.contextTail(proxy.documentContextBeforeInput)
        )
        #endif
    }
}
