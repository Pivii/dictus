// DictusKeyboard/Views/UIKit/SpecialKeyButtons.swift
// UIButton subclasses for all special keyboard keys with extended hit regions.
import UIKit
import AudioToolbox
import DictusCore
import QuartzCore

// MARK: - BaseSpecialKeyButton

/// Shared superclass for all special key buttons.
/// Provides common touch inset expansion, background colors, and corner radius/shadow setup.
///
/// WHY a shared superclass:
/// All special keys share the same hit-region expansion pattern (point(inside:with:) with
/// negative touchInsets), the same visual style (dynamic background, corner radius, shadow),
/// and the same pressed state animation. Extracting this avoids duplicating ~30 lines per subclass.
class BaseSpecialKeyButton: UIButton {

    /// Negative insets that EXPAND the touchable area beyond the visual bounds.
    /// Set by KeyboardContainerView.layoutSubviews() after layout.
    var touchInsets = UIEdgeInsets.zero

    /// Normal background: dark mode = 22% white, light mode = white.
    static let normalBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.22, alpha: 1) : .white
    }

    /// Pressed background: dark mode = 32% white, light mode = 88% white.
    static let pressedBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 0.88, alpha: 1)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    /// Inner view for visual appearance. Inset from button bounds so visual keys
    /// have gaps while the touch area fills 100% (zero dead zones).
    let backgroundView = UIView()

    private func commonInit() {
        // Button itself is transparent — touch area fills entire frame
        backgroundColor = .clear
        tintColor = .label

        // Visual appearance on inner backgroundView
        backgroundView.backgroundColor = Self.normalBackground
        backgroundView.layer.cornerRadius = KeyMetrics.keyCornerRadius
        backgroundView.layer.shadowColor = UIColor.black.cgColor
        backgroundView.layer.shadowOpacity = 0.15
        backgroundView.layer.shadowOffset = CGSize(width: 0, height: 1)
        backgroundView.layer.shadowRadius = 0
        backgroundView.clipsToBounds = false
        backgroundView.isUserInteractionEnabled = false
        addSubview(backgroundView)
        sendSubviewToBack(backgroundView)

        clipsToBounds = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let hInset = KeyMetrics.keySpacing / 2
        let vInset = KeyMetrics.rowSpacing / 2
        backgroundView.frame = bounds.insetBy(dx: hInset, dy: vInset)
        ensureImageOnTop()
    }

    /// Ensure the SF Symbol imageView is always above the backgroundView.
    ///
    /// WHY layoutSubviews and not just after setupIcon:
    /// UIButton may recreate or reorder its internal subviews during layout passes.
    /// Calling bringSubviewToFront in layoutSubviews guarantees correct z-order at render time.
    func ensureImageOnTop() {
        if let iv = imageView {
            bringSubviewToFront(iv)
        }
    }

    /// Expand the touchable area using negative insets -- eliminates dead zones.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.inset(by: touchInsets).contains(point)
    }

    /// Show pressed visual state.
    func showPressedState() {
        backgroundView.backgroundColor = Self.pressedBackground
    }

    /// Restore normal visual state.
    func showNormalState() {
        backgroundView.backgroundColor = Self.normalBackground
    }
}

// MARK: - ShiftKeyButton

/// Shift key with three states: off, shifted, caps lock.
/// Double-tap detected via timestamp: if second tap arrives within 400ms from shifted state,
/// activate caps lock.
///
/// WHY double-tap detection via Date instead of UITapGestureRecognizer:
/// UITapGestureRecognizer's numberOfTapsRequired delays the first tap. Using Date comparison
/// lets the first tap fire immediately and only promotes to caps lock on the second.
class ShiftKeyButton: BaseSpecialKeyButton {

    var shiftState: ShiftState = .off
    var onShiftChanged: ((ShiftState) -> Void)?

