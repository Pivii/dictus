// DictusKeyboard/Views/UIKit/KeyboardTouchGestureRecognizer.swift
// Custom gesture recognizer that bypasses iOS keyboard hitTest chain for zero dead zones.
import UIKit
import UIKit.UIGestureRecognizerSubclass
import DictusCore

/// Custom UIGestureRecognizer that intercepts ALL touches in the keyboard area.
///
/// WHY a gesture recognizer instead of a UIView overlay:
/// iOS's keyboard extension infrastructure intercepts the hitTest chain — touches
/// between keys (dead zones) never reach any of our UIView subclasses. Three approaches
/// were tried and failed (expanded touchInsets, forwarding view inside container,
/// forwarding view on top of hosting view). Logs proved dead zone touches produce
/// zero entries in any of our views.
///
/// UIGestureRecognizer operates on a fundamentally different path: "A window delivers
/// touch events to a gesture recognizer BEFORE it delivers them to the hit-test view"
/// (Apple documentation). This bypasses the entire hitTest chain that iOS controls.
///
/// Attached to kbInputView, this recognizer receives every touch in the keyboard area,
/// finds the nearest button by Euclidean distance, and calls the existing
/// `handleForwardedTouchDown/Moved/Up/Cancelled` methods on the button.
class KeyboardTouchGestureRecognizer: UIGestureRecognizer {

    // MARK: - Properties

    /// Flat array of all touchable buttons, populated by KeyboardContainerView.buildKeys().
    var allButtons: [UIView] = []

    /// The keyboard area rect in kbInputView coordinates.
    /// Updated by KeyboardContainerView.layoutSubviews().
    /// Touches outside this rect are ignored (passed through to toolbar/SwiftUI).
    var keyboardRect: CGRect = .zero

    /// Whether the keyboard is active (false during recording overlay).
    var isKeyboardActive: Bool = true

    /// Tracks which button each active touch is targeting.
    /// Once a touch begins on a button, ALL subsequent move/end/cancel go to the
    /// SAME button. This preserves accent drag, space trackpad, delete repeat.
    private var touchToButton: [UITouch: UIView] = [:]

    // MARK: - Gesture recognizer overrides

    /// Cannot be prevented by other recognizers (system or otherwise).
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    /// Can prevent other recognizers from firing for keyboard touches.
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    /// Reset state between gesture sequences.
    override func reset() {
        super.reset()
        touchToButton.removeAll()
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view = self.view else { return }

        for touch in touches {
            let point = touch.location(in: view)

            // TEMPORARY: log every touch to diagnose if recognizer fires at all
            PersistentLog.log(.diagnosticProbe(
                component: "TouchRecognizer",
                instanceID: "touch",
                action: "rawTouch",
                details: "point=(\(Int(point.x)),\(Int(point.y))) kbRect=(\(Int(keyboardRect.origin.x)),\(Int(keyboardRect.origin.y)),\(Int(keyboardRect.width)),\(Int(keyboardRect.height))) active=\(isKeyboardActive) buttons=\(allButtons.count)"
            ))

            // Non-keyboard touches: ignore → pass through to toolbar, SwiftUI, system bar
            guard keyboardRect.contains(point), isKeyboardActive else {
                ignore(touch, for: event)
                continue
            }

            // Find nearest button by distance
            guard let button = findNearestButton(to: point, in: view) else {
                ignore(touch, for: event)
                continue
            }

            // Store and forward
            touchToButton[touch] = button

            // TEMPORARY: debug dead zones — log every touch routing
            let buttonLabel: String
            if let letter = button as? LetterKeyButton {
                buttonLabel = letter.keyLabel
            } else {
                buttonLabel = String(describing: type(of: button)).replacingOccurrences(of: "KeyButton", with: "")
            }
            PersistentLog.log(.diagnosticProbe(
                component: "TouchRecognizer",
                instanceID: "touch",
                action: "routed",
                details: "point=(\(Int(point.x)),\(Int(point.y))) -> \(buttonLabel)"
            ))

            if let letter = button as? LetterKeyButton {
                letter.handleForwardedTouchDown(touch: touch, in: view)
            } else if let special = button as? BaseSpecialKeyButton {
                special.handleForwardedTouchDown(touch: touch, in: view)
            }
        }

        // Transition state
        if !touchToButton.isEmpty {
            if state == .possible {
                state = .began
            } else {
                state = .changed
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view = self.view else { return }

        for touch in touches {
            guard let button = touchToButton[touch] else { continue }
            // Always forward to SAME button — preserves gesture state
            if let letter = button as? LetterKeyButton {
                letter.handleForwardedTouchMoved(touch: touch, in: view)
            } else if let special = button as? BaseSpecialKeyButton {
                special.handleForwardedTouchMoved(touch: touch, in: view)
            }
        }

        if state == .began || state == .changed {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            guard let button = touchToButton[touch] else { continue }
            if let letter = button as? LetterKeyButton {
                letter.handleForwardedTouchUp()
            } else if let special = button as? BaseSpecialKeyButton {
                special.handleForwardedTouchUp()
            }
            touchToButton[touch] = nil
        }

        if touchToButton.isEmpty {
            state = .ended
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            guard let button = touchToButton[touch] else { continue }
            if let letter = button as? LetterKeyButton {
                letter.handleForwardedTouchCancelled()
            } else if let special = button as? BaseSpecialKeyButton {
                special.handleForwardedTouchCancelled()
            }
            touchToButton[touch] = nil
        }

        if touchToButton.isEmpty {
            state = .cancelled
        }
    }

    // MARK: - Nearest button lookup

    /// Find the nearest button to a point by squared Euclidean distance to button center.
    /// Point is in kbInputView coordinates (the gesture recognizer's view).
    private func findNearestButton(to point: CGPoint, in coordinateView: UIView) -> UIView? {
        var best: UIView?
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for button in allButtons {
            guard let parent = button.superview else { continue }
            let center = parent.convert(button.center, to: coordinateView)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let dist = dx * dx + dy * dy  // squared distance, skip sqrt
            if dist < bestDist {
                bestDist = dist
                best = button
            }
        }
        return best
    }
}
