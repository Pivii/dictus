// DictusKeyboard/Views/DictusKeyView.swift
// UIView subclass for a single keyboard key — handles tap, long-press accents, styling.
import UIKit
import AudioToolbox
import DictusCore

/// Delegate protocol for key events back to the keyboard container.
protocol DictusKeyViewDelegate: AnyObject {
    func keyTapped(_ key: KeyDefinition, output: String)
    func keyDeleteTapped()
    func keyDeleteWord()
    func keyShiftTapped()
    func keySpaceTapped()
    func keyReturnTapped()
    func keyGlobeTapped()
    func keyEmojiTapped()
    func keyLayerSwitchTapped()
    func keySymbolToggleTapped()
    func keyAccentAdaptiveTapped(_ output: String)
    func keyCursorMove(_ offset: Int)
    func keyTrackpadStateChanged(_ active: Bool)
    func showAccentPopup(accents: [String], fromKeyView: DictusKeyView)
    func showKeyPopup(label: String, fromKeyView: DictusKeyView)
    func hidePopups()
}

/// UIView for a single keyboard key.
///
/// WHY UIView subclass instead of UIControl:
/// We need custom gesture handling (long-press for accents, drag for accent selection,
/// long-press on space for trackpad). UIGestureRecognizers on a plain UIView give us
/// full control without fighting UIControl's built-in touch tracking.
final class DictusKeyView: UIView {

    // MARK: - Properties

    let key: KeyDefinition
    weak var delegate: DictusKeyViewDelegate?

    /// Current shift state — set by the parent container.
    var isShifted: Bool = false {
        didSet { updateLabel() }
    }

    /// Shift state for the shift key icon.
    var shiftState: ShiftState = .off {
        didSet { updateShiftIcon() }
    }

    /// Last typed character for adaptive accent key.
    var lastTypedChar: String? = nil {
        didSet { updateLabel() }
    }

    // MARK: - Subviews

    private let label = UILabel()
    private let iconView = UIImageView()

    // MARK: - Gesture state

    private var longPressTimer: Timer?
    private var deleteRepeatTimer: Timer?
    private var deleteCount: Int = 0
    private let wordModeThreshold = 10
    private var isTrackpadMode = false
    private var lastDragLocation: CGPoint = .zero
    private var accumulatedOffsetX: CGFloat = 0
    private var accumulatedOffsetY: CGFloat = 0
    private let pointsPerCharacter: CGFloat = 9.0

    // Accent state
    private var accentOptions: [String] = []
    private var showingAccents = false
    private var dragStartX: CGFloat = 0

    // Shift double-tap detection
    private var lastShiftTapTime: Date = .distantPast

    // MARK: - Init

    init(key: KeyDefinition) {
        self.key = key
        super.init(frame: .zero)
        setupView()
        setupGestures()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Setup

    private func setupView() {
        // Background and shape
        layer.cornerRadius = KeyboardColors.keyCornerRadius
        layer.shadowColor = KeyboardColors.keyShadowColor.cgColor
        layer.shadowOffset = KeyboardColors.keyShadowOffset
        layer.shadowRadius = KeyboardColors.keyShadowRadius
        layer.shadowOpacity = 1.0
        backgroundColor = backgroundColorForKeyType()

        // Label setup
        label.textAlignment = .center
        label.textColor = KeyboardColors.keyLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        // Icon setup (for shift, delete, return, globe, emoji)
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = KeyboardColors.keyLabel
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
        ])

