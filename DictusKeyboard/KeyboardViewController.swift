// DictusKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI
import DictusCore

class KeyboardViewController: UIInputViewController {
    let controllerID = String(UUID().uuidString.prefix(8))

    private var hostingController: UIHostingController<KeyboardRootView>?

    /// The UIKit keyboard container. Added ON TOP of the SwiftUI hosting view so it
    /// receives touches directly without any hitTest workaround.
    var keyboardContainer: KeyboardCollectionView?

    /// UIKit popup layer for key preview and accent strip. Sits above the collection view.
    var popupLayer: KeyPopupLayer?

    /// Shared touch state bridge between UIKit buttons and SwiftUI popup overlays.
    /// Created here (not in SwiftUI) because the UIKit container needs it at init time.
    let touchState = KeyboardTouchState()

    /// Explicit height constraint on inputView to prevent layout issues after app switch.
    /// WHY: Without this, iOS may not recalculate the keyboard height correctly when the
    /// extension is brought back to foreground after a URL scheme app switch. The system
    /// keyboard row (globe, mic) bleeds through and the recording overlay gets compressed.
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        PersistentLog.source = "KBD"
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidLoad",
            details: "version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") controllerClass=\(String(describing: type(of: self)))"
        ))

        #if DEBUG
        let result = AppGroupDiagnostic.run()
        if #available(iOS 14.0, *) {
            DictusLogger.keyboard.debug(
                "Diagnostic: canWrite=\(result.canWrite, privacy: .public) canRead=\(result.canRead, privacy: .public)"
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

        // ── 1. SwiftUI hosting view (added FIRST = BEHIND) ──
        // Contains toolbar, recording overlay, emoji picker.
        // The keyboard area in SwiftUI is a transparent spacer.
        // Dead zones are NOT caused by the hosting view — they were caused by
        // floating-point rounding in cell sizing (fixed with - 1 correction).
        let rootView = KeyboardRootView(controller: self, controllerID: controllerID, touchState: touchState)
        let hosting = UIHostingController(rootView: rootView)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "hostingCreated",
            details: "hosting=\(ObjectIdentifier(hosting).debugDescription)"
        ))

        self.hostingController = hosting
        addChild(hosting)
        kbInputView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        hosting.view.backgroundColor = .clear

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: kbInputView.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor)
        ])

        // ── 2. UIKit keyboard container — the ONLY visible keyboard content ──
        // 100% UIKit, same architecture as giellakbd-ios: UICollectionView with
        // zero-gap cells, touch handling on the parent view, no SwiftUI in the way.
        let kbHeight = CGFloat(4) * (KeyMetrics.keyHeight + KeyMetrics.rowSpacing)
        let container = KeyboardCollectionView()
        container.touchState = touchState
        container.translatesAutoresizingMaskIntoConstraints = false
        kbInputView.addSubview(container)
        self.keyboardContainer = container

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor, constant: -8),
            container.heightAnchor.constraint(equalToConstant: kbHeight),
        ])

        // ── 3. UIKit popup layer — above the collection view ──
        // Renders key preview and accent strip. isUserInteractionEnabled = false
        // so touches pass through to keys below.
        let popup = KeyPopupLayer()
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.isUserInteractionEnabled = false
        kbInputView.addSubview(popup)
        popup.configure(touchState: touchState)
        self.popupLayer = popup

        NSLayoutConstraint.activate([
            popup.topAnchor.constraint(equalTo: kbInputView.topAnchor),
            popup.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor),
            popup.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
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
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewWillAppear",
            details: "animated=\(animated)"
        ))
        PersistentLog.log(.keyboardDidAppear)
        KeyboardState.shared.registerControllerAppearance(controllerID: controllerID)

        // Force height recalculation when keyboard reappears (e.g., after app switch).
        // Without this, the inputView may retain a stale height from before the switch.
        heightConstraint?.constant = computeKeyboardHeight()
        inputView?.setNeedsLayout()

        // Disable gesture recognizer delays for instant key response.
        // WHY: iOS adds ~100-150ms delay to touches to check for system gestures (swipe from edges).
        // Pattern from giellakbd-ios: disabling delaysTouchesBegan makes keyboard response feel native.
        view.window?.gestureRecognizers?.forEach { $0.delaysTouchesBegan = false }

        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "registeredAppearance",
            details: ""
        ))

        // Cold start return detection: log for diagnostics.
        // DON'T clear coldStartActive here — KeyboardState.refreshFromDefaults() reads it
        // to activate the watchdog grace period (15s instead of 5s). The app's .background
        // handler clears it when the transition is complete.
        if AppGroup.defaults.bool(forKey: SharedKeys.coldStartActive) {
            DictusLogger.keyboard.info("Keyboard returned from cold start, recording should be active")
        }

        #if DEBUG
        if #available(iOS 14.0, *) {
            DictusLogger.keyboard.debug("viewWillAppear — refreshing mode")
        }
        #endif
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "viewDidDisappear",
            details: "animated=\(animated)"
        ))
        PersistentLog.log(.keyboardDidDisappear)
        KeyboardState.shared.registerControllerDisappearance(controllerID: controllerID)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "registeredDisappearance",
            details: ""
        ))
        // Darwin observers cleaned up by KeyboardState deinit
    }

    deinit {
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "deinit",
            details: ""
        ))
    }

    /// Calculate the total keyboard height including toolbar and banner.
    /// Must match the height computed in KeyboardRootView/KeyboardView.
    private func computeKeyboardHeight() -> CGFloat {
        let rows: CGFloat = 4
        let keyHeight: CGFloat = KeyMetrics.keyHeight  // Dynamic: 42pt SE, 46pt standard, 50pt Plus/Max
        let rowSpacing: CGFloat = KeyMetrics.rowSpacing  // 6pt
        let verticalPadding: CGFloat = 8
        let toolbarHeight: CGFloat = 52 // ToolbarView height (52pt: 48pt + 4pt top padding for mic ring)
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
}

