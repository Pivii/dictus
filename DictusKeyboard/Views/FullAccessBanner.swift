// DictusKeyboard/Views/FullAccessBanner.swift
import SwiftUI

/// Non-dismissible banner shown when Full Access is disabled.
/// Guides the user to Settings to enable Full Access for dictation.
struct FullAccessBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)

            Text("Dictée désactivée.")
                .font(.caption2)
                .foregroundColor(.primary)

            Spacer()

            // Deep-link to Settings
            // "app-settings:" opens the app's settings page in iOS Settings
            Link(destination: URL(string: "app-settings:")!) {
                Text("Activer")
                    .font(.caption2.bold())
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
    }
}
