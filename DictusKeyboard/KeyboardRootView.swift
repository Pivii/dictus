// DictusKeyboard/KeyboardRootView.swift
import SwiftUI

/// Root SwiftUI view for the keyboard extension.
/// Plan 1.3 replaces this placeholder with the full AZERTY layout.
struct KeyboardRootView: View {
    let controller: UIInputViewController

    var body: some View {
        VStack {
            Text("Dictus Keyboard")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Next Keyboard") {
                controller.advanceToNextInputMode()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 216)
        .background(Color(.secondarySystemBackground))
    }
}
