// DictusKeyboard/Views/UIKit/KeyPopupLayer.swift
// UIKit popup layer for key preview and accent strip — sits above the collection view.
import UIKit
import Combine

/// UIView layer that renders key preview popups and accent strip popups in UIKit.
///
/// WHY UIKit instead of SwiftUI for popups:
/// The KeyboardCollectionView sits ON TOP of the SwiftUI hosting view to receive touches
/// directly (avoiding iOS keyboard extension touch filtering). SwiftUI popups would render
/// BEHIND the collection view. UIKit popups in this layer render ABOVE everything.
///
/// WHY isUserInteractionEnabled = false:
/// Touches must pass through to the KeyboardCollectionView below. This layer is purely visual.
class KeyPopupLayer: UIView {

    // MARK: - Key preview subviews

    private let keyPreviewContainer = UIView()
    private let keyPreviewShape = CAShapeLayer()
    private let keyPreviewLabel = UILabel()

    // Key preview dimensions (match old SwiftUI KeyPopup)
    private let bubbleWidth: CGFloat = 52
    private let bubbleHeight: CGFloat = 42
    private let stemHeight: CGFloat = 10
    private let stemBaseWidth: CGFloat = 38
    private let cornerRadius: CGFloat = 8

    // MARK: - Accent strip subviews

    private let accentContainer = UIView()
    private var accentCells: [UIView] = []
    private var accentLabels: [UILabel] = []

    // Accent dimensions (match old SwiftUI AccentPopup)
    private let accentCellWidth: CGFloat = 36
    private let accentCellHeight: CGFloat = 48
    private let accentFontSize: CGFloat = 22

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Colors

