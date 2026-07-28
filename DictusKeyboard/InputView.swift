// DictusKeyboard/InputView.swift
import UIKit

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

    /// Convenience initializer using .keyboard input view style.
    convenience init() {
        self.init(frame: .zero, inputViewStyle: .keyboard)
    }

    /// Accept touches landing just BELOW this view so the key grid's downward tolerance
    /// can actually be reached (#138).
    ///
    /// WHY THIS VIEW TOO: hit testing is hierarchical. The key grid is pinned flush to this
    /// view's bottom edge, so a point below the grid is also below the input view. If the
    /// input view rejects it here, UIKit never descends into the grid and the grid's own
    /// `point(inside:with:)` override is never consulted. Both must agree on the same band.
    ///
    /// The band lies inside the area iOS reserves under the input view (home indicator), so
    /// it cannot capture touches meant for the host app. Nothing rendered changes: this
    /// widens acceptance only, never the frame.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if super.point(inside: point, with: event) {
            return true
        }
        let tolerance = KeyboardHitArea.bottomRowDownwardTolerance
        guard tolerance > 0 else { return false }
        return point.x >= bounds.minX
            && point.x < bounds.maxX
            && point.y >= bounds.maxY
            && point.y < bounds.maxY + tolerance
    }
}
