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

    /// Active model preparation requested by the keyboard without starting a
    /// recording. The overlay dismisses itself after its contextual ready state.
    @State private var preparingModelID: String?

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
        _preparingModelID = State(
            initialValue: launchIntent == .prepare ? Self.persistedActiveModelIdentifier : nil
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
            if let preparingModelID {
                ModelLoadingOverlay(
                    modelManager: modelManager,
                    modelIdentifier: preparingModelID,
                    context: .keyboardColdStart,
                    isPresented: Binding(
                        get: { self.preparingModelID != nil },
                        set: { if !$0 { self.preparingModelID = nil } }
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
        .onOpenURL { url in
            guard let intent = KeyboardDictationURL.intent(from: url) else { return }

            if intent == .prepare {
                preparingModelID = activeModelIdentifier
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
            preparingModelID = activeModelIdentifier
        }
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
