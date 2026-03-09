// DictusKeyboard/Views/DictusKeyboardView.swift
// Main UIView container for the 4-row keyboard — manages state, layers, popups.
import UIKit
import AudioToolbox
import DictusCore

/// Delegate for DictusKeyboardView to communicate with KeyboardViewController.
protocol DictusKeyboardViewDelegate: AnyObject {
    var textDocumentProxy: UITextDocumentProxy { get }
    func advanceToNextInputMode()
    func showEmojiPicker()
    func dismissEmojiPicker()
    func insertText(_ text: String)
    func deleteBackward()
    func adjustTextPosition(byCharacterOffset offset: Int)
    func checkAutocapitalize()
}

/// Main keyboard container — 4 rows of DictusKeyView, manages shift/layer state.
///
/// WHY a single UIView instead of a UIViewController:
/// Keyboard extensions have strict memory constraints. A simple UIView subclass
/// avoids the overhead of an additional view controller and its lifecycle.
/// State management is done with simple properties instead of ObservableObject.
final class DictusKeyboardView: UIView {

    // MARK: - State

    var currentLayer: KeyboardLayerType = .letters {
        didSet { rebuildRows() }
    }

    var shiftState: ShiftState = .off {
        didSet { updateRowStates() }
    }

    var lastTypedChar: String? = nil {
        didSet { updateRowStates() }
    }

    weak var delegate: DictusKeyboardViewDelegate?

    /// Remembers which layer to return to when dismissing the emoji picker.
    var previousLayer: KeyboardLayerType? = nil

    // MARK: - Subviews

    private var rowViews: [KeyRowView] = []
    private let trackpadOverlay = UIView()
    private let keyPopup = KeyPopupUIView()
    private let accentPopup = AccentPopupUIView()

    // MARK: - Computed

    private var isShifted: Bool {
        shiftState == .shifted || shiftState == .capsLocked
    }

    private var currentRows: [[KeyDefinition]] {
        switch currentLayer {
        case .letters:
            return KeyboardLayout.currentLettersRows().map { row in
                row.filter { $0.type != .mic }
            }
        case .numbers: return KeyboardLayout.numbersRows
        case .symbols: return KeyboardLayout.symbolsRows
        case .emoji: return []
        }
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Setup

    private func setupView() {
        backgroundColor = .clear

        // Trackpad overlay (hidden by default)
        trackpadOverlay.backgroundColor = KeyboardColors.trackpadOverlay
        trackpadOverlay.layer.cornerRadius = 8
        trackpadOverlay.isHidden = true
        trackpadOverlay.isUserInteractionEnabled = false
        addSubview(trackpadOverlay)

        rebuildRows()
    }

    /// Rebuild row views for the current layer.
    func rebuildRows() {
        // Remove existing rows
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = []

        let rows = currentRows
        for rowKeys in rows {
            let rowView = KeyRowView()
            rowView.configure(keys: rowKeys, delegate: self)
            addSubview(rowView)
            rowViews.append(rowView)
        }

        // Ensure trackpad overlay is on top of rows
        bringSubviewToFront(trackpadOverlay)

        updateRowStates()
        setNeedsLayout()
    }

    private func updateRowStates() {
        for rowView in rowViews {
            rowView.updateState(
                isShifted: isShifted,
                shiftState: shiftState,
                lastTypedChar: lastTypedChar
            )
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let rowCount = rowViews.count
        guard rowCount > 0 else { return }

        let keyHeight = KeyboardColors.keyHeight
        let rowSpacing = KeyboardColors.rowSpacing
        let verticalPadding: CGFloat = 4

        var y = verticalPadding
        for rowView in rowViews {
            rowView.frame = CGRect(
                x: 0,
                y: y,
                width: bounds.width,
                height: keyHeight
            )
            y += keyHeight + rowSpacing
        }

        // Trackpad overlay covers entire keyboard area
        trackpadOverlay.frame = bounds
    }

    // MARK: - Popup management

    /// The container view where popups are added (should be the inputView).
    /// Set by KeyboardViewController after setup.
    weak var popupContainer: UIView?

    func updateAccentSelection(_ index: Int) {
        accentPopup.updateSelection(index)
    }

    // MARK: - Trait changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            trackpadOverlay.backgroundColor = KeyboardColors.trackpadOverlay
        }
    }
}

// MARK: - DictusKeyViewDelegate

extension DictusKeyboardView: DictusKeyViewDelegate {