    /// Timestamp of the last shift tap, for double-tap caps lock detection.
    private var lastTapTime: Date = .distantPast

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupIcon()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupIcon()
    }

    private func setupIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        setImage(UIImage(systemName: "shift", withConfiguration: config), for: .normal)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        showPressedState()
        HapticFeedback.keyTapped()
        AudioServicesPlaySystemSound(KeySound.modifier)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        showNormalState()

        let now = Date()
        let interval = now.timeIntervalSince(lastTapTime)
        lastTapTime = now

        if interval < 0.4 && shiftState == .shifted {
            shiftState = .capsLocked
        } else {
            switch shiftState {
            case .off:
                shiftState = .shifted
            case .shifted:
                shiftState = .off
            case .capsLocked:
                shiftState = .off
            }
        }

        updateIcon()
        onShiftChanged?(shiftState)
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches ?? [], with: event)
        showNormalState()
    }

    /// Update the shift state and icon without recreating the button.
    func updateShiftState(_ state: ShiftState) {
        shiftState = state
        updateIcon()
    }

    private func updateIcon() {
        let iconName: String
        switch shiftState {
        case .off: iconName = "shift"
        case .shifted: iconName = "shift.fill"
        case .capsLocked: iconName = "capslock.fill"
        }
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
    }
}

// MARK: - DeleteKeyButton

/// Delete key with repeat-on-hold behavior and word-level acceleration.
///
/// ACCELERATION PATTERN (matches Apple):
/// - First 10 deletions: character-by-character at 100ms intervals
/// - After 10 deletions: word-by-word at 120ms intervals
/// - Counter resets on finger lift
///
/// WHY Task instead of Timer:
/// Timer.scheduledTimer is unreliable in keyboard extensions (RunLoop may not be active).
/// Swift concurrency Task works correctly in all execution contexts.
class DeleteKeyButton: BaseSpecialKeyButton {

    /// Returns true if text was actually deleted, false if text field was empty.
    /// WHY Bool: The repeat loop uses this to stop haptic/audio feedback when the
    /// text field is empty, preventing the annoying buzzing on an empty field.
    var onDelete: (() -> Bool)?
    var onWordDelete: (() -> Void)?

    private var repeatTask: Task<Void, Never>?
    private var deleteCount: Int = 0

    /// Number of character deletions before switching to word-level mode.
    private let wordModeThreshold = 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupIcon()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupIcon()
    }

    private func setupIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        setImage(UIImage(systemName: "delete.backward", withConfiguration: config), for: .normal)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        showPressedState()

        // Immediate first delete
        let deleted = onDelete?() ?? false
        if deleted {
            HapticFeedback.keyTapped()
            AudioServicesPlaySystemSound(KeySound.delete)
        }
        deleteCount = 1

        // Start repeat with acceleration
        repeatTask = Task { @MainActor [weak self] in
            // 400ms initial delay before repeat begins
            try? await Task.sleep(nanoseconds: 400_000_000)

            while !Task.isCancelled {
                guard let self = self else { return }
                if self.deleteCount >= self.wordModeThreshold {
                    self.onWordDelete?()
                    HapticFeedback.keyTapped()
                    AudioServicesPlaySystemSound(KeySound.delete)
                    try? await Task.sleep(nanoseconds: 120_000_000)
                } else {
                    let deleted = self.onDelete?() ?? false
                    if !deleted {
                        // Text field is empty -- stop repeating
                        break
                    }
                    HapticFeedback.keyTapped()
                    AudioServicesPlaySystemSound(KeySound.delete)
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                self.deleteCount += 1
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        cleanup()
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches ?? [], with: event)
        cleanup()
    }

    private func cleanup() {
        showNormalState()
        repeatTask?.cancel()
        repeatTask = nil
        deleteCount = 0
    }
}

// MARK: - SpaceKeyButton

