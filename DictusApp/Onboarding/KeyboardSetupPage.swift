// DictusApp/Onboarding/KeyboardSetupPage.swift
// Step 3 of onboarding: guide user to add the Dictus keyboard with auto-detection.
import SwiftUI
import UIKit
import DictusCore

/// Guides the user through adding the Dictus keyboard in iOS Settings.
///
/// WHY animated fake Settings card:
/// Users need to enable two toggles in iOS Settings (add keyboard + Full Access).
/// A visual simulation showing exactly what to toggle reduces friction and support
/// requests. The toggles animate in sequence on a loop so the user sees the steps
/// before opening Settings. Inspired by Wispr Flow / Super Whisper onboarding.
struct KeyboardSetupPage: View {
    let onNext: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    @State private var keyboardDetected = false

    /// Guard to prevent concurrent keyboard checks (race condition on Settings return).
    /// WHY this guard: When returning from iOS Settings after enabling the keyboard,
    /// scenePhase can change rapidly (.inactive -> .active). Without this guard,
    /// multiple concurrent calls to checkKeyboardInstalled() race and can crash
    /// when accessing UITextInputMode.activeInputModes.
    @State private var isCheckingKeyboard = false

    // Animation state for the fake toggles
    @State private var dictusToggleOn = false
    @State private var fullAccessToggleOn = false
    @State private var animationTimer: Timer?

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
                    .foregroundStyle(.primary)
                    .padding(.bottom, 28)

                // Fake Settings card
                fakeSettingsCard
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)

                // Open Settings link — plain text, no card wrapper
                Button(action: openSettings) {
                    Label("Ouvrir les Réglages", systemImage: "arrow.up.right")
                        .font(.dictusBody)
                        .foregroundColor(.dictusAccent)
                }
                .padding(.bottom, 20)

                // Auto-detection helper text
                Text("Le clavier sera détecté automatiquement")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)

                // Detection feedback + continue button
                if keyboardDetected {
                    VStack(spacing: 16) {
                        Label("Clavier détecté", systemImage: "checkmark.circle.fill")
                            .font(.dictusBody)
                            .foregroundColor(.dictusSuccess)

                        Button(action: onNext) {
                            Text("Continuer")
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
                    }
                    .padding(.bottom, 16)
                    .transition(.opacity)
                }

                Spacer(minLength: 48)
            }
        }
        .onAppear {
            checkKeyboardInstalled()
            startToggleAnimation()
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
        .onChange(of: scenePhase) { newPhase in
            // WHY debounced check with 500ms delay:
            // When returning from iOS Settings, scenePhase fires .active before
            // UITextInputMode.activeInputModes has updated. The 500ms delay gives
            // iOS time to register the newly-enabled keyboard. The isCheckingKeyboard
            // guard prevents concurrent checks from rapid phase transitions.
            if newPhase == .active {
                guard !isCheckingKeyboard else { return }
                isCheckingKeyboard = true
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        checkKeyboardInstalled()
                        isCheckingKeyboard = false
                    }
                }
            }
            #if DEBUG
            print("[KeyboardSetupPage] scenePhase changed to: \(newPhase)")
            #endif
        }
        .onChange(of: keyboardDetected) { detected in
            if detected {
                // Stop animation loop once detected
                animationTimer?.invalidate()
                animationTimer = nil
                // Show both toggles ON
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    dictusToggleOn = true
                    fullAccessToggleOn = true
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: keyboardDetected)
    }

    // MARK: - Fake Settings Card

    /// Simulates the iOS Settings screen for Dictus keyboard configuration.
    /// Uses real SwiftUI Toggle components (non-interactive) so they automatically
    /// adopt the native Liquid Glass style on iOS 26.
    private var fakeSettingsCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                Text("Réglages > Dictus")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Toggle rows using native SwiftUI Toggle for Liquid Glass styling.
            // allowsHitTesting(false) prevents user interaction — toggles are
            // driven programmatically by the animation timer.
            VStack(spacing: 0) {
                Toggle("Dictus", isOn: $dictusToggleOn)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dictusToggleOn)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                Divider()
                    .opacity(0.3)
                    .padding(.leading, 16)

                Toggle("Autoriser l'acces complet", isOn: $fullAccessToggleOn)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: fullAccessToggleOn)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .allowsHitTesting(false)
            .padding(.vertical, 4)
        }
        .padding(.bottom, 4)
        .dictusGlass(in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Toggle Animation Loop

    /// Starts a repeating animation cycle:
    /// 0.0s → reset both OFF
    /// 1.0s → toggle 1 ON (Dictus)
    /// 2.0s → toggle 2 ON (Full Access)
    /// 4.0s → restart cycle
    private func startToggleAnimation() {
        // Reset state
        dictusToggleOn = false
        fullAccessToggleOn = false

        // Run first cycle
        runAnimationCycle()

        // Repeat every 4 seconds
        animationTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            dictusToggleOn = false
            fullAccessToggleOn = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                runAnimationCycle()
            }
        }
    }

    private func runAnimationCycle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dictusToggleOn = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            fullAccessToggleOn = true
        }
    }

    // MARK: - Private

    private func openSettings() {
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