    func keyTapped(_ key: KeyDefinition, output: String) {
        AudioServicesPlaySystemSound(KeySound.letter)
        lastTypedChar = output
        delegate?.insertText(output)

        // Auto-unshift after one character (unless caps locked)
        if shiftState == .shifted {
            shiftState = .off
        }
        delegate?.checkAutocapitalize()
    }

    func keyDeleteTapped() {
        delegate?.deleteBackward()
        lastTypedChar = nil
        delegate?.checkAutocapitalize()
    }

    func keyDeleteWord() {
        deleteWordBackward()
        lastTypedChar = nil
        delegate?.checkAutocapitalize()
    }

    func keyShiftTapped() {
        // Shift state cycling: off → shifted → off, or shifted+double-tap → capsLocked
        switch shiftState {
        case .off:
            shiftState = .shifted
        case .shifted:
            // Check for double-tap (handled in DictusKeyView, but state update here)
            // DictusKeyView calls this once — we check timing there.
            // For simplicity, toggle: if already shifted, check timing.
            shiftState = .off
        case .capsLocked:
            shiftState = .off
        }
    }

    /// Called by DictusKeyView when shift is double-tapped (detected by timing).
    func activateCapsLock() {
        shiftState = .capsLocked
    }

    func keySpaceTapped() {
        AudioServicesPlaySystemSound(KeySound.modifier)
        delegate?.insertText(" ")
        lastTypedChar = nil
        delegate?.checkAutocapitalize()
    }

    func keyReturnTapped() {
        delegate?.insertText("\n")
        lastTypedChar = nil
        delegate?.checkAutocapitalize()
    }

    func keyGlobeTapped() {
        delegate?.advanceToNextInputMode()
    }

    func keyEmojiTapped() {
        previousLayer = currentLayer
        delegate?.showEmojiPicker()
    }

    func keyLayerSwitchTapped() {
        if currentLayer == .letters {
            currentLayer = .numbers
        } else {
            currentLayer = .letters
            shiftState = .off
        }
    }

    func keySymbolToggleTapped() {
        if currentLayer == .numbers {
            currentLayer = .symbols
        } else {
            currentLayer = .numbers
        }
    }

    func keyAccentAdaptiveTapped(_ output: String) {
        AudioServicesPlaySystemSound(KeySound.letter)
        // If replacing a vowel with its accent, delete the previous vowel first
        if AccentedCharacters.shouldReplace(afterTyping: lastTypedChar) {
            delegate?.deleteBackward()
        }
        lastTypedChar = output
        delegate?.insertText(output)

        if shiftState == .shifted {
            shiftState = .off
        }
        delegate?.checkAutocapitalize()
    }

    func keyCursorMove(_ offset: Int) {
        delegate?.adjustTextPosition(byCharacterOffset: offset)
    }

    func keyTrackpadStateChanged(_ active: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.trackpadOverlay.isHidden = !active
            self.trackpadOverlay.alpha = active ? 1 : 0
        }
    }

    func showAccentPopup(accents: [String], fromKeyView keyView: DictusKeyView) {
        hidePopups()
        guard let container = popupContainer else { return }
        accentPopup.show(accents: accents, aboveKeyView: keyView, in: container)
    }

    func showKeyPopup(label: String, fromKeyView keyView: DictusKeyView) {
        guard let container = popupContainer else { return }
        keyPopup.show(label: label, aboveKeyView: keyView, in: container)
    }

    func hidePopups() {
        keyPopup.hide()
        accentPopup.hide()
    }

    // MARK: - Word deletion

    private func deleteWordBackward() {
        guard let proxy = delegate?.textDocumentProxy else {
            delegate?.deleteBackward()
            return
        }
        guard let before = proxy.documentContextBeforeInput, !before.isEmpty else {
            delegate?.deleteBackward()
            return
        }

        var trimmed = before
        var trailingSpaces = 0
        while trimmed.hasSuffix(" ") {
            trimmed = String(trimmed.dropLast())
            trailingSpaces += 1
        }

        let charsInWord: Int
        if let lastSpace = trimmed.lastIndex(of: " ") {
            charsInWord = trimmed.distance(from: trimmed.index(after: lastSpace), to: trimmed.endIndex)
        } else {
            charsInWord = trimmed.count
        }

        let totalToDelete = trailingSpaces + charsInWord
        for _ in 0..<totalToDelete {
            delegate?.deleteBackward()
        }
    }
}
