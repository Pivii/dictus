// DictusKeyboard/Views/KeyRowView.swift
// UIView container for a single keyboard row — calculates dynamic key widths.
import UIKit

/// A single row of keyboard keys rendered with UIKit.
///
/// WHY manual frame layout instead of Auto Layout:
/// Keyboard rows recalculate on every layer switch and screen rotation.
/// Manual frame calculation is significantly faster than re-solving
/// Auto Layout constraints, which matters for keyboard responsiveness.
final class KeyRowView: UIView {

    // MARK: - Properties

    private(set) var keyViews: [DictusKeyView] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Configuration

    /// Configure this row with key definitions. Creates DictusKeyView subviews.
    func configure(keys: [KeyDefinition], delegate: DictusKeyViewDelegate?) {
        // Remove existing key views
        keyViews.forEach { $0.removeFromSuperview() }
        keyViews = []

        for key in keys {
            let keyView = DictusKeyView(key: key)
            keyView.delegate = delegate
            addSubview(keyView)
            keyViews.append(keyView)
        }
    }

    /// Update all key views with current state.
    func updateState(isShifted: Bool, shiftState: ShiftState, lastTypedChar: String?) {
        for keyView in keyViews {
            keyView.isShifted = isShifted
            if keyView.key.type == .shift {
                keyView.shiftState = shiftState
            }
            if keyView.key.type == .accentAdaptive || keyView.key.type == .character {
                keyView.lastTypedChar = lastTypedChar
            }
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        guard !keyViews.isEmpty else { return }

        let keys = keyViews.map { $0.key }
        let totalMultiplier = keys.reduce(CGFloat(0)) { $0 + $1.widthMultiplier }
        let totalSpacing = CGFloat(keys.count - 1) * KeyboardColors.keySpacing
        let horizontalPadding = KeyboardColors.rowHorizontalPadding * 2
        let availableWidth = bounds.width - horizontalPadding - totalSpacing
        let unitKeyWidth = availableWidth / totalMultiplier

        var x = KeyboardColors.rowHorizontalPadding

        for keyView in keyViews {
            let keyWidth = unitKeyWidth * keyView.key.widthMultiplier
            keyView.frame = CGRect(
                x: x,
                y: 0,
                width: keyWidth,
                height: bounds.height
            )
            x += keyWidth + KeyboardColors.keySpacing
        }
    }
}