/// Space bar key with trackpad mode on long-press.
///
/// Short tap inserts a space. Long-pressing for 400ms activates trackpad mode:
/// dragging moves the cursor through text. A greyed-out overlay is managed
/// by SwiftUI through the KeyboardTouchState bridge.
///
/// TRACKPAD TUNING:
/// - Dead zone: 8pt radius after activation to absorb jitter
/// - Sensitivity: 12 pt/char base (Apple uses ~12-15pt)
/// - Acceleration: cosine interpolation from 1.0x (slow) to 2.5x (fast)
/// - Rate limit: 16ms (60fps cap) to avoid overloading the text API
class SpaceKeyButton: BaseSpecialKeyButton {

    var onTap: (() -> Void)?
    var onCursorMove: ((Int) -> Void)?
    weak var touchState: KeyboardTouchState?

    private var longPressTask: Task<Void, Never>?
    private var isTrackpadMode = false
    private var lastDragLocation: CGPoint = .zero
    private var accumulatedOffsetX: CGFloat = 0
    private var accumulatedOffsetY: CGFloat = 0

    // Dead zone state
    private var activationLocation: CGPoint = .zero
    private var hasExitedDeadZone = false
    private var lastMoveTime: CFTimeInterval = 0

    // Tuning constants (same as existing SpaceKey SwiftUI view)
    private let basePtsPerChar: CGFloat = 12.0
    private let deadZoneRadius: CGFloat = 8.0
    private let minMoveInterval: CFTimeInterval = 0.016
    private let slowVelocity: CGFloat = 100
    private let fastVelocity: CGFloat = 400
    private let maxAccelMultiplier: CGFloat = 2.5

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLabel()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLabel()
    }

    private func setupLabel() {
        setTitle("espace", for: .normal)
        titleLabel?.font = .systemFont(ofSize: 15)
        setTitleColor(.label, for: .normal)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        showPressedState()

        if let touch = touches.first {
            lastDragLocation = touch.location(in: self)
        }

        HapticFeedback.keyTapped()
        AudioServicesPlaySystemSound(KeySound.modifier)

        // Start 400ms trackpad activation timer
        longPressTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.activateTrackpad()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        guard let touch = touches.first else { return }
        let currentLocation = touch.location(in: self)

        if isTrackpadMode {
            handleTrackpadDrag(currentLocation: currentLocation)
        }

        lastDragLocation = currentLocation
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        if !isTrackpadMode {
            onTap?() // Normal space insertion
        }
        deactivateTrackpad()
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches ?? [], with: event)
        deactivateTrackpad() // No tap on cancel
    }

    // MARK: - Trackpad logic

    private func activateTrackpad() {
        isTrackpadMode = true
        activationLocation = lastDragLocation
        hasExitedDeadZone = false
        lastMoveTime = CACurrentMediaTime()
        accumulatedOffsetX = 0
        accumulatedOffsetY = 0
        touchState?.setTrackpad(true)
        HapticFeedback.trackpadActivated()
    }

    private func deactivateTrackpad() {
        showNormalState()
        longPressTask?.cancel()
        longPressTask = nil

        if isTrackpadMode {
            isTrackpadMode = false
            touchState?.setTrackpad(false)
        }
        accumulatedOffsetX = 0
        accumulatedOffsetY = 0
        hasExitedDeadZone = false
        lastMoveTime = 0
    }

    private func handleTrackpadDrag(currentLocation: CGPoint) {
        // Dead zone: ignore movement until finger exits 8pt radius
        if !hasExitedDeadZone {
            let dx = currentLocation.x - activationLocation.x
            let dy = currentLocation.y - activationLocation.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance < deadZoneRadius { return }
            hasExitedDeadZone = true
            lastDragLocation = currentLocation
            lastMoveTime = CACurrentMediaTime()
            return
        }

        let now = CACurrentMediaTime()
        let elapsed = now - lastMoveTime
        let deltaX = currentLocation.x - lastDragLocation.x
        let deltaY = currentLocation.y - lastDragLocation.y

        // Rate limiting: skip if less than 16ms since last move
        if elapsed < minMoveInterval {
            accumulatedOffsetX += deltaX
            accumulatedOffsetY += deltaY
            return
        }

        let totalDeltaX = accumulatedOffsetX + deltaX
        let totalDeltaY = accumulatedOffsetY + deltaY

        // Velocity for acceleration curve
        let dragMagnitude = sqrt(totalDeltaX * totalDeltaX + totalDeltaY * totalDeltaY)
        let velocity = elapsed > 0 ? dragMagnitude / CGFloat(elapsed) : 0

        // Cosine interpolation: slow (<100) -> 1.0x, fast (>400) -> 2.5x
        let multiplier: CGFloat
        if velocity <= slowVelocity {
            multiplier = 1.0
        } else if velocity >= fastVelocity {
            multiplier = maxAccelMultiplier
        } else {
            let t = (velocity - slowVelocity) / (fastVelocity - slowVelocity)
            let smooth = (1.0 - cos(t * .pi)) / 2.0
            multiplier = 1.0 + (maxAccelMultiplier - 1.0) * smooth
        }

        let effectivePtsPerChar = basePtsPerChar / multiplier

        let charsFromX = Int(totalDeltaX / effectivePtsPerChar)
        let charsFromY = Int(totalDeltaY / effectivePtsPerChar)
        let totalChars = charsFromX + charsFromY

        if totalChars != 0 {
            onCursorMove?(totalChars)
            HapticFeedback.cursorMoved()
            accumulatedOffsetX = totalDeltaX - CGFloat(charsFromX) * effectivePtsPerChar
            accumulatedOffsetY = totalDeltaY - CGFloat(charsFromY) * effectivePtsPerChar
            lastMoveTime = now
        } else {
            accumulatedOffsetX = totalDeltaX
            accumulatedOffsetY = totalDeltaY
        }
    }
}

