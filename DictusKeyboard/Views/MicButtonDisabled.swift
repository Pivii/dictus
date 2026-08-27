// DictusKeyboard/Views/MicButtonDisabled.swift
import SwiftUI

/// Mic button shown when Full Access is not enabled.
/// Shows a popover explaining why Full Access is needed.
struct MicButtonDisabled: View {
    @State private var showExplanation = false

    var body: some View {
        Button {
            showExplanation = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundColor(.gray)
                .padding(12)
                .background(Color.gray.opacity(0.15))
                .clipShape(Circle())
        }
        .popover(isPresented: $showExplanation) {
            VStack(spacing: 8) {
                Text("Full access required")
                    .font(.headline)
                Text("Enable Full Access in Settings > Keyboards > Dictus to use dictation.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                // Force unwrap: "app-settings:" is a compile-time literal and a
                // well-formed URL, so the failable initializer cannot return nil.
                // swiftlint:disable:next force_unwrapping
                Link("Open Settings", destination: URL(string: "app-settings:")!)
                    .font(.caption.bold())
            }
            .padding()
            .frame(width: 250)
        }
    }
}

#Preview {
    MicButtonDisabled()
        .padding()
}
