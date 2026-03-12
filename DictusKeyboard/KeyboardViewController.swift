// DictusKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI
import DictusCore

class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardRootView>?

    /// Explicit height constraint on inputView to prevent layout issues after app switch.
    /// WHY: Without this, iOS may not recalculate the keyboard height correctly when the
    /// extension is brought back to foreground after a URL scheme app switch. The system
    /// keyboard row (globe, mic) bleeds through and the recording overlay gets compressed.
    private var heightConstraint: NSLayoutConstraint?

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

        // Create a KeyboardInputView (UIInputView + UIInputViewAudioFeedback)
        // and assign it as the controller's inputView. This is the critical step
        // that makes playInputClick() work: iOS checks that the UIInputViewController's
        // inputView conforms to UIInputViewAudioFeedback and returns true from
        // enableInputClicksWhenVisible. Without this assignment, click sounds are silent.
        let kbInputView = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        // Do NOT set translatesAutoresizingMaskIntoConstraints = false on the inputView.
        // iOS manages the inputView's frame via autoresizing masks — disabling them
        // causes the view to collapse to zero width.

        let rootView = KeyboardRootView(controller: self)
        let hosting = UIHostingController(rootView: rootView)

        // Critical: retain the hosting controller or it gets deallocated
        self.hostingController = hosting

        addChild(hosting)
        // Add hosting view as subview of kbInputView (NOT self.view)
        kbInputView.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        // Remove default background so the keyboard blends with host app
        hosting.view.backgroundColor = .clear

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: kbInputView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor)
        ])

        // Set explicit height constraint on inputView.
        // This tells iOS exactly how tall our keyboard should be, preventing
        // the system from guessing wrong after app transitions.
        let height = self.computeKeyboardHeight()
        let constraint = kbInputView.heightAnchor.constraint(equalToConstant: height)
        constraint.priority = .defaultHigh  // don't fight iOS if it needs to adjust
        constraint.isActive = true
        self.heightConstraint = constraint

        // Attempt to prevent top-row key popup clipping. iOS may re-enforce
        // clipsToBounds — if so, this is a known limitation of third-party keyboard extensions.
        kbInputView.clipsToBounds = false
        hosting.view.clipsToBounds = false

        // Assign as the controller's inputView — this activates audio feedback
        self.inputView = kbInputView
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PersistentLog.log(.keyboardDidAppear)

        // Force height recalculation when keyboard reappears (e.g., after app switch).
        // Without this, the inputView may retain a stale height from before the switch.
        heightConstraint?.constant = computeKeyboardHeight()
        inputView?.setNeedsLayout()

        // Notify SwiftUI views that the keyboard is (re)appearing so they can
        // refresh state that may have changed while the extension was suspended
        // (e.g., keyboard mode changed in Settings).
        NotificationCenter.default.post(name: .dictusKeyboardWillAppear, object: nil)

        // Cold start return detection: if the app set coldStartActive=true during
        // URL scheme handling, the keyboard is now returning after a cold start launch.
        // Clear the flag so subsequent keyboard appearances don't re-trigger.
        // The recording overlay appears naturally via the existing dictationStatus flow
        // (app sets status to .recording, keyboard picks it up via refreshFromDefaults).
        if AppGroup.defaults.bool(forKey: SharedKeys.coldStartActive) {
            DictusLogger.keyboard.info("Keyboard returned from cold start, recording should be active")
            AppGroup.defaults.set(false, forKey: SharedKeys.coldStartActive)
            AppGroup.defaults.synchronize()
        }

        #if DEBUG
        if #available(iOS 14.0, *) {
            DictusLogger.keyboard.debug("viewWillAppear — refreshing mode")
        }
        #endif
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        PersistentLog.log(.keyboardDidDisappear)
        // Darwin observers cleaned up by KeyboardState deinit
    }

    /// Calculate the total keyboard height including toolbar and banner.
    /// Must match the height computed in KeyboardRootView/KeyboardView.
    private func computeKeyboardHeight() -> CGFloat {
        let rows: CGFloat = 4
        let keyHeight: CGFloat = KeyMetrics.keyHeight  // Dynamic: 42pt SE, 46pt standard, 50pt Plus/Max
        let rowSpacing: CGFloat = KeyMetrics.rowSpacing  // 6pt
        let verticalPadding: CGFloat = 8
        let toolbarHeight: CGFloat = 48 // ToolbarView height (48pt for mic pill glow room)
        let bottomPadding: CGFloat = 8 // Experimental: push system dictation mic area down
        return (rows * keyHeight) + ((rows - 1) * rowSpacing) + verticalPadding + toolbarHeight + bottomPadding
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Notify KeyboardView that text changed externally (paste, cursor move, etc.)
        // so it can recheck autocapitalisation state.
        NotificationCenter.default.post(name: .dictusTextDidChange, object: nil)
    }
}

// MARK: - Notification names for keyboard internal communication

extension Notification.Name {
    /// Posted by KeyboardViewController when text changes externally (paste, cursor move).
    /// KeyboardView listens for this to recheck autocapitalisation.
    static let dictusTextDidChange = Notification.Name("dictusTextDidChange")

    /// Posted by KeyboardViewController in viewWillAppear (every keyboard show).
    /// KeyboardRootView listens for this to re-read KeyboardMode from App Group,
    /// so mode changes made in Settings take effect without a rebuild.
    static let dictusKeyboardWillAppear = Notification.Name("dictusKeyboardWillAppear")
}
