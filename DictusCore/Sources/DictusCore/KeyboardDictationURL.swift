// DictusCore/Sources/DictusCore/KeyboardDictationURL.swift
// The single rule that recognises the dictation URLs the keyboard sends to the app.
import Foundation

/// What the keyboard is asking the app to do with a `dictus://dictate` URL.
public enum KeyboardDictationIntent: String, Sendable, Equatable, CaseIterable {
    /// Start a dictation now (`dictus://dictate?source=keyboard`).
    case record
    /// Only load the active model, without recording (`&intent=prepare`, issue #262).
    case prepare
}

/// Recognises the dictation URLs sent by the keyboard extension.
///
/// WHY a shared parser instead of inline query lookups:
/// The same URL is inspected in three places — at scene connection (to decide the very
/// first frame, issue #264), in `MainTabView.onOpenURL`, and in `DictusApp.handleIncomingURL`.
/// Three copies of "host is dictate, source is keyboard, intent may be prepare" drift the
/// moment one of them gains a parameter, and a drifting copy shows the wrong overlay.
///
/// WHY in DictusCore:
/// The rule is pure `Foundation` and testable off-device, and the keyboard side may later
/// build its URLs from the same vocabulary.
public enum KeyboardDictationURL {
    /// The scheme registered by DictusApp in `CFBundleURLTypes`.
    private static let scheme = "dictus"
    /// The only host that carries a dictation request.
    private static let host = "dictate"

    /// Returns the intent carried by `url`, or `nil` when the URL is not a keyboard
    /// dictation request.
    ///
    /// Returning `nil` covers everything the caller must not treat as a keyboard
    /// dictation: another scheme, `dictus://stop`, and the widget's `dictus://dictate`
    /// deep link, which has no `source=keyboard` query item.
    public static func intent(from url: URL) -> KeyboardDictationIntent? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              queryItems.contains(where: { $0.name == "source" && $0.value == "keyboard" })
        else {
            return nil
        }

        let isPrepareOnly = queryItems.contains { $0.name == "intent" && $0.value == "prepare" }
        return isPrepareOnly ? .prepare : .record
    }
}
