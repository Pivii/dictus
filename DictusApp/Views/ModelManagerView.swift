// DictusApp/Views/ModelManagerView.swift
// Model management UI: download, select, and delete WhisperKit models.
// Redesigned with Downloaded/Available sections, gauge-based model cards, and engine descriptions.
import SwiftUI
import DictusCore

/// Displays WhisperKit models organized in two sections:
/// - "Téléchargés" (downloaded) — models on device, including deprecated ones
/// - "Disponibles" (available) — models available for download, excludes deprecated
///
/// WHY two sections instead of a flat list:
/// Users need to quickly see what's on their device vs. what they can download.
/// Separating sections provides clear visual hierarchy. Deprecated models (Tiny/Base)
/// only appear in Downloaded if the user already has them — they're hidden from
/// Available to guide users toward better models.
///
/// WHY engine description paragraphs:
/// Users may not know what "WhisperKit" means. A brief explanation helps them
/// understand the technology behind the models they're choosing.
struct ModelManagerView: View {
    @ObservedObject var modelManager: ModelManager

    /// Controls the delete confirmation alert.
    @State private var modelToDelete: ModelInfo?
    @State private var showDeleteAlert = false

    /// Tracks any download error to show in an alert.
    @State private var downloadError: String?
    @State private var showErrorAlert = false

    // MARK: - Computed model lists

    /// Downloaded models — includes deprecated (Tiny/Base) if user has them on device.
    /// Uses allIncludingDeprecated so deprecated models still show up for management.
    private var downloadedModels: [ModelInfo] {
        ModelInfo.allIncludingDeprecated.filter { modelManager.downloadedModels.contains($0.identifier) }
    }

    /// Available models — only .available visibility, excludes already-downloaded ones.
    /// Users won't see Tiny/Base here since they're deprecated.
    private var availableModels: [ModelInfo] {
        ModelInfo.all.filter { !modelManager.downloadedModels.contains($0.identifier) }
    }

    /// Which speech engines appear in the downloaded section (for engine descriptions).
    private var downloadedEngines: Set<SpeechEngine> {
        Set(downloadedModels.map(\.engine))
    }

    /// Which speech engines appear in the available section (for engine descriptions).
    private var availableEngines: Set<SpeechEngine> {
        Set(availableModels.map(\.engine))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Downloaded section
                if !downloadedModels.isEmpty {
                    modelSection(
                        title: "Téléchargés",
                        models: downloadedModels,
                        engines: downloadedEngines
                    )
                }

                // MARK: - Available section
                if !availableModels.isEmpty {
                    modelSection(
                        title: "Disponibles",
                        models: availableModels,
                        engines: availableEngines
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .navigationTitle("Modèles")
        .background(Color.dictusBackground.ignoresSafeArea())
        // Delete confirmation alert
        .alert("Supprimer le modèle ?", isPresented: $showDeleteAlert, presenting: modelToDelete) { model in
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                do {
                    try modelManager.deleteModel(model.identifier)
                } catch {
                    downloadError = error.localizedDescription
                    showErrorAlert = true
                }
            }
        } message: { model in
            Text("Supprimer \(model.displayName) ? (\(model.sizeLabel) seront libérés)")
        }
        // Error alert
        .alert("Erreur", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = downloadError {
                Text(error)
            }
        }
    }

    // MARK: - Section builder

    /// Builds a titled section with model cards and engine description paragraphs.
    ///
    /// WHY a helper function (not inline):
    /// Both Downloaded and Available sections have the same layout pattern.
    /// Extracting avoids duplication and keeps the body clean.
    @ViewBuilder
    private func modelSection(title: String, models: [ModelInfo], engines: Set<SpeechEngine>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.dictusSubheading)
                .foregroundStyle(.secondary)

            ForEach(models) { model in
                ModelCardView(
                    model: model,
                    modelManager: modelManager,
                    onDelete: {
                        modelToDelete = model
                        showDeleteAlert = true
                    },
                    onDownloadError: { error in
                        downloadError = error
                        showErrorAlert = true
                    }
                )
            }

            // Engine description paragraphs
            engineDescriptions(for: engines)
        }
    }

    // MARK: - Engine descriptions

    /// Shows a brief paragraph for each speech engine represented in the section.
    ///
    /// WHY per-section engine descriptions:
    /// Only show descriptions for engines the user can see. If all models in a section
    /// are WhisperKit, only the WhisperKit paragraph appears. This avoids confusion
    /// about engines with no visible models.
    @ViewBuilder
    private func engineDescriptions(for engines: Set<SpeechEngine>) -> some View {
        if engines.contains(.whisperKit) {
            engineParagraph(
                icon: "waveform",
                text: "WhisperKit — moteur de transcription développé par Argmax, optimisé pour les puces Apple. Modèles entraînés sur OpenAI Whisper."
            )
        }

        if engines.contains(.parakeet) {
            engineParagraph(
                icon: "bolt",
                text: "Parakeet — moteur de transcription développé par NVIDIA, optimisé pour la vitesse. Modèles Parakeet TDT."
            )
        }
    }

    /// A single engine description paragraph with icon.
    private func engineParagraph(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.dictusCaption)
                .foregroundStyle(.tertiary)

            Text(text)
                .font(.dictusCaption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }
}

#Preview {
    NavigationStack {
        ModelManagerView(modelManager: ModelManager())
    }
}
