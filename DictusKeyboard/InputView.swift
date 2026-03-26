// DictusKeyboard/InputView.swift
import UIKit
import DictusCore

/// Custom UIInputView that enables the system keyboard click sound.
/// UIInputViewAudioFeedback protocol must be adopted by a UIView subclass,
/// not by a SwiftUI view. We set this as the inputView of
/// UIInputViewController to enable UIDevice.current.playInputClick().
///
/// UIInputView (not UIView) is required because UIInputViewController.inputView
/// is typed as UIInputView?. Using .keyboard style tells iOS this view behaves
/// like a keyboard, which is necessary for playInputClick() to work.
class KeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    /// Return true to enable keyboard click sounds via playInputClick().
    var enableInputClicksWhenVisible: Bool { true }

    /// Reference to the UIKit keyboard container for touch routing.
    /// Set by KeyboardViewController after creating the container.
    weak var keyboardContainer: KeyboardContainerView?

    /// Prioritize the UIKit keyboard container for touch routing.
    ///
    /// WHY this override:
    /// _UIHostingView.hitTest returns an internal SwiftUI view for ANY point
    /// within its bounds, even when the SwiftUI content has allowsHitTesting(false).
    /// Since the hosting view is in front of the UIKit container, touches never
    /// reach the container. By checking the container first at the kbInputView level,
    /// keyboard touches go directly to buttons. Non-keyboard touches (toolbar, emoji)
    /// fall through to the normal chain via super.hitTest → hosting view.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let container = keyboardContainer {
            let converted = convert(point, to: container)
            if container.bounds.contains(converted),
               let hit = container.hitTest(converted, with: event) {
                return hit
            }
            // TEMPORARY: debug dead zones — log when touch misses container
            if !container.bounds.contains(converted) {
                PersistentLog.log(.diagnosticProbe(
                    component: "InputView",
                    instanceID: "hitTest",
                    action: "missedContainer",
                    details: "point=(\(Int(point.x)),\(Int(point.y))) converted=(\(Int(converted.x)),\(Int(converted.y))) containerBounds=\(Int(container.bounds.width))x\(Int(container.bounds.height)) containerFrame=(\(Int(container.frame.origin.x)),\(Int(container.frame.origin.y)),\(Int(container.frame.width)),\(Int(container.frame.height))"
                ))
            }
        }
        return super.hitTest(point, with: event)
    }

    /// Convenience initializer using .keyboard input view style.
    convenience init() {
        self.init(frame: .zero, inputViewStyle: .keyboard)
    }
}
