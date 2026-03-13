// DictusApp/Views/HomeView.swift
// Home dashboard showing model status, last transcription, and test dictation link.
import SwiftUI
import DictusCore

/// Home tab dashboard — the first screen users see after onboarding.
///
/// WHY a dedicated HomeView instead of reusing ContentView:
/// ContentView combined navigation, diagnostics, and model prompts in one view.
/// HomeView is focused: it's a dashboard showing current status and quick actions.
/// Diagnostics move to Settings (Plan 04-02), model management is its own tab.
struct HomeView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @ObservedObject var modelManager: ModelManager
    @State private var showCopiedFeedback = false

    /// Read active model name from App Group for display.
    private var activeModelName: String? {
        AppGroup.defaults.string(forKey: SharedKeys.activeModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo mark
            logoSection

            // Model status card
            modelStatusCard

            // Last transcription preview
            if let result = coordinator.lastResult {
                transcriptionCard(result: result)
            }

            // Test dictation button
            if modelManager.isModelReady {
                testDictationLink
            }

            Spacer()
        }
        .padding()
        .background(Color.dictusBackground.ignoresSafeArea())
        .onAppear {
            // Refresh model state every time HomeView appears.
            modelManager.loadState()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DictusOnboardingCompleted"))) { _ in
            // WHY onReceive in addition to onAppear:
            // HomeView mounts behind the onboarding fullScreenCover, so onAppear fires
            // before the model is downloaded. When onboarding completes and dismisses
            // the cover, onAppear does NOT re-fire. This notification-based refresh
            // ensures HomeView shows the correct model state immediately.
            modelManager.loadState()
        }
    }

    // MARK: - Logo Section

    /// Static 3-bar brand logo at the top of the home screen.
    private var logoSection: some View {
        VStack(spacing: 8) {
            DictusLogo(height: 60)
                .padding(.top, 8)
            Text("Dictus")
                .font(.dictusHeading)
                .foregroundColor(.dictusAccent)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Model Status Card

    /// Shows active model name and ready status, or prompts to download.
    ///
    /// WHY a prominent card for "no model" state:
    /// First-time users need clear guidance. Without a model, the app can't transcribe.
    /// The card makes the first required action obvious (navigate to Models tab).
    private var modelStatusCard: some View {
        Group {
            if modelManager.isModelReady, let modelName = activeModelName {
                // Active model display using ModelInfo for human-readable name/size.
                // WHY ModelInfo.forIdentifier: The raw identifier (e.g. "openai_whisper-small")
                // is not user-friendly. ModelInfo maps it to "Small" + "~250 MB".
                HStack {
                    let info = ModelInfo.forIdentifier(modelName)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Modèle actif")
                            .font(.dictusCaption)
                            .foregroundColor(.secondary)
                        Text("Whisper \(info?.displayName ?? modelName)")
                            .font(.dictusSubheading)
                        if let size = info?.sizeLabel {
                            Text(size)
                                .font(.dictusCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.dictusSuccess)
                }
                .padding()
                .dictusGlass()
            } else {
                // No model — prompt to download
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.dictusAccent)
                    Text("Télécharger un modèle pour commencer")
                        .font(.dictusSubheading)
                        .multilineTextAlignment(.center)
                    Text("Allez dans l'onglet Modèles pour télécharger votre premier modèle de transcription.")
                        .font(.dictusCaption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .dictusGlass()
            }
        }
    }

    // MARK: - Last Transcription Card

    /// Shows the most recent transcription result in a tappable glass card.
    /// Tap to copy to clipboard (same behavior as RecordingView result).
    private func transcriptionCard(result: String) -> some View {
        Button {
            UIPasteboard.general.string = result
            HapticFeedback.recordingStopped()
            showCopiedFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopiedFeedback = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(showCopiedFeedback ? "Copié !" : "Dernière transcription")
                        .font(.dictusCaption)
                        .foregroundColor(showCopiedFeedback ? .dictusSuccess : .secondary)
                        .animation(.easeOut(duration: 0.2), value: showCopiedFeedback)
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                Text(result)
                    .font(.dictusBody)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .dictusGlass()
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.97))
    }

    // MARK: - Test Dictation Link

    /// Prominent button to test dictation. Only shown when a model is ready.
    ///
    /// WHY a Button instead of NavigationLink to TestDictationView:
    /// NavigationLink pushes TestDictationView inside the NavigationStack. Meanwhile,
    /// MainTabView shows a RecordingView overlay when coordinator.status != .idle.
    /// This creates TWO stacked RecordingViews. When the overlay dismisses (status → idle),
    /// the pushed TestDictationView is still there with its nav bar visible.
    /// A Button just starts dictation — the MainTabView overlay handles the full UI.
    private var testDictationLink: some View {
        Button {
            coordinator.startDictation()
        } label: {
            HStack {
                Image(systemName: "waveform")
                Text("Nouvelle dictée")
                    .font(.dictusBody)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.dictusAccent)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(GlassPressStyle())
    }
}

#Preview {
    NavigationStack {
        HomeView(modelManager: ModelManager())
            .environmentObject(DictationCoordinator.shared)
    }
}
