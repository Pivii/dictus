// DictusKeyboard/Views/FullAccessBanner.swift
import SwiftUI

/// Non-dismissible banner shown when Full Access is disabled.
/// Guides the user to Settings to enable Full Access for dictation.
///
/// WHY dictusGlass instead of Material:
/// The glass modifier provides iOS 26 Liquid Glass with automatic Material fallback
/// on older versions, keeping the banner consistent with the rest of the design system.
struct FullAccessBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.dictusCaption)

            Text("Dictee desactivee.")
                .font(.dictusCaption)
                .foregroundStyle(.primary)

            Spacer()

            // Deep-link to Settings
            // "app-settings:" opens the app's settings page in iOS Settings
            Link(destination: URL(string: "app-settings:")!) {
                Text("Activer")
                    .font(.caption2.bold())
                    .foregroundColor(.dictusAccent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .dictusGlass(in: Rectangle())
    }
}
