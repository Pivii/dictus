// DictusKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI
import Combine
import DictusCore

class KeyboardViewController: UIInputViewController {
    let controllerID = String(UUID().uuidString.prefix(8))

    private var hostingController: UIHostingController<KeyboardRootView>?
    private var areaModeCancellable: AnyCancellable?

    /// Process-wide SuggestionState (see SuggestionState.shared). Per-controller
    /// instances leaked via SwiftUI @ObservedObject backing storage that survives
    /// KeyboardViewController.deinit; the singleton makes the leak benign.
    private let suggestionState = SuggestionState.shared

    /// The giellakbd-ios UICollectionView keyboard, added as a direct UIKit subview.
    /// WHY not wrapped in UIViewRepresentable: SwiftUI recreates representable views
    /// on state changes, which would destroy/rebuild the UICollectionView and lose
    /// scroll position, active key state, and long-press overlays. Adding as a direct
    /// sibling subview of kbInputView avoids this entirely.
    private var giellaKeyboard: GiellaKeyboardView?

    /// The `needsInputModeSwitchKey` value used the last time the layout was built.
    /// viewDidLoad runs before the host connection is established, so the flag read
    /// there is inaccurate (UIKit logs a warning). We record what we built with and,
    /// once the connection exists (viewWillAppear), rebuild only if the accurate
    /// value now differs — so the next-keyboard globe (4.4.1) is never wrongly
    /// shown or hidden. nil = never built yet.
    private var builtNeedsGlobe: Bool?

    /// Delegate adapter that translates giellakbd-ios key events into Dictus actions.
    private var bridge: DictusKeyboardBridge?

    /// Explicit height constraint on inputView to prevent layout issues after app switch.
    /// WHY: Without this, iOS may not recalculate the keyboard height correctly when the
    /// extension is brought back to foreground after a URL scheme app switch. The system
    /// keyboard row (globe, mic) bleeds through and the recording overlay gets compressed.
    private var heightConstraint: NSLayoutConstraint?

    /// Height constraint for the SwiftUI hosting view (toolbar + recording overlay).
    /// Changes from toolbarHeight (52pt) to full height when recording overlay is active.
    private var hostingHeightConstraint: NSLayoutConstraint?

    /// Idle-state bottom anchor: hosting sits directly above the keyboard.
    /// Active when not recording / emoji. Deactivated when expanding to fill
    /// the full keyboard area, where we instead pin hosting's bottom to
    /// kbInputView's bottom so the overlay fills the entire keyboard.
    private var hostingBottomToKeyboardTop: NSLayoutConstraint?

    /// Expanded-state bottom anchor: hosting's bottom == kbInputView's bottom.
    /// Active during recording overlay or emoji picker (when keyboard is
    /// hidden). With this active + height=276, hosting fills the whole
    /// keyboard area without leaving stripes off-screen.
    private var hostingBottomToInputBottom: NSLayoutConstraint?

    /// Fixed toolbar height matching ToolbarView (52pt: 48pt content + 4pt top padding).
    private let toolbarHeight: CGFloat = 52

    /// Whether viewWillAppear has fired at least once. Guards the Combine handler
    /// from changing hosting height before the controller is registered with KeyboardState.
    /// WHY: During cold start, the Combine subscription fires in viewDidLoad with a
    /// `.recording` mode, but SwiftUI still presents `.keys` (activeControllerID doesn't
    /// match). Expanding the hosting view at this point shows the toolbar in a full-height
    /// area, displacing it to the middle of the screen.
    private var hasAppeared = false

    /// Whether iOS currently has us on screen: set in viewWillAppear, cleared in
    /// viewDidDisappear. Unlike `hasAppeared`, which latches, this tracks the
    /// present tense.
    ///
    /// Half of the liveness test for claiming an ownerless keyboard area (#260);
    /// `isOnScreen` below is the other half and the one that carries the weight.
    private var isAttached = false

    /// Whether our view hierarchy is actually in a window right now.
    ///
    /// This is the test that decides whether we may claim an ownerless keyboard
    /// area (#260), and it is deliberately fail-closed. Every controller that can
    /// reach a claim has appeared, had its ownership overwritten by a later
    /// appearance, and not been told it disappeared — which describes the live
    /// keyboard whose ownership a dying instance took with it, and equally the
    /// cached instances iOS never notifies (#128). `isAttached` cannot tell them
    /// apart, because it is only written in `viewWillAppear` and
    /// `viewDidDisappear` and a stale controller never gets the latter. Window
    /// attachment can: detaching is what removes the view from the window.
    ///
    /// If this were permissive, a stale controller would *acquire* the area rather
    /// than merely be skipped — it would expand its own hosting to full height
    /// while the on-screen tree still rendered the keys, and lock the live
    /// controller out, since a claim is single-shot. That is the #116 shape, and
    /// strictly worse than the bug being fixed. If it is instead too strict — if
    /// iOS keeps no window on the controller we think is showing — the claim never
    /// fires and behaviour is exactly what it was before #260. `hasWindow=` is
    /// logged on every attempt so a device log settles which it is.
    ///
    /// Both `view` and `inputView` are checked because this controller assigns its
    /// own `inputView`, and either may be the one iOS parents into the keyboard
    /// window. `viewIfLoaded` rather than `view`: asking for the view would load
    /// it, and a controller whose view was never loaded is not on screen anyway.
    private var isOnScreen: Bool {
        viewIfLoaded?.window != nil || inputView?.window != nil
    }

    /// Whether this instance was counted into `KeyboardLifecycleProbe`'s live
    /// census, so `deinit` decrements exactly once and only for instances that
    /// incremented. `deinit` runs for every instance, `viewDidLoad` only for those
    /// whose view is loaded, and an uncounted decrement would drift `live=` — the
    /// one number the next #281 capture is meant to be readable from. No such
    /// instance appears in any of the four device logs analysed (52 controllers,
    /// zero deinits without a viewDidLoad), so this guards a case that is possible
    /// rather than one that is observed.
    private var didCountIntoLiveCensus = false