// MARK: - ReturnKeyButton

/// Return key with touchDown haptic/audio feedback.
///
/// For action contexts (Go, Search, Send), shows blue background with white text/icon
/// matching Apple's native keyboard styling.
class ReturnKeyButton: BaseSpecialKeyButton {

    var onTap: (() -> Void)?

    /// Whether the current returnKeyType uses the blue "action" style.
    private var isActionStyle = false

    /// Blue background for action return keys (Go, Search, Send).
    private static let actionBackground = UIColor.systemBlue

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupIcon()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupIcon()
    }

    private func setupIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        setImage(UIImage(systemName: "return.left", withConfiguration: config), for: .normal)
        titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        setTitleColor(.label, for: .normal)
    }

    /// Update the return key label/icon based on the host text field's returnKeyType.
    ///
    /// WHY this mapping:
    /// iOS text fields declare a returnKeyType (Search, Send, Go, etc.) that tells keyboards
    /// what label to show on the return key. The native keyboard adapts automatically, but
    /// custom keyboards must read the proxy's returnKeyType and update manually.
    ///
    /// Action types (go, search, send) get blue background + white icon/text like Apple.
    func updateReturnKeyType(_ type: UIReturnKeyType) {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        // Determine if this is an "action" type that gets blue styling
        let wantsAction: Bool
        switch type {
        case .go, .search, .send:
            wantsAction = true
        default:
            wantsAction = false
        }

        switch type {
        case .go:
            setTitle(nil, for: .normal)
            let arrowConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            setImage(UIImage(systemName: "arrow.right", withConfiguration: arrowConfig), for: .normal)
            ensureImageOnTop()
        case .search:
            setTitle(nil, for: .normal)
            setImage(UIImage(systemName: "magnifyingglass", withConfiguration: config), for: .normal)
            ensureImageOnTop()
        case .send:
            setImage(nil, for: .normal)
            setTitle("Send", for: .normal)
        case .done:
            setImage(nil, for: .normal)
            setTitle("OK", for: .normal)
        case .join:
            setImage(nil, for: .normal)
            setTitle("Join", for: .normal)
        case .route:
            setImage(nil, for: .normal)
            setTitle("Route", for: .normal)
        case .continue:
            setImage(nil, for: .normal)
            setTitle("Suite", for: .normal)
        case .emergencyCall:
            setImage(nil, for: .normal)
            setTitle("SOS", for: .normal)
        default:
            // .default, .next, and any unknown types use the return icon
            setTitle(nil, for: .normal)
            setImage(UIImage(systemName: "return.left", withConfiguration: config), for: .normal)
            ensureImageOnTop()
        }

        // Apply blue action style or restore normal style
        if wantsAction {
            isActionStyle = true
            backgroundView.backgroundColor = Self.actionBackground
            tintColor = .white
            setTitleColor(.white, for: .normal)
        } else {
            isActionStyle = false
            backgroundView.backgroundColor = Self.normalBackground
            tintColor = .label
            setTitleColor(.label, for: .normal)
        }
    }

    override func showPressedState() {
        if isActionStyle {
            backgroundView.backgroundColor = Self.actionBackground.withAlphaComponent(0.7)
        } else {
            super.showPressedState()
        }
    }

    override func showNormalState() {
        if isActionStyle {
            backgroundView.backgroundColor = Self.actionBackground
        } else {
            super.showNormalState()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        showPressedState()
        HapticFeedback.keyTapped()
        AudioServicesPlaySystemSound(KeySound.modifier)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        showNormalState()
        onTap?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches ?? [], with: event)
        showNormalState()
    }
}

