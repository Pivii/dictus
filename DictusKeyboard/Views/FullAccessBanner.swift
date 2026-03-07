// DictusKeyboard/Views/FullAccessBanner.swift
import SwiftUI
import DictusCore

/// Non-dismissible banner shown when Full Access is disabled.
/// Guides the user to Settings to enable Full Access for dictation.
///
/// WHY onActivate closure instead of Link:
/// SwiftUI's Link view does not work in keyboard extensions — the responder chain
/// doesn't route URL opening correctly. Instead we accept a closure from the parent
/// that calls openURL through the environment, which does work.
struct FullAccessBanner: View {
    let onActivate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.footnote)

            Text("Dictee desactivee.")
                .font(.footnote)
                .foregroundStyle(.primary)

            Spacer()

            Button(action: onActivate) {
                Text("Activer")
                    .font(.footnote.bold())
                    .foregroundColor(.dictusAccent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }
}
