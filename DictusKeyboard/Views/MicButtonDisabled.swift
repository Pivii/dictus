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
                Text("Accès complet requis")
                    .font(.headline)
                Text("Active l'Accès complet dans Réglages > Claviers > Dictus pour utiliser la dictée.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                Link("Ouvrir Réglages", destination: URL(string: "app-settings:")!)
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
