// DictusKeyboard/Views/UIKit/KeyboardContainerView.swift
// UIView that assembles keyboard rows using UIStackView with dynamic touch inset computation.
import UIKit
import DictusCore

/// Action callbacks from key presses, wired from KeyboardRootView via the controller.
///
/// WHY a struct instead of individual closures on each button:
/// Consolidating all callbacks into a single struct makes it easy to pass through
/// the UIViewRepresentable boundary and ensures all actions are wired consistently.
struct KeyboardActions {
    var onCharacter: (String) -> Void = { _ in }
    /// Returns true if text was deleted, false if text field was empty.
    var onDelete: () -> Bool = { false }
    var onWordDelete: () -> Void = {}
    var onSpace: () -> Void = {}
    var onReturn: () -> Void = {}
    var onGlobe: () -> Void = {}
    var onEmoji: () -> Void = {}
    var onLayerSwitch: () -> Void = {}
    var onSymbolToggle: () -> Void = {}
    var onAccentAdaptive: (String) -> Void = { _ in }
    var onCursorMove: (Int) -> Void = { _ in }
    var onShiftChanged: (ShiftState) -> Void = { _ in }
    /// Returns the current returnKeyType from the text document proxy.
    var onReturnKeyType: (() -> UIReturnKeyType)? = { .default }
}

/// UIView that arranges keyboard key buttons in rows using UIStackView.
///
/// WHY UIStackView layout:
/// UIStackView handles distribution of key widths proportionally (via width constraints
/// relative to row width). Auto Layout computes the exact pixel position of every key,
/// which layoutSubviews() uses to compute negative touch insets that fill gaps.
///
/// WHY vertical stack with horizontal row stacks:
/// Matches the existing SwiftUI VStack > HStack > key pattern. Each row is a horizontal
/// UIStackView, and the rows are stacked vertically. This gives precise control over
/// row heights and key widths via Auto Layout constraints.
class KeyboardContainerView: UIView {

    // MARK: - Properties

    private let mainStack = UIStackView()
    private var rowStacks: [UIStackView] = []
    private var letterButtons: [LetterKeyButton] = []
    private var shiftButton: ShiftKeyButton?
    private var deleteButton: DeleteKeyButton?
    private var spaceButton: SpaceKeyButton?
    private var returnButton: ReturnKeyButton?
    private var accentButton: AdaptiveAccentKeyButton?

    /// Flat array of all created buttons, used by the top-level touch forwarding view.
    private var allButtons: [UIView] = []

    /// Stored actions for deferred queries (e.g., returnKeyType).
    private var actions: KeyboardActions?

    /// Bridge to SwiftUI for popup/accent/trackpad state.
    weak var touchState: KeyboardTouchState?

    /// Reference to the top-level forwarding view (owned by KeyboardViewController).
    weak var forwardingView: KeyboardTouchForwardingView?

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
        backgroundColor = .clear

