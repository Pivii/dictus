// DictusCore/Sources/DictusCore/KnownAppSchemes.swift
// URL scheme registry for the top messaging apps used with Dictus.
import Foundation

/// Represents a known app's URL scheme for auto-return navigation.
///
/// WHY two separate scheme fields:
/// - `scheme` is the full URL (e.g., "whatsapp://") used to open the app via UIApplication.open(_:).
/// - `queryScheme` is the bare scheme (e.g., "whatsapp") used with canOpenURL(_:) to check
///   if the app is installed. iOS requires bare schemes in the LSApplicationQueriesSchemes
///   Info.plist array for canOpenURL to work.
public struct AppScheme: Sendable {
    /// Human-readable app name (e.g., "WhatsApp")
    public let name: String
    /// Full URL scheme including "://" (e.g., "whatsapp://")
    public let scheme: String
    /// Bare scheme for canOpenURL checks (e.g., "whatsapp")
    public let queryScheme: String

    public init(name: String, scheme: String, queryScheme: String) {
        self.name = name
        self.scheme = scheme
        self.queryScheme = queryScheme
    }
}

/// Registry of the top 10 messaging apps' URL schemes.
///
/// WHY in DictusCore (not DictusApp):
/// Both DictusApp (for auto-return via UIApplication.open) and DictusKeyboard
/// (for source detection via canOpenURL) need access to these schemes.
/// Placing them in the shared framework avoids duplication.
///
/// WHY these 10 apps:
/// Selected based on French App Store messaging app rankings and common
/// use cases for dictation (chat apps, notes). Can be extended later.
public enum KnownAppSchemes {
    public static let all: [AppScheme] = [
        AppScheme(name: "WhatsApp", scheme: "whatsapp://", queryScheme: "whatsapp"),
        AppScheme(name: "Messages", scheme: "sms://", queryScheme: "sms"),
        AppScheme(name: "Telegram", scheme: "tg://", queryScheme: "tg"),
        AppScheme(name: "Messenger", scheme: "fb-messenger://", queryScheme: "fb-messenger"),
        AppScheme(name: "Signal", scheme: "sgnl://", queryScheme: "sgnl"),
        AppScheme(name: "Slack", scheme: "slack://", queryScheme: "slack"),
        AppScheme(name: "Discord", scheme: "discord://", queryScheme: "discord"),
        AppScheme(name: "Teams", scheme: "msteams://", queryScheme: "msteams"),
        AppScheme(name: "Instagram", scheme: "instagram://", queryScheme: "instagram"),
        AppScheme(name: "Notes", scheme: "mobilenotes://", queryScheme: "mobilenotes")
    ]
}