// MARK: - GlobeKeyButton

/// Globe key (switch keyboards) with touchDown haptic/audio feedback.
class GlobeKeyButton: BaseSpecialKeyButton {

    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupIcon()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupIcon()
    }

    private func setupIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        setImage(UIImage(systemName: "globe", withConfiguration: config), for: .normal)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        showPressedState()
        HapticFeedback.keyTapped()
        AudioServicesPlaySystemSound(KeySound.modifier)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        showNormalState()
        onTap?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches ?? [], with: event)
        showNormalState()
    }
}

// MARK: - EmojiKeyButton

/// Emoji key with touchDown haptic/audio feedback.
class EmojiKeyButton: BaseSpecialKeyButton {

    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupIcon()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupIcon()
    }

    private func setupIcon() {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        setImage(UIImage(systemName: "face.smiling", withConfiguration: config), for: .normal)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        showPressedState()
        HapticFeedback.keyTapped()
        AudioServicesPlaySystemSound(KeySound.modifier)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        showNormalState()
        onTap?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches ?? [], with: event)
        showNormalState()
    }
}

// MARK: - LayerSwitchKeyButton

/// Layer switch key ("123", "ABC", "#+=") with touchDown haptic/audio feedback.
class LayerSwitchKeyButton: BaseSpecialKeyButton {

    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLabel()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLabel()
    }

    private func setupLabel() {
        titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        setTitleColor(.label, for: .normal)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        showPressedState()
        HapticFeedback.keyTapped()
        AudioServicesPlaySystemSound(KeySound.modifier)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        showNormalState()
        onTap?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches ?? [], with: event)
        showNormalState()
    }

    /// Update the displayed text for layer switching (e.g., "123" -> "ABC").
    func updateLabel(_ text: String) {
        setTitle(text, for: .normal)
    }
}

// MARK: - AdaptiveAccentKeyButton

/// Adaptive accent key: shows apostrophe by default, accent after typing a vowel.
/// Long-press on an accent shows all variants via the touchState bridge.
///
/// WHY this key exists:
/// On the native French AZERTY keyboard, apostrophe requires a layer switch. Having it
/// one tap away on the letters layer eliminates that overhead. The adaptive behavior
/// adds contextual accent insertion without losing the apostrophe default.
class AdaptiveAccentKeyButton: BaseSpecialKeyButton {

    var lastTypedChar: String?
    var isShifted: Bool = false
    var onTap: ((String) -> Void)?
    weak var touchState: KeyboardTouchState?

    private var longPressTimer: Task<Void, Never>?
    private var longPressFired = false
    private let accentCellWidth: CGFloat = 36

    /// The character the key should display right now.
    private var displayChar: String {
        AccentedCharacters.adaptiveKeyLabel(afterTyping: lastTypedChar)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLabel()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLabel()
    }

