// DictusKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI
import Combine
import AudioToolbox
import DictusCore

/// Main keyboard view controller — orchestrates UIKit keyboard + SwiftUI toolbar/overlay.
///
/// WHY hybrid UIKit + SwiftUI:
/// The keyboard keys are UIKit (DictusKeyboardView) for native-level performance.
/// The toolbar (mic button), recording overlay, and emoji picker remain SwiftUI
/// because they don't have the same per-keystroke performance requirements.
class KeyboardViewController: UIInputViewController {

    // MARK: - State

    private let keyboardState = KeyboardState()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UIKit keyboard

    private let keyboardView = DictusKeyboardView()

    // MARK: - SwiftUI hosting controllers

    private var toolbarHosting: UIHostingController<AnyView>?
    private var recordingHosting: UIHostingController<AnyView>?
    private var emojiHosting: UIHostingController<AnyView>?

    // MARK: - Layout

    private var heightConstraint: NSLayoutConstraint?
    private var isEmojiMode = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        #if DEBUG
        let result = AppGroupDiagnostic.run()
        if #available(iOS 14.0, *) {
            DictusLogger.keyboard.debug(
                "Diagnostic: canWrite=\(result.canWrite) canRead=\(result.canRead)"
            )
        }
        #endif

        // Provide controller reference to KeyboardState for auto-insert
        keyboardState.controller = self
        keyboardState.openURL = { [weak self] url in
            self?.extensionContext?.open(url)
        }

        // Create input view with audio feedback support
        let kbInputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)

        // --- UIKit keyboard ---
        keyboardView.delegate = self
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        kbInputView.addSubview(keyboardView)

        // Set popupContainer so popups appear above the clipped keyboard area
        keyboardView.popupContainer = kbInputView

        // --- SwiftUI Toolbar ---
        let toolbarView = ToolbarView(
            hasFullAccess: hasFullAccess,
            dictationStatus: keyboardState.dictationStatus,
            onMicTap: { [weak self] in self?.keyboardState.startRecording() }
        )
        let toolbarHC = UIHostingController(rootView: AnyView(toolbarView))
        toolbarHC.view.backgroundColor = .clear
        toolbarHC.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(toolbarHC)
        kbInputView.addSubview(toolbarHC.view)
        toolbarHC.didMove(toParent: self)
        self.toolbarHosting = toolbarHC

        // --- Layout constraints ---
        let keyHeight = KeyboardColors.keyHeight
        let rows: CGFloat = 4
        let rowSpacing = KeyboardColors.rowSpacing
        let keyboardAreaHeight = (rows * keyHeight) + ((rows - 1) * rowSpacing) + 8 // +8 vertical padding
        let toolbarHeight: CGFloat = 48
        let bottomPadding: CGFloat = 8

        NSLayoutConstraint.activate([
            // Toolbar at top
            toolbarHC.view.topAnchor.constraint(equalTo: kbInputView.topAnchor),
            toolbarHC.view.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            toolbarHC.view.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
            toolbarHC.view.heightAnchor.constraint(equalToConstant: toolbarHeight),

            // Keyboard below toolbar
            keyboardView.topAnchor.constraint(equalTo: toolbarHC.view.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
            keyboardView.heightAnchor.constraint(equalToConstant: keyboardAreaHeight),
        ])

        // Height constraint
        let totalHeight = toolbarHeight + keyboardAreaHeight + bottomPadding
        let constraint = kbInputView.heightAnchor.constraint(equalToConstant: totalHeight)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        self.heightConstraint = constraint

        // Attempt to prevent popup clipping
        kbInputView.clipsToBounds = false

        self.inputView = kbInputView

        // Pre-allocate haptic generators
        HapticFeedback.warmUp()

        // Set initial autocapitalization
        checkAutocapitalize()

        // Observe dictation status changes to show/hide recording overlay
        observeDictationStatus()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        heightConstraint?.constant = computeKeyboardHeight()
        inputView?.setNeedsLayout()

        // Update toolbar with current state
        updateToolbar()
    }

    // MARK: - Height calculation

    private func computeKeyboardHeight() -> CGFloat {
        let rows: CGFloat = 4
        let keyHeight = KeyboardColors.keyHeight
        let rowSpacing = KeyboardColors.rowSpacing
        let verticalPadding: CGFloat = 8
        let toolbarHeight: CGFloat = 48
        let bottomPadding: CGFloat = 8
        return (rows * keyHeight) + ((rows - 1) * rowSpacing) + verticalPadding + toolbarHeight + bottomPadding
    }

    // MARK: - Text changes

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        checkAutocapitalize()
    }

    // MARK: - Dictation status observation

    private func observeDictationStatus() {
        keyboardState.$dictationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                self.updateToolbar()

                let isRecording = (status == .recording || status == .transcribing)

                if isRecording {
                    self.showRecordingOverlay()
                } else {
                    self.hideRecordingOverlay()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Toolbar updates

    /// Rebuild the toolbar SwiftUI view to reflect current state.
    /// WHY rebuild: ToolbarView takes dictationStatus as a value, not a binding.
    /// Since it's hosted via UIHostingController, we update the rootView.
    private func updateToolbar() {
        let toolbarView = ToolbarView(
            hasFullAccess: hasFullAccess,
            dictationStatus: keyboardState.dictationStatus,
            onMicTap: { [weak self] in self?.keyboardState.startRecording() }
        )
        toolbarHosting?.rootView = AnyView(toolbarView)
    }

    // MARK: - Recording overlay

    private func showRecordingOverlay() {
        guard recordingHosting == nil else { return }
        guard let kbInputView = inputView else { return }

        // Hide keyboard + toolbar
        keyboardView.isHidden = true
        toolbarHosting?.view.isHidden = true

        let state = keyboardState
        let overlayView = RecordingOverlayWrapper(state: state)
        let hosting = UIHostingController(rootView: AnyView(overlayView))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hosting)
        kbInputView.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: kbInputView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
        ])

        self.recordingHosting = hosting
    }

    private func hideRecordingOverlay() {
        guard recordingHosting != nil else { return }

        recordingHosting?.willMove(toParent: nil)
        recordingHosting?.view.removeFromSuperview()
        recordingHosting?.removeFromParent()
        recordingHosting = nil

        // Show keyboard + toolbar
        keyboardView.isHidden = false
        toolbarHosting?.view.isHidden = false
    }

    // MARK: - Emoji picker

    private func showEmojiPickerView() {
        guard emojiHosting == nil else { return }
        guard let kbInputView = inputView else { return }

        isEmojiMode = true

        // Hide keyboard + toolbar
        keyboardView.isHidden = true
        toolbarHosting?.view.isHidden = true

        let emojiView = EmojiPickerView(
            onEmojiInsert: { [weak self] emoji in
                self?.textDocumentProxy.insertText(emoji)
            },
            onDelete: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            onDismiss: { [weak self] in
                HapticFeedback.keyTapped()
                AudioServicesPlaySystemSound(KeySound.modifier)
                self?.hideEmojiPickerView()
            }
        )
        let hosting = UIHostingController(rootView: AnyView(emojiView))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hosting)
        kbInputView.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        // Emoji picker takes full height (toolbar + keyboard + bottom padding)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: kbInputView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
        ])

        self.emojiHosting = hosting
    }

    private func hideEmojiPickerView() {
        guard emojiHosting != nil else { return }

        emojiHosting?.willMove(toParent: nil)
        emojiHosting?.view.removeFromSuperview()
        emojiHosting?.removeFromParent()
        emojiHosting = nil

        isEmojiMode = false

        // Restore layer from before emoji
        if let previousLayer = keyboardView.previousLayer {
            keyboardView.currentLayer = previousLayer
            keyboardView.previousLayer = nil
        } else {
            keyboardView.currentLayer = .letters
        }

        // Show keyboard + toolbar
        keyboardView.isHidden = false
        toolbarHosting?.view.isHidden = false
    }
}

