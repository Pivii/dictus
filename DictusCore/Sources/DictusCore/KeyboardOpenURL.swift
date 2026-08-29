// DictusCore/Sources/DictusCore/KeyboardOpenURL.swift
// The URLs the keyboard sends to bring the app to a particular screen (issues #241, #404).
import Foundation

/// Where the keyboard is asking the app to land.
///
/// Distinct from `KeyboardDictationIntent`, which answers a different question on a
/// different host: that one says *what to do with a dictation*, this one says *which
/// screen to show*. Keeping them apart is what stops a paywall request from reaching
/// `ColdStartLaunch`, whose whole job is deciding the first frame of a dictation.
public enum KeyboardOpenIntent: String, Sendable, Equatable, CaseIterable {

    /// The paywall. Sent by the hamburger panel's Dictus Pro pill (#241) and by the
    /// long-press fan's Dictus Pro row (#404).
    case pro

    /// The app's settings. It has no route of its own — the app simply comes to the
    /// foreground — and that is still true; the case exists so the vocabulary is
    /// closed rather than open to typos.
    case settings
}

/// The `dictus://open` URLs, built by the keyboard and read by the app.
///
/// WHY a shared type rather than a string on each side: the keyboard extension has no
/// test bundle, so a URL it builds by interpolation and the app parses by hand is a
/// cross-process contract nothing can check. #404 is the bill for that being loose —
/// the fan's Dictus Pro row carried `intent=pro` faithfully, and the app had no `open`
/// route at all, so the one row in the fan that leads anywhere landed on whatever
/// screen happened to be showing. Building and parsing here makes the round trip a
/// test rather than a hope.
///
/// WHY the host is not `dictate`: `KeyboardDictationURL` deliberately answers nil for
/// everything that is not a dictation, and that nil is load-bearing — it is what keeps
/// the widget's own `dictus://dictate` out of the keyboard hand-off path. Adding a
/// screen intent to that enum would put a paywall request inside the type the
/// cold-start overlay switches on.
public enum KeyboardOpenURL {

    /// The scheme registered by DictusApp in `CFBundleURLTypes`.
    private static let scheme = "dictus"

    /// The host that carries a "bring the app to this screen" request.
    private static let host = "open"

    /// The URL the keyboard opens for `intent`.
    public static func url(intent: KeyboardOpenIntent) -> URL? {
        URL(string: "\(scheme)://\(host)?source=keyboard&intent=\(intent.rawValue)")
    }

    /// The intent carried by `url`, or nil when it is not one of ours.
    ///
    /// `source=keyboard` is required for the same reason `KeyboardDictationURL` requires
    /// it: the scheme is public, and a screen request is only a screen request when we
    /// sent it.
    public static func intent(from url: URL) -> KeyboardOpenIntent? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              queryItems.contains(where: { $0.name == "source" && $0.value == "keyboard" }),
              let raw = queryItems.first(where: { $0.name == "intent" })?.value
        else {
            return nil
        }
        return KeyboardOpenIntent(rawValue: raw)
    }
}
