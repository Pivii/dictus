// DictusApp/Views/HomeView.swift
// Home dashboard showing model status, last transcription, and test dictation link.
import SwiftUI
import DictusCore

/// Home tab dashboard — the first screen users see after onboarding.
///
/// WHY a dedicated HomeView instead of reusing ContentView:
/// ContentView combined navigation, diagnostics, and model prompts in one view.
/// HomeView is focused: it's a dashboard showing current status and quick actions.
/// Diagnostics move to Settings (Plan 04-02), model management is its own tab.
struct HomeView: View {
    @EnvironmentObject var coordinator: DictationCoordinator
    @EnvironmentObject var proStatus: ProStatusManager
    @EnvironmentObject var history: TranscriptionHistoryStore
    @ObservedObject var modelManager: ModelManager

    /// Raises the model preparation screen when a tap arrives during a load (#484).
    @Environment(\.presentModelPreparation) private var presentModelPreparation

    @State private var showCopiedFeedback = false

    /// Drives the history sheet (#70).
    @State private var showHistory = false

    /// Drives the paywall when a non-subscriber reaches for the history.
    @State private var showPaywall = false

    /// What the history offers this user (#70, corrected 2026-08-28): the feature is
    /// Pro, so the hint and the gesture are open, locked, or absent.
    ///
    /// Recomputed on every body evaluation rather than stored, and read through
    /// `proStatus.isProActive` first so SwiftUI actually re-renders: `FeatureGate`
    /// goes straight to the App Group, which publishes nothing. Without touching the
    /// observed object here, a subscription that arrived or lapsed while this screen
    /// was on show would not move the hint until something else redrew it.
    private var entryPoint: HistoryEntryPoint {
        _ = proStatus.isProActive
        return HistoryAvailability.entryPoint
    }

    /// How far up the finger has to travel before the history opens.
    ///
    /// WHY 60pt and not the 20pt that would already register as a drag: this gesture
    /// sits over the whole dashboard, including two buttons and a card. A short flick
    /// while reaching for one of them must not open another screen.
    private let swipeUpThreshold: CGFloat = 60

