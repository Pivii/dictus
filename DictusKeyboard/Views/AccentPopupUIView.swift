// DictusKeyboard/Views/AccentPopupUIView.swift
// UIView popup for accented character selection on long-press.
import UIKit

/// Horizontal popup of accented characters shown during long-press on a vowel key.
///
/// WHY added to inputView directly:
/// Same clipsToBounds issue as KeyPopupUIView — must be added to a view that
/// isn't clipped by the keyboard container.
final class AccentPopupUIView: UIView {

    private var accentLabels: [UILabel] = []
    private var accents: [String] = []
    private var selectedIndex: Int? = nil

    private let cellWidth: CGFloat = 36
    private let cellHeight: CGFloat = 48
    private let fontSize: CGFloat = 22

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
    }

    /// Show the accent popup above the given key view.
    func show(accents: [String], aboveKeyView keyView: UIView, in containerView: UIView) {
        self.accents = accents
        self.selectedIndex = nil

        // Remove old labels
        accentLabels.forEach { $0.removeFromSuperview() }
        accentLabels = []

        let totalWidth = CGFloat(accents.count) * cellWidth
        let keyFrame = keyView.convert(keyView.bounds, to: containerView)
        let gap: CGFloat = 12

        self.frame = CGRect(
            x: keyFrame.midX - totalWidth / 2,
            y: keyFrame.minY - cellHeight - gap,
            width: totalWidth,
            height: cellHeight
        )

        // Clamp to screen edges
        if frame.minX < 4 {
            frame.origin.x = 4
        }
        let screenWidth = containerView.bounds.width
        if frame.maxX > screenWidth - 4 {
            frame.origin.x = screenWidth - 4 - totalWidth
        }

        // Create accent labels
        for (index, accent) in accents.enumerated() {
            let accentLabel = UILabel()
            accentLabel.text = accent
            accentLabel.font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
            accentLabel.textAlignment = .center
            accentLabel.textColor = KeyboardColors.keyLabel
            accentLabel.frame = CGRect(
                x: CGFloat(index) * cellWidth,
                y: 0,
                width: cellWidth,
                height: cellHeight
            )
            addSubview(accentLabel)
            accentLabels.append(accentLabel)
        }

        containerView.addSubview(self)
        isHidden = false
    }

    /// Update the selected accent index — highlights the cell under the finger.
    func updateSelection(_ index: Int?) {
        selectedIndex = index
        for (i, accentLabel) in accentLabels.enumerated() {
            if i == index {
                accentLabel.backgroundColor = KeyboardColors.accentSelectedBackground
                accentLabel.textColor = .white
                accentLabel.layer.cornerRadius = KeyboardColors.keyCornerRadius
                accentLabel.clipsToBounds = true
            } else {
                accentLabel.backgroundColor = .clear
                accentLabel.textColor = KeyboardColors.keyLabel
            }
        }
    }

    func hide() {
        removeFromSuperview()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            backgroundColor = KeyboardColors.popupBackground
            layer.shadowColor = UIColor.black.cgColor
            // Re-apply selection colors
            updateSelection(selectedIndex)
        }
    }
}
