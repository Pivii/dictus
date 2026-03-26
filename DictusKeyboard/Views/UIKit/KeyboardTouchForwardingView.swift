// DictusKeyboard/Views/UIKit/KeyboardTouchForwardingView.swift
// Transparent overlay that intercepts ALL keyboard touches and routes to nearest button.
import UIKit

/// A transparent UIView that intercepts all touches on the keyboard surface and forwards
/// them to the nearest button by Euclidean distance.
///
/// WHY this pattern (ForwardingView / single touch surface):
/// UIStackView's internal hitTest uses `subview.frame.contains(point)` -- it NEVER calls
/// `point(inside:with:)` on subviews. This means negative touchInsets expansions on buttons
/// are ignored by UIStackView, creating dead zones between keys. Rather than fight UIKit's
/// hit-test chain, we bypass it entirely: this view sits on top of all stacks, claims every
/// touch, and routes to the nearest button via custom `handleForwardedTouch*` methods.
///
/// WHY custom methods instead of forwarding `touchesBegan` directly:
/// UIKit internally tracks which view "owns" each UITouch. If the forwarding view is the
/// hit-test winner but we call `button.touchesBegan(touches, with:)`, UIKit may send
/// spurious `touchesCancelled` to the button because the touch's `view` property points
/// to the forwarding view, not the button. Custom methods bypass this ownership tracking.
///
/// Proven pattern from `tasty-imitation-keyboard` (1400+ stars, most-forked open-source
/// iOS keyboard on GitHub).
class KeyboardTouchForwardingView: UIView {

    // MARK: - Properties

    /// Flat array of all touchable buttons, populated by KeyboardContainerView after buildKeys().
    var allButtons: [UIView] = []

    /// Tracks which button each active touch is targeting.
    /// CRITICAL: Once a touch begins on a button, ALL subsequent move/end/cancel for
    /// that UITouch go to the SAME button. This preserves accent drag, space trackpad,
    /// delete repeat, and shift double-tap.
    private var touchToButton: [UITouch: UIView] = [:]

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    // MARK: - Hit testing

    /// Always return self if the point is inside bounds -- claim all touches.
    /// This prevents UIStackView from ever participating in touch routing.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return nil }
        guard self.point(inside: point, with: event) else { return nil }
        return self
    }

    // MARK: - Touch forwarding

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let button = findNearestButton(to: point) else { continue }
            touchToButton[touch] = button

            if let letter = button as? LetterKeyButton {
                letter.handleForwardedTouchDown(touch: touch, in: self)
            } else if let special = button as? BaseSpecialKeyButton {
                special.handleForwardedTouchDown(touch: touch, in: self)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let button = touchToButton[touch] else { continue }
            // Always forward to SAME button -- preserves gesture state
            if let letter = button as? LetterKeyButton {
                letter.handleForwardedTouchMoved(touch: touch, in: self)
            } else if let special = button as? BaseSpecialKeyButton {
                special.handleForwardedTouchMoved(touch: touch, in: self)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let button = touchToButton[touch] else { continue }
            if let letter = button as? LetterKeyButton {
                letter.handleForwardedTouchUp()
            } else if let special = button as? BaseSpecialKeyButton {
                special.handleForwardedTouchUp()
            }
            touchToButton[touch] = nil
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let button = touchToButton[touch] else { continue }
            if let letter = button as? LetterKeyButton {
                letter.handleForwardedTouchCancelled()
            } else if let special = button as? BaseSpecialKeyButton {
                special.handleForwardedTouchCancelled()
            }
            touchToButton[touch] = nil
        }
    }

    // MARK: - Nearest button lookup

    /// Find the nearest button to a point by squared Euclidean distance to button center.
    ///
    /// WHY linear scan instead of spatial grid:
    /// A keyboard has ~30-40 buttons. Linear scan with squared distance (no sqrt) takes
    /// < 0.1ms -- well under the touch latency budget. A spatial grid (ProximityGrid) would
    /// add complexity for zero measurable benefit at this scale.
    private func findNearestButton(to point: CGPoint) -> UIView? {
        var best: UIView?
        var bestDist: CGFloat = .greatestFiniteMagnitude
        for button in allButtons {
            guard let parent = button.superview else { continue }
            let center = parent.convert(button.center, to: self)
            let dx = point.x - center.x
            let dy = point.y - center.y
            let dist = dx * dx + dy * dy  // squared distance, skip sqrt for perf
            if dist < bestDist {
                bestDist = dist
                best = button
            }
        }
        return best
    }
}
