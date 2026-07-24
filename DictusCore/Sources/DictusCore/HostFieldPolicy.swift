// DictusCore/Sources/DictusCore/HostFieldPolicy.swift
// Pure decision logic for issue #200: should autocorrect/suggestions run in the
// current host text field, based on its UITextInputTraits?
//
// WHY in DictusCore (not DictusKeyboard):
// DictusKeyboard has no test target, so any logic living there is untestable.
// This type takes platform-neutral inputs (no UIKit import) and is unit-tested
// in DictusCoreTests. DictusKeyboard maps UITextDocumentProxy traits to these
// enums in HostInputTraits.swift.

import Foundation

/// Per-field policy derived from the host text field's input traits.
///
/// iOS disables autocorrection in fields where it does more harm than good:
/// search bars, URL/email fields, username fields. Dictus mirrors that behavior:
/// - `autocorrectAllowed == false`: never auto-apply a correction on space.
/// - `suggestionsAllowed == false`: don't generate suggestion-bar content at all
///   (an empty bar collapses to the language switcher, matching the native
///   keyboard hiding its predictions in these fields).
public struct HostFieldPolicy: Equatable {

    /// Platform-neutral projection of UIKeyboardType.
    /// Only the cases that affect the policy are distinguished; everything else
    /// maps to `.standard`.
    public enum KeyboardKind: String {
        case standard
        case asciiCapable
        case url
        case email
        case webSearch
        case twitter
        case numeric
        case phone
        case namePhone
    }

    /// Platform-neutral projection of UITextContentType.
    public enum ContentKind: String {
        case none
        case username
        case password
        case url
        case email
        case oneTimeCode
        case other
    }

    public let autocorrectAllowed: Bool
    public let suggestionsAllowed: Bool

    /// Short machine-readable explanation for DEBUG logs
    /// (e.g. "autocorrectionType.no", "keyboardType.webSearch").
    public let reason: String

    /// Default policy: everything enabled (normal prose field).
    public static let allowed = HostFieldPolicy(
        autocorrectAllowed: true,
        suggestionsAllowed: true,
        reason: "default"
    )

    public init(autocorrectAllowed: Bool, suggestionsAllowed: Bool, reason: String) {
        self.autocorrectAllowed = autocorrectAllowed
        self.suggestionsAllowed = suggestionsAllowed
        self.reason = reason
    }

    /// Derives the policy from host field traits.
    ///
    /// Decision order (first match wins):
    /// 1. Secure entry (passwords): disable everything.
    /// 2. Host explicitly disabled autocorrection: disable everything.
    ///    This is the strongest signal — Safari search and most social-app
    ///    search fields set `autocorrectionType == .no`.
    /// 3. Content type identifies a token field (username, URL, email, OTP):
    ///    disable everything — these hold identifiers, not prose.
    /// 4. Keyboard type implies a non-prose field (URL, email, web search,
    ///    twitter handles/hashtags, number/phone pads): disable everything.
    ///    `.asciiCapable` stays enabled — many normal fields use it.
    /// 5. Host disabled spell checking only: keep completions/predictions but
    ///    never auto-apply a correction.
    public static func evaluate(
        keyboard: KeyboardKind,
        content: ContentKind,
        autocorrectionDisabled: Bool,
        spellCheckingDisabled: Bool,
        isSecureEntry: Bool
    ) -> HostFieldPolicy {
        if isSecureEntry {
            return HostFieldPolicy(
                autocorrectAllowed: false, suggestionsAllowed: false,
                reason: "secureTextEntry"
            )
        }
        if autocorrectionDisabled {
            return HostFieldPolicy(
                autocorrectAllowed: false, suggestionsAllowed: false,
                reason: "autocorrectionType.no"
            )
        }
        switch content {
        case .username, .password, .url, .email, .oneTimeCode:
            return HostFieldPolicy(
                autocorrectAllowed: false, suggestionsAllowed: false,
                reason: "textContentType.\(content.rawValue)"
            )
        case .none, .other:
            break
        }
        switch keyboard {
        case .url, .email, .webSearch, .twitter, .numeric, .phone, .namePhone:
            return HostFieldPolicy(
                autocorrectAllowed: false, suggestionsAllowed: false,
                reason: "keyboardType.\(keyboard.rawValue)"
            )
        case .standard, .asciiCapable:
            break
        }
        if spellCheckingDisabled {
            return HostFieldPolicy(
                autocorrectAllowed: false, suggestionsAllowed: true,
                reason: "spellCheckingType.no"
            )
        }
        return .allowed
    }
}
