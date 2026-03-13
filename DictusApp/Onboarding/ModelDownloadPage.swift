// DictusApp/Onboarding/ModelDownloadPage.swift
// Step 4 of onboarding: download the recommended model (RAM-based).
import SwiftUI
import DictusCore

/// Downloads the recommended model with visible progress.
///
/// WHY dynamic recommendation:
/// ModelInfo.recommendedIdentifier() picks the best model for the device's RAM:
/// - >=6 GB RAM → Parakeet v3 (fast, accurate, NVIDIA)
/// - <=4 GB RAM → Whisper Small (compact, good accuracy)
/// The model card displays name, size, and description from the ModelInfo catalog.
///
/// WHY @StateObject for ModelManager:
/// Each page in the TabView needs its own lifecycle. @StateObject ensures
/// ModelManager is created once and persists through re-renders.
struct ModelDownloadPage: View {
    let onNext: () -> Void

    @StateObject private var modelManager = ModelManager()

    /// The recommended model to download during onboarding.
    /// WHY computed property: Uses ModelInfo.recommendedIdentifier() to pick
    /// the best model for this device's RAM, instead of hardcoding "whisper-small".
    private var recommendedModel: String {
        ModelInfo.recommendedIdentifier()
    }

    @State private var isDownloading = false
    @State private var downloadComplete = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Download icon
            Image(systemName: downloadComplete ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(downloadComplete ? .dictusSuccess : .dictusAccent)
                .padding(.bottom, 24)

            // Title
            Text("Modèle vocal")
                .font(.dictusHeading)
                .foregroundStyle(.primary)
                .padding(.bottom, 12)

            // Explanatory text
            Text("Pour transcrire votre voix, Dictus a besoin d'un modèle vocal. Le téléchargement peut prendre quelques minutes.")
                .font(.dictusBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

            // Model card
            modelCard
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

            // Download progress (only show bar when we have actual progress data)
            if isDownloading, let progress = modelManager.downloadProgress[recommendedModel] {
                VStack(spacing: 8) {
                    ProgressView(value: Double(progress))
                        .tint(.dictusAccent)
                        .padding(.horizontal, 32)

                    Text("\(Int(progress * 100))%")
                        .font(.dictusCaption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 16)
            }

            // Prewarming indicator
            if modelManager.modelStates[recommendedModel] == .prewarming {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.dictusAccent)
                    Text("Optimisation en cours...")
                        .font(.dictusCaption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 16)
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.dictusCaption)
                    .foregroundColor(.dictusRecording)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }

            Spacer()

            // Action button
            if downloadComplete {
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
                .padding(.bottom, 48)
            } else if !isDownloading {
                VStack(spacing: 16) {
                    Button(action: startDownload) {
                        Text("Installer le modèle")
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
                .padding(.bottom, 48)
            } else {
                // Downloading — show nothing (progress is above)
                Spacer().frame(height: 48)
            }
        }
        .onAppear {
            // Check if model is already downloaded (user may have downloaded before)
            if modelManager.downloadedModels.contains(recommendedModel) {
                downloadComplete = true
            }
        }
    }

    // MARK: - Model Card

    /// Model card that displays name, size, and description from the ModelInfo catalog.
    /// WHY data-driven: On a 6GB+ device this shows "Parakeet v3 / ~800 MB / Rapide et precis (NVIDIA)"
    /// instead of the old hardcoded "Whisper Small / ~500 Mo / Bonne precision".
    private var modelCard: some View {
        let info = ModelInfo.forIdentifier(recommendedModel)
        return VStack(alignment: .leading, spacing: 12) {
            Text(info?.displayName ?? "Modèle vocal")
                .font(.dictusSubheading)
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                Label(info?.sizeLabel ?? "~500 Mo", systemImage: "internaldrive")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)

                Label(info?.description ?? "Précis et équilibré", systemImage: "waveform")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
            }

            Text("Recommandé pour votre iPhone")
                .font(.dictusCaption)
                .foregroundColor(.dictusAccent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dictusGlass()
    }

    // MARK: - Private

    private func startDownload() {
        isDownloading = true
        errorMessage = nil

        Task {
            do {
                try await modelManager.downloadModel(recommendedModel)
                downloadComplete = true
                isDownloading = false
            } catch {
                errorMessage = error.localizedDescription
                isDownloading = false
            }
        }
    }
}
