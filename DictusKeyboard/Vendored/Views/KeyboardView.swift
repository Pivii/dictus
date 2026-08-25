// DictusKeyboard/Vendored/Views/GiellaKeyboardView.swift
// Vendored from giellakbd-ios Keyboard/Views/GiellaKeyboardView.swift
// Stripped: No external dependencies to remove (no Sentry in this file)

import UIKit
import AudioToolbox
import DictusCore

protocol GiellaKeyboardViewDelegate: AnyObject {
    func didSwipeKey(_ key: KeyDefinition)
    func didTriggerKey(_ key: KeyDefinition)
    func didTriggerDoubleTap(forKey key: KeyDefinition)
    func didTriggerHoldKey(_ key: KeyDefinition)
    /// Perform `key`'s auto-repeat action and report whether a deletion was actually
    /// issued. The repeat tick fires its haptic and its click on that answer (#390).
    func didTriggerRepeat(_ key: KeyDefinition, wordMode: Bool) -> Bool
    func didMoveCursor(_ movement: Int)
}

@objc protocol GiellaKeyboardViewKeyboardKeyDelegate {
    @objc func didTriggerKeyboardButton(sender: UIView, forEvent event: UIEvent)
}

protocol GiellaKeyboardViewProvider {
    var page: KeyboardPage { get set }
    func update()
    func remove()
    var topAnchor: NSLayoutYAxisAnchor { get }
    var bottomAnchor: NSLayoutYAxisAnchor { get }
    var leftAnchor: NSLayoutXAxisAnchor { get }
    var rightAnchor: NSLayoutXAxisAnchor { get }
}