// MARK: - DictusKeyboardViewDelegate

extension KeyboardViewController: DictusKeyboardViewDelegate {

    func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func showEmojiPicker() {
        showEmojiPickerView()
    }

    func dismissEmojiPicker() {
        hideEmojiPickerView()
    }

    func checkAutocapitalize() {
        let proxy = textDocumentProxy

        if let autocapType = proxy.autocapitalizationType,
           autocapType == .none {
            return
        }

        let before = proxy.documentContextBeforeInput ?? ""

        let shouldCap: Bool
        if before.isEmpty {
            shouldCap = true
        } else if before.hasSuffix(". ") || before.hasSuffix("! ") || before.hasSuffix("? ") {
            shouldCap = true
        } else if before.hasSuffix("\n") {
            shouldCap = true
        } else {
            shouldCap = false
        }

        if shouldCap && keyboardView.shiftState == .off {
            keyboardView.shiftState = .shifted
        }
    }
}

// MARK: - RecordingOverlayWrapper

/// SwiftUI wrapper that observes KeyboardState for real-time recording overlay updates.
///
/// WHY a wrapper instead of passing values directly:
/// RecordingOverlay needs live waveform data and elapsed time from KeyboardState.
/// This wrapper uses @ObservedObject to get automatic SwiftUI updates when
/// KeyboardState publishes changes.
private struct RecordingOverlayWrapper: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        RecordingOverlay(
            waveformEnergy: state.waveformEnergy,
            elapsedSeconds: state.recordingElapsed,
            isTranscribing: state.dictationStatus == .transcribing,
            onCancel: { state.requestCancel() },
            onStop: { state.requestStop() }
        )
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted by KeyboardViewController when text changes externally (paste, cursor move).
    static let dictusTextDidChange = Notification.Name("dictusTextDidChange")
}
