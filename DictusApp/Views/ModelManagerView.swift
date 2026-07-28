// DictusApp/Views/ModelManagerView.swift
// Model management UI: download, select, and delete WhisperKit models.
// Redesigned with Downloaded/Available sections, gauge-based model cards, and engine descriptions.
// Swipe-to-delete on downloaded non-active model cards (like iOS Mail), plus an
// explicit overflow menu on downloaded cards for discoverability (issue #193).
import SwiftUI
import DictusCore

/// Displays WhisperKit models organized in two sections:
/// - "Downloaded" — models on device, including deprecated ones
/// - "Available" — models available for download, excludes deprecated
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

    /// Controls the partial-download delete confirmation alert (issue #235).
    /// Separate from modelToDelete because the confirmed action differs:
    /// cleanupFailedModel (wipe kept files of a failed download) instead of
    /// deleteModel (remove a ready model, guarded by the last-model rule).
    @State private var partialModelToDelete: ModelInfo?
    @State private var showPartialDeleteAlert = false

    /// Tracks any download error to show in an alert.
    @State private var downloadError: String?
    @State private var showErrorAlert = false

    /// Issue #144: the model identifier currently being prepared (downloading,
    /// compiling, or loading into RAM). When non-nil the full-screen overlay
    /// blocks the manager UI until prep completes. Driven by the @State below
    /// rather than the computed value because we want the overlay to keep its
    /// "ready" celebration moment after the model state flips back to .ready.
    @State private var preparingModelID: String?

    // MARK: - Computed model lists

    /// Downloaded models — includes deprecated (Tiny/Base) if user has them on device,
    /// plus any models currently downloading or prewarming (so they appear here immediately).
    private var downloadedModels: [ModelInfo] {
        ModelInfo.allIncludingDeprecated.filter { model in
            let state = modelManager.modelStates[model.identifier] ?? .notDownloaded
            switch state {
            case .downloading, .prewarming, .ready, .error:
                return true
            case .notDownloaded:
                return modelManager.downloadedModels.contains(model.identifier)
            }
        }
    }

    /// Available models — excludes downloaded, downloading, and prewarming models.
    /// Users won't see Tiny/Base here since they're deprecated.
    ///
    /// Phase 37 (issue #104): uses `ModelInfo.available(on:)` so per-device gated
    /// models (e.g. Whisper Turbo on low-RAM devices) are completely hidden rather
    /// than shown disabled. The "Downloaded" section above stays ungated so a user
    /// who obtained a gated model under a permissive build can still manage/delete it.
    private var availableModels: [ModelInfo] {
        ModelInfo.available(on: DeviceCapabilities.current()).filter { model in
            let state = modelManager.modelStates[model.identifier] ?? .notDownloaded
            switch state {
            case .downloading, .prewarming, .ready, .error:
                return false
            case .notDownloaded:
                return !modelManager.downloadedModels.contains(model.identifier)
            }
        }
    }

    /// First model identifier currently in a user-facing prep phase.
    /// Priority: active load > prewarming > downloading.
    private var liveActivePrepModel: String? {
        if modelManager.modelLoadState == .loading,
           let active = modelManager.activeModel {
            return active
        }
        for model in ModelInfo.allIncludingDeprecated {
            switch modelManager.modelStates[model.identifier] ?? .notDownloaded {
            case .prewarming:
                return model.identifier
            default:
                continue
            }
        }
        for model in ModelInfo.allIncludingDeprecated {
            switch modelManager.modelStates[model.identifier] ?? .notDownloaded {
            case .downloading:
                return model.identifier
            default:
                continue
            }
        }
        return nil
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
            // WHY no Section header: parameter:
            // List Section headers are sticky by default in iOS. Using an inline Text row
            // as the first item in a plain Section makes it scroll with the content.
            if !downloadedModels.isEmpty {
                Section {
                    // Inline section header — scrolls with content (not sticky)
                    Text("Downloaded")
                        .font(.dictusSubheading)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))

                    ForEach(downloadedModels) { model in
                        ModelCardView(
                            model: model,
                            modelManager: modelManager,
                            onDownloadError: { error in
                                downloadError = error
                                showErrorAlert = true
                            },
                            // Issue #193: explicit delete entry point via the
                            // card's overflow menu. Funnels into the same
                            // confirmation alert as swipe-to-delete.
                            onDeleteRequest: {
                                modelToDelete = model
                                showDeleteAlert = true
                            },
                            // Issue #235: full reset for a failed download via
                            // the overflow menu. Only wired here — error cards
                            // always live in the Downloaded section (the
                            // Available filter excludes the .error state).
                            onDeletePartialRequest: {
                                partialModelToDelete = model
                                showPartialDeleteAlert = true
                            }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canDelete(model) {
                                Button(role: .destructive) {
                                    modelToDelete = model
                                    showDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                        .frame(maxHeight: .infinity)
                                }
                                .tint(.red)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            }

            // MARK: - Available section
            if !availableModels.isEmpty {
                Section {
                    // Inline section header — scrolls with content (not sticky)
                    Text("Available")
                        .font(.dictusSubheading)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))

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
                }
            }

            // MARK: - Engine descriptions footer
            // WHY a separate section at the bottom:
            // Engine descriptions are reference info, not per-section content.
            // Placing them as a fixed footer at the bottom keeps the model sections clean
            // and avoids duplicating descriptions across Downloaded/Available sections.
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    engineParagraph(
                        icon: "waveform",
                        text: "WhisperKit — transcription engine developed by Argmax, optimized for Apple chips. Models trained on OpenAI Whisper."
                    )
                    engineParagraph(
                        icon: "bolt",
                        text: "Parakeet — transcription engine developed by NVIDIA, optimized for speed. Parakeet TDT models."
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("Models")
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
        .alert("Delete model?", isPresented: $showDeleteAlert, presenting: modelToDelete) { model in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                do {
                    try modelManager.deleteModel(model.identifier)
                } catch {
                    downloadError = error.localizedDescription
                    showErrorAlert = true
                }
            }
        } message: { model in
            Text("Delete \(model.displayName)? The model will be removed from your device.")
        }
        // Partial-download delete confirmation alert (issue #235).
        // WHY no ModelManager error handling here: cleanupFailedModel cannot
        // throw — file removals are best-effort (try?) and the state reset to
        // .notDownloaded always happens, moving the card back to "Available".
        .alert("Delete partial download?", isPresented: $showPartialDeleteAlert, presenting: partialModelToDelete) { model in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelManager.cleanupFailedModel(model.identifier)
            }
        } message: { model in
            Text("Delete the partially downloaded files for \(model.displayName)? The next download will start from the beginning.")
        }
        // Error alert
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = downloadError {
                Text(error)
            }
        }
        // Issue #144: full-screen overlay during model download / compile / RAM-load.
        // We watch the live computed property and lift it into a @State binding the
        // overlay can flip back to nil when it's ready to dismiss.
        .onChange(of: liveActivePrepModel) { _, newValue in
            if let id = newValue, preparingModelID == nil {
                preparingModelID = id
            }
        }
        .onAppear {
            if preparingModelID == nil, let id = liveActivePrepModel {
                preparingModelID = id
            }
        }
        .fullScreenCover(item: Binding<PreparingModelItem?>(
            get: { preparingModelID.map(PreparingModelItem.init) },
            set: { preparingModelID = $0?.id }
        )) { item in
            ModelLoadingOverlay(
                modelManager: modelManager,
                modelIdentifier: item.id,
                isPresented: Binding(
                    get: { preparingModelID != nil },
                    set: { if !$0 { preparingModelID = nil } }
                )
            )
        }
    }

    /// Wrapper so we can use `.fullScreenCover(item:)` with a plain String.
    private struct PreparingModelItem: Identifiable {
        let id: String
    }

    // MARK: - Engine descriptions

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
