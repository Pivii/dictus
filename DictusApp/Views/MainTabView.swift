// DictusApp/Views/MainTabView.swift
// Root navigation container with 3 tabs and full-screen recording overlay.
import SwiftUI
import DictusCore

/// Root view presenting the 3-tab navigation structure.
///
/// WHY TabView instead of NavigationStack:
/// The app has 3 distinct sections (Home, Models, Settings) that the user should be able
/// to switch between freely. A TabView provides standard iOS navigation for this pattern.
/// Each tab wraps its content in its own NavigationStack so push navigation works
/// independently per tab.
///
/// WHY ZStack overlay for RecordingView:
/// When dictation is active, the recording UI must cover the entire screen INCLUDING
/// the tab bar. A ZStack overlay with ignoresSafeArea achieves this, while a sheet or
/// fullScreenCover would leave the tab bar visible underneath on some iOS versions.
struct MainTabView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @StateObject private var modelManager = ModelManager()

    @State private var selectedTab: Int = 0

    /// In-memory flag: true after the first URL has been handled in this process.
    /// Resets naturally when iOS terminates the process (true cold start).
    /// WHY static on MainTabView (not DictusApp): onOpenURL fires inner-to-outer in SwiftUI,
    /// so MainTabView's handler fires BEFORE DictusApp's. We need the detection here.
    private static var hasHandledURL = false

    /// Tracks whether the app was opened from the keyboard for cold start dictation.
    @State private var isColdStartMode: Bool

    /// Active model preparation shown without starting a recording. The overlay dismisses
    /// itself after its contextual ready state.
    ///
    /// Three of its four writers are URL-driven — the keyboard asking for `intent=prepare` —
    /// and the two of those that can fire while the process is already alive are gated on
    /// #458's rule below. `init`'s launch-intent seed is not: a process being launched has no
    /// dictation to interrupt. The fourth is `presentModelPreparation`, an in-app record tap
    /// that landed during a load (#484), which carries its own context and its own gate.
    ///
    /// WHY the model and the context travel together in one value: the overlay's copy is
    /// chosen from the context and names the model, so a context left behind by a previous
    /// presentation would put "Return to your app and tap the microphone again." in front of
    /// a user who never left Dictus. Storing them apart makes that a two-line mistake.
    @State private var preparation: PreparationPresentation?

    /// A preparation screen to show: which model, and why it is up.
    private struct PreparationPresentation: Equatable {
        let modelIdentifier: String
        let context: ModelPreparationContext
    }

    /// The paywall, opened from the keyboard (#404).
    ///
    /// WHY here and not in `SettingsView`, which owns the other two entry points: a
    /// `dictus://open?intent=pro` URL is answered by whichever view is in the tree, and
    /// `SettingsView` only is when the Settings tab is selected. `paywallCover` is
    /// documented as *"one way to open the paywall, shared by every entry point"*, and
    /// a cover presented here covers the tab bar as well, so which tab the user lands
    /// on stops mattering.
    @State private var showsPaywall = false

    @Environment(\.scenePhase) private var scenePhase

    /// Seeds the presentation state from the URL this process was launched with (issue #264).
    ///
    /// WHY in init rather than in `.onOpenURL`:
    /// SwiftUI evaluates `body` before any URL handler runs, so a cold start decided in
    /// `.onOpenURL` always rendered one frame of the home screen first. `ColdStartLaunch`
    /// reads the launch URL at scene connection, which happens before this view is built,
    /// so the very first frame is already the right one. Every other launch leaves the
    /// intent nil and lands on the tab navigation with nothing added to the path.
    init() {
        let launchIntent = ColdStartLaunch.intent
        _isColdStartMode = State(initialValue: launchIntent == .record)
        _preparation = State(
            initialValue: launchIntent == .prepare
                ? PreparationPresentation(
                    modelIdentifier: Self.persistedActiveModelIdentifier,
                    context: .keyboardColdStart
                )
                : nil
        )
    }

    /// The active model as persisted in the App Group, with the shipped default.
    /// Static so `init` can read it before `modelManager` exists — `ModelManager.init`
    /// loads `activeModel` from the same key, so both paths agree.
    private static var persistedActiveModelIdentifier: String {
        AppGroup.defaults.string(forKey: SharedKeys.activeModel) ?? "openai_whisper-small"
    }

    private var activeModelIdentifier: String {
        modelManager.activeModel ?? Self.persistedActiveModelIdentifier
    }

    var body: some View {
        ZStack {
            if let preparation {
                ModelLoadingOverlay(
                    modelManager: modelManager,
                    modelIdentifier: preparation.modelIdentifier,
                    context: preparation.context,
                    isPresented: Binding(
                        get: { self.preparation != nil },
                        set: { if !$0 { self.preparation = nil } }
                    )
                )
            } else if isColdStartMode {
                // Full-screen branded overlay with animated swipe gesture and bilingual text.
                // WHY SwipeBackOverlayView instead of inline code:
                // The overlay has its own animation state and bilingual logic -- keeping it
                // in a separate file follows "one file = one responsibility".
                SwipeBackOverlayView()
            } else {
                // Main tab navigation (normal launch path)
                TabView(selection: $selectedTab) {
                    // Tab 0: Home dashboard
                    NavigationStack {
                        HomeView(modelManager: modelManager)
                    }
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)

                    // Tab 1: Model management
                    NavigationStack {
                        ModelManagerView(modelManager: modelManager)
                    }
                    .tabItem {
                        Label("Models", systemImage: "cpu")
                    }
                    .tag(1)

                    // Tab 2: Settings
                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(2)
                }
                .tint(.dictusAccent)
            }

            // Full-screen recording overlay covers everything including tab bar.
            // WHY not shown in cold start mode: During cold start, the recording runs
            // in the background while the user sees the SwipeBackOverlayView. Showing
            // RecordingView would cover the swipe-back instructions.
            if coordinator.status != .idle && !isColdStartMode {
                RecordingView(mode: .standalone)
            }
        }
        // Detect cold start directly from URL params. MainTabView's onOpenURL fires
        // BEFORE DictusApp's (SwiftUI propagates inner-to-outer), so we can't rely
        // on DictusApp having set the AppGroup flag yet.
        //
        // A URL-launched cold start has already been answered in init, but this handler
        // still runs for it: it is what marks the URL handled, and re-asserting the same
        // state is a no-op. It remains the only path for every URL that arrives while the
        // process is already alive.
        .paywallCover(isPresented: $showsPaywall)
        .onOpenURL { url in
            // The keyboard's Pro entries (#241's panel pill, #404's fan row). Until
            // 2026-08-29 nothing routed on `dictus://open` at all, so both of them
            // brought the app forward on whatever screen it happened to be showing and
            // left the user to find the paywall — which empties a Pro row of its
            // purpose.
            //
            // Gated on `paywallVisible` on this side too (#236). The keyboard already
            // refuses to draw either entry while the flag is down, but the scheme is
            // public and the app must not be the half of the pair that trusts it.
            if KeyboardOpenURL.intent(from: url) == .pro {
                guard PremiumFlags.paywallVisible else { return }
                // Logged because the two halves of this live in different processes:
                // the keyboard records that it opened the URL, and this is the line
                // that says the app received it and answered.
                PersistentLog.log(.diagnosticProbe(
                    component: "paywall", instanceID: "0", action: "keyboardProIntent",
                    details: "source=keyboard"
                ))
                showsPaywall = true
                return
            }

            guard let intent = KeyboardDictationURL.intent(from: url) else { return }

            if intent == .prepare {
                // #458's rule applies here too. This overlay sits BELOW `RecordingView`
                // in the ZStack above, so it could never be what replaced the recording
                // screen — but raising it during a dictation would still leave the app
                // showing a preparation screen the moment the dictation ended.
                //
                // A prepare URL arrives because the keyboard refused a mic tap while a
                // load was in flight, so the app's own status is normally `.idle` here;
                // this guard is about the case where it is not.
                guard !ModelPreparationGate.dictationOwnsTheDisplay(coordinator.status) else {
                    return
                }
                preparation = PreparationPresentation(
                    modelIdentifier: activeModelIdentifier,
                    context: .keyboardColdStart
                )
                return
            }

            if !Self.hasHandledURL {
                // True cold start: process was just launched by keyboard URL.
                isColdStartMode = true
            } else if !coordinator.isEngineRunning {
                // Engine-dead restart: app is in memory but audio engine was stopped
                // (e.g., Power button in Dynamic Island). User needs the swipe-back
                // overlay to know how to return to their keyboard.
                isColdStartMode = true
            }
            Self.hasHandledURL = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .dictusKeyboardPreparationRequested)) { _ in
            // Gated for the same reason as the `.prepare` branch above, and gated with
            // it rather than instead of it: `DictusApp.handleIncomingURL` posts this
            // notification for the very same `dictate?…prepare` URL that handler sees,
            // so the two are one event and must not disagree about whether to answer it.
            guard !ModelPreparationGate.dictationOwnsTheDisplay(coordinator.status) else {
                return
            }
            preparation = PreparationPresentation(
                modelIdentifier: activeModelIdentifier,
                context: .keyboardColdStart
            )
        }
        // The fourth writer (#484): a record button inside the app, tapped while a model load
        // was in flight. The decision to present rather than to call `startDictation` was
        // already made at the button — `RecordTapRouting` in DictusCore, where it is tested —
        // so this handler only presents. It is installed on the ZStack rather than on the
        // TabView so `RecordingView`, a sibling and the second of the two buttons, sees it too.
        .environment(\.presentModelPreparation, PresentModelPreparationAction {
            preparation = PreparationPresentation(
                modelIdentifier: activeModelIdentifier,
                context: .appRecordTap
            )
        })
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                isColdStartMode = false
                // The launch intent describes the frame this process launched into.
                // Forgetting it here keeps a view rebuilt later in the same process
                // from replaying the cold-start overlay (issue #264).
                ColdStartLaunch.clear()
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(DictationCoordinator.shared)
        .environmentObject(TranscriptionHistoryStore.shared)
}