    override func viewDidLoad() {
        super.viewDidLoad()
        PersistentLog.source = "KBD"
        let memEntry = MemoryFootprint.residentMB()
        // live= is the #281 headline probe: healthy cold starts peak at 2 live
        // controllers, both #281 occurrences peak at 3. See KeyboardLifecycleProbe.
        didCountIntoLiveCensus = true
        let liveOnLoad = KeyboardLifecycleProbe.controllerDidLoad()
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidLoad",
            details: "controllerClass=\(String(describing: type(of: self))) memMB=\(memEntry) live=\(liveOnLoad)"
        ))

        #if DEBUG
        let result = AppGroupDiagnostic.run()
        if #available(iOS 14.0, *) {
            DictusLogger.keyboard.debug(
                "Diagnostic: canWrite=\(result.canWrite, privacy: .public) canRead=\(result.canRead, privacy: .public)"
            )
        }
        #endif

        // Create a KeyboardInputView (UIInputView + UIInputViewAudioFeedback)
        // and assign it as the controller's inputView. This is the critical step
        // that makes playInputClick() work: iOS checks that the UIInputViewController's
        // inputView conforms to UIInputViewAudioFeedback and returns true from
        // enableInputClicksWhenVisible. Without this assignment, click sounds are silent.
        let kbInputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        // Do NOT set translatesAutoresizingMaskIntoConstraints = false on the inputView.
        // iOS manages the inputView's frame via autoresizing masks -- disabling them
        // causes the view to collapse to zero width.

        // #92 fix: kbInputView is opaque by default (UIInputView base) and with
        // backgroundColor=nil it paints a default grey in any region not covered
        // by a subview. During iOS's keyboard entry animation, iOS forces the
        // inputView to ~504pt at constraint priority 1000 (we cannot win against
        // it). Our content fills only 276pt — without these two lines, the
        // remaining 228pt rendered as a visible grey rectangle. Forcing the view
        // truly transparent + non-opaque makes that uncovered area composite
        // with whatever sits behind the keyboard window (the host app),
        // matching what Apple's own keyboards do.
        kbInputView.backgroundColor = .clear
        kbInputView.isOpaque = false

        // --- 1. Create the giellakbd-ios UIKit keyboard ---
        // needsInputModeSwitchKey is false on recent iPhones (system draws its own globe)
        // and true on iPad / older iPhones, where we must supply a next-keyboard key (4.4.1).
        // NOTE: read here it is inaccurate (host connection not yet established); the value
        // is re-checked and the layout rebuilt if needed in viewWillAppear.
        let needsGlobe = needsInputModeSwitchKey
        builtNeedsGlobe = needsGlobe
        let definition = KeyboardLayouts.current(needsGlobe: needsGlobe)
        let theme = Theme.current(for: traitCollection)
        let keyboard = GiellaKeyboardView(definition: definition, theme: theme)
        keyboard.translatesAutoresizingMaskIntoConstraints = false

        // --- 2. Create and wire the delegate bridge ---
        let keyBridge = DictusKeyboardBridge()
        keyBridge.controller = self
        keyBridge.keyboardView = keyboard
        keyboard.delegate = keyBridge
        keyBridge.suggestionState = suggestionState
        keyBridge.onEmojiToggle = { [weak self] in
            self?.toggleEmojiPicker()
        }
        self.bridge = keyBridge
        self.giellaKeyboard = keyboard

        // --- 3. Create SwiftUI hosting for toolbar + recording overlay ONLY ---
        // NOTE: do NOT pass `self` into KeyboardRootView. Storing the controller on
        // the View struct creates a strong ref cycle through UIHostingController that
        // prevents stale controllers from deiniting across app-switches (#134).
        // The view accesses the controller through KeyboardState.shared.controller
        // (weak), which is set in viewWillAppear below.
        let rootView = KeyboardRootView(
            controllerID: controllerID,
            suggestionState: suggestionState,
            bridge: keyBridge,
            onLanguageChanged: { [weak self] newLang in
                self?.handleLanguageChange(newLang)
            }
        )
        let hosting = UIHostingController(rootView: rootView)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "hostingCreated",
            details: "hosting=\(ObjectIdentifier(hosting).debugDescription)"
        ))

        // Critical: retain the hosting controller or it gets deallocated
        self.hostingController = hosting

        // Disable safe area regions so SwiftUI content uses the full hosting bounds.
        // WHY: Keyboard extensions can have unexpected safe area insets from the system.
        // Note: Do NOT set layoutMargins/directionalLayoutMargins to zero — this
        // triggers layout recalculation that causes the keyboard height to shrink
        // when top-row key popups extend above bounds.
        if #available(iOS 16.4, *) {
            hosting.safeAreaRegions = []
        }

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        // Hide hosting view until viewWillAppear has applied the correct state.
        // During cold start, there's a gap between viewDidLoad (hosting created with
        // toolbar content) and viewWillAppear (constraint + SwiftUI state synchronized).
        // Without this, the toolbar briefly renders in an expanded hosting view,
        // displacing FR/mic to the middle of the screen.
        hosting.view.isHidden = true

        // --- 4. Add both views to kbInputView ---
        // Order matters: hosting (toolbar) at top, keyboard below
        kbInputView.addSubview(hosting.view)
        kbInputView.addSubview(keyboard)
        hosting.didMove(toParent: self)

        // --- 5. Set up Auto Layout constraints ---
        // Hosting view (toolbar): pinned to top, leading, trailing. Height = toolbarHeight.
        let hostingHeight = hosting.view.heightAnchor.constraint(equalToConstant: toolbarHeight)
        // Priority 999 (just below .required): ensures our explicit height always wins over
        // UIHostingController's intrinsic content size (compression resistance = 750).
        // At .defaultHigh (750), the constraint was ambiguous with SwiftUI's own sizing,
        // causing the hosting view to get stuck at wrong heights after recording overlay dismiss.
        hostingHeight.priority = UILayoutPriority(999)
        self.hostingHeightConstraint = hostingHeight

        // Prevent SwiftUI content from fighting the height constraint.
        // WHY: UIHostingController sets compression resistance at .defaultHigh (750).
        // When content switches from RecordingOverlay (full height) to ToolbarView (52pt),
        // the stale intrinsic size can compete with our constraint at equal priority.
        // NOTE: Only lower compression resistance, NOT content hugging — the hosting view
        // must be able to EXPAND to full height during recording overlay.
        hosting.view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // Pin keyboard grid to a fixed height (key grid only) so it never stretches
        // beyond its natural 224pt — even when iOS forces the inputView to 504pt
        // during the entry animation. With a bottom-anchor pin the giellaKeyboard
        // would stretch to ~452pt → "double-size keys" flash (#116 / ba12a69).
        let keyGridHeight = computeKeyboardHeight() - toolbarHeight
        let keyboardHeight = keyboard.heightAnchor.constraint(equalToConstant: keyGridHeight)
        keyboardHeight.priority = UILayoutPriority(999)

        // #92 fix: bottom-anchor the content stack inside kbInputView (matches
        // upstream giellakbd-ios). Combined with kbInputView.backgroundColor =
        // .clear, this makes the 228pt empty zone appear at the TOP of the
        // expanded inputView during the entry animation transient — i.e. in
        // the host-app-content region right above the toolbar — instead of at
        // the bottom (between keys and screen edge), which was extremely
        // visible. With the inputView transparent the host app shows through,
        // matching what Apple's own keyboards render in that area.
        let hostingBottomIdle = hosting.view.bottomAnchor.constraint(equalTo: keyboard.topAnchor)
        let hostingBottomExpanded = hosting.view.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor)
        hostingBottomIdle.isActive = true
        hostingBottomExpanded.isActive = false
        self.hostingBottomToKeyboardTop = hostingBottomIdle
        self.hostingBottomToInputBottom = hostingBottomExpanded

        NSLayoutConstraint.activate([
            // UIKit keyboard pinned to the bottom of the inputView
            keyboard.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor),
            keyboard.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
            keyboardHeight,

            // Toolbar (SwiftUI hosting) — bottom anchor swapped at runtime
            // (see hostingBottomToKeyboardTop / hostingBottomToInputBottom)
            hosting.view.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
            hostingHeight
        ])

        // --- 6. Defer the height constraint to viewDidLayoutSubviews first run ---
        // #92: installing this constraint in viewDidLoad fights iOS's
        // priority-1000 UIView-Encapsulated-Layout-Height during the entry
        // animation, producing a visible "keyboard grows then shrinks"
        // transient (956 → 504 → 276 over ~150ms).
        //
        // Upstream giellakbd-ios installs its height constraint in
        // viewDidLayoutSubviews first run, dispatched async to the main queue,
        // with the comment: "If this is removed, iPhone 5s glitches before
        // finding the correct height." Adding the constraint AFTER iOS has
        // completed its initial layout pass lets our 999-priority constraint
        // win without fighting the encapsulated-layout-height directly.
        //
        // Constraint creation moved to installInputViewHeightConstraint().

        // Attempt to prevent top-row key popup clipping. iOS may re-enforce
        // clipsToBounds -- if so, this is a known limitation of third-party keyboard extensions.
        kbInputView.clipsToBounds = false
        hosting.view.clipsToBounds = false

        // Assign as the controller's inputView -- this activates audio feedback
        self.inputView = kbInputView

        // --- 7. Wire post-transcription suggestion refresh ---
        // After dictation inserts text, update the suggestion bar with completions
        // for the last word of the transcription.
        KeyboardState.shared.onTranscriptionInserted = { [weak self] in
            guard let self = self else { return }
            let context = self.textDocumentProxy.documentContextBeforeInput
            self.suggestionState.updateAsync(context: context)
            self.bridge?.updateCapitalization()
        }

        // Memory after all viewDidLoad allocations — delta vs entry tells us
        // per-controller allocation cost (UIHostingController + GiellaKeyboardView
        // + SuggestionState + DictusKeyboardBridge + constraints).
        let memExit = MemoryFootprint.residentMB()
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidLoad_exit",
            details: "memMB=\(memExit) delta=\(memExit - memEntry)"
        ))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // CRITICAL: Disable touch delay on system gesture recognizers.
        // iOS attaches gesture recognizers to the keyboard's UIWindow that have
        // delaysTouchesBegan=true (for system gesture disambiguation at screen edges).
        // This causes edge key touches to be delayed ~100ms, making haptic/popup fire
        // on touchUp instead of touchDown, and long-press accent to fail on outer edges.
        // The original giellakbd-ios uses this exact same technique.
        disableWindowGestureDelay()

        // Issue #116 diagnostic: snapshot state at entry BEFORE any mutation.
        let entryStatus = KeyboardState.shared.dictationStatus.rawValue
        let entryStoredStatus = AppGroup.defaults.string(forKey: SharedKeys.dictationStatus) ?? "nil"
        let entryColdStart = AppGroup.defaults.bool(forKey: SharedKeys.coldStartActive)
        let entryBounds = inputView?.bounds.size ?? .zero
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewWillAppear_entry",
            details: "animated=\(animated) status=\(entryStatus) storedStatus=\(entryStoredStatus) coldStart=\(entryColdStart) inputBounds=\(Int(entryBounds.width))x\(Int(entryBounds.height)) hostingConst=\(hostingHeightConstraint?.constant ?? -1) heightConst=\(heightConstraint?.constant ?? -1) memMB=\(MemoryFootprint.residentMB())"
        ))
        PersistentLog.log(.keyboardDidAppear)
        KeyboardState.shared.registerControllerAppearance(controllerID: controllerID)
        // Point KeyboardState's weak controller ref at the currently-visible controller
        // so call sites in KeyboardRootView and KeyboardState can access textDocumentProxy.
        // Previously set from KeyboardRootView.onAppear, which held a strong ref → #134.
        KeyboardState.shared.controller = self
        hasAppeared = true
        isAttached = true

        // 4.4.1 next-keyboard globe: the host connection now exists, so
        // needsInputModeSwitchKey is finally accurate. If viewDidLoad built the
        // layout with the wrong value (its early read is inaccurate and UIKit warns
        // about it), rebuild once now so the globe matches reality. Skipped in the
        // common case where the value already matched — reloadKeyboardLayout is a
        // full ~200ms UICollectionView rebuild we don't want on every appearance.
        let accurateNeedsGlobe = needsInputModeSwitchKey
        if builtNeedsGlobe != accurateNeedsGlobe {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "globeMismatchReload",
                details: "built=\(builtNeedsGlobe.map(String.init(describing:)) ?? "nil") accurate=\(accurateNeedsGlobe)"
            ))
            reloadKeyboardLayout()
        }

        // (Re)subscribe to the keyboard area mode here, not in viewDidLoad.
        // WHY: iOS caches UIInputViewController instances across app-switches and
        // rarely deallocates them, so stale controllers would keep mutating
        // hostingHeightConstraint on every mode change (issue #128). By subscribing
        // in viewWillAppear and cancelling in viewDidDisappear, only the currently
        // visible controller is reactive. Assignment is idempotent — the previous
        // AnyCancellable is released on reassignment, which cancels its subscription.
        observeKeyboardAreaMode()

        // Force height recalculation when keyboard reappears (e.g., after app switch).
        // Without this, the inputView may retain a stale height from before the switch.
        let oldHeight = heightConstraint?.constant ?? -1
        let newHeight = computeKeyboardHeight()
        heightConstraint?.constant = newHeight
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "heightRecalc_viewWillAppear",
            details: "old=\(oldHeight) new=\(newHeight) hSizeClass=\(traitCollection.horizontalSizeClass.rawValue) vSizeClass=\(traitCollection.verticalSizeClass.rawValue)"
        ))

        // Apply the current keyboard area mode now that we're registered.
        // During cold start, applyAreaMode was skipped (hasAppeared was false).
        // Now that activeControllerID matches, KeyboardRootView.presentedMode agrees
        // with us, so the constraint and SwiftUI content change together — no
        // displaced toolbar. This also restores a picker the user left open when
        // iOS hands the keyboard to a fresh controller.
        let statusBeforeHandle = KeyboardState.shared.dictationStatus.rawValue

        // The hamburger panel does not survive leaving the keyboard (#241 device
        // feedback). Switching away with the globe and coming back put the user
        // straight back into the menu instead of the keys, which is not what
        // returning to a keyboard should mean. The emoji picker deliberately keeps
        // the old restore behaviour: browsing emoji is a task worth resuming,
        // choosing a language is not.
        if KeyboardState.shared.areaMode == .panel {
            KeyboardState.shared.presentAreaMode(.keys)
        }

        applyAreaMode(KeyboardState.shared.areaMode)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewWillAppear_afterHandle",
            details: "statusBefore=\(statusBeforeHandle) statusAfter=\(KeyboardState.shared.dictationStatus.rawValue) mode=\(KeyboardState.shared.areaMode.rawValue) hostingConst=\(hostingHeightConstraint?.constant ?? -1)"
        ))

        inputView?.setNeedsLayout()
        inputView?.layoutIfNeeded()  // Force synchronous layout to reduce loading flicker (#92)

        // Show hosting view now that constraints and SwiftUI state are synchronized.
        // Was hidden in viewDidLoad to prevent cold start flash (toolbar in full-height hosting).
        hostingController?.view.isHidden = false

        // Force synchronous layout AFTER unhiding (#99). During cold start, the status
        // can transition .recording → .idle between handleDictationStatusChange and this
        // unhide. The constraint is updated but the visual frame is stale without this.
        inputView?.layoutIfNeeded()

        // Update theme when keyboard reappears (dark/light mode may have changed)
        if let keyboard = giellaKeyboard {
            keyboard.updateTheme(theme: Theme.current(for: traitCollection))
        }

        // Set initial shift state based on the text field's autocapitalization setting.
        // WHY here and not viewDidLoad: The textDocumentProxy is not fully connected
        // until the view is about to appear. Calling in viewDidLoad would read stale data.
        bridge?.updateCapitalization()

        // Read the host field's input traits now that the connection exists (#200).
        // Search/URL/email fields disable autocorrect and suggestions.
        bridge?.refreshHostPolicy()

        // Re-sync the learned-words dictionary from the App Group (#222).
        // The singleton caches in memory per process; if the user reset the
        // dictionary in the app, this cached keyboard process must drop the
        // stale copy or learned words keep bypassing autocorrect.
        UserDictionary.shared.reload()

        // Set default opening layer from user preference.
        // WHY here not viewDidLoad: viewWillAppear fires each time the keyboard appears,
        // allowing the user to change settings in the app and see the effect immediately.
        let defaultLayer = DefaultKeyboardLayer.active
        if defaultLayer == .numbers {
            giellaKeyboard?.page = .symbols1
        }

        // Refresh prediction language from App Group on every keyboard appearance.
        // WHY here not viewDidLoad: The user can change language in the app between
        // keyboard appearances. viewWillAppear fires each time, picking up the change.
        let lang = AppGroup.defaults.string(forKey: SharedKeys.language) ?? "fr"
        suggestionState.setLanguage(lang)

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "registeredAppearance",
            details: ""
        ))

        // Cold start return detection: log for diagnostics.
        // DON'T clear coldStartActive here -- KeyboardState.refreshFromDefaults() reads it
        // to activate the watchdog grace period (15s instead of 5s). The app's .background
        // handler clears it when the transition is complete.
        if AppGroup.defaults.bool(forKey: SharedKeys.coldStartActive) {
            DictusLogger.keyboard.info("Keyboard returned from cold start, recording should be active")
        }

        #if DEBUG
        if #available(iOS 14.0, *) {
            DictusLogger.keyboard.debug("viewWillAppear -- refreshing mode")
        }
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Issue #116 diagnostic: snapshot final frames after layout settles.
        // We log both sizes and constraint constants so we can detect priority mismatches
        // where iOS imposed a different height than we asked for.
        logLayoutSnapshot(action: "viewDidAppear_settled")

        // #281: record which text field we settled into. Emitted here rather than
        // from viewWillAppear because reading the proxy costs a synchronous round
        // trip to the host app, and viewWillAppear is the timing-sensitive path the
        // failure sits on. Both #281 captures show every doomed controller reaching
        // viewDidAppear, so this loses no occurrence. One line per controller.
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "inputContext_settled",
            details: "\(inputContextProbeDetails) live=\(KeyboardLifecycleProbe.liveCount)"
        ))

        // Issue #129 investigation: viewDidAppear fires BEFORE iOS finishes the
        // keyboard entry animation, so bounds captured here may still be
        // transient. Schedule deferred snapshots to confirm whether 504pt is
        // actually the final, user-visible size — or just a mid-animation value
        // that iOS later resolves to our requested 276pt constraint.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.logLayoutSnapshot(action: "layoutSnapshot_500ms")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.logLayoutSnapshot(action: "layoutSnapshot_1000ms")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.logLayoutSnapshot(action: "layoutSnapshot_2000ms")
        }
    }

    /// First-run flag for viewDidLayoutSubviews. Used by upstream
    /// giellakbd-ios pattern (#92): install the input view height constraint
    /// after iOS finishes its initial layout pass, not in viewDidLoad.
    private var isFirstLayoutPass = true

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if isFirstLayoutPass {
            isFirstLayoutPass = false
            // Defer constraint installation to the next runloop turn so we
            // don't mutate constraints inside iOS's own layout pass. Upstream
            // comment: "If this is removed, iPhone 5s glitches before finding
            // the correct height."
            DispatchQueue.main.async { [weak self] in
                self?.installInputViewHeightConstraint()
            }
        }
    }

    /// Installs the 999-priority height constraint on kbInputView. Called once
    /// (lazy) from the first viewDidLayoutSubviews via async dispatch. Adding
    /// the constraint here, AFTER iOS has completed its initial layout pass,
    /// lets us win against the encapsulated-layout-height (priority 1000)
    /// without the entry animation flashing at 504pt.
    private func installInputViewHeightConstraint() {
        guard heightConstraint == nil, let kbInputView = inputView else { return }
        let height = computeKeyboardHeight()
        let constraint = kbInputView.heightAnchor.constraint(equalToConstant: height)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        self.heightConstraint = constraint
    }

    /// Swap hosting view's bottom anchor between idle and expanded positions.
    /// - Idle: hosting.bottom = keyboard.top (sits above the keys at 52pt).
    /// - Expanded: hosting.bottom = kbInputView.bottom (fills the full
    ///   keyboard area, used when the recording overlay or emoji picker is
    ///   shown and the keyboard view is hidden).
    ///
    /// Without this swap, expanding the hosting height alone (with the idle
    /// bottom anchor still active) pushes hosting.top above kbInputView,
    /// leaving the overlay stuck off-screen — the bug in #92 follow-up.
    private func setHostingExpanded(_ expanded: Bool) {
        if expanded {
            hostingBottomToKeyboardTop?.isActive = false
            hostingBottomToInputBottom?.isActive = true
        } else {
            hostingBottomToInputBottom?.isActive = false
            hostingBottomToKeyboardTop?.isActive = true
        }
    }

    /// Emits the same layout snapshot we log in `viewDidAppear_settled`,
    /// reusable from deferred blocks to compare mid- vs post-animation sizes.
    private func logLayoutSnapshot(action: String) {
        let inputBounds = inputView?.bounds.size ?? .zero
        let keyboardFrame = giellaKeyboard?.frame.size ?? .zero
        let hostingFrame = hostingController?.view.frame.size ?? .zero
        let viewBounds = view.bounds.size
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: action,
            details: "inputBounds=\(Int(inputBounds.width))x\(Int(inputBounds.height)) viewBounds=\(Int(viewBounds.width))x\(Int(viewBounds.height)) keyboardFrame=\(Int(keyboardFrame.width))x\(Int(keyboardFrame.height)) hostingFrame=\(Int(hostingFrame.width))x\(Int(hostingFrame.height)) hostingConst=\(hostingHeightConstraint?.constant ?? -1) heightConst=\(heightConstraint?.constant ?? -1) status=\(KeyboardState.shared.dictationStatus.rawValue) mode=\(KeyboardState.shared.areaMode.rawValue) memMB=\(MemoryFootprint.residentMB())"
        ))
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // We are off screen from here on, whether or not we keep ownership below
        // (#260): a detached controller must not adopt an ownerless dictation.
        isAttached = false

        // Restore system gesture recognizer delay (be a good citizen)
        restoreWindowGestureDelay()

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidDisappear",
            details: "animated=\(animated) memMB=\(MemoryFootprint.residentMB())"
                + " live=\(KeyboardLifecycleProbe.liveCount)"
                + " \(dismissalProbeDetails) \(inputContextProbeDetails)"
        ))
        PersistentLog.log(.keyboardDidDisappear)

        // Tear down the area mode subscription so this (now-detached) controller
        // no longer reacts when KeyboardState publishes. iOS caches
        // UIInputViewController and rarely releases it, so without this cleanup
        // 10+ stale controllers race on hostingHeightConstraint (issue #128).
        // viewWillAppear re-subscribes on reattach.
        areaModeCancellable?.cancel()
        areaModeCancellable = nil

        // Issue #142: skip registerControllerDisappearance during an active
        // dictation session. iOS calls viewDidDisappear on the keyboard right
        // before bringing DictusApp foreground for cold-start; an immediate
        // unregister would flip activeControllerID→nil and isKeyboardVisible
        // →false, making KeyboardRootView.presentedMode fall back to `.keys` and
        // SwiftUI swap RecordingOverlay→ToolbarView while hostingConst is still
        // 276pt. iOS's keyboard-down animation snapshot then captures that
        // inconsistent layout (toolbar centred in expanded hosting), freezing
        // it on screen for the duration of the transition.
        //
        // The successor controller's registerControllerAppearance overwrites
        // activeControllerID, so a clean handoff happens automatically. If the
        // keyboard is truly dismissed during recording (no successor), the area
        // becomes ownerless when we are deallocated — see
        // registerControllerDeallocation (#260).
        let status = KeyboardState.shared.dictationStatus
        if status.ownsKeyboardArea {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "skippedUnregister_activeSession",
                details: "status=\(status.rawValue) activeID=\(KeyboardState.shared.activeControllerID ?? "none")"
            ))
        } else {
            KeyboardState.shared.registerControllerDisappearance(controllerID: controllerID)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "registeredDisappearance",
                details: ""
            ))
        }

        // Darwin observers cleaned up by KeyboardState deinit
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // iOS sends this shortly before it's willing to jetsam the extension.
        // Logging it proves whether the grey-overlay freeze correlates with
        // a memory-pressure signal iOS actually gave us vs an out-of-the-blue kill.
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "didReceiveMemoryWarning",
            details: "memMB=\(MemoryFootprint.residentMB())"
        ))
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        let hadColorChange = traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "traitCollectionDidChange",
            details: "prevStyle=\(previousTraitCollection?.userInterfaceStyle.rawValue ?? -1) newStyle=\(traitCollection.userInterfaceStyle.rawValue) hadColorChange=\(hadColorChange)"
                // #281: both occurrences show the style flipping to dark (2) on a
                // device in light mode, seconds before the teardown, and 15 clean
                // cold starts show no flip at all. If the flip is a different text
                // field arriving, docID changes with it; if it is the same field
                // re-rendered, docID holds. Bounded at 2-3 lines per controller.
                + " docID=\(textDocumentProxy.documentIdentifier.uuidString.prefix(8))"
                + " hasWindow=\(viewIfLoaded?.window != nil || inputView?.window != nil)"
        ))
        // Update keyboard theme when dark/light mode changes while keyboard is visible.
        if hadColorChange {
            let newTheme = Theme.current(for: traitCollection)
            giellaKeyboard?.updateTheme(theme: newTheme)
        }
    }

    deinit {
        // Issue #142 safety net, corrected by #260: viewDidDisappear skips
        // unregistration during an active dictation session to avoid a SwiftUI
        // race that produces a centred-toolbar artefact during cold-start
        // handoff, so a dismissed keyboard would otherwise leave ownership
        // pointing at a deallocated controller.
        //
        // This used to unregister outright whenever we still owned the area, on
        // the assumption that "no successor has registered yet" meant "the
        // keyboard was dismissed". That assumption is false under churn: ownership
        // is last-writer-wins on appearance, so the instance holding it is often
        // not the keyboard on screen, and releasing the area on its way out left
        // the controller that *is* on screen unable to present anything — with no
        // path back, since its viewWillAppear had already run.
        //
        // The area is marked reclaimable now. Every reader still sees an ownerless,
        // invisible keyboard exactly as it did before, so nothing downstream
        // changes; what the marker adds is that a controller still in a window may
        // claim the area (see applyAreaMode).
        KeyboardState.shared.registerControllerDeallocation(controllerID: controllerID)

        // Symmetric tear-down for the addChild()/didMove(toParent:) we did in viewDidLoad.
        // Without this, UIKit holds the hosting controller in `children` and SwiftUI may
        // keep its observation graph alive past our own deinit, perpetuating the
        // KeyboardRootView zombies seen receiving activeControllerChanged broadcasts in
        // logs (#134). Same reasoning applies to giellaKeyboard's superview membership.
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil

        giellaKeyboard?.removeFromSuperview()
        giellaKeyboard = nil

        bridge = nil

        // live=0 on this line marks the exact moment the extension has no
        // controller left, which is the start of the #281 window (#281).
        let liveAfter = didCountIntoLiveCensus
            ? KeyboardLifecycleProbe.controllerDidDeinit()
            : KeyboardLifecycleProbe.liveCount
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "deinit",
            details: "memMB=\(MemoryFootprint.residentMB()) live=\(liveAfter)"
        ))
    }

    // MARK: - Keyboard Height

    /// Calculate the total keyboard height using giellakbd-ios KeyboardHeightProvider
    /// for the key grid height, plus toolbar and padding.
    private func computeKeyboardHeight() -> CGFloat {
        let deviceContext = DeviceContext.current
        let keyGridHeight = KeyboardHeightProvider.height(
            for: deviceContext,
            traitCollection: traitCollection
        )
        // bottomPadding was previously 8pt but had no real effect — keyboard view's
        // bottomAnchor is pinned to kbInputView.bottomAnchor, so the extra height got
        // divided across 4 row cells (+2pt per row), making each visible key 2.3pt
        // taller than Apple's. Setting to 0 restores Apple-matched cell height (#117).
        let bottomPadding: CGFloat = 0
        let total = keyGridHeight + toolbarHeight + bottomPadding
        let screen = UIScreen.main.bounds.size
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "computeKbHeight",
            details: "grid=\(keyGridHeight) total=\(total) screen=\(Int(screen.width))x\(Int(screen.height)) landscape=\(deviceContext.isLandscape)"
        ))
        return total
    }

    // MARK: - Keyboard Area Mode Observation

    /// Observe KeyboardState.areaMode to keep the UIKit side of the keyboard area
    /// in step with what SwiftUI renders: hosting height, hosting bottom anchor,
    /// and whether the key grid is hidden.
    ///
    /// WHY areaModePublisher and not $dictationStatus: the mode is recomputed in
    /// `dictationStatus`'s `didSet`, which runs *after* `$dictationStatus` has
    /// already published. A sink on the status would therefore read a stale mode.
    /// The mode's own publisher carries the value we need — and it emits from
    /// `didSet`, so the synchronous layout below cannot make SwiftUI render an
    /// already-superseded mode. See the note on `KeyboardState.areaMode`.
    ///
    /// WHY Combine instead of NotificationCenter: this needs no manual
    /// notification posts — and it is precisely the NotificationCenter round-trip
    /// that #271 removed.
    private func observeKeyboardAreaMode() {
        areaModeCancellable = KeyboardState.shared.areaModePublisher
            // No .receive(on: .main) — areaMode is only ever set on the main thread
            // (Darwin observer dispatches to main, key taps are UI actions).
            // Staying synchronous ensures the constraint change lands in the same
            // turn as the mode change, BEFORE SwiftUI draws. Without this, there's a
            // 1-frame delay where the overlay renders at 52pt (toolbar height)
            // before the hosting view expands to full height — causing the waveform
            // to flash at the top then drop to center.
            .sink { [weak self] mode in
                self?.applyAreaMode(mode)
            }
    }

    /// React to a keyboard-area mode change: check that we are the controller
    /// allowed to touch the layout, then apply it.
    ///
    /// The probe action names below are deliberately unchanged from the
    /// status-driven handler this replaced — #260 and #261 are open and quote
    /// `dictStatusChange_enter` / `dictStatusChange_skippedInactive` from device
    /// logs. `mode=` is additive.
    private func applyAreaMode(_ mode: KeyboardAreaMode) {
        // The subscription above is deliberately synchronous — no .receive(on: .main)
        // — and this method mutates Auto Layout constraints and view visibility, so
        // an emission from a background thread would corrupt UIKit state silently.
        // WHY assert and not dispatchPrecondition: the latter also traps in release,
        // and crashing a shipped keyboard is worse than the bug it would catch.
        assert(Thread.isMainThread, "applyAreaMode must run on the main thread — it mutates UIKit layout")

        // Issue #116 diagnostic: entry log (fires even when a guard trips).
        let status = KeyboardState.shared.dictationStatus.rawValue
        let oldHosting = hostingHeightConstraint?.constant ?? -1
        let activeID = KeyboardState.shared.activeControllerID ?? "none"
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "dictStatusChange_enter",
            details: "status=\(status) mode=\(mode.rawValue) hasAppeared=\(hasAppeared) oldHosting=\(oldHosting) activeID=\(activeID)"
        ))

        // Don't change hosting height until the controller is registered with
        // KeyboardState: an unregistered controller's KeyboardRootView still
        // presents `.keys`, so expanding now would show the toolbar displaced in a
        // full-height hosting view. viewWillAppear registers, then applies the mode
        // explicitly. The subscription is also created there, and areaModePublisher
        // does not replay on subscribe, so nothing should reach this before
        // viewWillAppear — the guard stays as a cheap invariant on that ordering.
        guard hasAppeared else { return }

        // #260: a dictation can be left with no owning controller at all.
        // Ownership is last-writer-wins on appearance, so under churn an instance
        // iOS is about to throw away can hold the area, and when it is deallocated
        // the keyboard the user is looking at is left unable to present the
        // overlay — ownership is what the guard below and
        // KeyboardRootView.presentedMode both key on, and nothing re-registers us:
        // viewWillAppear already ran.
        //
        // KeyboardState marks such an area reclaimable rather than released, so
        // the controller iOS is showing can claim it here instead of waiting for
        // iOS to build a replacement — which in the captures took 2.5 s, or four
        // seconds and a manual trip to DictusApp.
        //
        // `isOnScreen` is what keeps this from being a licence for the stale
        // controllers the guard below exists to exclude; see its declaration.
        //
        // Only for `.recording`, matching that guard: the pickers are opened by a
        // key on the visible keyboard and are not gated on ownership.
        if mode == .recording, isAttached, KeyboardState.shared.activeControllerID != controllerID {
            let onScreen = isOnScreen
            let claimed = KeyboardState.shared.claimOwnership(
                controllerID: controllerID,
                isOnScreen: onScreen
            )
            if claimed {
                PersistentLog.log(.diagnosticProbe(
                    component: "KeyboardViewController",
                    instanceID: controllerID,
                    action: "claimedOwnerlessArea",
                    details: "status=\(status) mode=\(mode.rawValue) previousActiveID=\(activeID) hasWindow=\(onScreen)"
                ))
            }
        }

        // Defense-in-depth for #128: iOS caches UIInputViewController and does not
        // reliably fire viewDidDisappear on stale instances (observed: controllers
        // responding to Darwin status changes for minutes after losing window
        // attachment, no viewDidDisappear event logged). The subscription-cancel
        // path in viewDidDisappear covers the well-behaved case; this guard
        // short-circuits stale controllers that iOS forgot to notify.
        //
        // It applies to `.recording` only, mirroring KeyboardRootView.presentedMode
        // exactly — the two layers have to agree on what is presented, and that is
        // where the reasoning lives. A picker is opened by a key on the visible
        // keyboard, which is not the case #128 was ever about.
        guard mode != .recording || KeyboardState.shared.activeControllerID == controllerID else {
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "dictStatusChange_skippedInactive",
                details: "status=\(status) mode=\(mode.rawValue) activeID=\(activeID)"
            ))
            return
        }

        applyLayout(for: mode)
    }

    /// The keyboard area's layout, one branch per mode.
    ///
    /// Every case sets all three things explicitly — hosting height, hosting
    /// bottom anchor, key-grid visibility — with no fallthrough. Before #271 this
    /// was a chain of negated guards where restoring the collapsed toolbar height
    /// was conditional on the emoji flag being false, so a full-area state that
    /// was not added to the chain collapsed to 52 pt while still rendering.
    ///
    /// None of these branches touches `heightConstraint`, the keyboard's own
    /// declared height — that remains a no-go zone (#166).
    private func applyLayout(for mode: KeyboardAreaMode) {
        let oldHosting = hostingHeightConstraint?.constant ?? -1
        let status = KeyboardState.shared.dictationStatus.rawValue

        switch mode {
        case .keys:
            giellaKeyboard?.isHidden = false
            hostingHeightConstraint?.constant = toolbarHeight
            setHostingExpanded(false)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_idle",
                details: "old=\(oldHosting) new=\(toolbarHeight) status=\(status) mode=\(mode.rawValue)"
            ))

        case .emoji:
            giellaKeyboard?.isHidden = true
            let fullHeight = computeKeyboardHeight()
            hostingHeightConstraint?.constant = fullHeight
            setHostingExpanded(true)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_emojiOpen",
                details: "old=\(oldHosting) new=\(fullHeight) status=\(status) mode=\(mode.rawValue)"
            ))

        case .panel:
            // Reserved for #241. No view is attached yet, but the geometry is:
            // adding the panel is adding a SwiftUI branch, not editing this switch.
            giellaKeyboard?.isHidden = true
            let fullHeight = computeKeyboardHeight()
            hostingHeightConstraint?.constant = fullHeight
            setHostingExpanded(true)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_panelOpen",
                details: "old=\(oldHosting) new=\(fullHeight) status=\(status) mode=\(mode.rawValue)"
            ))

        case .recording:
            giellaKeyboard?.isHidden = true
            let fullHeight = computeKeyboardHeight()
            hostingHeightConstraint?.constant = fullHeight
            setHostingExpanded(true)
            PersistentLog.log(.diagnosticProbe(
                component: "KeyboardViewController",
                instanceID: controllerID,
                action: "hostingSet_recording",
                details: "old=\(oldHosting) new=\(fullHeight) status=\(status) mode=\(mode.rawValue)"
            ))
        }

        inputView?.setNeedsLayout()
        inputView?.layoutIfNeeded()
    }

    // MARK: - Text Change

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Invalidate autocorrect undo on external text changes (paste, cursor tap, host autocorrect).
        bridge?.suggestionState?.pendingUndo = nil
        // When text changes externally (paste, cursor move, autocorrect by host app),
        // recheck autocapitalization. This ensures shift state stays correct even when
        // the user moves the cursor to a different position in the text.
        bridge?.updateCapitalization()
        // The focused field may have changed (e.g. tapping another field in the
        // same app) — re-read its input traits (#200).
        bridge?.refreshHostPolicy()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        // Some hosts move focus between fields without emitting textDidChange.
        // Re-read the field's input traits so the autocorrect/suggestions policy
        // matches the newly-focused field (#200).
        bridge?.refreshHostPolicy()
    }

    // MARK: - Window Gesture Delay

    /// Hashes of gesture recognizers we disabled, so we can restore them on disappear.
    private var disabledGestureHashes = Set<Int>()

    /// Disable `delaysTouchesBegan` on all UIWindow gesture recognizers.
    ///
    /// WHY: iOS attaches system gesture recognizers to the keyboard's UIWindow with
    /// `delaysTouchesBegan = true`. These recognizers check for system gestures (swipe-back,
    /// Control Center) before delivering touches to the keyboard. This adds ~100ms delay
    /// on edge key touches, causing haptic/popup to fire on touchUp instead of touchDown
    /// and long-press accent popup to fail on outer edge of edge keys.
    ///
    /// This is the same technique used by the original giellakbd-ios keyboard.
    private func disableWindowGestureDelay() {
        guard let window = view.window,
              let recognizers = window.gestureRecognizers else { return }
        for recognizer in recognizers where recognizer.delaysTouchesBegan {
            recognizer.delaysTouchesBegan = false
            disabledGestureHashes.insert(recognizer.hash)
        }
    }

    /// Restore `delaysTouchesBegan` on gesture recognizers we previously disabled.
    private func restoreWindowGestureDelay() {
        guard let window = view.window,
              let recognizers = window.gestureRecognizers else { return }
        for recognizer in recognizers where disabledGestureHashes.contains(recognizer.hash) {
            recognizer.delaysTouchesBegan = true
        }
        disabledGestureHashes.removeAll()
    }

    // MARK: - Language Change

    /// Handles a language cycle from the toolbar's LanguageSwitcherView.
    ///
    /// WHY full rebuild: GiellaKeyboardView (UICollectionView) does not support
    /// hot-swapping its KeyboardDefinition. The cleanest approach is to remove the
    /// old view and create a new one with the updated definition. The ~200ms rebuild
    /// is masked by the language code animation in the toolbar.
    private func handleLanguageChange(_ newLang: SupportedLanguage) {
        // 1. Reload suggestion/autocorrect dictionaries for the new language
        suggestionState.setLanguage(newLang.rawValue)

        // 2. Rebuild the keyboard grid with the new layout
        reloadKeyboardLayout()

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "languageChanged",
            details: "lang=\(newLang.rawValue) layout=\(LayoutType.active.rawValue)"
        ))
    }

    /// Destroys the current GiellaKeyboardView and creates a new one
    /// with the current language and layout preferences from App Group.
    private func reloadKeyboardLayout() {
        guard let kbInputView = inputView else { return }

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "reloadLayout_begin",
            details: "status=\(KeyboardState.shared.dictationStatus.rawValue) oldHosting=\(hostingHeightConstraint?.constant ?? -1) oldHeight=\(heightConstraint?.constant ?? -1) inputBounds=\(Int(kbInputView.bounds.width))x\(Int(kbInputView.bounds.height))"
        ))

        // Remove old keyboard
        giellaKeyboard?.removeFromSuperview()

        // Create new keyboard with updated definition
        // needsInputModeSwitchKey is false on recent iPhones (system draws its own globe)
        // and true on iPad / older iPhones, where we must supply a next-keyboard key (4.4.1).
        let needsGlobe = needsInputModeSwitchKey
        builtNeedsGlobe = needsGlobe
        let definition = KeyboardLayouts.current(needsGlobe: needsGlobe)
        let theme = Theme.current(for: traitCollection)
        let keyboard = GiellaKeyboardView(definition: definition, theme: theme)
        keyboard.translatesAutoresizingMaskIntoConstraints = false

        // Re-wire the bridge
        bridge?.keyboardView = keyboard
        keyboard.delegate = bridge

        // Add to view hierarchy below the hosting view
        kbInputView.addSubview(keyboard)

        // Re-create constraints. Mirrors the bottom-anchor layout from viewDidLoad
        // (#92 fix): keyboard pinned to kbInputView.bottomAnchor with a fixed
        // height, hosting view sits directly above it.
        //
        // Note: the old hostingBottomToKeyboardTop pointed at the previous
        // keyboard view (about to be deallocated) — we deactivate it and
        // create a new one referencing the new keyboard.
        hostingBottomToKeyboardTop?.isActive = false
        if let hostingView = hostingController?.view {
            let keyGridHeight = computeKeyboardHeight() - toolbarHeight
            let keyboardHeight = keyboard.heightAnchor.constraint(equalToConstant: keyGridHeight)
            keyboardHeight.priority = UILayoutPriority(999)
            let newHostingBottomIdle = hostingView.bottomAnchor.constraint(equalTo: keyboard.topAnchor)
            NSLayoutConstraint.activate([
                keyboard.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor),
                keyboard.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
                keyboard.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
                keyboardHeight,
                newHostingBottomIdle
            ])
            self.hostingBottomToKeyboardTop = newHostingBottomIdle
        }
        // The rebuild above always produces a fresh, visible key grid pinned to the
        // idle anchor, so make sure the expanded bottom anchor isn't lingering
        // active from the state we're about to re-derive.
        hostingBottomToInputBottom?.isActive = false

        self.giellaKeyboard = keyboard

        // Re-apply whatever the keyboard area presents, rather than hardcoding the
        // toolbar height. Leaving the hosting view at full height would squash the
        // new key grid below a large empty area (the key-shrinking bug on language
        // switch); hardcoding 52pt instead squashed the emoji picker, which keeps
        // the language switcher in its toolbar and can therefore trigger a reload
        // while it owns the area. The switch is the only thing that gets both right.
        applyLayout(for: KeyboardState.shared.areaMode)

        // Force height recalculation — the new GiellaKeyboardView may have different
        // intrinsic content size during initial layout. Without this, iOS keeps the
        // stale height constraint from before the rebuild, causing a visible gap
        // between the toolbar and the key grid.
        let oldHeightRL = heightConstraint?.constant ?? -1
        let newHeightRL = computeKeyboardHeight()
        heightConstraint?.constant = newHeightRL
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "reloadLayout_heightRecalc",
            details: "old=\(oldHeightRL) new=\(newHeightRL)"
        ))
        kbInputView.setNeedsLayout()
        kbInputView.layoutIfNeeded()
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "reloadLayout_end",
            details: "inputBounds=\(Int(kbInputView.bounds.width))x\(Int(kbInputView.bounds.height)) keyboardFrame=\(Int(keyboard.frame.width))x\(Int(keyboard.frame.height)) hostingFrame=\(Int(hostingController?.view.frame.width ?? 0))x\(Int(hostingController?.view.frame.height ?? 0))"
        ))

        // Apply current shift state
        bridge?.updateCapitalization()
    }

    // MARK: - Emoji Picker

    /// Toggle emoji picker visibility, called by the bridge's emoji key through
    /// the onEmojiToggle closure.
    ///
    /// It only moves the shared mode: the layout follows from the $areaMode
    /// subscription and SwiftUI re-renders off the same value. Before #271 this
    /// method mutated a controller-local Bool, drove the layout by hand, and then
    /// posted a NotificationCenter message so KeyboardRootView's own Bool could
    /// catch up — three ways for the two layers to disagree.
    func toggleEmojiPicker() {
        KeyboardState.shared.toggleEmojiPresentation()
    }
}

// MARK: - Notification names for keyboard internal communication

extension Notification.Name {
    /// Posted by KeyboardViewController when text changes externally (paste, cursor move).
    /// KeyboardView listens for this to recheck autocapitalisation.
    static let dictusTextDidChange = Notification.Name("dictusTextDidChange")
}