    private func setupLabel() {
        titleLabel?.font = .systemFont(ofSize: 22)
        setTitleColor(.label, for: .normal)
        refreshTitle()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        showPressedState()
        HapticFeedback.keyTapped()
        AudioServicesPlaySystemSound(KeySound.letter)

        // Publish press state for popup preview
        let frameInKeyboard = frameInKeyboardCoordinateSpace()
        touchState?.showPress(label: displayChar, frame: frameInKeyboard)

        // Start 400ms long-press timer for accent popup
        longPressFired = false
        longPressTimer?.cancel()
        longPressTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.handleLongPress()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        guard longPressFired, touchState?.showingAccents == true,
              let touch = touches.first else { return }

        let location = touch.location(in: self)
        let accentCount = touchState?.accentOptions.count ?? 0
        guard accentCount > 0 else { return }

        // Apply same edge clamping as the SwiftUI accent overlay
        let totalWidth = CGFloat(accentCount) * accentCellWidth
        let kbWidth = touchState?.keyboardWidth ?? bounds.width * 10  // fallback: no clamping
        let frameInKB = frameInKeyboardCoordinateSpace()
        let rawMidX = frameInKB.midX
        let halfWidth = totalWidth / 2
        let clampedMidX = max(halfWidth, min(rawMidX, kbWidth - halfWidth))

        // Convert clamped position back to button-local coordinates
        let clampedLocalMidX = bounds.midX + (clampedMidX - rawMidX)
        let popupStartX = clampedLocalMidX - totalWidth / 2
        let index = Int((location.x - popupStartX) / accentCellWidth)

        if index >= 0 && index < accentCount {
            touchState?.updateAccentSelection(at: index)
        } else {
            touchState?.updateAccentSelection(at: nil)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        longPressTimer?.cancel()
        longPressTimer = nil
        showNormalState()

        if let state = touchState, state.showingAccents,
           let index = state.selectedAccentIndex,
           index >= 0, index < state.accentOptions.count {
            // Accent selected from popup
            onTap?(state.accentOptions[index])
            touchState?.hideAccents()
        } else if !longPressFired {
            // Normal tap: insert the displayed character
            onTap?(displayChar)
        }

        touchState?.hidePress()
        touchState?.hideAccents()
        longPressFired = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches ?? [], with: event)

        longPressTimer?.cancel()
        longPressTimer = nil
        showNormalState()
        touchState?.hidePress()
        touchState?.hideAccents()
        longPressFired = false
    }

    // MARK: - Long-press

    private func handleLongPress() {
        longPressFired = true

        // Only show accent popup if displaying an accent (not apostrophe)
        guard let vowel = AccentedCharacters.adaptiveKeyVowel(afterTyping: lastTypedChar),
              let accents = AccentedCharacters.accents(for: vowel), !accents.isEmpty else { return }

        // Derive case from lastTypedChar
        let isUppercase = lastTypedChar?.uppercased() == lastTypedChar
            && lastTypedChar?.lowercased() != lastTypedChar
        let accentList: [String]
        if isUppercase {
            accentList = accents.map { $0.uppercased() }
        } else {
            accentList = accents
        }

        let frameInKeyboard = frameInKeyboardCoordinateSpace()
        touchState?.showAccents(accentList, keyFrame: frameInKeyboard)
    }

    // MARK: - Configuration

    /// Update display state when the last typed character or shift state changes.
    func updateState(lastTypedChar: String?, isShifted: Bool) {
        self.lastTypedChar = lastTypedChar
        self.isShifted = isShifted
        refreshTitle()
    }

    private func refreshTitle() {
        setTitle(displayChar, for: .normal)
    }

    /// Convert this button's bounds to keyboard coordinate space.
    private func frameInKeyboardCoordinateSpace() -> CGRect {
        var target: UIView? = superview?.superview?.superview
        if target == nil { target = superview }
        return convert(bounds, to: target)
    }
}
