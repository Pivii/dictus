// DictusApp/Views/ModelLoadingOverlay.swift
// Full-screen blocking overlay shown while a model is downloading, compiling
// for the Neural Engine, or being loaded into RAM. Issue #144.
import SwiftUI
import DictusCore

/// Full-screen cover that surfaces long-running model preparation work to the user.
///
/// Why this exists:
/// Whisper turbo (~954 MB) takes ~2 min of one-off Core ML compilation on a 15 Pro Max
/// and a couple of seconds to load into RAM after each cold start. Without a blocking UI
/// the user could mistake the wait for a frozen app, tap the keyboard mic mid-load,
/// and trigger a `Swift.CancellationError` cascade (issue #144). The overlay refuses
/// any further model interaction until `modelLoadState == .ready`.
///
/// The overlay observes two signals to decide which copy to show:
/// 1. `ModelManager.modelStates[id]` — `.downloading`, `.prewarming`, `.ready`
/// 2. `ModelManager.modelLoadState` (mirrored from the App Group via Combine) —
///    `.loading` once `DictationCoordinator.preloadActiveModel` is in flight.
struct ModelLoadingOverlay: View {
    @ObservedObject var modelManager: ModelManager

    /// Identifier of the model the user just acted on (download or select).
    /// Drives the phase logic and which copy is shown.
    let modelIdentifier: String

    /// Two-way binding controlled by the parent. The overlay flips it to false
    /// once the model becomes ready so the cover dismisses itself.
    @Binding var isPresented: Bool

    /// The user-facing flow that caused preparation to be shown.
    let context: ModelPreparationContext

    @State private var showCompletion = false
    @State private var activeContext: ModelPreparationContext

    /// Tracks whether we have ever observed an active prep phase (downloading,
    /// compiling, or loading). Without this, the overlay would auto-dismiss
    /// when presented synchronously by the parent before `downloadModel`
    /// has had a chance to flip `modelStates[id]` from `.notDownloaded` to
    /// `.downloading` — the onboarding race that surfaced after f5ba7ab.
    @State private var hasSeenWorkPhase = false

    private enum Phase {
        case downloading
        case compiling
        case loading
        case ready
    }

    init(
        modelManager: ModelManager,
        modelIdentifier: String,
        context: ModelPreparationContext = .modelSelection,
        isPresented: Binding<Bool>
    ) {
        self.modelManager = modelManager
        self.modelIdentifier = modelIdentifier
        self.context = context
        self._isPresented = isPresented
        self._activeContext = State(initialValue: context)
    }

