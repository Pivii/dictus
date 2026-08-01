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

    /// The input traits of the text field this controller is editing.
    ///
    /// `kbAppear` is the surviving test of the #281 style-flip marker: both
    /// occurrences show the keyboard's `userInterfaceStyle` flipping to dark (2) on
    /// a device in light mode shortly before the teardown, which is what a text
    /// field requesting `UIKeyboardAppearance.dark` would produce. If `kbAppear`
    /// reads dark on the controller that flips, the flip is the input context; if
    /// it reads `.default` throughout, the flip comes from somewhere else.
    ///
    /// **Do not add `UITextDocumentProxy.documentIdentifier` here.** It is the
    /// obvious probe — per-document identity would say directly whether the two
    /// replacement controllers edit the same text field — and it crashed the
    /// extension on every launch (PR #282, first device build). `UIInputViewController.h`
    /// declares it `NSUUID *` with **no nullability annotation** and the header has
    /// no `NS_ASSUME_NONNULL_BEGIN`, so Swift imports it as a non-optional `UUID`
    /// while ObjC is free to return nil. It does return nil before the host input
    /// session is established, and the bridge traps. The compiler cannot help:
    /// optional chaining on it is a *compile error*, so there is no way to guard the
    /// read in Swift. Recovering this probe needs an ObjC shim re-declaring the
    /// property `nullable` behind a bridging header — a deliberate decision, not a
    /// drive-by addition.
    ///
    /// Every read below is verified to import as an Optional or a plain `Bool`, so
    /// none of them can trap on a nil host connection.
    ///
    /// Cost: reading the proxy is a synchronous round trip to the host app, so this
    /// is deliberately kept off `viewWillAppear` — the critical path of keyboard
    /// presentation, and a path whose timing #281 may be sensitive to.
    var inputContextProbeDetails: String {
        let appearance = textDocumentProxy.keyboardAppearance?.rawValue ?? -1
        return "fullAccess=\(hasFullAccess) kbAppear=\(appearance)"
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