    private static let letterNormal = UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.22, alpha: 1) : .white
    }

    private static let accentBlue = UIColor(red: 0x3D / 255.0, green: 0x7E / 255.0, blue: 0xFF / 255.0, alpha: 1)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = false

        setupKeyPreview()
        setupAccentStrip()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Setup

    private func setupKeyPreview() {
        let totalHeight = bubbleHeight + stemHeight

        keyPreviewContainer.frame = CGRect(x: 0, y: 0, width: bubbleWidth, height: totalHeight)
        keyPreviewContainer.backgroundColor = .clear
        keyPreviewContainer.isHidden = true
        keyPreviewContainer.clipsToBounds = false

        // Shape layer for the popup bubble path
        keyPreviewShape.fillColor = Self.letterNormal.cgColor
        keyPreviewShape.shadowColor = UIColor.black.cgColor
        keyPreviewShape.shadowOpacity = 0.18
        keyPreviewShape.shadowOffset = CGSize(width: 0, height: 2)
        keyPreviewShape.shadowRadius = 4
        keyPreviewContainer.layer.addSublayer(keyPreviewShape)

        // Label
        keyPreviewLabel.font = .systemFont(ofSize: 32, weight: .regular)
        keyPreviewLabel.textColor = .label
        keyPreviewLabel.textAlignment = .center
        keyPreviewLabel.frame = CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
        keyPreviewContainer.addSubview(keyPreviewLabel)

        addSubview(keyPreviewContainer)
        updateKeyPreviewPath()
    }

    private func setupAccentStrip() {
        accentContainer.backgroundColor = .clear
        accentContainer.isHidden = true
        accentContainer.clipsToBounds = false

        // Background with shadow
        accentContainer.layer.shadowColor = UIColor.black.cgColor
        accentContainer.layer.shadowOpacity = 0.2
        accentContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
        accentContainer.layer.shadowRadius = 3

        addSubview(accentContainer)
    }

    // MARK: - Key preview path

    private func updateKeyPreviewPath() {
        let totalHeight = bubbleHeight + stemHeight
        let rect = CGRect(x: 0, y: 0, width: bubbleWidth, height: totalHeight)
        let midX = rect.midX
        let bubbleBottom = rect.height - stemHeight
        let bubbleHW = bubbleWidth / 2
        let baseHW = stemBaseWidth / 2
        let cr = cornerRadius

        let path = CGMutablePath()

        // Start at top-left after corner radius
        path.move(to: CGPoint(x: midX - bubbleHW + cr, y: 0))
        // Top edge
        path.addLine(to: CGPoint(x: midX + bubbleHW - cr, y: 0))
        // Top-right corner
        path.addQuadCurve(to: CGPoint(x: midX + bubbleHW, y: cr),
                          control: CGPoint(x: midX + bubbleHW, y: 0))
        // Right edge
        path.addLine(to: CGPoint(x: midX + bubbleHW, y: bubbleBottom))
        // Right transition to stem
        path.addQuadCurve(to: CGPoint(x: midX + baseHW, y: rect.height),
                          control: CGPoint(x: midX + bubbleHW, y: rect.height))
        // Bottom edge
        path.addLine(to: CGPoint(x: midX - baseHW, y: rect.height))
        // Left transition from stem
        path.addQuadCurve(to: CGPoint(x: midX - bubbleHW, y: bubbleBottom),
                          control: CGPoint(x: midX - bubbleHW, y: rect.height))
        // Left edge
        path.addLine(to: CGPoint(x: midX - bubbleHW, y: cr))
        // Top-left corner
        path.addQuadCurve(to: CGPoint(x: midX - bubbleHW + cr, y: 0),
                          control: CGPoint(x: midX - bubbleHW, y: 0))
        path.closeSubpath()

        keyPreviewShape.path = path
    }

    // MARK: - Configure (Combine observation)

    /// Set up Combine subscriptions to observe KeyboardTouchState.
    func configure(touchState: KeyboardTouchState) {
        // Key preview
        touchState.$pressedKeyLabel
            .combineLatest(touchState.$pressedKeyFrame, touchState.$showingAccents)
            .receive(on: RunLoop.main)
            .sink { [weak self] label, frame, showingAccents in
                if let label = label, !showingAccents {
                    self?.showKeyPreview(label: label, keyFrame: frame)
                } else {
                    self?.hideKeyPreview()
                }
            }
            .store(in: &cancellables)

        // Accent strip — split into two combineLatest (max 4 publishers each)
        touchState.$showingAccents
            .combineLatest(touchState.$accentOptions, touchState.$accentKeyFrame, touchState.$selectedAccentIndex)
            .combineLatest(touchState.$keyboardWidth)
            .receive(on: RunLoop.main)
            .sink { [weak self] combo, kbWidth in
                let (showing, options, frame, selected) = combo
                if showing, !options.isEmpty {
                    self?.showAccentStrip(accents: options, keyFrame: frame,
                                          selectedIndex: selected, keyboardWidth: kbWidth)
                } else {
                    self?.hideAccentStrip()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Key preview show/hide

    private func showKeyPreview(label: String, keyFrame: CGRect) {
        keyPreviewLabel.text = label

        // Update shape fill color for current appearance
        keyPreviewShape.fillColor = Self.letterNormal.cgColor

        let totalHeight = bubbleHeight + stemHeight
        // Position: centered on key, above it
        let x = keyFrame.midX - bubbleWidth / 2
        let y = keyFrame.minY - totalHeight + stemHeight / 2
        keyPreviewContainer.frame = CGRect(x: x, y: y, width: bubbleWidth, height: totalHeight)
        keyPreviewLabel.frame = CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)

        keyPreviewContainer.isHidden = false
    }

    private func hideKeyPreview() {
        keyPreviewContainer.isHidden = true
    }

    // MARK: - Accent strip show/hide

    private func showAccentStrip(accents: [String], keyFrame: CGRect,
                                  selectedIndex: Int?, keyboardWidth: CGFloat) {
        let count = accents.count
        let totalWidth = CGFloat(count) * accentCellWidth
        let halfWidth = totalWidth / 2

        // Edge clamping (same logic as old SwiftUI)
        let rawMidX = keyFrame.midX
        let clampedMidX = max(halfWidth, min(rawMidX, keyboardWidth - halfWidth))

        let x = clampedMidX - halfWidth
        let y = keyFrame.minY - accentCellHeight - 4

        accentContainer.frame = CGRect(x: x, y: y, width: totalWidth, height: accentCellHeight)

        // Background
        accentContainer.layer.cornerRadius = 8
        accentContainer.backgroundColor = Self.letterNormal

        // Rebuild cells if count changed
        if accentCells.count != count {
            // Remove old cells
            for cell in accentCells { cell.removeFromSuperview() }
            accentCells.removeAll()
            accentLabels.removeAll()

            for i in 0..<count {
                let cell = UIView()
                cell.layer.cornerRadius = KeyMetrics.keyCornerRadius
                cell.clipsToBounds = true

                let lbl = UILabel()
                lbl.font = .systemFont(ofSize: accentFontSize, weight: .regular)
                lbl.textAlignment = .center
                cell.addSubview(lbl)

                let cellX = CGFloat(i) * accentCellWidth
                cell.frame = CGRect(x: cellX, y: 0, width: accentCellWidth, height: accentCellHeight)
                lbl.frame = cell.bounds

                accentContainer.addSubview(cell)
                accentCells.append(cell)
                accentLabels.append(lbl)
            }
        }

        // Update content and selection
        for i in 0..<count {
            accentLabels[i].text = accents[i]

            let isSelected = (i == selectedIndex)
            accentCells[i].backgroundColor = isSelected ? Self.accentBlue : Self.letterNormal
            accentLabels[i].textColor = isSelected ? .white : .label

            let cellX = CGFloat(i) * accentCellWidth
            accentCells[i].frame = CGRect(x: cellX, y: 0, width: accentCellWidth, height: accentCellHeight)
            accentLabels[i].frame = accentCells[i].bounds
        }

        accentContainer.isHidden = false
        hideKeyPreview()
    }

    private func hideAccentStrip() {
        accentContainer.isHidden = true
    }

    // MARK: - Trait changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Update colors for dark/light mode change
        keyPreviewShape.fillColor = Self.letterNormal.cgColor
    }
}
