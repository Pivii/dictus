// DictusKeyboard/Views/KeyPopupUIView.swift
// UIView popup preview shown above a pressed key.
import UIKit

/// Key preview popup — shows the pressed character in a larger bubble above the key.
///
/// WHY added to inputView directly (not DictusKeyboardView):
/// iOS forces clipsToBounds = true on keyboard extension containers. Adding the popup
/// to the inputView (which we control) allows it to appear above the key rows.
/// Positioned in absolute coordinates relative to the inputView.
final class KeyPopupUIView: UIView {

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupView() {
        backgroundColor = KeyboardColors.popupBackground
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 3
        layer.shadowOpacity = 0.2

        label.font = UIFont.systemFont(ofSize: 32, weight: .regular)
        label.textColor = KeyboardColors.keyLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// Show the popup above the given key view.
    func show(label text: String, aboveKeyView keyView: UIView, in containerView: UIView) {
        label.text = text

        // Convert key position to container coordinates
        let keyFrame = keyView.convert(keyView.bounds, to: containerView)

        let popupWidth: CGFloat = 50
        let popupHeight: CGFloat = 56
        let gap: CGFloat = 8

        self.frame = CGRect(
            x: keyFrame.midX - popupWidth / 2,
            y: keyFrame.minY - popupHeight - gap,
            width: popupWidth,
            height: popupHeight
        )

        containerView.addSubview(self)
        isHidden = false
    }

    func hide() {
        removeFromSuperview()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            backgroundColor = KeyboardColors.popupBackground
            layer.shadowColor = UIColor.black.cgColor
        }
    }
}
