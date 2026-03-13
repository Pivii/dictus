// DictusApp/Views/ModelManagerView.swift
// Model management UI: download, select, and delete WhisperKit models.
// Redesigned with Downloaded/Available sections, gauge-based model cards, and engine descriptions.
// Swipe-to-delete on downloaded non-active model cards (like iOS Mail).
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
/// WHY List instead of ScrollView+VStack:
/// SwiftUI's .swipeActions modifier only works inside List context. We style the List
/// with transparent backgrounds and hidden separators to preserve the glass card aesthetic.
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

    /// Whether a given model can be deleted (not active, not the last one).
    private func canDelete(_ model: ModelInfo) -> Bool {
        let state = modelManager.modelStates[model.identifier] ?? .notDownloaded
        guard case .ready = state else { return false }
        let isActive = modelManager.activeModel == model.identifier
        let isLastDownloaded = modelManager.downloadedModels.count <= 1
        return !isActive && !isLastDownloaded
    }

    var body: some View {
        List {
            // MARK: - Downloaded section
            if !downloadedModels.isEmpty {
                Section {
                    ForEach(downloadedModels) { model in
                        ModelCardView(
                            model: model,
                            modelManager: modelManager,
                            onDownloadError: { error in
                                downloadError = error
                                showErrorAlert = true
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canDelete(model) {
                                Button("Supprimer", role: .destructive) {
                                    modelToDelete = model
                                    showDeleteAlert = true
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }

                    // Engine description paragraphs for downloaded section
                    engineDescriptions(for: downloadedEngines)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } header: {
                    Text("Téléchargés")
                        .font(.dictusSubheading)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            // MARK: - Available section
            if !availableModels.isEmpty {
                Section {
                    ForEach(availableModels) { model in
                        ModelCardView(
                            model: model,
                            modelManager: modelManager,
                            onDownloadError: { error in
                                downloadError = error
                                showErrorAlert = true
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }

                    // Engine description paragraphs for available section
                    engineDescriptions(for: availableEngines)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } header: {
                    Text("Disponibles")
                        .font(.dictusSubheading)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("Modèles")
        .background(Color.dictusBackground.ignoresSafeArea())
        // Sync state from onboarding's separate ModelManager instance (Bug #25 fix).
        // WHY onAppear loadState:
        // When the user downloads a model during onboarding, a separate ModelManager
        // writes state to App Group defaults. This view's ModelManager instance may
        // not reflect that. Calling loadState() on appear re-reads from the shared
        // UserDefaults so the model shows as downloaded and active.
        .onAppear {
            modelManager.loadState()
        }
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
            Text("Supprimer \(model.displayName) ? Le modèle sera supprimé de votre appareil.")
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

    // MARK: - Engine descriptions

    /// Shows a brief paragraph for each speech engine represented in the section.
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
