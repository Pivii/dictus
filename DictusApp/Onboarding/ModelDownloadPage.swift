// DictusApp/Onboarding/ModelDownloadPage.swift
// Step 4 of onboarding: download the recommended model (RAM-based).
import SwiftUI
import DictusCore

/// Downloads the recommended model with visible progress.
///
/// WHY dynamic recommendation:
/// ModelInfo.recommendedIdentifier() picks the best compatible model for the device:
/// - A12/A13 iPhones → Whisper Base (Argmax-supported fallback)
/// - >=6 GB RAM → Parakeet v3 (fast, accurate, NVIDIA)
/// - Other <=4 GB iPhones → Whisper Small (compact, good accuracy)
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

    /// Issue #144: identifier currently being prepared. Drives a full-screen
    /// `ModelLoadingOverlay` while the model goes through download → compile →
    /// RAM load, so the onboarding shares the same wait UX as the in-app
    /// model manager.
    @State private var preparingModelID: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Download icon
            Image(systemName: downloadComplete ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(downloadComplete ? .dictusSuccess : .dictusAccent)
                .padding(.bottom, 24)

            // Title
            Text("Voice model")
                .font(.dictusHeading)
                .foregroundStyle(.primary)
                .padding(.bottom, 12)

            // Explanatory text
            Text("To transcribe your voice, Dictus needs a voice model. The download may take a few minutes.")
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

                    // Moving byte counter — reads as alive even while the
                    // percentage crawls through the 445 MB Encoder file (#207).
                    if let bytes = modelManager.downloadByteInfo[recommendedModel] {
                        Text("\(bytes.downloadedMB) MB of \(bytes.totalMB) MB")
                            .font(.dictusCaption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, 16)
            }

            // Prewarming indicator
            if modelManager.modelStates[recommendedModel] == .prewarming {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.dictusAccent)
                    Text("Optimizing...")
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
                    Text("Continue")
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
                        Text("Install model")
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
            // If the user backgrounded the app mid-prep, surface the overlay again.
            if preparingModelID == nil, let id = liveActivePrepModel {
                preparingModelID = id
            }
        }
        .onChange(of: liveActivePrepModel) { _, newValue in
            if let id = newValue, preparingModelID == nil {
                preparingModelID = id
            }
        }
        .fullScreenCover(item: Binding<PreparingItem?>(
            get: { preparingModelID.map(PreparingItem.init) },
            set: { preparingModelID = $0?.id }
        )) { item in
            ModelLoadingOverlay(
                modelManager: modelManager,
                modelIdentifier: item.id,
                context: .onboarding,
                isPresented: Binding(
                    get: { preparingModelID != nil },
                    set: { if !$0 { preparingModelID = nil } }
                )
            )
        }
    }

    /// Wrapper so `.fullScreenCover(item:)` works with a plain String identifier.
    private struct PreparingItem: Identifiable {
        let id: String
    }

    /// First identifier currently in a user-facing prep phase. Mirrors the same
    /// computation as `ModelManagerView` so the overlay behavior is identical.
    private var liveActivePrepModel: String? {
        if modelManager.modelLoadState == .loading,
           let active = modelManager.activeModel {
            return active
        }
        switch modelManager.modelStates[recommendedModel] ?? .notDownloaded {
        case .prewarming, .downloading:
            return recommendedModel
        default:
            return nil
        }
    }

    // MARK: - Model Card

    /// Model card that displays name, size, and description from the ModelInfo catalog.
    /// WHY data-driven: On a 6GB+ device this shows "Parakeet v3 / ~800 MB / Rapide et precis (NVIDIA)"
    /// instead of the old hardcoded "Whisper Small / ~500 Mo / Bonne precision".
    private var modelCard: some View {
        let info = ModelInfo.forIdentifier(recommendedModel)
        return VStack(alignment: .leading, spacing: 12) {
            Text(info?.displayName ?? "Voice model")
                .font(.dictusSubheading)
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                Label(info?.sizeLabel ?? "~500 Mo", systemImage: "internaldrive")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)

                Label(info?.description ?? "Accurate and balanced", systemImage: "waveform")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
            }

            Text("Recommended for your iPhone")
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
        // Surface the full-screen overlay immediately so the user sees feedback
        // even before the first download progress callback fires.
        preparingModelID = recommendedModel

        Task {
            do {
                try await modelManager.downloadModel(recommendedModel)
                downloadComplete = true
                isDownloading = false
                // The overlay closes itself once preloadActiveModel reaches .ready;
                // we don't flip preparingModelID here.
            } catch {
                errorMessage = error.localizedDescription
                isDownloading = false
                preparingModelID = nil
            }
        }
    }
}
