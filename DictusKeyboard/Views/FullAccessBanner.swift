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
                .font(.body)

            Text("Dictee desactivee.")
                .font(.footnote)
                .foregroundStyle(.primary)

            Spacer()

            // Open DictusApp via URL scheme — better than app-settings: which opens
            // a blank iOS Settings page. The app can show keyboard setup instructions.
            Link(destination: URL(string: "dictus://settings")!) {
                Text("Activer")
                    .font(.footnote.bold())
                    .foregroundColor(.dictusAccent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .dictusGlass(in: Rectangle())
    }
}
