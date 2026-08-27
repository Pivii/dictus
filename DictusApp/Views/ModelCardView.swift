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
/// - .error -> relaunch the download in place (issue #235)
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

    /// Why this device cannot run the model, or nil when it can (issue #369).
    /// Non-nil greys the card out, drops its download control, and prints the
    /// reason under the description. Defaults to nil so the Downloaded section
    /// and the onboarding card keep their existing call sites untouched.
    var incompatibilityReason: ModelInfo.IncompatibilityReason?

    /// Called when the user asks to delete this model from the overflow menu
    /// (issue #193). The parent owns the confirmation alert so the menu and
    /// swipe-to-delete share the exact same deletion path. Nil hides the menu
    /// (e.g. cards in the "Available" section or the onboarding flow).
    var onDeleteRequest: (() -> Void)?

    /// Called when the user asks to delete the kept files of a FAILED download
    /// from the overflow menu (issue #235). Separate from `onDeleteRequest`
    /// because the cleanup path differs (cleanupFailedModel, not deleteModel)
    /// and the `.ready` deletion rules (never active, never last) do not apply:
    /// a partial download is never active or usable. The parent owns the
    /// confirmation alert, mirroring the #193 pattern.
    var onDeletePartialRequest: (() -> Void)?

    /// Tap-target padding around the ellipsis glyph and trailing space the
    /// badge row reserves for it. Scaled with Dynamic Type (relative to the
    /// glyph's .title3 font) so badges never slide under the button and the
    /// enlarged menu hit area never eats card taps at accessibility sizes.
    @ScaledMetric(relativeTo: .title3) private var overflowTapPadding: CGFloat = 12
    // 44pt per control: ~20pt .title3 glyph + 12pt tap padding on each side.
    @ScaledMetric(relativeTo: .title3) private var overflowReservedWidth: CGFloat = 44

    /// Presents the supported-languages detail sheet (issue #240).
    /// Card-local state: each card owns its own sheet, which keeps the
    /// parent Downloaded/Available sections free of per-model plumbing and
    /// automatically covers deprecated models shown in "Downloaded".
    @State private var showsLanguageInfo = false

    /// The current state for this model, with a safe default.
    private var state: ModelState {
        modelManager.modelStates[model.identifier] ?? .notDownloaded
    }

    /// Whether this model is the currently active one.
    private var isActive: Bool {
        modelManager.activeModel == model.identifier
    }

    /// Whether the card should be tappable (disabled during download/prewarming,
    /// and permanently when the device cannot run the model — issue #369).
    private var isCardDisabled: Bool {
        if incompatibilityReason != nil { return true }
        switch state {
        case .downloading, .prewarming:
            return true
        default:
            return false
        }
    }

    /// Whether the overflow menu is visible. Shown on downloaded (.ready) cards
    /// and on failed-download (.error) cards, each gated on the parent having
    /// provided the matching handler.
    ///
    /// WHY .ready and .error only:
    /// During download/prewarming the card is busy and deletion would race the
    /// file operations. Error cards need the menu since issue #235: the card
    /// tap now retries the download in place, so the full reset (delete kept
    /// files) moved from the tap to an explicit destructive menu entry.
    private var showsOverflowMenu: Bool {
        switch state {
        case .ready:
            return onDeleteRequest != nil
        case .error:
            return onDeletePartialRequest != nil
        default:
            return false
        }
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
        // Issue #369: recess an incompatible card rather than hiding it. Opacity
        // over the finished glass card keeps the Liquid Glass language already in
        // this file instead of introducing a second disabled style; `.disabled`
        // above is what actually blocks interaction, this only signals it.
        .opacity(incompatibilityReason == nil ? 1 : 0.55)
        // VoiceOver reads the disabled state from `.disabled` ("dimmed"); the hint
        // carries the reason, which the visual row shows as text.
        .accessibilityHint(incompatibilityReason.map { Text($0.localizedText) } ?? Text(""))
        // Overflow menu and language-info button live in an overlay OUTSIDE
        // the Button label: interactive controls nested inside a Button label
        // never receive taps (the whole label belongs to the button), so both
        // must sit above the card in the view hierarchy to be tappable.
        .overlay(alignment: .topTrailing) {
            // WHY spacing 0: each control carries its own scaled tap padding
            // (overflowTapPadding), which already provides ~44pt targets and
            // the visual gap between the two glyphs.
            //
            // WHY ⓘ is the OUTERMOST (trailing) element (design round,
            // issue #240): the info button exists on every card state, so
            // anchoring it at the corner keeps it at the exact same position
            // whether or not the state-dependent overflow menu is present.
            // The menu slides in to its left instead of pushing ⓘ around.
            HStack(spacing: 0) {
                if showsOverflowMenu {
                    overflowMenu
                }
                languageInfoButton
            }
        }
        // Supported-languages detail sheet (issue #240). Attached to the card
        // (not the parent list) so every card — Downloaded, Available, and
        // deprecated models — exposes it without extra wiring.
        .sheet(isPresented: $showsLanguageInfo) {
            ModelLanguageDetailView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Language info button (issue #240)

    /// Unobtrusive ⓘ entry point for the per-model supported-languages sheet.
    /// Visible in every model state: language coverage is useful before
    /// downloading, while downloading, and on error/deprecated cards alike.
    /// Styled identically to the overflow glyph so the top-trailing controls
    /// read as one cluster.
    private var languageInfoButton: some View {
        Button {
            showsLanguageInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                // Generous padding enlarges the tap target toward ~44pt.
                .padding(overflowTapPadding)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Supported languages")
    }

    // MARK: - Overflow menu (issue #193)

    /// Explicit, always-visible entry point for model deletion so users don't
    /// need to discover the swipe gesture. When deletion is blocked (active or
    /// last model) the menu explains why instead of silently hiding the action.
    private var overflowMenu: some View {
        Menu {
            if case .error = state {
                // Issue #235: full reset for a failed download. Frees the kept
                // files (the resume cache) and returns the card to "Available".
                // The .ready rules (never active, never last) deliberately do
                // NOT gate this entry — a partial download is never usable.
                Button(role: .destructive) {
                    onDeletePartialRequest?()
                } label: {
                    Label("Delete partial download", systemImage: "trash")
                }
            } else if canDeleteModel {
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
            // Reserve room for the overlaid top-trailing controls so badges
            // never slide underneath them on narrow screens. The ⓘ button is
            // always present (one width); the ellipsis menu adds a second.
            .padding(.trailing, showsOverflowMenu ? overflowReservedWidth * 2 : overflowReservedWidth)

            // Row 2: Localized description
            Text(model.localizedDescription)
                .font(.dictusCaption)
                .foregroundStyle(.secondary)

            // Row 2b (issue #369): why this device cannot run the model. Sits
            // directly under the description so the reason reads as part of the
            // model's identity, not as an error banner bolted onto the card.
            if let incompatibilityReason {
                Label(incompatibilityReason.localizedText, systemImage: "exclamationmark.triangle")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
            }

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
        // Issue #369 acceptance criterion: a disabled row must not start a download
        // by ANY route. `.disabled` already blocks the tap; this guard also covers
        // an accessibility activation or any future call site that forgets to pass
        // the reason through to the modifier.
        guard incompatibilityReason == nil else { return }
        switch state {
        case .ready:
            if !isActive {
                modelManager.selectModel(model.identifier)
            }
        case .notDownloaded, .error:
            // Issue #235: .error shares the .notDownloaded path so tapping
            // "Retry" relaunches the download in place. Both engine paths keep
            // completed files after a download failure (issue #210 resume
            // policy) and ModelRepoDownloader skips files already on disk, so
            // this resumes instead of restarting from zero. A second failure
            // lands back in .error through downloadModel's own catch blocks.
            // The old behavior (cleanupFailedModel) wiped the kept files and
            // moved the card to "Available" — that full reset now lives in the
            // overflow menu's "Delete partial download" entry.
            Task {
                do {
                    try await modelManager.downloadModel(model.identifier)
                } catch {
                    onDownloadError(error.localizedDescription)
                }
            }
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
            // No download hint icon (design round, issue #240): the
            // "Available" section already communicates downloadability and
            // the whole card is the tap target, so the arrow was redundant
            // and clashed visually with the corner-anchored info button.
            EmptyView()

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
