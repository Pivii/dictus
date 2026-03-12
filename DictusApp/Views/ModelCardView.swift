// DictusApp/Views/ModelCardView.swift
// Individual model card with gauges, engine badge, and state controls.
import SwiftUI
import DictusCore

/// Displays a single model's metadata and state-dependent controls inside a glass card.
///
/// WHY a separate view (not inline in ForEach):
/// Each model card has complex layout (4 rows) and interaction logic (download, select,
/// delete, progress, error states). Extracting keeps ModelManagerView's body clean and
/// makes each card independently previewable.
///
/// LAYOUT (top to bottom):
/// Row 1: displayName + engine badge ("WK"/"PK") + optional "Recommande" badge
/// Row 2: Short French description
/// Row 3: Two gauge bars side-by-side (Precision in blue, Vitesse in green)
/// Row 4: Size label + state-dependent trailing content
struct ModelCardView: View {
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
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Name + engine badge + recommended badge
            HStack(spacing: 6) {
                Text(model.displayName)
                    .font(.dictusSubheading)

                // Engine badge pill (e.g. "WK" or "PK")
                Text(model.engine.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.dictusAccent)
                    .foregroundColor(.white)
                    .cornerRadius(4)

                if modelManager.isRecommended(model.identifier) {
                    Text("Recommande")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.dictusAccent.opacity(0.15))
                        .foregroundColor(.dictusAccent)
                        .cornerRadius(4)
                }
            }

            // Row 2: French description
            Text(model.description)
                .font(.dictusCaption)
                .foregroundStyle(.secondary)

            // Row 3: Gauge bars (Precision + Vitesse)
            HStack(spacing: 16) {
                GaugeBarView(
                    value: model.accuracyScore,
                    label: "Precision",
                    color: .dictusAccent
                )

                GaugeBarView(
                    value: model.speedScore,
                    label: "Vitesse",
                    color: .dictusSuccess
                )
            }

            // Row 4: Size + state-dependent controls
            HStack {
                Label(model.sizeLabel, systemImage: "internaldrive")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)

                Spacer()

                trailingContent
            }
        }
        .padding(16)
        .dictusGlass()
    }

    // MARK: - State-dependent trailing content

    /// The trailing content changes based on the model's current state.
    ///
    /// WHY @ViewBuilder:
    /// Swift's opaque return types require a single concrete type. @ViewBuilder
    /// lets us return different view types from each switch case using SwiftUI's
    /// conditional content builder.
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
                    .foregroundColor(.dictusAccent)
            }
            .buttonStyle(.plain)

        case .downloading:
            // WHY if-let instead of ?? 0:
            // Defensive fallback — if downloadProgress is nil (removed before state
            // transitions to .prewarming), show an indeterminate spinner instead of
            // a determinate bar stuck at 0%.
            if let progress = modelManager.downloadProgress[model.identifier] {
                VStack(spacing: 2) {
                    ProgressView(value: progress, total: 1.0)
                        .frame(width: 60)
                        .tint(.dictusAccent)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
            }

        case .prewarming:
            VStack(spacing: 2) {
                ProgressView()
                Text("Optimisation en cours...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            if isActive {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.dictusSuccess)
                    Text("Actif")
                        .font(.dictusCaption)
                        .foregroundColor(.dictusSuccess)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Choisir") {
                        modelManager.selectModel(model.identifier)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.dictusAccent)

                    if !isLastModel {
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.dictusRecording)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        case .error(let message):
            Button {
                // Clean up corrupted/partial files before resetting state.
                // cleanupFailedModel already sets state to .notDownloaded.
                modelManager.cleanupFailedModel(model.identifier)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.title3)
                        .foregroundColor(.orange)
                    Text("Reessayer")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            .buttonStyle(.plain)
            .help(message)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ModelCardView(
                model: ModelInfo.all[0],
                modelManager: ModelManager(),
                onDelete: {},
                onDownloadError: { _ in }
            )
        }
        .padding()
    }
    .background(Color.dictusBackground)
}
