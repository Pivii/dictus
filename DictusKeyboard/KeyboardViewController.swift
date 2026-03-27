// DictusKeyboard/KeyboardViewController.swift
import UIKit
import SwiftUI
import DictusCore

class KeyboardViewController: UIInputViewController {
    let controllerID = String(UUID().uuidString.prefix(8))

    private var hostingController: UIHostingController<KeyboardRootView>?

    /// The UIKit keyboard container, added directly to kbInputView (NOT via SwiftUI).
    /// Contains the visual key layout (UIStackViews, buttons with isUserInteractionEnabled=false).
    var keyboardContainer: KeyboardContainerView?

    /// Touch forwarding view added as topmost subview of kbInputView.
    /// Routes on-key touches to nearest button. Dead zones between keys remain
    /// a known iOS limitation (see .planning/debug/dead-zones-uikit-keyboard.md).
    var touchForwardingView: KeyboardTouchForwardingView?

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

        // ── UIKit keyboard container (added FIRST = behind SwiftUI) ──
        let container = KeyboardContainerView()
        container.touchState = touchState
        container.translatesAutoresizingMaskIntoConstraints = false
        kbInputView.addSubview(container)
        self.keyboardContainer = container

        // ── SwiftUI hosting view (added SECOND = in front) ──
        let rootView = KeyboardRootView(controller: self, controllerID: controllerID, touchState: touchState)
        let hosting = UIHostingController(rootView: rootView)
        PersistentLog.log(.diagnosticProbe(
            component: "KeyboardViewController",
            instanceID: controllerID,
            action: "hostingCreated",
            details: "hosting=\(ObjectIdentifier(hosting).debugDescription)"
        ))

        // Critical: retain the hosting controller or it gets deallocated
        self.hostingController = hosting

        addChild(hosting)
        // Add hosting view as subview of kbInputView — ON TOP of container
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

        // Constrain keyboard container to match the keyboard area (below toolbar, above bottom spacer).
        // The keyboard height must match KeyboardRootView's keyboardHeight for correct alignment.
        let kbHeight = CGFloat(4) * (KeyMetrics.keyHeight + KeyMetrics.rowSpacing)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor, constant: -8),
            container.heightAnchor.constraint(equalToConstant: kbHeight),
        ])

        // ── Touch forwarding view (topmost subview) ──
        // Routes on-key touches to nearest button via handleForwardedTouch* methods.
        // Dead zones between keys are a known iOS limitation — see debug docs.
        let fwd = KeyboardTouchForwardingView()
        fwd.translatesAutoresizingMaskIntoConstraints = false
        kbInputView.addSubview(fwd)
        NSLayoutConstraint.activate([
            fwd.leadingAnchor.constraint(equalTo: kbInputView.leadingAnchor),
            fwd.trailingAnchor.constraint(equalTo: kbInputView.trailingAnchor),
            fwd.bottomAnchor.constraint(equalTo: kbInputView.bottomAnchor, constant: -8),
            fwd.heightAnchor.constraint(equalToConstant: kbHeight),
        ])
        self.touchForwardingView = fwd
        container.forwardingView = fwd

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

