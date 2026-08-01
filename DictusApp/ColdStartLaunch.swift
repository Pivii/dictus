// DictusApp/ColdStartLaunch.swift
// Captures the dictation URL that launched the process, before SwiftUI draws anything.
import UIKit
import DictusCore

/// The keyboard dictation intent this process was *launched with*, if any.
///
/// WHY this exists (issue #264):
/// `MainTabView` decided cold start inside `.onOpenURL`, and SwiftUI evaluates `body` at
/// least once before any URL handler runs. On a keyboard-launched cold start the home
/// screen was therefore always drawn for a frame before the swipe-back overlay replaced
/// it. Reading `SharedKeys.coldStartActive` does not help: that flag is written by
/// DictusApp's own `.onOpenURL`, which fires even later, so at first render it still holds
/// the previous session's value.
///
/// The launch URL is the only source of truth that exists early enough. iOS hands it to
/// the scene in `scene(_:willConnectTo:options:)`, before SwiftUI builds any view, so
/// `MainTabView` can seed its state from it in `init`.
///
/// WHY this does NOT consume the URL:
/// `.onOpenURL` still fires for the same launch URL and remains the only place that starts
/// the dictation, writes the App Group flag and flips the "has handled a URL in this
/// process" flags. Marking the URL handled here would flip those flags early and make a
/// later engine-dead restart look like a warm start.
enum ColdStartLaunch {
    /// The intent carried by the launch URL. `nil` for every other launch path
    /// (Home screen, notification, widget), which is what keeps the normal launch
    /// rendering its tab navigation immediately.
    private(set) static var intent: KeyboardDictationIntent?

    /// Records the launch URL handed to the scene at connection time.
    ///
    /// WHY only the first match: a scene connects with a set of URL contexts, and the
    /// dictation URL is the only one we care about. Anything else leaves `intent` nil.
    static func capture(_ urlContexts: Set<UIOpenURLContext>) {
        guard let launchIntent = urlContexts.lazy
            .compactMap({ KeyboardDictationURL.intent(from: $0.url) })
            .first
        else {
            return
        }

        intent = launchIntent
        PersistentLog.log(.diagnosticProbe(
            component: "coldStart", instanceID: "0",
            action: "launchURLCaptured",
            details: "intent=\(launchIntent.rawValue)"
        ))
    }

    /// Forgets the launch URL.
    ///
    /// WHY: the intent describes the frame this process launched into, not a lasting mode.
    /// It is cleared with the rest of the cold-start state when the scene goes to the
    /// background, so a view rebuilt later in the same process never replays a cold start.
    static func clear() {
        intent = nil
    }
}

/// Scene delegate installed for the sole purpose of seeing the launch URL.
///
/// WHY a scene delegate in a SwiftUI-lifecycle app:
/// `UIScene.ConnectionOptions` is the only place the launch URL is exposed, and it is
/// only passed to `scene(_:willConnectTo:options:)`. SwiftUI keeps owning the window and
/// the view hierarchy — this delegate creates nothing and, by not implementing
/// `scene(_:openURLContexts:)`, leaves URL delivery to SwiftUI's `.onOpenURL` untouched.
final class DictusSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        ColdStartLaunch.capture(connectionOptions.urlContexts)
    }
}
