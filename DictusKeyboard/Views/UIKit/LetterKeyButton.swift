// DictusKeyboard/Views/UIKit/LetterKeyButton.swift
// UIButton subclass for letter keys with extended hit regions and accent long-press.
import UIKit
import AudioToolbox
import DictusCore

/// A UIButton subclass for keyboard letter keys that eliminates dead zones via
/// `point(inside:with:)` with negative UIEdgeInsets.
///
/// WHY UIButton instead of SwiftUI:
/// Phase 15.4 proved that SwiftUI's DragGesture cannot extend hit regions beyond
/// the view's frame. UIButton's `point(inside:with:)` allows expanding the touchable
/// area with negative insets, so every pixel between keys resolves to a key tap.
///
/// WHY touchesBegan for audio/haptic:
/// Matches Apple's native keyboard: feedback fires on press (touchDown), not release.
/// This is a locked decision from Phase 15.3.
///
/// WHY 400ms long-press for accents:
/// iOS system keyboard uses ~350-500ms for long-press detection. 400ms balances
/// responsiveness with avoiding false triggers during fast typing.
class LetterKeyButton: UIButton {

    // MARK: - Properties

    /// Negative insets that EXPAND the touchable area beyond the button's visual bounds.
    /// Set by KeyboardContainerView.layoutSubviews() after layout is computed.
    ///
    /// WHY negative values: UIEdgeInsets with negative values in `bounds.inset(by:)`
    /// produce a LARGER rect. For example, UIEdgeInsets(top: -5, ...) adds 5pt above.
    var touchInsets = UIEdgeInsets.zero

    /// The base key label (lowercase, e.g., "a"). Used for accent lookup.
    var keyLabel: String = ""

    /// Whether the key is currently in shifted (uppercase) mode.
    var isShifted: Bool = false {
        didSet {
            setTitle(displayLabel, for: .normal)
        }
    }

    /// Whether the long-press timer has fired (accent mode is active).
    private var longPressFired = false

    /// Weak reference to the ObservableObject bridge for publishing press/accent state to SwiftUI.
    weak var touchState: KeyboardTouchState?

    /// Callback when a character should be inserted (normal tap or accent selection).
    var onTap: ((String) -> Void)?

    /// Task for the 400ms accent long-press timer.
    private var longPressTimer: Task<Void, Never>?

    /// Cell width for accent popup hit-testing (matches AccentPopup.cellWidth).
    private let accentCellWidth: CGFloat = 36

    // MARK: - Computed properties

    /// The label to display: uppercase if shifted, lowercase otherwise.
    var displayLabel: String {
        isShifted ? keyLabel.uppercased() : keyLabel.lowercased()
    }

    /// The character to insert on tap: uppercase if shifted, lowercase otherwise.
    var outputChar: String {
        isShifted ? keyLabel.uppercased() : keyLabel.lowercased()
    }

    // MARK: - Dynamic colors

    /// Normal background: dark mode = 22% white, light mode = white.
    /// Uses UIColor dynamic provider so it updates automatically on trait changes.
    private static let normalBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.22, alpha: 1) : .white
    }

    /// Pressed background: dark mode = 32% white, light mode = 88% white.
    private static let pressedBackground = UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 0.88, alpha: 1)
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        titleLabel?.font = .systemFont(ofSize: 22)
        setTitleColor(.label, for: .normal)
        backgroundColor = Self.normalBackground
        layer.cornerRadius = KeyMetrics.keyCornerRadius
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        clipsToBounds = false
    }

    // MARK: - Hit testing

    /// Expand the touchable area using negative insets.
    /// This is the core mechanism that eliminates dead zones between keys.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.inset(by: touchInsets).contains(point)
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        let touchDownState = KeyTapSignposter.beginTouchDown()

        // 1. Visual highlight
        backgroundColor = Self.pressedBackground
        KeyTapSignposter.emitHighlight(touchDownState)

        // 2. Audio on touchDown
        AudioServicesPlaySystemSound(KeySound.letter)

        // 3. Haptic on touchDown
        HapticFeedback.keyTapped()
        KeyTapSignposter.emitHaptic(touchDownState)

        // 4. Prepare Taptic Engine for NEXT tap
        HapticFeedback.prepareForNextTap()

        KeyTapSignposter.endTouchDown(touchDownState)

        // 5. Publish press state to SwiftUI for popup preview
        let frameInKeyboard = frameInKeyboardCoordinateSpace()
        touchState?.showPress(label: displayLabel, frame: frameInKeyboard)

        // 6. Start 400ms accent long-press timer
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

        // If accent popup is showing, track which accent the finger is over
        guard longPressFired, touchState?.showingAccents == true,
              let touch = touches.first else { return }

        let location = touch.location(in: self)
        let accentCount = touchState?.accentOptions.count ?? 0
        guard accentCount > 0 else { return }

        let totalWidth = CGFloat(accentCount) * accentCellWidth
        let popupStartX = bounds.midX - totalWidth / 2
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

        // Reset visual state
        backgroundColor = Self.normalBackground

        if let state = touchState, state.showingAccents,
           let index = state.selectedAccentIndex,
           index >= 0, index < state.accentOptions.count {
            // Accent selected: insert the selected accent
            onTap?(state.accentOptions[index])
            touchState?.hideAccents()
        } else if !longPressFired {
            // Normal tap: insert the character
            onTap?(outputChar)
        }
        // If long press fired but no accent selected (e.g., no accents for this key),
        // dismiss without inserting

        touchState?.hidePress()
        touchState?.hideAccents()
        longPressFired = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches ?? [], with: event)

        longPressTimer?.cancel()
        longPressTimer = nil

        // Reset visual state -- NO character insertion on cancel
        backgroundColor = Self.normalBackground
        touchState?.hidePress()
        touchState?.hideAccents()
        longPressFired = false
    }

    // MARK: - Long-press

    /// Called after 400ms: check for accented variants and show popup if available.
    private func handleLongPress() {
        longPressFired = true

        guard let accents = AccentedCharacters.accents(for: keyLabel.lowercased()),
              !accents.isEmpty else { return }

        let accentList: [String]
        if isShifted {
            accentList = accents.map { $0.uppercased() }
        } else {
            accentList = accents
        }

        let frameInKeyboard = frameInKeyboardCoordinateSpace()
        touchState?.showAccents(accentList, keyFrame: frameInKeyboard)
    }

    // MARK: - Configuration

    /// Configure the button with a KeyDefinition and shift state.
    func configure(key: KeyDefinition, shifted: Bool) {
        keyLabel = key.label
        isShifted = shifted
        setTitle(displayLabel, for: .normal)
    }

    /// Update shift state without recreating the button.
    func updateShift(_ shifted: Bool) {
        isShifted = shifted
    }

    // MARK: - Helpers

    /// Convert this button's bounds to the keyboard's coordinate space.
    /// Walks up the view hierarchy to find the KeyboardContainerView (superview chain).
    private func frameInKeyboardCoordinateSpace() -> CGRect {
        // Walk up to find the KeyboardContainerView (3 levels: button -> rowStack -> mainStack -> container)
        var target: UIView? = superview?.superview?.superview
        if target == nil { target = superview }
        return convert(bounds, to: target)
    }
}