final internal class GiellaKeyboardView: UIView,
    GiellaKeyboardViewProvider,
    UICollectionViewDataSource,
    UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout,
    LongPressOverlayDelegate,
    LongPressCursorMovementDelegate
{
    // The three cadences below are Apple's own, measured rather than guessed --
    // Apple documents none of this. See docs/research/419-backspace-cadence/ for the
    // timeline and the raw samples (#419).
    private static let pauseBeforeRepeatTimeInterval: TimeInterval = 0.5
    private static let keyRepeatTimeInterval: TimeInterval = 0.1
    /// Word mode is slower than character mode, not faster: Apple's word deletions
    /// arrive as spaced waves 345.7-358.6 ms apart (mean 350.0 over 20 intervals),
    /// where ours used to arrive at the character cadence -- ten words a second, with
    /// no gap between them, which is how a held backspace ate whole paragraphs (#419).
    private static let wordModeRepeatTimeInterval: TimeInterval = 0.35
    private var theme: Theme

    private let definition: KeyboardDefinition

    weak var delegate: (GiellaKeyboardViewDelegate & GiellaKeyboardViewKeyboardKeyDelegate)?

    private var ghostKeyView: GhostKeyView?

    private var currentPage: [[KeyDefinition]] {
        return keyDefinitionsForPage(page)
    }

    private func keyDefinitionsForPage(_ page: KeyboardPage) -> [[KeyDefinition]] {
        guard let layout = definition.currentDeviceLayout else {
            return []
        }
        switch page {
        case .symbols1:
            return layout.symbols1
        case .symbols2:
            return layout.symbols2
        case .shifted, .capslock:
            return layout.shifted
        default:
            return layout.normal
        }
    }

    /// The row a long-press popup sizes its keys against: the first of the current page's
    /// letter rows.
    ///
    /// WHY not `currentPage.first`, which is what this was (#337): with the number row on
    /// (#331) the first row of a letter page is the ten digits, and QWERTZ is the one layout
    /// whose letter rows do not carry ten keys — ü closes the top row, ö and ä the home row
    /// (#151). Sizing off the first row therefore moved the divisor 11 → 10 the moment the
    /// setting was turned on, and every QWERTZ popup key got ~10% wider. The digit row is not
    /// representative of the keyboard the popup belongs to; the letter rows are.
    ///
    /// WHY not the pressed key's own row, the other candidate in #337: it would size the popup
    /// by an accident of which row was tapped, and QWERTZ rows 1-2 and row 3 do not agree.
    ///
    /// WHY the row is recognised by its contents rather than by asking
    /// `KeyboardLayouts.drawsDigitRow`: that flag is read at long-press time and the page was
    /// built earlier, so the two can disagree while a rebuild is pending. The contents cannot.
    ///
    /// The symbols pages are excluded because their leading digits are their own — `symbols1`
    /// carries `1234567890` as its real first row and never gets the injected one.
    private var popupSizingRow: [KeyDefinition]? {
        let rows = currentPage
        switch page {
        case .normal, .shifted, .capslock:
            guard let first = rows.first, first.isDigitRow else {
                return rows.first
            }
            return rows.dropFirst().first
        case .symbols1, .symbols2:
            return rows.first
        }
    }

    public var page: KeyboardPage = .normal {
        didSet {
            update()
        }
    }

    private let reuseIdentifier = "cell"
    private let collectionView: UICollectionView
    private let layout = UICollectionViewFlowLayout()

    private var longpressController: LongPressBehaviorProvider?
    private var currentlyLongpressedKey: KeyDefinition?

    private var keyboardButtonFrame: CGRect? {
        didSet {
            // CRITICAL — never mutate the view hierarchy here (#202). This setter runs
            // inside the collection view's layout pass (`willDisplay`), and `bounds.didSet`
            // resets it to nil on every Auto Layout pass. The original giellakbd code
            // tore down and re-added the overlay button on each change; addSubview /
            // removeFromSuperview invalidate the parent's layout, which re-runs the pass,
            // which fires this setter again → infinite layout loop. On device the loop
            // allocates until the ~90 MB jetsam limit kills the extension (~4 s); on the
            // simulator it spins forever and the keyboard renders as a blank grey area.
            // Instead: create the button once, then only move/hide it — neither
            // `frame` assignment nor `isHidden` invalidates the parent's layout.
            guard keyboardButtonFrame != oldValue else { return }
            if let keyboardButtonFrame = keyboardButtonFrame {
                let button = keyboardButtonExtraButton ?? makeKeyboardButton()
                button.frame = keyboardButtonFrame
                button.isHidden = false
            } else {
                keyboardButtonExtraButton?.isHidden = true
            }
        }
    }

    /// One-time creation of the invisible tap surface overlaying the globe cell.
    /// Collection view cells are reused, so a stable UIButton on top of the cell is the
    /// reliable way to catch taps for `advanceToNextInputMode()`. Called at most once
    /// per keyboard view; the single `addSubview` happens before the first frame is
    /// visible, so it cannot feed the layout loop described above.
    private func makeKeyboardButton() -> UIButton {
        let button = UIButton()
        button.backgroundColor = .clear
        button.isAccessibilityElement = true
        button.accessibilityLabel = NSLocalizedString("accessibility.nextKeyboard", comment: "")
        // .allTouchEvents is REQUIRED: the delegate forwards to UIInputViewController.
        // handleInputModeList(from:with:), which needs the complete touch stream to
        // distinguish tap (advance to next keyboard) from long-press (keyboard picker
        // menu) and to support drag-selection inside the menu.
        button.addTarget(delegate,
                         action: #selector(GiellaKeyboardViewKeyboardKeyDelegate.didTriggerKeyboardButton),
                         for: UIControl.Event.allTouchEvents)
        addSubview(button)
        keyboardButtonExtraButton = button
        return button
    }

    private var keyboardButtonExtraButton: UIButton?
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private(set) lazy var longpressGestureRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(GiellaKeyboardView.touchesFoundLongpress))
        recognizer.cancelsTouchesInView = false
        // Ensure touchesBegan is delivered immediately to the view, without waiting
        // for the gesture recognizer to fail. This prevents iOS from delaying touch
        // delivery at screen edges where system gesture disambiguation can add ~100ms.
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        return recognizer
    }()

    required init(definition: KeyboardDefinition, theme: Theme) {
        self.definition = definition
        self.theme = theme

        collectionView = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)

        super.init(frame: CGRect.zero)
        update()

        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(KeyCell.self, forCellWithReuseIdentifier: reuseIdentifier)
        collectionView.isUserInteractionEnabled = false
        collectionView.isScrollEnabled = false

        addSubview(collectionView)
        collectionView.topAnchor.constraint(equalTo: topAnchor).enable()
        collectionView.bottomAnchor.constraint(equalTo: bottomAnchor).enable()
        collectionView.leftAnchor.constraint(equalTo: leftAnchor).enable()
        collectionView.rightAnchor.constraint(equalTo: rightAnchor).enable()
        collectionView.backgroundColor = .clear

        addGestureRecognizer(longpressGestureRecognizer)

        // Pre-warm the local haptic generator so first touch has zero latency
        hapticFeedback.prepare()

        isMultipleTouchEnabled = true
    }

    func updateTheme(theme: Theme) {
        self.theme = theme
        update()
    }

    /// Current label for the adaptive accent key. Updated by the bridge after each keystroke.
    /// Defaults to apostrophe (the most useful non-letter character in French).
    var accentKeyLabel: String = "'"

    public func update() {
        backgroundColor = theme.backgroundColor
        keyboardButtonFrame = nil
        calculateRows()
    }

    /// Update the accent key label and refresh its cell.
    /// Called by DictusKeyboardBridge after every keystroke to keep the accent key's
    /// displayed character in sync with context (accent after vowel, apostrophe otherwise).
    func updateAccentKeyLabel(_ label: String) {
        guard label != accentKeyLabel else { return }
        accentKeyLabel = label
        // Update the accent key cell directly without reloadItems.
        // reloadItems triggers a collection view layout pass which causes iOS to
        // recalculate the keyboard height — shrinking keys on top-row taps because
        // the popup overlay extends above bounds.
        for section in 0..<currentPage.count {
            for row in 0..<currentPage[section].count {
                if case .input(_, let alt) = currentPage[section][row].type, alt == "accent" {
                    let indexPath = IndexPath(row: row, section: section)
                    if let cell = collectionView.cellForItem(at: indexPath) as? KeyCell {
                        let key = KeyDefinition(type: .input(key: accentKeyLabel, alternate: nil))
                        cell.configure(page: page, key: key, theme: theme, traits: self.traitCollection)
                    }
                    return
                }
            }
        }
    }

    func remove() {
        delegate = nil
        removeFromSuperview()
    }

    // MARK: - Overlay handling

    private(set) var overlays: [KeyType: KeyOverlayView] = [:]

    override var bounds: CGRect {
        didSet {
            // CRITICAL (#202): only rebuild when the geometry actually changed.
            // Auto Layout re-assigns bounds (same value) on every layout pass. The
            // unconditional update() -> reloadData() was harmless while nothing in a
            // display pass dirtied the parent's layout, but the globe key's overlay
            // button (frame/visibility updates during `willDisplay`) re-marks this view
            // for layout on each pass: bounds re-set -> update() -> reloadData() ->
            // willDisplay -> layout dirty -> bounds re-set... An infinite loop that
            // allocates cells until jetsam kills the extension (measured: ~2200
            // reloadData cycles, 75k cells, 1.8 GB before the kill). Guarding on a real
            // change breaks the cycle at its root.
            guard bounds != oldValue else { return }
            update()
        }
    }

    private func ensureValidKeyView(at indexPath: IndexPath) -> Bool {
        guard collectionView.cellForItem(at: indexPath)?.subviews.first?.subviews.first?.subviews.first != nil else {
            return false
        }
        return true
    }

    private func applyOverlayConstraints(to overlay: KeyOverlayView, ghostKeyView: GhostKeyView) {
        guard let superview = superview else {
            return
        }

        overlay.heightAnchor
            .constraint(greaterThanOrEqualTo: ghostKeyView.heightAnchor)
            .enable(priority: .defaultHigh)

        overlay.widthAnchor.constraint(
            greaterThanOrEqualTo: ghostKeyView.widthAnchor,
            constant: theme.popupCornerRadius * 2)
            .enable(priority: .required)

        // REMOVED (#69): topAnchor constraint caused Auto Layout to shrink keyboard
        // keys when top-row popups extended above bounds. The overlay renders above
        // bounds safely because clipsToBounds = false on all ancestor views.

        let offset: CGFloat = 0.5
        overlay.bottomAnchor.constraint(equalTo: ghostKeyView.contentView.bottomAnchor, constant: offset)
            .enable(priority: .defaultHigh)

        overlay.centerXAnchor.constraint(equalTo: ghostKeyView.centerXAnchor)
            .enable(priority: .defaultHigh)

        overlay.leftAnchor.constraint(greaterThanOrEqualTo: ghostKeyView.leftAnchor)
            .enable(priority: .defaultHigh)
        overlay.leftAnchor
            .constraint(greaterThanOrEqualTo: superview.leftAnchor)
            .enable(priority: .required)

        overlay.rightAnchor.constraint(lessThanOrEqualTo: ghostKeyView.rightAnchor)
            .enable(priority: .defaultHigh)
        overlay.rightAnchor
            .constraint(lessThanOrEqualTo: superview.rightAnchor)
            .enable(priority: .required)
    }

    private func showOverlay(forKeyAtIndexPath indexPath: IndexPath) {
        guard let keyCell = collectionView.cellForItem(at: indexPath) as? KeyCell,
              let keyView = keyCell.keyView,
              ensureValidKeyView(at: indexPath) else {
            return
        }
        let key = currentPage[indexPath.section][indexPath.row]
        removeAllOverlays()

        ghostKeyView = GhostKeyView(keyView: keyView, in: self)
        guard let ghostKeyView = ghostKeyView else {
            return
        }

        ghostKeyView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(ghostKeyView)

        ghostKeyView.leftAnchor.constraint(equalTo: self.leftAnchor, constant: ghostKeyView.frame.minX).enable(priority: .required)
        ghostKeyView.topAnchor.constraint(equalTo: self.topAnchor, constant: ghostKeyView.frame.minY).enable(priority: .required)
        ghostKeyView.widthAnchor.constraint(equalToConstant: ghostKeyView.frame.width).enable(priority: .required)
        ghostKeyView.heightAnchor.constraint(equalToConstant: ghostKeyView.frame.height).enable(priority: .required)

        let overlay = KeyOverlayView(ghostKeyView: ghostKeyView, key: key, theme: theme)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(overlay)

        applyOverlayConstraints(to: overlay, ghostKeyView: ghostKeyView)
        overlays[key.type] = overlay

        overlay.clipsToBounds = false

        let keyLabelContainerView = UIView()
        keyLabelContainerView.backgroundColor = .clear
        keyLabelContainerView.translatesAutoresizingMaskIntoConstraints = false

        // Emoji key popup: show SF Symbol (monochrome) instead of colored emoji glyph.
        let isEmojiKey: Bool
        if case let .input(title, _) = key.type, title == "\u{1F600}" {
            isEmojiKey = true
        } else {
            isEmojiKey = false
        }

        let keyLabelHeight = longpressKeySize().height
        overlay.overlayContentView.addSubview(keyLabelContainerView)

        if isEmojiKey {
            let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
            let imageView = UIImageView(image: UIImage(systemName: "face.smiling", withConfiguration: config))
            imageView.tintColor = theme.textColor
            imageView.contentMode = .center
            imageView.translatesAutoresizingMaskIntoConstraints = false
            keyLabelContainerView.addSubview(imageView)
            imageView.centerXAnchor.constraint(equalTo: keyLabelContainerView.centerXAnchor).isActive = true
            imageView.centerYAnchor.constraint(equalTo: keyLabelContainerView.centerYAnchor).isActive = true
        } else {
            let keyLabel = UILabel(frame: .zero)
            keyLabel.clipsToBounds = false
            if case let .input(title, _) = key.type {
                keyLabel.text = title
            }
            keyLabel.textColor = theme.textColor
            switch page {
            case .normal:
                keyLabel.font = theme.popupLowerKeyFont
            default:
                keyLabel.font = theme.popupCapitalKeyFont
            }
            keyLabel.textAlignment = .center
            keyLabel.translatesAutoresizingMaskIntoConstraints = false
            keyLabelContainerView.addSubview(keyLabel)
            keyLabel.centerIn(superview: keyLabelContainerView)
        }

        keyLabelContainerView.heightAnchor.constraint(equalToConstant: keyLabelHeight).enable(priority: .required)
        keyLabelContainerView.fill(superview: overlay.overlayContentView)

        // NOTE: Do NOT call superview?.setNeedsLayout() here.
        // The overlay has its own constraints and will layout correctly.
        // Forcing the parent (kbInputView) to relayout causes the keyboard
        // height to expand on top-row key taps because the overlay extends
        // above bounds and iOS resolves the height constraint upward.
    }

    func removeOverlay(forKey key: KeyDefinition) {
        ghostKeyView?.removeFromSuperview()
        ghostKeyView = nil
        overlays[key.type]?.removeFromSuperview()
        overlays[key.type] = nil
    }

    func removeAllOverlays() {
        ghostKeyView?.removeFromSuperview()
        ghostKeyView = nil
        for overlay in overlays.values {
            overlay.removeFromSuperview()
        }
        overlays = [:]
    }

    // MARK: - LongPressOverlayDelegate

    func longpress(didCreateOverlayContentView contentView: UIView) {
        hapticFeedback.impactOccurred()

        if overlays.first?.value.overlayContentView == nil {
            if let activeKey = activeKey {
                showOverlay(forKeyAtIndexPath: activeKey.indexPath)
            }
        }

        guard let overlayContentView = self.overlays.first?.value.overlayContentView else {
            return
        }

        overlayContentView.subviews.forEach { $0.removeFromSuperview() }
        overlayContentView.addSubview(contentView)
        contentView.setContentCompressionResistancePriority(.required, for: .vertical)
        contentView.fill(superview: overlayContentView)

        if activeKey != nil,
            let longpressValues = (self.longpressController as? LongPressOverlayController)?.longpressValues {
            let count = longpressValues.count

            let widthConstant: CGFloat
            if count > theme.popupLongpressKeysPerRow {
                widthConstant = longpressKeySize().width * ceil(CGFloat(count) / 2.0) + theme.keyHorizontalMargin
            } else {
                widthConstant = longpressKeySize().width * CGFloat(count) + theme.keyHorizontalMargin
            }

            let heightConstant: CGFloat

            if count > theme.popupLongpressKeysPerRow {
                heightConstant = longpressKeySize().height * 2
            } else {
                heightConstant = longpressKeySize().height
            }

            contentView.widthAnchor.constraint(equalToConstant: widthConstant).enable(priority: .required)
            contentView.heightAnchor.constraint(equalToConstant: heightConstant).enable(priority: .required)
        } else {
            let constant = longpressKeySize().height
            contentView.heightAnchor.constraint(equalToConstant: constant).enable(priority: .required)
        }
        contentView.layoutIfNeeded()
    }

    func longpressDidCancel() {
        longpressController = nil
        currentlyLongpressedKey = nil
        collectionView.alpha = 1.0
        if shouldUseiPadLayout, let activeKey = activeKey {
            switch activeKey.key.type {
            case .spacebar(name: _):
                break
            default:
                delegate?.didTriggerKey(activeKey.key)
            }
        }
    }

    func longpress(didSelectKey key: KeyDefinition) {
        delegate?.didTriggerKey(key)
        longpressController = nil
        currentlyLongpressedKey = nil
    }

    func longpressFrameOfReference() -> CGRect {
        return bounds
    }

    func longpressKeySize() -> CGSize {
        switch currentlyLongpressedKey?.type {
        case .returnkey(name: _):
            return CGSize(width: 50, height: 35)
        case .keyboardMode:
            return CGSize(width: 75, height: 53)
        default:
            break
        }

        let width = bounds.size.width / CGFloat(popupSizingRow?.count ?? 10)
        // Reduce height to 60% so first-row popups stay within keyboard bounds (#69).
        var height = ((bounds.size.height / CGFloat(currentPage.count)) - theme.popupCornerRadius * 2) * 0.6
        height = max(24.0, height)
        return CGSize(
            width: width,
            height: height
        )
    }

    // MARK: - LongPressCursorMovementDelegate

    func longpress(movedCursor: Int) {
        delegate?.didMoveCursor(movedCursor)
    }

    // MARK: - Input handling

    struct KeyTriggerTiming {
        let time: TimeInterval
        let key: KeyDefinition

        static let doubleTapTime: TimeInterval = 0.4
    }

    var keyTriggerTiming: KeyTriggerTiming?
    var keyRepeatTimer: Timer?
    var dismissOverlayTimer: Timer?

    /// Tracks how many times the key repeat timer has fired during the current hold.
    /// Used to switch from character-level to word-level deletion after threshold.
    private var deleteRepeatCount: Int = 0

    /// After this many character repeats, switch to word-level deletion.
    ///
    /// Apple switches on the 21st repeat tick, so 20 here (#419). At the 0.1 s
    /// character cadence that puts the switch 2.5 s after touch-down instead of the
    /// 1.5 s it used to take -- the "arrives too early" half of the complaint. The
    /// measurement cannot say whether Apple counts ticks or elapsed time, because its
    /// character cadence is fixed: 20 ticks and 2.0 s are the same moment.
    private static let wordModeThreshold = 20

    struct ActiveKey: Hashable {
        static func == (lhs: GiellaKeyboardView.ActiveKey, rhs: GiellaKeyboardView.ActiveKey) -> Bool {
            return lhs.key.type == rhs.key.type
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(key.type)
        }

        let key: KeyDefinition
        let indexPath: IndexPath
    }

    var activeKey: ActiveKey? {
        willSet {
            dismissOverlayTimer?.invalidate()
            dismissOverlayTimer = nil

            if let activeKey = activeKey,
                let cell = collectionView.cellForItem(at: activeKey.indexPath) as? KeyCell,
                newValue?.indexPath != activeKey.indexPath {
                cell.keyView?.active = false
            }
            if newValue == nil, let activeKey = activeKey {
                dismissOverlayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false, block: { [weak self] _ in
                    self?.removeOverlay(forKey: activeKey.key)
                })
                stopKeyRepeat(reason: "touch")
            }

            if let key = newValue, key.key.type.supportsRepeatTrigger, keyRepeatTimer == nil {
                keyRepeatTimer = makeKeyRepeatTimer(timeInterval: GiellaKeyboardView.pauseBeforeRepeatTimeInterval)
            }
        }
        didSet {
            if let activeKey = activeKey,
                let cell = collectionView.cellForItem(at: activeKey.indexPath) as? KeyCell,
                activeKey.indexPath != oldValue?.indexPath {
                cell.keyView?.active = true
                if case .input = activeKey.key.type, !shouldUseiPadLayout {
                    showOverlay(forKeyAtIndexPath: activeKey.indexPath)
                }
            }
        }
    }

    /// Schedule the auto-repeat tick.
    ///
    /// WHY the block form rather than `target:selector:` (#390): a scheduled `Timer` is
    /// retained by its run loop AND retains its target, so the selector form kept this
    /// whole view alive after the controller had dropped it. A hold interrupted by a
    /// layout rebuild or by the keyboard being dismissed left a detached view ticking
    /// haptics forever. The sibling `dismissOverlayTimer` above already takes
    /// `[weak self]`; this now matches it.
    private func makeKeyRepeatTimer(timeInterval: TimeInterval) -> Timer {
        return Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                // Nothing left to stop this from the inside. The tick count went with
                // the view, so the line reports it as unknown rather than as zero.
                timer.invalidate()
                PersistentLog.log(.keyRepeatStopped(ticks: -1, reason: "viewDeallocated"))
                return
            }
            self.keyRepeatTimerDidTrigger()
        }
    }

    /// Invalidate the auto-repeat timer and close its log entry.
    ///
    /// Logs only a repeat that had actually engaged: every backspace *tap* schedules the
    /// same timer for its 0.5 s pause, and a line per keystroke would bury the signal in
    /// a 1 MB log whose reader is an agent (#255).
    private func stopKeyRepeat(reason: String) {
        keyRepeatTimer?.invalidate()
        keyRepeatTimer = nil
        if deleteRepeatCount > 0 {
            PersistentLog.log(.keyRepeatStopped(ticks: deleteRepeatCount, reason: reason))
        }
        deleteRepeatCount = 0
    }

    /// Stop any auto-repeat in flight, from outside the touch sequence.
    ///
    /// WHY this exists (#390): `activeKey` is cleared by `touchesEnded` and
    /// `touchesCancelled` and by nothing else, so a view torn down mid-hold kept a
    /// populated `activeKey` and a live timer. The controller calls this when it goes
    /// off screen and before it drops this view, and `willMove(toWindow:)` below calls
    /// it for every other path that detaches us.
    func cancelKeyRepeat(reason: String) {
        stopKeyRepeat(reason: reason)
        // Clearing the active key is what `touchesCancelled` does, and it is what stops
        // the tick's own `activeKey != nil` guard from letting a stale hold resume if
        // anything reschedules. `stopKeyRepeat` already ran, so the `willSet` below
        // finds no timer and logs nothing a second time.
        activeKey = nil
    }

    /// Leaving the window is the one teardown signal this view gets on every path that
    /// drops it: a layout rebuild, the controller deallocating, the keyboard being
    /// dismissed mid-hold. None of them delivers a touch event (#390).
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            cancelKeyRepeat(reason: "windowDetached")
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        // Fire haptic on touchDown for ALL keys (not just triggersOnTouchDown).
        // The delegate's didTriggerKey() may fire on touchUp for input keys,
        // but the user should FEEL the tap immediately on finger contact.
        // The matching click is played in handleTouches below, as soon as the touch
        // resolves to a key — it needs the key to pick a category, the haptic does not (#286).
        hapticFeedback.prepare()
        HapticFeedback.keyTapped()

        if let longpressController = self.longpressController, let touch = touches.first {
            longpressController.touchesBegan(touch.location(in: collectionView))
            return
        }

        if let key = activeKey?.key {
            if key.type.triggersOnTouchUp {
                if let delegate = delegate {
                    delegate.didTriggerKey(key)
                }
            }
            activeKey = nil
        }

        handleTouches(touches)
    }

    /// Play `key`'s click, if it has one. Silent keys (spacer, caps) play nothing.
    private func playSound(for key: KeyDefinition) {
        guard let category = KeySound.category(for: key) else { return }
        AudioServicesPlaySystemSound(category.systemSoundID)
    }

    private func handleTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            let touchPoint = clampedPoint(touch.location(in: collectionView))
            if let indexPath = collectionView.indexPathForItem(at: touchPoint) {
                let key = currentPage[indexPath.section][indexPath.row]

                // Click on finger contact, in step with the haptic fired above (#286).
                // This is the only point where a touch resolves to a key, so it is also
                // the only place the click is emitted — the bridge handlers no longer
                // play one, which is what keeps touchDown keys from clicking twice.
                // Placed before the double-tap branch below: that branch returns early,
                // and a double-tapped shift must still click exactly once.
                playSound(for: key)

                if key.type.supportsDoubleTap {
                    let timeInterval = Date.timeIntervalSinceReferenceDate
                    if let keyTriggerTiming = keyTriggerTiming {
                        if max(0.0, timeInterval - keyTriggerTiming.time) < KeyTriggerTiming.doubleTapTime {
                            if let delegate = delegate {
                                delegate.didTriggerDoubleTap(forKey: key)
                                self.keyTriggerTiming = nil
                                return
                            }
                        }
                    }
                    keyTriggerTiming = KeyTriggerTiming(time: timeInterval, key: key)
                }

                if !key.type.isInputKey {
                    removeAllOverlays()
                }

                if key.type.triggersOnTouchDown {
                    if let delegate = delegate {
                        delegate.didTriggerKey(key)
                    }
                }

                let isSymbolsKey = key.type == .symbols || key.type == .shiftSymbols
                let shouldSetActiveKey = (key.type.triggersOnTouchUp ||
                                         key.type.supportsRepeatTrigger ||
                                         key.type.triggersOnTouchDown) && !isSymbolsKey

                if shouldSetActiveKey {
                    activeKey = ActiveKey(key: key, indexPath: indexPath)
                }
            }
        }
    }

    /// Clamp a touch point into the collection view's content area.
    ///
    /// WHY: `indexPathForItem(at:)` returns nil if the point is even 1pt outside any
    /// cell's frame. Edge keys (a, q, p, m) have their outer edge flush with the screen,
    /// but the user's finger center can land slightly outside. Clamping the point inward
    /// by a small margin ensures `indexPathForItem` finds the intended edge cell.
    ///
    /// This approach is simpler and more reliable than iterating visibleCells, because
    /// it uses the same layout engine that `indexPathForItem` uses internally.
    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        let margin: CGFloat = 4.0
        return CGPoint(
            x: min(max(point.x, margin), collectionView.bounds.width - margin),
            y: min(max(point.y, margin), collectionView.bounds.height - margin)
        )
    }

    override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let longpressController = self.longpressController, let touch = touches.first {
            longpressController.touchesMoved(touch.location(in: collectionView))
            return
        }

        if let activeKey = activeKey,
            let cell = collectionView.cellForItem(at: activeKey.indexPath) as? KeyCell,
            let swipeKeyView = cell.keyView,
            swipeKeyView.isSwipeKey,
            let touchLocation = touches.first?.location(in: cell.superview) {
            let deadZone: CGFloat = 20.0
            let delta: CGFloat = 60.0
            let yOffset = touchLocation.y - cell.center.y

            var percentage: CGFloat = 0.0
            if yOffset > deadZone {
                if yOffset - deadZone > delta {
                    percentage = 1.0
                } else {
                    percentage = (yOffset - deadZone) / delta
                }
            }
            swipeKeyView.percentageAlternative = percentage
            return
        }

        if activeKey != nil {
            for touch in touches {
                let movePoint = clampedPoint(touch.location(in: collectionView))
                if let indexPath = collectionView.indexPathForItem(at: movePoint) {
                    let key = currentPage[indexPath.section][indexPath.row]
                    activeKey = ActiveKey(key: key, indexPath: indexPath)
                } else {
                    activeKey = nil
                }
            }
        }
    }

    override func touchesCancelled(_: Set<UITouch>, with _: UIEvent?) {
        longpressController = nil
        activeKey = nil
    }

    override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let longpressController = self.longpressController, let touch = touches.first {
            longpressController.touchesEnded(touch.location(in: collectionView))
            removeAllOverlays()
            activeKey = nil
            return
        }

        if let activeKey = activeKey {
            if activeKey.key.type.triggersOnTouchUp {
                if let cell = collectionView.cellForItem(at: activeKey.indexPath) as? KeyCell,
                    let swipeKeyView = cell.keyView,
                    swipeKeyView.isSwipeKey,
                    swipeKeyView.percentageAlternative > 0.5 {
                    delegate?.didSwipeKey(activeKey.key)
                } else {
                    delegate?.didTriggerKey(activeKey.key)
                }
            }
        }

        if activeKey != nil {
            activeKey = nil
        }
    }

    private func showKeyboardModeOverlay(_ longpressGestureRecognizer: UILongPressGestureRecognizer, key: KeyDefinition) {
        let longpressValues = keyboardModeDefinitions()
        let longpressController = LongPressOverlayController(key: key, page: page, theme: theme, longpressValues: longpressValues)
        longpressController.delegate = self

        self.longpressController = longpressController
        longpressController.touchesBegan(
            longpressGestureRecognizer.location(in: collectionView))
    }

    private func keyboardModeDefinitions() -> [KeyDefinition] {
        if shouldUseiPadLayout {
            return [
                KeyDefinition(type: .sideKeyboardLeft),
                KeyDefinition(type: .normalKeyboard),
                KeyDefinition(type: .sideKeyboardRight),
                KeyDefinition(type: .splitKeyboard)
            ]
        } else {
            return [
                KeyDefinition(type: .sideKeyboardLeft),
                KeyDefinition(type: .normalKeyboard),
                KeyDefinition(type: .sideKeyboardRight)
            ]
        }
    }

    @objc func touchesFoundLongpress(_ longpressGestureRecognizer: UILongPressGestureRecognizer) {
        let longpressPoint = clampedPoint(longpressGestureRecognizer.location(in: collectionView))
        if let indexPath = collectionView.indexPathForItem(at: longpressPoint),
            longpressController == nil {
            let key = currentPage[indexPath.section][indexPath.row]
            currentlyLongpressedKey = key
            switch key.type {
            case let .input(string, _):
                guard let longpressValues = longpressKeys(for: string),
                    longpressGestureRecognizer.state == .began else {
                        break
                }
                let longpressController = LongPressOverlayController(
                    key: key,
                    page: page,
                    theme: theme,
                    longpressValues: longpressValues)
                longpressController.delegate = self

                self.longpressController = longpressController
                let location = longpressGestureRecognizer.location(in: collectionView)
                longpressController.touchesBegan(location)
            case .keyboardMode:
                if longpressGestureRecognizer.state == .began {
                    showKeyboardModeOverlay(longpressGestureRecognizer, key: key)
                }

            case .spacebar:
                if longpressGestureRecognizer.state == .began {
                    let longpressController = LongPressCursorMovementController()
                    longpressController.delegate = self
                    self.longpressController = longpressController
                    collectionView.alpha = 0.4
                    // Initialize baseline so touchesMoved can compute deltas
                    let startPoint = longpressGestureRecognizer.location(in: collectionView)
                    longpressController.touchesBegan(startPoint)
                }
            case .backspace:
                break
            case .returnkey(name: _):
                if longpressGestureRecognizer.state == .began {
                    showKeyboardModeOverlay(longpressGestureRecognizer, key: key)
                }
            default:
                delegate?.didTriggerHoldKey(key)
            }
        }
    }

    func keyRepeatTimerDidTrigger() {
        guard let activeKey = activeKey, activeKey.key.type.supportsRepeatTrigger else { return }

        deleteRepeatCount += 1
        if deleteRepeatCount == 1 {
            // The hold outlasted the 0.5 s pause, so this is where the repeat begins.
            PersistentLog.log(.keyRepeatStarted)
        }

        // Word-level deletion after threshold, character-level before it.
        let wordMode = deleteRepeatCount > Self.wordModeThreshold
        let deleted = delegate?.didTriggerRepeat(activeKey.key, wordMode: wordMode) ?? false

        // The feedback follows the deletion, not the tick (#390). Both used to fire
        // unconditionally, which is what produced "haptics in a chain while nothing is
        // deleted": with no delegate left there is nothing to delete into and the repeat
        // has to be silent. Still exactly one haptic and one click per deletion, as #286
        // left it -- each repeat tick used to click from inside the bridge's delete
        // handlers, and emitting it here is what keeps that count right now they are
        // silent.
        if deleted {
            HapticFeedback.keyTapped()
            playSound(for: activeKey.key)
        }

        increaseKeyRepeatRateIfNeeded()
    }

    private func increaseKeyRepeatRateIfNeeded() {
        guard let timer = keyRepeatTimer else { return }

        // Stage 1 -> Stage 2: After initial pause (0.5s), switch to character repeat (0.1s)
        if timer.timeInterval == GiellaKeyboardView.pauseBeforeRepeatTimeInterval {
            keyRepeatTimer?.invalidate()
            keyRepeatTimer = makeKeyRepeatTimer(timeInterval: GiellaKeyboardView.keyRepeatTimeInterval)
        }
        // Stage 2 -> Stage 3: word mode has just started, so slow down to its cadence.
        // This branch used to rebuild the timer at the interval it already had, making
        // it a no-op that left word deletion running at ten a second (#419). Apple's
        // first word deletion also lands on the normal character tick and only the
        // ones after it are spaced, which is why the change happens here, after the
        // tick, rather than on the threshold itself.
        else if deleteRepeatCount == Self.wordModeThreshold + 1 && timer.timeInterval == GiellaKeyboardView.keyRepeatTimeInterval {
            keyRepeatTimer?.invalidate()
            keyRepeatTimer = makeKeyRepeatTimer(timeInterval: GiellaKeyboardView.wordModeRepeatTimeInterval)
        }
    }

    private func longpressKeys(for key: String) -> [KeyDefinition]? {
        // Case-insensitive lookup: AccentedCharacters.mappings uses lowercase keys,
        // but on shifted/capslock pages the key string is uppercase ("E" not "e").
        let longpressKeys = self.definition
        .longPress[key.lowercased()]?
        .compactMap({
            KeyDefinition(type: .input(key: $0, alternate: nil))
        })

        guard var keys = longpressKeys else {
            return nil
        }

        // Apply case transformation for shifted/capslock pages
        // so that long-pressing "E" shows uppercase accents (E, E, E, E)
        // KeyCaseTransform rather than uppercased(): Unicode's full case mapping turns
        // ß into the two characters "SS", which this popup drew as one key and inserted
        // as two letters (#322). The candidate is inserted verbatim by the bridge, so the
        // transformation has to be one character in, one character out.
        if page == .shifted || page == .capslock {
            keys = keys.map { keyDef in
                if case let .input(char, alt) = keyDef.type {
                    return KeyDefinition(type: .input(key: KeyCaseTransform.uppercased(char), alternate: alt))
                }
                return keyDef
            }
        }

        if shouldUseiPadLayout == false {
            let originalKey = KeyDefinition(type: .input(key: key, alternate: nil))
            if keys.contains(where: { (keyDefinition) -> Bool in
                keyDefinition.type == originalKey.type
            }) {
                // Already contains this key. Do nothing.
            } else {
                keys = [originalKey] + keys
            }
        }

        return keys
    }

    // MARK: - CollectionView

    private var rowNumberOfUnits: [CGFloat]!

    private func calculateRows() {
        var mutableWidths = [CGFloat]()

        for row in currentPage {
            let numberOfUnits = row.reduce(0.0) { (sum, key) -> CGFloat in
                sum + key.size.width
            }
            mutableWidths.append(numberOfUnits)
        }

        rowNumberOfUnits = mutableWidths

        collectionView.reloadData()
    }

    func numberOfSections(in _: UICollectionView) -> Int {
        return currentPage.count
    }

    func collectionView(_: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return currentPage[section].count
    }

    func collectionView(_ collectionView: UICollectionView,
                        willDisplay cell: UICollectionViewCell,
                        forItemAt indexPath: IndexPath) {
        let key = currentPage[indexPath.section][indexPath.row]

        if key.type == .keyboard {
            keyboardButtonFrame = cell.frame
        }

        if let keyCell = cell as? KeyCell,
           let activeKey = activeKey,
           activeKey.indexPath == indexPath {
            keyCell.keyView?.active = true
        } else if let keyCell = cell as? KeyCell {
            keyCell.keyView?.active = false
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier,
                                                            for: indexPath) as? KeyCell else {
            fatalError("Unable to cast to KeyCell")
        }
        var key = currentPage[indexPath.section][indexPath.row]

        // For the adaptive accent key, substitute the display label with the current
        // dynamic value (accent after vowel, apostrophe otherwise). Pass nil for
        // alternate so the sentinel "accent" is NOT rendered as a visible label.
        // The original key in currentPage still has alternate: "accent" for identification.
        if case .input(_, let alt) = key.type, alt == "accent" {
            key = KeyDefinition(type: .input(key: accentKeyLabel, alternate: nil))
        }

        cell.configure(page: page, key: key, theme: theme, traits: self.traitCollection)

        if let swipeKeyView = cell.keyView, swipeKeyView.isSwipeKey {
            swipeKeyView.percentageAlternative = 0.0
        }

        return cell
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let key = currentPage[indexPath.section][indexPath.row]

        let width = key.size.width * ((bounds.size.width - 1) / rowNumberOfUnits[indexPath.section])
        let height = bounds.size.height / CGFloat(currentPage.count)
        return CGSize(width: width, height: height)
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout,
                        minimumInteritemSpacingForSectionAt _: Int) -> CGFloat {
        return 0
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, minimumLineSpacingForSectionAt _: Int) -> CGFloat {
        return 0
    }

    final class KeyCell: UICollectionViewCell {
        var keyView: KeyView?

        override init(frame: CGRect) {
            super.init(frame: frame)

            contentView.clipsToBounds = false
            contentView.translatesAutoresizingMaskIntoConstraints = false
            contentView.fill(superview: self)
        }

        func configure(page: KeyboardPage, key: KeyDefinition, theme: Theme, traits: UITraitCollection) {
            contentView.subviews.forEach { view in
                view.removeFromSuperview()
            }
            keyView = nil

            if case .spacer = key.type {
                let emptyview = UIView(frame: .zero)
                emptyview.translatesAutoresizingMaskIntoConstraints = false
                emptyview.backgroundColor = .clear
                contentView.addSubview(emptyview)
                emptyview.fill(superview: contentView)
            } else {
                let keyView = KeyView(page: page, key: key, theme: theme, traits: traits)
                if let accessibilityLabel = key.accessibilityLabel(for: page) {
                    keyView.isAccessibilityElement = true
                    keyView.accessibilityLabel = accessibilityLabel
                }
                keyView.translatesAutoresizingMaskIntoConstraints = false
                contentView.addSubview(keyView)
                keyView.fill(superview: contentView)
                self.keyView = keyView
            }
        }

        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

private extension Array where Element == KeyDefinition {
    /// True for the digit row the number-row setting prepends to a letter page (#331).
    ///
    /// Ten plain input keys, every one of them a digit. No letter page has a row of its own
    /// that answers this, so the test cannot mistake one — see `popupSizingRow`, its only
    /// caller. `KeyType.isDigit` is the shared atom: `KeyView` asks the same question of a
    /// single key when it picks that key's font (#336).
    var isDigitRow: Bool {
        !isEmpty && allSatisfy { $0.type.isDigit }
    }
}

// GhostKeyView: used to remember the position of a key that was tapped on the keyboard
// Needed because the collectionView forgets the position of keys after they've been tapped,
// and the overlay view needs this to be accurately drawn
final class GhostKeyView: UIView {
    let contentView: UIView

    init(keyView: KeyView, in parentView: UIView) {
        let translatedFrame = keyView.convert(keyView.frame, to: parentView)
        contentView = UIView(frame: keyView.contentView.convert(keyView.contentView.frame, to: parentView))

        contentView.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: translatedFrame)

        self.addSubview(contentView)

        contentView.centerXAnchor.constraint(equalTo: self.centerXAnchor).enable(priority: .required)
        contentView.centerYAnchor.constraint(equalTo: self.centerYAnchor).enable(priority: .required)
        contentView.widthAnchor.constraint(equalToConstant: contentView.frame.width).enable(priority: .required)
        contentView.heightAnchor.constraint(equalToConstant: contentView.frame.height).enable(priority: .required)

        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
