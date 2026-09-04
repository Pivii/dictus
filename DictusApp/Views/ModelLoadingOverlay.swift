// DictusApp/Views/ModelLoadingOverlay.swift
// Full-screen blocking overlay shown while a model is downloading, compiling
// for the Neural Engine, or being loaded into RAM. Issue #144.
import SwiftUI
import DictusCore

/// Full-screen cover that surfaces long-running model preparation work to the user.
///
/// Why this exists:
/// Whisper turbo (~645 MB) takes about three and a half minutes of one-off Core ML
/// compilation on a 15 Pro Max, and a couple of seconds to load into RAM every time
/// after that. The "~2 min" figure this comment used to quote was never measured on
/// this variant at all — it described the ~954 MB one issue #408 replaced. Four cold
/// readings of the current variant now live in `ModelInfo.firstPreparationSeconds`,
/// which is where the number belongs. Without a blocking UI the user could mistake
/// the wait for a frozen app, tap the keyboard mic mid-load, and trigger a
/// `Swift.CancellationError` cascade (issue #144). The overlay refuses any further
/// model interaction until `modelLoadState == .ready`.
///
/// Refusing to let the user act made it this screen's job to SAY how long the wait is
/// (issue #432). The maintainer sat through a Turbo preparation and could not tell a
/// normal wait from a stuck app, which is the correct reading of a screen that names
/// no duration and looks identical for a model that is ready in thirty seconds.
/// `firstPreparationNotice` is that sentence, and it stays a sentence: Core ML reports
/// no progress for a compile, which is why there is a bar under the download and
/// nothing under the compile.
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

    /// Set when the load ended because the app STOPPED WAITING for it, rather than
    /// because it finished (third review, finding D).
    ///
    /// Both outcomes leave `modelLoadState == .idle`, and `rawPhase` maps a downloaded
    /// model plus `.idle` to `.ready` — so a deadline expiring with this screen up, the
    /// keyboard-cold-start case issue #428 exists for, showed the user the "Model ready"
    /// checkmark while the compile was still running and no engine was loaded. The
    /// reason travels on the notification that already drives this screen.
    @State private var loadGaveUp = false

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
                BrandWaveform(maxHeight: 100, animation: .sweep)
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
        .onReceive(NotificationCenter.default.publisher(for: .dictusModelLoadStateChanged)) { note in
            if let reason = note.userInfo?["reason"] as? String,
               ModelPreparationOutcome.reasonMeansGaveUp(reason) {
                loadGaveUp = true
            }
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

            if let completionInstruction {
                Text(completionInstruction)
                    .font(.dictusCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    /// What the user does next, once the model is ready.
    ///
    /// Only the two prepare-only contexts have anything to say here: they are the ones reached
    /// from a tap that deliberately does NOT become a recording, so the screen owes the user
    /// the action that does. Which sentence is a question about where they came from, not
    /// about the prepare-only rule — hence `startedFromAnotherApp` and not `isPrepareOnly`
    /// (#484). Onboarding and model selection dismiss into the screen the user was already on.
    private var completionInstruction: LocalizedStringKey? {
        switch activeContext {
        case .onboarding, .modelSelection:
            return nil
        case .keyboardColdStart:
            return "Return to your app and tap the microphone again."
        case .appRecordTap:
            return "Tap again to start your dictation."
        }
    }

    private var stayOnPageNotice: some View {
        VStack(spacing: 8) {
            Text(explanationText)
                .font(.dictusCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // The one line that answers "how long am I here for" (issue #432).
            // Semibold rather than a colour or a larger size: it has to be the line
            // the eye lands on among three captions, and this screen deliberately
            // carries no alarm colour of any kind.
            if let firstPreparationNotice {
                Text(firstPreparationNotice)
                    .font(.dictusCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if !(showCompletion && activeContext.isPrepareOnly) {
                // WHICH OF THE TWO, and why it is not `isPrepareOnly` (#484): "stay on this
                // page" is only sayable to someone who is on it. The keyboard cold start
                // brings a user whose next move is to leave, so it asks for patience instead.
                // The in-app tap does not — and staying in the foreground is what keeps the
                // compile off the system's background throttle (#472), so it is the stronger
                // of the two sentences and the right one here.
                Text(activeContext.startedFromAnotherApp
                     ? "Please wait for preparation to finish."
                     : "Please stay on this page and do not leave the app.")
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
            // This used to read "This preparation may take a moment and is usually not
            // needed for every dictation". `firstPreparationNotice` now says both
            // halves better, and "a moment" was actively false for the model that made
            // issue #432 necessary.
            return "Dictus is preparing this model for offline dictation."
        case .keyboardColdStart:
            return "Your model needs to be prepared before this dictation. This is usually an exceptional step."
        case .appRecordTap:
            // Says out loud why the tap did nothing, which is the whole of #484: the button
            // used to swallow it in silence. The keyboard's wording cannot be reused as is —
            // it is written for someone who arrived from another app.
            return "Your dictation cannot start yet: Dictus is preparing your model. This is usually an exceptional step."
        }
    }

    /// How long this model's first preparation takes, said out loud (issue #432).
    ///
    /// WHY only under the compile and the load, and never under the download:
    /// those two phases are the ones with nothing moving on screen. The download has a
    /// bar and a byte counter that already answer "is this stuck", and its duration
    /// belongs to the network rather than to the model, so a sentence about the
    /// model's preparation shown there would be read as a claim about the download.
    ///
    /// WHY both of the other two, which took reading `rawPhase` to see: a
    /// download-then-prepare spends the compile in `.compiling`, but a launch that
    /// finds the model already on disk spends it in `.loading` — and that second case
    /// is the one issue #432 was filed from, an app opened after an install with Turbo
    /// active. Wording it as a fact about the model rather than about this particular
    /// wait keeps it true in the ordinary `.loading` case too, where the Core ML cache
    /// exists and the screen is gone in three seconds.
    private var firstPreparationNotice: String? {
        guard currentPhase == .compiling || currentPhase == .loading else { return nil }
        switch ModelPreparationWait.forModel(modelIdentifier) {
        case .minutes(let minutes):
            return String(localized: "The first preparation of this model takes about \(minutes) minutes. It happens only once, and later ones take a few seconds.")
        case .brief:
            return String(localized: "The first preparation of this model takes under a minute. It happens only once, and later ones take a few seconds.")
        case .unmeasured:
            // No number is invented for a model nobody has timed. The half of the
            // message that matters most is true of every model and is still said.
            return String(localized: "This preparation happens only once for this model. Later ones take a few seconds.")
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
            // These change every 2.5s (`CyclingLoadingText.interval`), so eight of them
            // come round about every 20s and a Turbo compile sees the list ten times
            // over. The comment that used to sit here claimed twelve phrases were
            // "enough variety so the copy doesn't visibly loop" within Turbo's window;
            // twelve never were either, at 30s a cycle against a compile of minutes.
            // Repetition is not the problem worth solving here. The duration is, and
            // `firstPreparationNotice` is what answers it (issue #432).
            //
            // WHAT IS GONE and why: every phrase that promised imminence. "Almost
            // ready…" and "A few more seconds…" arriving on a 2.5s loop for three and a
            // half minutes are the copy version of the bug in issue #432 — they tell a
            // waiting user the end is near, over and over, while it is not — and they
            // would now contradict a line directly underneath naming four minutes.
            return [
                String(localized: "Preparing the model…"),
                String(localized: "Optimizing for your iPhone…"),
                String(localized: "Setting up offline transcription…"),
                String(localized: "Adapting the model to your iPhone…"),
                String(localized: "Configuring voice transcription…"),
                String(localized: "Getting Dictus ready…"),
                String(localized: "Setting up the transcription engine…"),
                String(localized: "Checking the model…")
            ]
        case .loading:
            // A load that finds the Core ML cache is over in seconds, so this list is
            // short on purpose. It drops the same two imminence phrases ("Almost
            // ready…", "One last step…") for a sharper reason than the compile list
            // does: the first launch after any install has no cache, so this phase and
            // not `.compiling` is where the maintainer's three and a half minutes were
            // actually spent (issue #432). It borrows a compile phrase rather than
            // inventing a new one.
            return [
                String(localized: "Loading the model…"),
                String(localized: "Preparing dictation…"),
                String(localized: "Getting transcription ready…"),
                String(localized: "Setting up the transcription engine…")
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

        // Nothing to celebrate: the app gave up on this load, the compile is still
        // running, and no engine arrived. Leave without the checkmark (finding D).
        guard !loadGaveUp else {
            isPresented = false
            return
        }

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
            m.modelStates["openai_whisper-large-v3-v20240930_turbo_632MB"] = .downloading
            m.downloadProgress["openai_whisper-large-v3-v20240930_turbo_632MB"] = 0.42
            return m
        }(),
        modelIdentifier: "openai_whisper-large-v3-v20240930_turbo_632MB",
        isPresented: .constant(true)
    )
    .preferredColorScheme(.light)
}

#Preview("Compiling — dark") {
    ModelLoadingOverlay(
        modelManager: {
            let m = ModelManager()
            m.modelStates["openai_whisper-large-v3-v20240930_turbo_632MB"] = .prewarming
            return m
        }(),
        modelIdentifier: "openai_whisper-large-v3-v20240930_turbo_632MB",
        isPresented: .constant(true)
    )
    .preferredColorScheme(.dark)
}
