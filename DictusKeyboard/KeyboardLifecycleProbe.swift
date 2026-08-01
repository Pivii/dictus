// DictusKeyboard/KeyboardLifecycleProbe.swift
import UIKit
import os

/// Observation-only helpers for the #281 investigation.
///
/// #281: iOS sends `viewDidDisappear` to every live `KeyboardViewController` and
/// deallocates them all roughly one second after one of them appeared, settled and
/// rendered the recording overlay correctly — then builds no replacement for ~10 s
/// while the host app is in the foreground and the app keeps recording.
///
/// The mechanism is unknown and no hypothesis has been tested, so nothing in this
/// file changes behaviour. Every symbol here is read by `PersistentLog` call sites
/// and by nothing else: no control flow, no lifecycle, no layout depends on it.
enum KeyboardLifecycleProbe {

    /// Number of `KeyboardViewController` instances alive in this process.
    ///
    /// WHY this is the headline probe. Across the six device logs available for
    /// build 1.8.0 (24), the peak number of controllers alive at once separates
    /// every capture showing #281 from every capture that does not:
    ///
    /// - healthy captures (15 clean cold starts in `dictus-logs 39`, plus 35/36)
    ///   peak at **2** — the outgoing controller plus its single replacement;
    /// - both #281 occurrences (`38-bug281` 09:48, `34` 11:30) peak at **3**,
    ///   because iOS built a *second* replacement while the first was already
    ///   on screen and settled, then tore both down together.
    ///
    /// Reading that off a log currently takes a script that pairs every
    /// `viewDidLoad` with its `deinit`. `live=` puts it on the line, so the next
    /// capture is diagnostic on its own.
    private static let liveControllers = OSAllocatedUnfairLock(initialState: 0)

    /// Records a controller entering the process. Returns the new live count,
    /// including the caller.
    static func controllerDidLoad() -> Int {
        liveControllers.withLock { count in
            count += 1
            return count
        }
    }

    /// Records a controller leaving the process. Returns the live count *after*
    /// the caller is gone, so `live=0` on a `deinit` line marks the exact moment
    /// the extension has no controller left — the start of the #281 window.
    static func controllerDidDeinit() -> Int {
        liveControllers.withLock { count in
            count -= 1
            return count
        }
    }

    /// Live count without mutating it, for probes that only observe.
    static var liveCount: Int {
        liveControllers.withLock { $0 }
    }
}

extension UIInputViewController {

    /// Identity of the text field this controller is editing, plus the traits that
    /// would change if iOS re-parented it into a different one.
    ///
    /// `UITextDocumentProxy.documentIdentifier` is per-document: it holds steady
    /// while the user keeps editing one field and changes when the first responder
    /// changes. That is precisely the observation the current log cannot make, and
    /// it separates the two readings of the #281 teardown:
    ///
    /// - **same `docID` across both replacement controllers** → iOS rebuilt the
    ///   input view for the *same* text field, so the teardown is a transition
    ///   artefact and the host app's first responder never moved;
    /// - **different `docID`** → the host app moved first responder mid-transition,
    ///   which would make the teardown legitimate and the missing rebuild the bug.
    ///
    /// `kbAppear` is logged with it because the two #281 captures both show the
    /// keyboard's `userInterfaceStyle` flipping to dark (2) on a device in light
    /// mode, which is what a text field requesting `UIKeyboardAppearance.dark`
    /// would produce. If `kbAppear` changes in step with `docID`, the flip and the
    /// context switch are one event; if `kbAppear` changes while `docID` holds,
    /// they are not.
    ///
    /// Cost: reading the proxy is a synchronous round trip to the host app, so this
    /// is deliberately kept off `viewWillAppear` — the critical path of keyboard
    /// presentation, and a path whose timing #281 may be sensitive to.
    var inputContextProbeDetails: String {
        let docID = textDocumentProxy.documentIdentifier.uuidString.prefix(8)
        let appearance = textDocumentProxy.keyboardAppearance?.rawValue ?? -1
        return "docID=\(docID) fullAccess=\(hasFullAccess) kbAppear=\(appearance)"
    }

    /// Why UIKit is taking this controller off screen.
    ///
    /// The #281 log shows `viewDidDisappear` reaching every live controller at once
    /// and cannot say whether iOS is dismissing the keyboard or rotating instances
    /// underneath it. These are the flags that distinguish them:
    ///
    /// - `beingDismissed=true` / `movingFromParent=true` → UIKit is dismissing this
    ///   controller, i.e. the keyboard is genuinely going away;
    /// - both false with the window already gone → the view was detached from the
    ///   hierarchy without a dismissal, which is what an input-view hierarchy being
    ///   discarded wholesale looks like.
    ///
    /// No IPC: every read is local UIKit state.
    var dismissalProbeDetails: String {
        let hasWindow = viewIfLoaded?.window != nil
        let hasInputWindow = inputView?.window != nil
        return "beingDismissed=\(isBeingDismissed) movingFromParent=\(isMovingFromParent)"
            + " hasParent=\(parent != nil) hasWindow=\(hasWindow) hasInputWindow=\(hasInputWindow)"
    }
}
