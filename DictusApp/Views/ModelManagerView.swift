// DictusApp/Views/ModelManagerView.swift
// Model management UI: download, select, and delete WhisperKit models.
import SwiftUI
import DictusCore

/// Displays all available WhisperKit models with download/select/delete controls.
///
/// WHY a dedicated view (not inline in ContentView):
/// Model management is a distinct feature with its own state and interactions.
/// Separating it follows Single Responsibility and keeps ContentView focused
/// on top-level navigation.
struct ModelManagerView: View {
    @ObservedObject var modelManager: ModelManager

    /// Controls the delete confirmation alert.
    @State private var modelToDelete: ModelInfo?
    @State private var showDeleteAlert = false

    /// Tracks any download error to show in an alert.
    @State private var downloadError: String?
    @State private var showErrorAlert = false

    var body: some View {
        List {
            ForEach(ModelInfo.all) { model in
                ModelRow(
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
        }
        .navigationTitle("Modeles")
        // Delete confirmation alert
        .alert("Supprimer le modele ?", isPresented: $showDeleteAlert, presenting: modelToDelete) { model in
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
            Text("Supprimer \(model.displayName) ? (\(model.sizeLabel) seront liberes)")
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
}

/// A single row in the model list showing metadata and state-dependent controls.
///
/// WHY a separate struct (not inline in ForEach):
/// Each row has its own interaction logic (download task, state display).
/// Extracting it keeps ModelManagerView's body clean and each row testable.
private struct ModelRow: View {
    let model: ModelInfo
    @ObservedObject var modelManager: ModelManager
    let onDelete: () -> Void
    let onDownloadError: (String) -> Void

    /// The current state for this model, with a safe default.
    private var state: ModelState {
        modelManager.modelStates[model.identifier] ?? .notDownloaded
    }

    /// Whether this model is the currently active one.
    private var isActive: Bool {
        modelManager.activeModel == model.identifier
    }

    /// Whether this is the last downloaded model (cannot be deleted).
    private var isLastModel: Bool {
        modelManager.downloadedModels.count <= 1 &&
        modelManager.downloadedModels.contains(model.identifier)
    }

    var body: some View {
        HStack {
            // Model info (left side)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.headline)

                    if modelManager.isRecommended(model.identifier) {
                        Text("Recommande")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 12) {
                    Label(model.sizeLabel, systemImage: "arrow.down.circle")
                    Label(model.accuracyLabel, systemImage: "target")
                    Label(model.speedLabel, systemImage: "bolt")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // State-dependent trailing content (right side)
            trailingContent
        }
        .padding(.vertical, 4)
        // Swipe to delete (only for ready, non-active, non-last models)
        .swipeActions(edge: .trailing) {
            if case .ready = state, !isActive, !isLastModel {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            }
        }
    }

    /// The trailing content changes based on the model's current state.
    ///
    /// WHY @ViewBuilder:
    /// Swift's @ViewBuilder lets us return different view types from a single
    /// computed property using if/else, which SwiftUI handles via type erasure.
    @ViewBuilder
    private var trailingContent: some View {
        switch state {
        case .notDownloaded:
            Button {
                Task {
                    do {
                        try await modelManager.downloadModel(model.identifier)
                    } catch {
                        onDownloadError(error.localizedDescription)
                    }
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

        case .downloading:
            VStack(spacing: 2) {
                ProgressView(value: modelManager.downloadProgress[model.identifier] ?? 0, total: 1.0)
                    .frame(width: 60)
                let pct = Int((modelManager.downloadProgress[model.identifier] ?? 0) * 100)
                Text("\(pct)%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

        case .prewarming:
            VStack(spacing: 2) {
                ProgressView()
                Text("Optimisation...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

        case .ready:
            if isActive {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Actif")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Choisir") {
                        modelManager.selectModel(model.identifier)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !isLastModel {
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .error(let message):
            HStack(spacing: 8) {
                Button {
                    // Reset state and allow retry
                    modelManager.modelStates[model.identifier] = .notDownloaded
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.title3)
                            .foregroundColor(.orange)
                        Text("Réessayer")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                .buttonStyle(.plain)

                // Allow cleanup of failed model files to free disk space
                Button {
                    modelManager.cleanupFailedModel(model.identifier)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .help(message)
        }
    }
}

#Preview {
    NavigationStack {
        ModelManagerView(modelManager: ModelManager())
    }
}