    /// Read active model name from App Group for display.
    private var activeModelName: String? {
        AppGroup.defaults.string(forKey: SharedKeys.activeModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo mark
            logoSection

            // Model status card
            modelStatusCard

            // Last transcription preview
            if let result = coordinator.lastResult {
                transcriptionCard(result: result)
            }

            // Test dictation button
            if modelManager.isModelReady {
                testDictationLink
            }

            // Pro banner (hidden when subscribed).
            // Gated behind PremiumFlags.paywallVisible until the first Pro
            // feature ships and ASC setup is done (#236, #79, #215).
            if PremiumFlags.paywallVisible {
                ProBannerView()
            }

            Spacer()

            // The affordance for the history (#70), last so it sits at the bottom
            // edge the swipe starts from. Absent entirely on `.hidden`: while the
            // paywall is unreachable the app must look like there is no subscription
            // at all (#236), and a lock leading nowhere is the one place that would
            // break it.
            switch entryPoint {
            case .open:
                SwipeUpHintView { showHistory = true }
            case .locked:
                SwipeUpHintView(isLocked: true) { showPaywall = true }
            case .hidden:
                EmptyView()
            }
        }
        .padding()
        .background(Color.dictusBackground.ignoresSafeArea())
        // The swipe itself. Attached to the whole dashboard rather than to the hint,
        // because the issue asks for a swipe up "from the home screen" — the hint
        // says where, it is not the only place the gesture is allowed to start.
        //
        // `.gesture` and not `.simultaneousGesture`: a simultaneous drag would fire
        // alongside the buttons underneath instead of losing to their taps, which is
        // exactly backwards. With `minimumDistance` set, a tap never reaches here.
        //
        // Installed only when the gesture leads somewhere. On `.hidden` there is no
        // gesture at all, so nothing on this screen behaves differently for someone
        // who has never heard of the feature; on `.locked` the same swipe opens the
        // paywall, because a user who performed the gesture has asked for the thing.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    // The predicted end is what makes a fast flick work: the finger
                    // may lift after 30pt while still travelling. Either the actual
                    // or the predicted travel clearing the threshold opens the sheet.
                    let travelled = min(value.translation.height, value.predictedEndTranslation.height)
                    guard travelled < -swipeUpThreshold else { return }
                    if entryPoint == .open {
                        showHistory = true
                    } else {
                        showPaywall = true
                    }
                },
            // `.none` rather than an optional gesture: `gesture(_:)` takes a
            // concrete `Gesture`, and the mask is the API's own way to say "declared
            // but not receiving". On `.hidden` no touch on this screen reaches the
            // drag at all.
            including: entryPoint == .hidden ? .none : .all
        )
        .sheet(isPresented: $showHistory) {
            // A sheet is the vertical transition the issue asks for, and it brings
            // the swipe-down back to the home screen with it. See HistoryView.
            //
            // The store is handed over explicitly rather than left to the ambient
            // environment: a sheet is presented from a different part of the view
            // tree, and an `@EnvironmentObject` that resolves today because the root
            // happens to publish it is a crash waiting for someone to move it.
            HistoryView()
                .environmentObject(history)
                .environmentObject(proStatus)
        }
        .paywallCover(isPresented: $showPaywall)
        .onAppear {
            // Refresh model state every time HomeView appears.
            modelManager.loadState()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DictusOnboardingCompleted"))) { _ in
            // WHY onReceive in addition to onAppear:
            // HomeView mounts behind the onboarding fullScreenCover, so onAppear fires
            // before the model is downloaded. When onboarding completes and dismisses
            // the cover, onAppear does NOT re-fire. This notification-based refresh
            // ensures HomeView shows the correct model state immediately.
            modelManager.loadState()
        }
    }

    // MARK: - Logo Section

    /// Static 3-bar brand logo at the top of the home screen.
    /// Subscribers see the Dictus Pro gradient wordmark from the paywall hero,
    /// a quiet permanent reminder of what they unlocked.
    private var logoSection: some View {
        VStack(spacing: 8) {
            DictusLogo(height: 60)
                .padding(.top, 8)
            if proStatus.isProActive {
                Text("Dictus Pro")
                    .font(.dictusHeading)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.dictusGradientStart, .dictusGradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            } else {
                Text("Dictus")
                    .font(.dictusHeading)
                    .foregroundColor(.dictusAccent)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Model Status Card

    /// Shows active model name and ready status, or prompts to download.
    ///
    /// WHY a prominent card for "no model" state:
    /// First-time users need clear guidance. Without a model, the app can't transcribe.
    /// The card makes the first required action obvious (navigate to Models tab).
    private var modelStatusCard: some View {
        Group {
            if modelManager.isModelReady, let modelName = activeModelName {
                // Active model display using ModelInfo for human-readable name/size.
                // WHY ModelInfo.forIdentifier: The raw identifier (e.g. "openai_whisper-small")
                // is not user-friendly. ModelInfo maps it to "Small" + "~250 MB".
                HStack {
                    let info = ModelInfo.forIdentifier(modelName)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Active model")
                            .font(.dictusCaption)
                            .foregroundColor(.secondary)
                        Text(info?.displayName ?? modelName)
                            .font(.dictusSubheading)
                        if let size = info?.sizeLabel {
                            Text(size)
                                .font(.dictusCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.dictusSuccess)
                }
                .padding()
                .dictusGlass()
            } else {
                // No model — prompt to download
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.dictusAccent)
                    Text("Download a model to get started")
                        .font(.dictusSubheading)
                        .multilineTextAlignment(.center)
                    Text("Go to the Models tab to download your first transcription model.")
                        .font(.dictusCaption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .dictusGlass()
            }
        }
    }

    // MARK: - Last Transcription Card

    /// Shows the most recent transcription result in a tappable glass card.
    /// Tap to copy to clipboard (same behavior as RecordingView result).
    private func transcriptionCard(result: String) -> some View {
        Button {
            UIPasteboard.general.string = result
            HapticFeedback.recordingStopped()
            showCopiedFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopiedFeedback = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(showCopiedFeedback ? "Copied!" : "Last transcription")
                        .font(.dictusCaption)
                        .foregroundColor(showCopiedFeedback ? .dictusSuccess : .secondary)
                        .animation(.easeOut(duration: 0.2), value: showCopiedFeedback)
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                Text(result)
                    .font(.dictusBody)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .dictusGlass()
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.97))
    }

    // MARK: - Test Dictation Link

    /// Prominent button to test dictation. Only shown when a model is ready.
    ///
    /// WHY a Button instead of NavigationLink to TestDictationView:
    /// NavigationLink pushes TestDictationView inside the NavigationStack. Meanwhile,
    /// MainTabView shows a RecordingView overlay when coordinator.status != .idle.
    /// This creates TWO stacked RecordingViews. When the overlay dismisses (status → idle),
    /// the pushed TestDictationView is still there with its nav bar visible.
    /// A Button just starts dictation — the MainTabView overlay handles the full UI.
    private var testDictationLink: some View {
        Button {
            // A tap that lands during a model load gets the preparation screen instead of
            // being swallowed by `startDictation`'s guard (#484). The button stays live and
            // keeps its shape: `isModelReady` above says a model is on disk and elected, which
            // is a different question from whether one is loading right now.
            switch coordinator.recordTapDecision {
            case .presentPreparation:
                presentModelPreparation()
            case .startDictation:
                coordinator.startDictation(origin: .app)
            }
        } label: {
            HStack {
                Image(systemName: "waveform")
                Text("New dictation")
                    .font(.dictusBody)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.dictusAccent)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(GlassPressStyle())
    }
}

#Preview {
    NavigationStack {
        HomeView(modelManager: ModelManager())
            .environmentObject(DictationCoordinator.shared)
            .environmentObject(ProStatusManager())
            .environmentObject(TranscriptionHistoryStore.shared)
    }
}