        configureContent()
    }

    private func configureContent() {
        switch key.type {
        case .character:
            label.font = UIFont.systemFont(ofSize: 22, weight: .regular)
            iconView.isHidden = true
            updateLabel()

        case .shift:
            label.isHidden = true
            updateShiftIcon()

        case .delete:
            label.isHidden = true
            iconView.image = UIImage(systemName: "delete.backward")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        case .space:
            label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
            iconView.isHidden = true
            label.text = "espace"

        case .returnKey:
            label.isHidden = true
            iconView.image = UIImage(systemName: "return.left")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        case .globe:
            label.isHidden = true
            iconView.image = UIImage(systemName: "globe")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)

        case .emoji:
            label.isHidden = true
            iconView.image = UIImage(systemName: "face.smiling")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)

        case .layerSwitch, .symbolToggle:
            label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            iconView.isHidden = true
            label.text = key.label

        case .accentAdaptive:
            label.font = UIFont.systemFont(ofSize: 22, weight: .regular)
            iconView.isHidden = true
            updateLabel()

        case .mic:
            // Mic keys are filtered out — should not be created
            label.isHidden = true
            iconView.isHidden = true
        }
    }

    private func updateLabel() {
        switch key.type {
        case .character:
            label.text = isShifted ? key.label.uppercased() : key.label.lowercased()
        case .accentAdaptive:
            label.text = AccentedCharacters.adaptiveKeyLabel(afterTyping: lastTypedChar)
        default:
            break
        }
    }

    private func updateShiftIcon() {
        guard key.type == .shift else { return }
        let iconName: String
        switch shiftState {
        case .off: iconName = "shift"
        case .shifted: iconName = "shift.fill"
        case .capsLocked: iconName = "capslock.fill"
        }
        iconView.image = UIImage(systemName: iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        iconView.tintColor = shiftState != .off ? .white : KeyboardColors.keyLabel
    }

    private func backgroundColorForKeyType() -> UIColor {
        switch key.type {
        case .character, .accentAdaptive:
            return KeyboardColors.inputKeyBackground
        case .space:
            return KeyboardColors.spaceKeyBackground
        case .shift, .delete, .returnKey, .globe, .emoji, .layerSwitch, .symbolToggle, .mic:
            return KeyboardColors.actionKeyBackground
        }
    }

    // MARK: - Gestures

    private func setupGestures() {
        switch key.type {
        case .character, .accentAdaptive:
            // Long press for accent popup + pan for accent selection
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleCharLongPress(_:)))
            longPress.minimumPressDuration = 0.4
            longPress.allowableMovement = 100
            addGestureRecognizer(longPress)

            // Tap for normal character insert
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleCharTap(_:)))
            tap.require(toFail: longPress)
            addGestureRecognizer(tap)

        case .delete:
            // Custom touch handling for repeat-on-hold
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleDeleteLongPress(_:)))
            longPress.minimumPressDuration = 0.4
            addGestureRecognizer(longPress)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleDeleteTap(_:)))
            tap.require(toFail: longPress)
            addGestureRecognizer(tap)

        case .space:
            // Long press for trackpad mode
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleSpaceLongPress(_:)))
            longPress.minimumPressDuration = 0.4
            addGestureRecognizer(longPress)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleSpaceTap(_:)))
            tap.require(toFail: longPress)
            addGestureRecognizer(tap)

        case .shift:
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleShiftTap(_:)))
            addGestureRecognizer(tap)

        default:
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleGenericTap(_:)))
            addGestureRecognizer(tap)
        }
    }

    // MARK: - Touch feedback

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        animatePress(true)

        // Show key popup for character keys on press
        if key.type == .character {
            let displayLabel = isShifted ? key.label.uppercased() : key.label.lowercased()
            delegate?.showKeyPopup(label: displayLabel, fromKeyView: self)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        animatePress(false)
        if !showingAccents {
            delegate?.hidePopups()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        animatePress(false)
        delegate?.hidePopups()
    }

    private func animatePress(_ pressed: Bool) {
        // Subtle brightness change on press (like Apple keyboard)
        UIView.animate(withDuration: 0.05) {
            self.alpha = pressed ? 0.7 : 1.0
        }
    }

    // MARK: - Character key handlers

    @objc private func handleCharTap(_ gesture: UITapGestureRecognizer) {
        let output: String
        if key.type == .accentAdaptive {
            output = AccentedCharacters.adaptiveKeyLabel(afterTyping: lastTypedChar)
        } else {
            let rawOutput = key.output ?? key.label
            output = isShifted ? rawOutput.uppercased() : rawOutput
        }

        if key.type == .accentAdaptive {
            delegate?.keyAccentAdaptiveTapped(output)
        } else {
            delegate?.keyTapped(key, output: output)
        }
        HapticFeedback.keyTapped()
        delegate?.hidePopups()
    }

    @objc private func handleCharLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            // Show accent popup
            let baseChar: String
            if key.type == .accentAdaptive {
                // For adaptive accent key, look up the vowel that triggered the current display
                guard let vowel = AccentedCharacters.adaptiveKeyVowel(afterTyping: lastTypedChar),
                      let accents = AccentedCharacters.accents(for: vowel), !accents.isEmpty else {
                    return
                }
                let isUppercase = lastTypedChar?.uppercased() == lastTypedChar && lastTypedChar?.lowercased() != lastTypedChar
                accentOptions = isUppercase ? accents.map { $0.uppercased() } : accents
            } else {
                baseChar = key.label.lowercased()
                guard let accents = AccentedCharacters.accents(for: baseChar), !accents.isEmpty else {
                    return
                }
                accentOptions = isShifted ? accents.map { $0.uppercased() } : accents
            }

            showingAccents = true
            dragStartX = gesture.location(in: self).x
            delegate?.showAccentPopup(accents: accentOptions, fromKeyView: self)
            HapticFeedback.keyTapped()

        case .changed:
            if showingAccents {
                // Track finger position for accent selection
                let location = gesture.location(in: self)
                let accentCellWidth: CGFloat = 36
                let totalPopupWidth = CGFloat(accentOptions.count) * accentCellWidth
                let popupStartX = dragStartX - totalPopupWidth / 2
                let relativeX = location.x - popupStartX
                let index = Int(relativeX / accentCellWidth)

                if index >= 0 && index < accentOptions.count {
                    // Update accent popup selection via delegate
                    if let parentView = superview?.superview as? DictusKeyboardView {
                        parentView.updateAccentSelection(index)
                    }
                }
            }

        case .ended, .cancelled:
            if showingAccents {
                // Find selected accent and insert it
                let location = gesture.location(in: self)
                let accentCellWidth: CGFloat = 36
                let totalPopupWidth = CGFloat(accentOptions.count) * accentCellWidth
                let popupStartX = dragStartX - totalPopupWidth / 2
                let relativeX = location.x - popupStartX
                let index = Int(relativeX / accentCellWidth)

                if index >= 0 && index < accentOptions.count {
                    if key.type == .accentAdaptive {
                        delegate?.keyAccentAdaptiveTapped(accentOptions[index])
                    } else {
                        delegate?.keyTapped(key, output: accentOptions[index])
                    }
                    HapticFeedback.keyTapped()
                }

                showingAccents = false
                accentOptions = []
            }
            delegate?.hidePopups()
            animatePress(false)

        default:
            break
        }
    }

    // MARK: - Delete key handlers

    @objc private func handleDeleteTap(_ gesture: UITapGestureRecognizer) {
        delegate?.keyDeleteTapped()
        HapticFeedback.keyTapped()
        AudioServicesPlaySystemSound(KeySound.delete)
    }

    @objc private func handleDeleteLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            deleteCount = 0
            startDeleteRepeat()

        case .ended, .cancelled:
            stopDeleteRepeat()
            animatePress(false)

        default:
            break
        }
    }

    private func startDeleteRepeat() {
        deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.deleteCount += 1
            if self.deleteCount >= self.wordModeThreshold {
                self.delegate?.keyDeleteWord()
            } else {
                self.delegate?.keyDeleteTapped()
            }
            HapticFeedback.keyTapped()
            AudioServicesPlaySystemSound(KeySound.delete)
        }
    }

    private func stopDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
        deleteCount = 0
    }

    // MARK: - Space key handlers

    @objc private func handleSpaceTap(_ gesture: UITapGestureRecognizer) {
        delegate?.keySpaceTapped()
        HapticFeedback.keyTapped()
    }

    @objc private func handleSpaceLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            isTrackpadMode = true
            lastDragLocation = gesture.location(in: self)
            accumulatedOffsetX = 0
            accumulatedOffsetY = 0
            delegate?.keyTrackpadStateChanged(true)
            HapticFeedback.trackpadActivated()

        case .changed:
            if isTrackpadMode {
                let currentLocation = gesture.location(in: self)
                handleTrackpadDrag(currentLocation: currentLocation)
            }

        case .ended, .cancelled:
            if isTrackpadMode {
                isTrackpadMode = false
                delegate?.keyTrackpadStateChanged(false)
            }
            animatePress(false)

        default:
            break
        }
    }

    private func handleTrackpadDrag(currentLocation: CGPoint) {
        let deltaX = currentLocation.x - lastDragLocation.x
        let deltaY = currentLocation.y - lastDragLocation.y
        lastDragLocation = currentLocation

        accumulatedOffsetX += deltaX
        let horizontalChars = acceleratedOffset(accumulatedOffsetX, sensitivity: pointsPerCharacter)
        if horizontalChars != 0 {
            delegate?.keyCursorMove(horizontalChars)
            accumulatedOffsetX -= CGFloat(horizontalChars) * pointsPerCharacter
        }

        accumulatedOffsetY += deltaY
        let verticalChars = acceleratedOffset(accumulatedOffsetY, sensitivity: pointsPerCharacter)
        if verticalChars != 0 {
            delegate?.keyCursorMove(verticalChars)
            accumulatedOffsetY -= CGFloat(verticalChars) * pointsPerCharacter
        }
    }

    private func acceleratedOffset(_ rawAccumulated: CGFloat, sensitivity: CGFloat) -> Int {
        let baseChars = rawAccumulated / sensitivity
        let velocity = abs(rawAccumulated)
        let multiplier: CGFloat = velocity > 20 ? 2.0 : (velocity > 10 ? 1.5 : 1.0)
        return Int(baseChars * multiplier)
    }

    // MARK: - Shift key handler

    @objc private func handleShiftTap(_ gesture: UITapGestureRecognizer) {
        HapticFeedback.keyTapped()
        AudioServicesPlaySystemSound(KeySound.modifier)

        let now = Date()
        let interval = now.timeIntervalSince(lastShiftTapTime)
        lastShiftTapTime = now

        if interval < 0.4 && shiftState == .shifted {
            // Double-tap while shifted: activate caps lock
            if let keyboardView = findKeyboardView() {
                keyboardView.activateCapsLock()
            }
        } else {
            delegate?.keyShiftTapped()
        }
    }

    /// Walk up the view hierarchy to find the DictusKeyboardView container.
    private func findKeyboardView() -> DictusKeyboardView? {
        var current: UIView? = superview
        while let view = current {
            if let kbView = view as? DictusKeyboardView {
                return kbView
            }
            current = view.superview
        }
        return nil
    }

    // MARK: - Generic key handler

    @objc private func handleGenericTap(_ gesture: UITapGestureRecognizer) {
        HapticFeedback.keyTapped()

        switch key.type {
        case .returnKey:
            AudioServicesPlaySystemSound(KeySound.modifier)
            delegate?.keyReturnTapped()
        case .globe:
            AudioServicesPlaySystemSound(KeySound.modifier)
            delegate?.keyGlobeTapped()
        case .emoji:
            AudioServicesPlaySystemSound(KeySound.modifier)
            delegate?.keyEmojiTapped()
        case .layerSwitch:
            AudioServicesPlaySystemSound(KeySound.modifier)
            delegate?.keyLayerSwitchTapped()
        case .symbolToggle:
            AudioServicesPlaySystemSound(KeySound.modifier)
            delegate?.keySymbolToggleTapped()
        default:
            break
        }
    }

    // MARK: - Trait changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            backgroundColor = backgroundColorForKeyType()
            layer.shadowColor = KeyboardColors.keyShadowColor.cgColor
        }
    }
}
