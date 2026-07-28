// DictusKeyboard/TouchHandling/KeyboardHitArea.swift
import CoreGraphics

/// Hit-area policy for the keyboard's key grid (issue #138).
///
/// PROBLEM: the key grid view is pinned flush to the bottom of the input view and its
/// collection view fills it exactly, so bottom-row cell frames end at that edge. A touch
/// landing below it fails UIKit's default `point(inside:with:)`, is never delivered to the
/// touch handler, and resolves to no key at all — the existing point-clamping helper cannot
/// compensate because it only runs on touches the view already accepted. Apple's system
/// keyboard keeps responding lower than ours does, so users with Apple muscle memory tap a
/// spot Dictus silently ignores. The spacebar is where it hurts most: the dropped space
/// concatenates words.
///
/// FIX: extend only WHERE TOUCHES ARE ACCEPTED, never the geometry. Adding real height is
/// the trap — cell height is `bounds.height / rowCount`, so extra height divides across all
/// four rows and makes every key taller. That regression was already shipped and reverted
/// (#117), which is why the keyboard's `bottomPadding` constant sits at `0` today.
enum KeyboardHitArea {
    /// Downward hit tolerance, in points, below the bottom edge of the key grid.
    /// Touches landing in this band are accepted and resolve to the bottom-row key
    /// directly above them.
    ///
    /// ⚠️ PROVISIONAL VALUE — NOT MEASURED ON DEVICE.
    /// It was chosen from constraints, not from a comparison against Apple's keyboard:
    /// - it must stay below the home-indicator inset iOS reserves under the input view
    ///   (~34pt portrait, ~21pt landscape) so the band can never reach the host app;
    /// - each bottom-row cell already carries `Theme.keyVerticalMargin` (5.5pt portrait,
    ///   3.5pt landscape) of hit area under the visible key glyph, so this adds to that
    ///   rather than replacing it;
    /// - it stays well under half a cell height, so a tap intended for the home-indicator
    ///   swipe area is not systematically captured by the keyboard.
    ///
    /// TUNING: this is the single knob. Change this number and nothing else. Measure first
    /// with the `bottomRowHitArea` / `bottomRowBelowBoundsTouch` probes emitted by
    /// `GiellaKeyboardView` (see Settings → Logs), then compare against where Apple's system
    /// keyboard stops responding on the same device. Setting it to `0` restores the exact
    /// pre-fix behaviour.
    static let bottomRowDownwardTolerance: CGFloat = 12.0
}
