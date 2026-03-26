// DictusKeyboard/Views/UIKit/KeyboardContainerView.swift
// UIView that assembles keyboard rows using UIStackView with dynamic touch inset computation.
import UIKit
import DictusCore

/// Action callbacks from key presses, passed through from SwiftUI via KeyboardUIView.
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

    /// Flat array of all created buttons for hitTest fallback routing.
    /// Populated in buildKeys() -- includes both LetterKeyButton and BaseSpecialKeyButton subclasses.
    private var allButtons: [UIView] = []

    /// Stored actions for deferred queries (e.g., returnKeyType).
    private var actions: KeyboardActions?

    /// Bridge to SwiftUI for popup/accent/trackpad state.
    weak var touchState: KeyboardTouchState?

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
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 0
            rowStack.distribution = .fill
            rowStack.alignment = .fill

            // Collect created buttons first (some keys like .mic return nil)
            var createdButtons: [(UIView, KeyDefinition)] = []
            for key in row {
                if let button = createButton(for: key, actions: actions) {
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

    // MARK: - Layout and touch insets

    /// Compute touch insets for every button after Auto Layout positions them.
    ///
    /// WHY in layoutSubviews:
    /// Auto Layout needs to compute the exact pixel position of every key before we can
    /// measure the gaps between them. layoutSubviews() is called after constraints are
    /// resolved, so button frames are final and accurate.
    ///
    /// HOW touch insets work:
    /// Each button gets negative UIEdgeInsets that expand its touchable area to cover
    /// the gap between it and its neighbors. Edge buttons extend to the keyboard edge.
    /// Vertical insets cover half the row spacing above and below.
    override func layoutSubviews() {
        super.layoutSubviews()

        // Publish keyboard width for accent strip edge clamping in SwiftUI overlay
        touchState?.keyboardWidth = bounds.width

        let rowCount = rowStacks.count

        for (rowIndex, rowStack) in rowStacks.enumerated() {
            let buttons = rowStack.arrangedSubviews

            // Vertical extension: half the row spacing above and below
            // Top row gets extra top extension, bottom row gets extra bottom extension
            let topExt: CGFloat
            let bottomExt: CGFloat

            if rowIndex == 0 {
                // Top row: extend to top edge of container
                topExt = KeyMetrics.rowSpacing / 2 + 4  // Extra padding at top
            } else {
                topExt = KeyMetrics.rowSpacing / 2
            }

            if rowIndex == rowCount - 1 {
                // Bottom row: extend to bottom edge of container
                bottomExt = KeyMetrics.rowSpacing / 2 + 4  // Extra padding at bottom
            } else {
                bottomExt = KeyMetrics.rowSpacing / 2
            }

            for (i, view) in buttons.enumerated() {
                // Horizontal extensions
                let leftExt: CGFloat
                let rightExt: CGFloat

                if i == 0 {
                    // Leftmost key: extend to left edge of row
                    leftExt = view.frame.minX
                } else {
                    let prevButton = buttons[i - 1]
                    leftExt = (view.frame.minX - prevButton.frame.maxX) / 2
                }

                if i == buttons.count - 1 {
                    // Rightmost key: extend to right edge of row
                    rightExt = rowStack.bounds.width - view.frame.maxX
                } else {
                    let nextButton = buttons[i + 1]
                    rightExt = (nextButton.frame.minX - view.frame.maxX) / 2
                }

                // Apply negative insets to expand touch area
                let insets = UIEdgeInsets(
                    top: -topExt,
                    left: -leftExt,
                    bottom: -bottomExt,
                    right: -rightExt
                )

                // Set touchInsets on the button (all our button types have this property)
                if let letterButton = view as? LetterKeyButton {
                    letterButton.touchInsets = insets
                } else if let specialButton = view as? BaseSpecialKeyButton {
                    specialButton.touchInsets = insets
                }
            }
        }
    }

    // MARK: - Hit test fallback

    /// Route touches that miss the UIStackView chain to the nearest button.
    ///
    /// WHY this override:
    /// The mainStack is inset by KeyMetrics.rowSidePadding (3-5pt) from the container edges.
    /// Touches in that padding zone hit no button because the UIStackView chain never forwards
    /// them. This override catches those missed touches and routes to the nearest button by
    /// center distance, eliminating dead zones at keyboard edges and sub-pixel gaps.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // First, try the normal hit-test chain (UIStackView routing)
        let superHit = super.hitTest(point, with: event)

        // IMPORTANT: only return if superHit is an actual button.
        // UIStackView.hitTest returns itself when the point is between button frames
        // (inside rowStack bounds but no button.frame.contains(point) matches).
        // That rowStack "swallows" the touch silently. By checking the type,
        // any non-button hit (rowStack, mainStack, self) falls through to the
        // nearest-button fallback, eliminating dead zones.
        if let hit = superHit, hit is LetterKeyButton || hit is BaseSpecialKeyButton {
            return hit
        }

        // Fallback: find the nearest button by distance to its center
        guard bounds.contains(point) else { return nil }
        var bestButton: UIView?
        var bestDistance: CGFloat = .greatestFiniteMagnitude
        for button in allButtons {
            guard let parent = button.superview else { continue }
            let center = parent.convert(button.center, to: self)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let dist = dx * dx + dy * dy  // squared distance (skip sqrt for perf)
            if dist < bestDistance {
                bestDistance = dist
                bestButton = button
            }
        }

        // Diagnostic log (temporary) — verify fallback fires for dead zone touches
        let usedFallback = !(superHit is LetterKeyButton || superHit is BaseSpecialKeyButton)
        let buttonLabel: String
        if let lb = bestButton as? LetterKeyButton { buttonLabel = lb.keyLabel }
        else if let sb = bestButton as? BaseSpecialKeyButton { buttonLabel = String(describing: type(of: sb)) }
        else { buttonLabel = "none" }
        PersistentLog.log(.diagnosticProbe(
            component: "HitTest",
            instanceID: "container",
            action: "route",
            details: "x=\(Int(point.x)) y=\(Int(point.y)) superHit=\(superHit.map { String(describing: type(of: $0)) } ?? "nil") fallback=\(usedFallback) key=\(buttonLabel)"
        ))

        return bestButton
    }

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
