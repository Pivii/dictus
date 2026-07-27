// DictusApp/Views/ModelCardView.swift
// Individual model card with gauges, engine badge, and tap-to-select/download interaction.
import SwiftUI
import DictusCore

/// Displays a single model's metadata and state-dependent controls inside a glass card.
///
/// WHY a separate view (not inline in ForEach):
/// Each model card has complex layout (4 rows) and interaction logic (download, select,
/// delete, progress, error states). Extracting keeps ModelManagerView's body clean and
/// makes each card independently previewable.
///
/// INTERACTION MODEL (v2 — tap-to-act):
/// The entire card is a single tappable surface. Behavior depends on model state:
/// - .ready + not active -> select as active model
/// - .notDownloaded -> start download
/// - .error -> cleanup and retry
/// - .downloading / .prewarming -> card disabled (no tap)
///
/// WHY no separate buttons:
/// Removing "Choisir", download arrow, and trash buttons simplifies the UI.
/// Cards behave like native radio buttons — tap to select. Deletion uses
/// swipe-to-delete in the parent ModelManagerView (like iOS Mail), plus an
/// explicit overflow menu on downloaded cards (issue #193) because the rich
/// card design does not signal that swipe actions exist.
///
/// LAYOUT (top to bottom):
/// Row 1: displayName + engine badge ("WK"/"PK") + optional "Recommended" badge
/// Row 2: Short localized description
/// Row 3: Two gauge bars side-by-side (Accuracy in blue, Speed in blue highlight)
/// Row 4: Size label + state-dependent status indicator
struct ModelCardView: View {
    let model: ModelInfo
    @ObservedObject var modelManager: ModelManager
    let onDownloadError: (String) -> Void

    /// Called when the user asks to delete this model from the overflow menu
    /// (issue #193). The parent owns the confirmation alert so the menu and
    /// swipe-to-delete share the exact same deletion path. Nil hides the menu
    /// (e.g. cards in the "Available" section or the onboarding flow).
    var onDeleteRequest: (() -> Void)? = nil

    /// Tap-target padding around the ellipsis glyph and trailing space the
    /// badge row reserves for it. Scaled with Dynamic Type (relative to the
    /// glyph's .title3 font) so badges never slide under the button and the
    /// enlarged menu hit area never eats card taps at accessibility sizes.
    @ScaledMetric(relativeTo: .title3) private var overflowTapPadding: CGFloat = 12
    @ScaledMetric(relativeTo: .title3) private var overflowReservedWidth: CGFloat = 32

    /// The current state for this model, with a safe default.
    private var state: ModelState {
        modelManager.modelStates[model.identifier] ?? .notDownloaded
    }

    /// Whether this model is the currently active one.
    private var isActive: Bool {
        modelManager.activeModel == model.identifier
    }

    /// Whether the card should be tappable (disabled during download/prewarming).
    private var isCardDisabled: Bool {
        switch state {
        case .downloading, .prewarming:
            return true
        default:
            return false
        }
    }

    /// Whether the overflow menu is visible. Only downloaded (.ready) cards
    /// show it, and only when the parent provided a delete handler.
    ///
    /// WHY only .ready:
    /// During download/prewarming the card is busy and deletion would race the
    /// file operations; error cards already expose a retry/cleanup tap.
    private var showsOverflowMenu: Bool {
        guard onDeleteRequest != nil else { return false }
        if case .ready = state { return true }
        return false
    }

    /// Whether this model can actually be deleted right now.
    /// Mirrors the swipe-to-delete rules in ModelManagerView: never the active
    /// model, never the last downloaded one.
    private var canDeleteModel: Bool {
        !isActive && modelManager.downloadedModels.count > 1
    }

