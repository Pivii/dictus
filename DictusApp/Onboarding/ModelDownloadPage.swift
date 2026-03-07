// DictusApp/Onboarding/ModelDownloadPage.swift
// Step 4 of onboarding: download the recommended Whisper model.
import SwiftUI
import DictusCore

/// Downloads the recommended Whisper model with visible progress.
///
/// WHY pre-select "small" model:
/// The "small" model offers a good balance of accuracy and speed for most modern
/// iPhones (A12+). We recommend it during onboarding to get users started with
/// quality transcription. Users can change models later in the Models tab.
///
/// WHY @StateObject for ModelManager:
/// Each page in the TabView needs its own lifecycle. @StateObject ensures
/// ModelManager is created once and persists through re-renders.
struct ModelDownloadPage: View {
    let onNext: () -> Void

    @StateObject private var modelManager = ModelManager()

    /// The recommended model to download during onboarding.
    private let recommendedModel = "openai_whisper-small"

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
            Text("Telecharger un modele")
                .font(.dictusHeading)
                .foregroundStyle(.primary)
                .padding(.bottom, 24)

            // Model card
            modelCard
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

            // Download progress
            if isDownloading {
                let progress = modelManager.downloadProgress[recommendedModel] ?? 0
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
                    Text("Preparation du modele...")
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
                        .foregroundStyle(.primary)
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
                        Text("Telecharger")
                            .font(.dictusSubheading)
                            .foregroundStyle(.primary)
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

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Whisper Small")
                .font(.dictusSubheading)
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                Label("~500 Mo", systemImage: "internaldrive")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)

                Label("Bonne precision", systemImage: "waveform")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
            }

            Text("Recommande pour la plupart des appareils")
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

                // Auto-advance after brief delay to show checkmark
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onNext()
                }
            } catch {
                errorMessage = error.localizedDescription
                isDownloading = false
            }
        }
    }
}