        mainStack.axis = .vertical
        mainStack.spacing = 0
        mainStack.distribution = .fillEqually
        mainStack.alignment = .fill
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        mainStack.isUserInteractionEnabled = false

        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: KeyMetrics.rowSidePadding),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -KeyMetrics.rowSidePadding),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: - Build keys

    /// Build all key buttons from layout definitions and wire action callbacks.
    ///
    /// WHY full rebuild on layer switch:
    /// When switching between letters/numbers/symbols, the key types and counts change
    /// completely. Rebuilding is simpler and more reliable than trying to update in-place.
    /// For shift-only changes, use updateShift() instead (no rebuild needed).
    func buildKeys(rows: [[KeyDefinition]], actions: KeyboardActions) {
        // Store actions for deferred queries (e.g., returnKeyType)
        self.actions = actions

        // Clear existing
        for view in mainStack.arrangedSubviews {
            mainStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        rowStacks.removeAll()
        letterButtons.removeAll()
        allButtons.removeAll()
        shiftButton = nil
        deleteButton = nil
        spaceButton = nil
        returnButton = nil
        accentButton = nil

        for row in rows {
            let rowStack = KeyboardRowStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 0
            rowStack.distribution = .fill
            rowStack.alignment = .fill
            rowStack.isUserInteractionEnabled = false

            // Collect created buttons first (some keys like .mic return nil)
            var createdButtons: [(UIView, KeyDefinition)] = []
            for key in row {
                if let button = createButton(for: key, actions: actions) {
                    button.isUserInteractionEnabled = false
                    rowStack.addArrangedSubview(button)
                    createdButtons.append((button, key))
                    allButtons.append(button)
                }
            }

            // Constrain all but the LAST button's width proportionally.
            // WHY skip last: UIStackView with .fill distribution sizes the last
            // arranged subview to fill remaining space. If we also constrain it,
            // the system is over-determined and crashes with mutually exclusive
            // constraints (NSInternalInconsistencyException).
            let actualTotal = createdButtons.reduce(CGFloat(0)) { $0 + $1.1.widthMultiplier }
            if actualTotal > 0 {
                for (index, (button, key)) in createdButtons.enumerated() {
                    if index < createdButtons.count - 1 {
                        button.widthAnchor.constraint(
                            equalTo: rowStack.widthAnchor,
                            multiplier: key.widthMultiplier / actualTotal
                        ).isActive = true
                    }
                }
            }

            mainStack.addArrangedSubview(rowStack)
            rowStacks.append(rowStack)
        }

        // Populate the forwarding view with all buttons
        forwardingView?.allButtons = allButtons

        setNeedsLayout()
    }

    // MARK: - Button factory

    /// Create the appropriate UIButton subclass for a key definition.
    private func createButton(for key: KeyDefinition, actions: KeyboardActions) -> UIView? {
        switch key.type {
        case .character:
            let button = LetterKeyButton()
            button.configure(key: key, shifted: false)
            button.touchState = touchState
            button.onTap = actions.onCharacter
            letterButtons.append(button)
            return button

        case .shift:
            let button = ShiftKeyButton()
            button.onShiftChanged = actions.onShiftChanged
            shiftButton = button
            return button

        case .delete:
            let button = DeleteKeyButton()
            button.onDelete = actions.onDelete
            button.onWordDelete = actions.onWordDelete
            deleteButton = button
            return button

        case .space:
            let button = SpaceKeyButton()
            button.onTap = actions.onSpace
            button.onCursorMove = actions.onCursorMove
            button.touchState = touchState
            spaceButton = button
            return button

        case .returnKey:
            let button = ReturnKeyButton()
            button.onTap = actions.onReturn
            returnButton = button
            return button

        case .globe:
            let button = GlobeKeyButton()
            button.onTap = actions.onGlobe
            return button

        case .emoji:
            let button = EmojiKeyButton()
            button.onTap = actions.onEmoji
            return button

        case .layerSwitch:
            let button = LayerSwitchKeyButton()
            button.updateLabel(key.label)
            button.onTap = actions.onLayerSwitch
            return button

        case .symbolToggle:
            let button = LayerSwitchKeyButton()
            button.updateLabel(key.label)
            button.onTap = actions.onSymbolToggle
            return button

        case .accentAdaptive:
            let button = AdaptiveAccentKeyButton()
            button.touchState = touchState
            button.onTap = actions.onAccentAdaptive
            accentButton = button
            return button

        case .mic:
            // Mic is in the toolbar, not the keyboard grid. Safety guard.
            return nil
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Publish keyboard width for accent strip edge clamping in SwiftUI overlay
        touchState?.keyboardWidth = bounds.width
    }

    // MARK: - Hit test

    // No hitTest override needed — the top-level KeyboardTouchForwardingView
    // (in kbInputView, above the hosting view) handles all touch routing.
    // This container is layout-only: isUserInteractionEnabled=false on all subviews.

    // MARK: - Update methods (avoid full rebuild)

    /// Update shift state on all letter buttons without rebuilding the view hierarchy.
    func updateShift(_ shifted: Bool) {
        for button in letterButtons {
            button.updateShift(shifted)
        }
        accentButton?.isShifted = shifted
    }

    /// Update the shift icon without rebuilding.
    func updateShiftIcon(_ state: ShiftState) {
        shiftButton?.updateShiftState(state)
    }

    /// Update the adaptive accent key's display state.
    func updateAccentState(lastTypedChar: String?, isShifted: Bool) {
        accentButton?.updateState(lastTypedChar: lastTypedChar, isShifted: isShifted)
    }

    /// Update the return key label based on the host text field's returnKeyType.
    /// Called on every updateUIView -- cheap operation, just reads the proxy value.
    func updateReturnKeyType() {
        let type = actions?.onReturnKeyType?() ?? .default
        returnButton?.updateReturnKeyType(type)
    }
}

// MARK: - KeyboardRowStackView

/// UIStackView subclass used for keyboard rows. Touch handling is now done by
/// KeyboardTouchForwardingView — this class only exists for layout purposes.
class KeyboardRowStackView: UIStackView {}