    var body: some View {
        Button {
            handleCardTap()
        } label: {
            cardContent
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.95))
        .disabled(isCardDisabled)
        // Overflow menu lives in an overlay OUTSIDE the Button label:
        // interactive controls nested inside a Button label never receive
        // taps (the whole label belongs to the button), so the menu must sit
        // above the card in the view hierarchy to be tappable.
        .overlay(alignment: .topTrailing) {
            if showsOverflowMenu {
                overflowMenu
            }
        }
    }

    // MARK: - Overflow menu (issue #193)

    /// Explicit, always-visible entry point for model deletion so users don't
    /// need to discover the swipe gesture. When deletion is blocked (active or
    /// last model) the menu explains why instead of silently hiding the action.
    private var overflowMenu: some View {
        Menu {
            if canDeleteModel {
                Button(role: .destructive) {
                    onDeleteRequest?()
                } label: {
                    Label("Delete Model", systemImage: "trash")
                }
            } else if modelManager.downloadedModels.count <= 1 {
                // Last-model case must win over the active case: a lone
                // downloaded model is auto-activated by ModelManager, so
                // checking isActive first would show "select another model"
                // when there is no other model to select. This is also the
                // only rule ModelManager.deleteModel actually enforces.
                Button("At least one model must stay on your device") { }
                    .disabled(true)
            } else {
                // Disabled explanatory row: the active model cannot be
                // deleted, dictation would be left without a model.
                Button("Select another model to delete this one") { }
                    .disabled(true)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                // Generous padding enlarges the tap target toward ~44pt.
                .padding(overflowTapPadding)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Model options")
    }

    // MARK: - Card content

    private var cardContent: some View {
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
                    Text("Recommended")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.dictusAccent.opacity(0.15))
                        .foregroundColor(.dictusAccent)
                        .cornerRadius(4)
                }
            }
            // Reserve room for the overlaid ellipsis button so badges never
            // slide underneath it on narrow screens.
            .padding(.trailing, showsOverflowMenu ? overflowReservedWidth : 0)

            // Row 2: Localized description
            Text(model.localizedDescription)
                .font(.dictusCaption)
                .foregroundStyle(.secondary)

            // Row 3: Gauge bars OR full-width progress during download/prewarming
            if case .downloading = state, let progress = modelManager.downloadProgress[model.identifier] {
                // Full-width progress bar replaces gauges during download
                VStack(spacing: 4) {
                    ProgressView(value: progress, total: 1.0)
                        .tint(.dictusAccent)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else if case .prewarming = state {
                // Full-width indeterminate progress during CoreML compilation
                VStack(spacing: 4) {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                    Text("Optimizing...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Normal gauge bars (Accuracy + Speed) — both blue palette
                HStack(spacing: 16) {
                    GaugeBarView(
                        value: model.accuracyScore,
                        label: "Accuracy",
                        color: .dictusAccent
                    )

                    GaugeBarView(
                        value: model.speedScore,
                        label: "Speed",
                        color: .dictusAccentHighlight
                    )
                }
            }

            // Row 4: Size + state-dependent status indicator
            HStack {
                Label(model.sizeLabel, systemImage: "internaldrive")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)

                Spacer()

                trailingContent
            }
        }
        .padding(16)
        .background(
            Group {
                if isActive {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.dictusAccent.opacity(0.10))
                }
            }
        )
        .dictusGlass()
        .overlay(
            // Active model gets a dark blue border stroke on top of glass
            Group {
                if isActive {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.dictusAccent.opacity(0.6), lineWidth: 2)
                }
            }
        )
    }

    // MARK: - Tap handler

    /// Routes card tap based on current model state.
    ///
    /// WHY a function instead of inline closure:
    /// Multiple state branches with different async/sync behavior.
    /// A named function keeps the Button action clean and testable.
    private func handleCardTap() {
        switch state {
        case .ready:
            if !isActive {
                modelManager.selectModel(model.identifier)
            }
        case .notDownloaded:
            Task {
                do {
                    try await modelManager.downloadModel(model.identifier)
                } catch {
                    onDownloadError(error.localizedDescription)
                }
            }
        case .error:
            modelManager.cleanupFailedModel(model.identifier)
        case .downloading, .prewarming:
            // Card is disabled in these states — this shouldn't fire
            break
        }
    }

    // MARK: - State-dependent trailing content

    /// The trailing content changes based on the model's current state.
    /// Now shows status indicators only (no action buttons — the card itself is the button).
    @ViewBuilder
    private var trailingContent: some View {
        switch state {
        case .notDownloaded:
            // Subtle download hint icon
            Image(systemName: "arrow.down.circle")
                .font(.title2)
                .foregroundColor(.dictusAccent)

        case .downloading:
            // Progress is shown full-width in card body (Row 3)
            EmptyView()

        case .prewarming:
            // Progress is shown full-width in card body (Row 3)
            EmptyView()

        case .ready:
            // No checkmark, no button — active state shown via background tint + border
            EmptyView()

        case .error(let message):
            VStack(spacing: 2) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text("Retry")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
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
                onDownloadError: { _ in }
            )
        }
        .padding()
    }
    .background(Color.dictusBackground)
}
