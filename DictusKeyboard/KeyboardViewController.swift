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

        // Assign as the controller's inputView — this activates audio feedback
        self.inputView = kbInputView
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Force height recalculation when keyboard reappears (e.g., after app switch).
        // Without this, the inputView may retain a stale height from before the switch.
        heightConstraint?.constant = computeKeyboardHeight()
        inputView?.setNeedsLayout()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Darwin observers cleaned up by KeyboardState deinit
    }

    /// Calculate the total keyboard height including toolbar.
    /// Must match the height computed in KeyboardRootView/KeyboardView.
    private func computeKeyboardHeight() -> CGFloat {
        let rows: CGFloat = 4
        let keyHeight: CGFloat = KeyMetrics.keyHeight  // 46pt, matches native iOS keyboard
        let rowSpacing: CGFloat = KeyMetrics.rowSpacing  // 6pt
        let verticalPadding: CGFloat = 8
        let toolbarHeight: CGFloat = 44 // ToolbarView approximate height
        return (rows * keyHeight) + ((rows - 1) * rowSpacing) + verticalPadding + toolbarHeight
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Future: react to cursor position changes, return key type, etc.
    }
}
