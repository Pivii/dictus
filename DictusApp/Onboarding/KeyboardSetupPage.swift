// DictusApp/Onboarding/KeyboardSetupPage.swift
// Step 3 of onboarding: guide user to add the Dictus keyboard and enable Full Access.
import SwiftUI
import UIKit

/// Guides the user through adding the Dictus keyboard in iOS Settings.
///
/// WHY two separate instruction blocks:
/// Adding a keyboard and enabling Full Access are two distinct steps in iOS Settings.
/// Numbering them makes the multi-step process clear for first-time users.
///
/// WHY manual fallback button:
/// Auto-detection of keyboard installation checks UITextInputMode.activeInputModes,
/// but this API is unreliable — it may not update immediately after the user adds
/// the keyboard. The manual "J'ai ajoute le clavier" button is always visible
/// as a reliable fallback path.
struct KeyboardSetupPage: View {
    let onNext: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var keyboardDetected = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // Keyboard icon
                Image(systemName: "keyboard")
                    .font(.system(size: 64))
                    .foregroundColor(.dictusAccent)
                    .padding(.bottom, 24)

                // Title
                Text("Ajouter le clavier")
                    .font(.dictusHeading)
                    .foregroundColor(.white)
                    .padding(.bottom, 32)

                // Instruction block 1: Add keyboard
                instructionBlock(
                    number: "1",
                    title: "Ouvrez Reglages > Dictus > Claviers > Ajouter un clavier",
                    buttonTitle: "Ouvrir les Reglages",
                    action: openSettings
                )
                .padding(.bottom, 24)

                // Instruction block 2: Enable Full Access
                instructionBlock(
                    number: "2",
                    title: "Activez l'Acces complet pour le microphone",
                    subtitle: "L'acces complet permet a Dictus d'enregistrer votre voix depuis le clavier"
                )
                .padding(.bottom, 32)

                // Detection feedback
                if keyboardDetected {
                    Label("Clavier detecte", systemImage: "checkmark.circle.fill")
                        .font(.dictusBody)
                        .foregroundColor(.dictusSuccess)
                        .padding(.bottom, 16)
                }

                // Manual confirmation button (always visible as fallback)
                Button(action: onNext) {
                    Text(keyboardDetected ? "Continuer" : "J'ai ajoute le clavier")
                        .font(.dictusSubheading)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.dictusAccent)
                        )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            // When user returns from Settings, check if keyboard was added
            if newPhase == .active {
                checkKeyboardInstalled()
            }
        }
    }

    // MARK: - Instruction Block

    private func instructionBlock(
        number: String,
        title: String,
        subtitle: String? = nil,
        buttonTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number circle
            Text(number)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.dictusAccent.opacity(0.3)))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.dictusBody)
                    .foregroundColor(.white)

                if let subtitle {
                    Text(subtitle)
                        .font(.dictusCaption)
                        .foregroundColor(.white.opacity(0.5))
                }

                if let buttonTitle, let action {
                    Button(action: action) {
                        Label(buttonTitle, systemImage: "arrow.up.right")
                            .font(.dictusCaption)
                            .foregroundColor(.dictusAccent)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Private

    private func openSettings() {
        // UIApplication.openSettingsURLString opens the app's own Settings page
        // in the iOS Settings app. From there the user navigates to Keyboards.
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Check if the Dictus keyboard is installed by inspecting active input modes.
    ///
    /// WHY UITextInputMode.activeInputModes:
    /// This is the only public API to detect installed keyboards. It returns
    /// an array of UITextInputMode objects whose `value(forKey: "identifier")`
    /// contains the bundle identifier. We look for our keyboard extension's
    /// bundle ID "com.pivi.dictus.keyboard".
    private func checkKeyboardInstalled() {
        let modes = UITextInputMode.activeInputModes
        for mode in modes {
            if let identifier = mode.value(forKey: "identifier") as? String,
               identifier.contains("com.pivi.dictus") {
                keyboardDetected = true
                return
            }
        }
    }
}