    var body: some View {
        ZStack {
            // Adaptive brand background — auto switches between light/dark
            // (#F2F2F7 in light, #0A1628 in dark).
            Color.dictusBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                modelTitleHeader
                    .padding(.top, 24)

                Spacer()

                // Waveform lives in the vertical flow, ABOVE the progress area.
                // It used to be a ZStack background centered on the screen, which
                // collided with the (also centered) progress bar on squat aspect
                // ratios — iPad letterboxed compatibility mode, iPhone SE. Same
                // height/opacity as the onboarding welcome screen; edge-to-edge
                // width, no horizontal padding.
                BrandWaveform(maxHeight: 100, isProcessing: true)
                    .opacity(0.55)
                    .allowsHitTesting(false)

                // Fixed-height swap area so toggling between active and completion
                // states doesn't reflow the surrounding layout (and shift the
                // waveform above).
                ZStack {
                    if showCompletion {
                        completionView
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    } else {
                        activeView
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: activeContext.isPrepareOnly ? 164 : 140)
                .padding(.top, 24)

                Spacer()

                stayOnPageNotice
                    .padding(.bottom, 40)
            }
        }
        .interactiveDismissDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: .dictusModelLoadStateChanged)) { _ in
            checkForCompletion()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dictusKeyboardPreparationRequested)) { _ in
            activeContext = .keyboardColdStart
        }
        .onChange(of: currentModelState) { _, _ in
            checkForCompletion()
        }
        .onAppear {
            checkForCompletion()
        }
    }

    // MARK: - Sub-views

    private var modelTitleHeader: some View {
        // Tracking value used on the phase label. Pulled out so the leading
        // compensation padding stays in sync — `.tracking()` adds half its width
        // of trailing space after the last character, which shifts the optical
        // center off relative to the un-tracked model name above. We add the
        // same width as a leading offset to push the label back to true center.
        let labelTracking: CGFloat = 1.4

        return VStack(spacing: 8) {
            if let info = ModelInfo.forIdentifier(modelIdentifier) {
                Text(info.displayName)
                    .font(.dictusSubheading)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            Text(phaseLabel)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.dictusAccent)
                .tracking(labelTracking)
                .padding(.leading, labelTracking)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var activeView: some View {
        VStack(spacing: 24) {
            if currentPhase == .downloading,
               let progress = modelManager.downloadProgress[modelIdentifier] {
                VStack(spacing: 6) {
                    ProgressView(value: Double(progress), total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.dictusAccent)
                        .frame(maxWidth: 240)
                    Text("\(Int(progress * 100)) %")
                        .font(.dictusCaption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    // Moving byte counter — reads as alive even while the
                    // percentage crawls through the 445 MB Encoder file (#207).
                    if let bytes = modelManager.downloadByteInfo[modelIdentifier] {
                        Text("\(bytes.downloadedMB) MB of \(bytes.totalMB) MB")
                            .font(.dictusCaption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            CyclingLoadingText(phrases: phrases(for: currentPhase))
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.dictusAccent)
            Text("Model ready")
                .font(.dictusSubheading)
                .foregroundStyle(.primary)

            if activeContext.isPrepareOnly {
                Text("Return to your app and tap the microphone again.")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var stayOnPageNotice: some View {
        VStack(spacing: 8) {
            Text(explanationText)
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !(showCompletion && activeContext.isPrepareOnly) {
                Text(activeContext.isPrepareOnly
                     ? "Please wait for preparation to finish."
                     : "Please stay on this page — do not leave the app.")
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
        }
    }

    private var explanationText: LocalizedStringKey {
        switch activeContext {
        case .onboarding:
            return "Dictus prepares your transcription model for offline dictation."
        case .modelSelection:
            return "This preparation may take a moment and is usually not needed for every dictation."
        case .keyboardColdStart:
            return "Your model needs to be prepared before this dictation. This is usually an exceptional step."
        }
    }

    // MARK: - Phase logic

    private var currentModelState: ModelState {
        modelManager.modelStates[modelIdentifier] ?? .notDownloaded
    }

    private var currentPhase: Phase {
        let raw = rawPhase
        // While we have not yet seen a real work phase, treat `.ready` as the
        // initial download phase so the copy doesn't briefly flash "ready"
        // before the parent's async download Task starts. This is the seam
        // that fixes the onboarding presentation race (commit f5ba7ab follow-up).
        if !hasSeenWorkPhase && raw == .ready {
            return .downloading
        }
        return raw
    }

    private var rawPhase: Phase {
        switch currentModelState {
        case .downloading:
            return .downloading
        case .prewarming:
            return .compiling
        case .ready:
            switch modelManager.modelLoadState {
            case .loading:
                return .loading
            case .ready:
                return .ready
            case .idle:
                // Defensive: model is ready on disk but no load is in flight.
                // Treat as ready so the overlay can dismiss.
                return .ready
            }
        case .notDownloaded, .error:
            return .ready
        }
    }

    private var phaseLabel: LocalizedStringKey {
        switch currentPhase {
        case .downloading: return "Downloading"
        case .compiling: return "Optimizing"
        case .loading: return "Loading"
        case .ready: return "Ready"
        }
    }

    private func phrases(for phase: Phase) -> [String] {
        switch phase {
        case .downloading:
            return [
                String(localized: "Downloading the model…"),
                String(localized: "Preparing the files…"),
                String(localized: "Getting everything ready…"),
                String(localized: "Almost there…"),
                String(localized: "Finishing the download…")
            ]
        case .compiling:
            // Turbo's compile takes ~2 minutes — needs enough variety so the
            // copy doesn't visibly loop within that window.
            return [
                String(localized: "Preparing the model…"),
                String(localized: "Optimizing for your iPhone…"),
                String(localized: "Setting up offline transcription…"),
                String(localized: "Adapting the model to your iPhone…"),
                String(localized: "Configuring voice transcription…"),
                String(localized: "Preparing the final steps…"),
                String(localized: "Getting Dictus ready…"),
                String(localized: "Setting up the transcription engine…"),
                String(localized: "Checking the model…"),
                String(localized: "Almost ready…"),
                String(localized: "A few more seconds…"),
                String(localized: "Finishing the preparation…")
            ]
        case .loading:
            return [
                String(localized: "Loading the model…"),
                String(localized: "Preparing dictation…"),
                String(localized: "Getting transcription ready…"),
                String(localized: "Almost ready…"),
                String(localized: "One last step…")
            ]
        case .ready:
            return []
        }
    }

    private func checkForCompletion() {
        // A failed download must dismiss the cover immediately — without this,
        // `.error` falls into rawPhase's `.ready` mapping below and flashes the
        // "Model ready" celebration on a failure (issue #207). The parent view
        // surfaces the error message once the cover is gone.
        if case .error = currentModelState {
            isPresented = false
            return
        }
        // Latch the work-phase flag the first time we observe real activity.
        // We read `rawPhase` here (not the user-facing `currentPhase`) because
        // the latter masquerades the initial `.ready` state as `.downloading`
        // until this flag flips, which would cause an infinite loop.
        if rawPhase != .ready {
            hasSeenWorkPhase = true
            return
        }
        // The model is ready, but if we have never seen any actual work happen
        // yet, the parent likely just opened the overlay and the state will
        // imminently flip to `.downloading`. Keep the cover up.
        let preparationWasAlreadyReady = activeContext.isPrepareOnly
            && currentModelState == .ready
            && modelManager.modelLoadState == .ready
        guard hasSeenWorkPhase || preparationWasAlreadyReady else {
            return
        }
        guard !showCompletion else { return }

        withAnimation(.easeInOut(duration: 0.35)) {
            showCompletion = true
        }

        // Brief celebration moment before the cover slides away.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.4)) {
                isPresented = false
            }
        }
    }
}

#Preview("Downloading — light") {
    ModelLoadingOverlay(
        modelManager: {
            let m = ModelManager()
            m.modelStates["openai_whisper-large-v3_turbo_954MB"] = .downloading
            m.downloadProgress["openai_whisper-large-v3_turbo_954MB"] = 0.42
            return m
        }(),
        modelIdentifier: "openai_whisper-large-v3_turbo_954MB",
        isPresented: .constant(true)
    )
    .preferredColorScheme(.light)
}

#Preview("Compiling — dark") {
    ModelLoadingOverlay(
        modelManager: {
            let m = ModelManager()
            m.modelStates["openai_whisper-large-v3_turbo_954MB"] = .prewarming
            return m
        }(),
        modelIdentifier: "openai_whisper-large-v3_turbo_954MB",
        isPresented: .constant(true)
    )
    .preferredColorScheme(.dark)
}
