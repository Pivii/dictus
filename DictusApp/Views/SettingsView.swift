// DictusApp/Views/SettingsView.swift
// iOS-style grouped settings list with preferences persisted via App Group.
import SwiftUI
import UIKit
import DictusCore

/// Settings screen: Dictus Pro, Transcription, Keyboard, Pro Features, About.
///
/// WHY @AppStorage with App Group store:
/// Preferences need to be readable by both the main app AND the keyboard extension.
/// @AppStorage with the App Group suite writes to the shared UserDefaults container,
/// making preferences available across processes without any additional sync logic.
///
/// WHY grouped List style:
/// iOS standard settings pattern — users immediately recognize the familiar
/// grouped rows with section headers and footers.
struct SettingsView: View {

    @EnvironmentObject var proStatus: ProStatusManager

    // MARK: - Preferences (App Group persisted)

    @AppStorage(SharedKeys.language, store: UserDefaults(suiteName: AppGroup.identifier))
    private var language = "fr"

    /// Transcription (STT) language mode, decoupled from the keyboard language (#226).
    /// Stored as its raw App Group encoding: "follow" (default), "auto", or an
    /// explicit code ("fr"/"en"/"es"/"de"). "follow" preserves the historical
    /// behavior where STT tracks the keyboard language.
    @AppStorage(SharedKeys.transcriptionLanguage, store: UserDefaults(suiteName: AppGroup.identifier))
    private var transcriptionLanguage = TranscriptionLanguageMode.followStoredValue

    /// Bumped whenever the Layout picker writes, to re-evaluate the body.
    ///
    /// WHY not @AppStorage like every other preference here: since #272 the layout is
    /// stored per keyboard language (`KeyboardLayoutPreference`), so there is no single
    /// key for @AppStorage to observe — the value the picker shows depends on the
    /// language selected in the row above it.
    @State private var layoutRevision = 0

    @AppStorage(SharedKeys.hapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var hapticsEnabled = true

    /// Persistent digit row above the letter rows (#331). Off by default: it makes the
    /// keyboard a fifth taller, and nobody's keyboard may change shape on update.
    /// Portrait only — the keyboard reads this through `NumberRowPreference` and never draws
    /// the row in landscape, where it would take 72% of the screen.
    @AppStorage(SharedKeys.numberRowEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var numberRowEnabled = false

    @AppStorage(SharedKeys.activeModel, store: UserDefaults(suiteName: AppGroup.identifier))
    private var activeModel = "openai_whisper-small"

    /// WHY default true: Most users expect autocorrect to be active by default.
    /// Power users who find it annoying can toggle it off here.
    @AppStorage(SharedKeys.autocorrectEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var autocorrectEnabled = true

    @AppStorage(SharedKeys.liveActivityEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var liveActivityEnabled = true

    /// Post-STT polish toggle (issue #141). Off by default — opt-in measurement at round 1.
    @AppStorage(SharedKeys.polishEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var polishEnabled = false

    #if DEBUG
    /// Debug-only: logs autocorrect decisions with user text to the debug log.
    /// This toggle only exists in DEBUG builds — the Release binary doesn't contain
    /// either this @AppStorage or the AutocorrectDebugLog code that reads it.
    @AppStorage(SharedKeys.autocorrectDebugLogging, store: UserDefaults(suiteName: AppGroup.identifier))
    private var autocorrectDebugLogging = false

    /// Debug-only: forces the Pro entitlement on, so the Smart Mode surfaces can be
    /// exercised before #215 makes a real subscription purchasable.
    @AppStorage(SharedKeys.debugForceProActive, store: UserDefaults(suiteName: AppGroup.identifier))
    private var debugForceProActive = false
    #endif

    /// The keyboard language the pickers below operate on.
    private var keyboardLanguage: SupportedLanguage {
        SupportedLanguage(rawValue: language) ?? .french
    }

    /// The Layout picker's selection: the layout of whichever keyboard language is
    /// currently selected above it (#272).
    ///
    /// The getter reads `layoutRevision` so a write re-renders the picker; the setter is
    /// the only thing that records an explicit layout from this screen. Changing the
    /// *language* runs neither — which is the whole point, the language no longer
    /// overwrites the layout.
    private var layoutSelection: Binding<LayoutType> {
        let selectedLanguage = keyboardLanguage
        return Binding(
            get: {
                _ = layoutRevision
                return KeyboardLayoutPreference.layout(for: selectedLanguage)
            },
            set: { newLayout in
                KeyboardLayoutPreference.setLayout(newLayout, for: selectedLanguage)
                layoutRevision += 1
            }
        )
    }

    /// Whether the currently active model uses the Parakeet engine (CTC/TDT).
    /// Parakeet auto-detects language — the language picker has no effect on it.
    private var isParakeetActive: Bool {
        ModelInfo.forIdentifier(activeModel)?.engine == .parakeet
    }

    /// Tracks log export async operation for spinner display.
    @State private var isExporting = false
    @State private var exportURL: URL?

    /// Hidden polish debug screen (#141). Reached via long-press 3s on the Version row.
    @State private var showPolishDebug = false

    /// Confirmation dialog for resetting the learned-words dictionary (#222).
    @State private var showResetDictionaryConfirmation = false

    /// Drives the paywall cover. Shared by the Dictus Pro row and every locked
    /// feature row: they open the same screen, so one flag serves both.
    @State private var showPaywall = false

    // MARK: - Body

    var body: some View {
        List {
            // Section 0: Dictus Pro — always first.
            // Gated behind PremiumFlags.paywallVisible until the first Pro
            // feature ships and ASC setup is done (#236, #79, #215).
            if PremiumFlags.paywallVisible {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.dictusAccent)
                            Text("Dictus Pro")
                                .foregroundColor(.primary)
                            Spacer()
                            if proStatus.isProActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.dictusSuccess)
                                    .accessibilityLabel("Pro active")
                            }
                            // A Button in a List draws no disclosure indicator,
                            // and this row still leads somewhere. Matching the
                            // system one by hand keeps the section reading like
                            // the rows around it.
                            listDisclosureIndicator
                        }
                    }
                }
            }

            // Section 1: Transcription
            Section {
                // STT language, decoupled from the keyboard language (#226).
                // "Follow keyboard language" is the default and preserves the
                // historical coupled behavior. "Auto-detect" lets Whisper pick
                // the language itself, unlocking languages without a Dictus
                // keyboard (Chinese, Italian, …). Explicit entries stay limited
                // to the four tested languages by product decision — the long
                // tail goes through Auto-detect only.
                Picker("Transcription language", selection: $transcriptionLanguage) {
                    Text("Follow keyboard language")
                        .tag(TranscriptionLanguageMode.followStoredValue)
                    Text("Auto-detect")
                        .tag(TranscriptionLanguageMode.autoStoredValue)
                    ForEach(SupportedLanguage.allCases, id: \.rawValue) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                if isParakeetActive {
                    Text("Parakeet automatically detects the spoken language. This setting only applies to Whisper models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if PolishAvailability.isToggleVisible {
                    Toggle("Polish transcription", isOn: $polishEnabled)
                    polishStateFooter
                }
            } header: {
                Text("Transcription")
            } footer: {
                // Explain Auto-detect behavior (#226) — since #239 polish runs
                // in this mode with the language-agnostic prompt — plus a
                // pointer to the per-model language details (#240).
                // The Whisper-specific line is hidden while Parakeet is active
                // (the caveat above already says the setting has no effect
                // there), but the per-model language pointer stays useful for
                // both engines.
                if transcriptionLanguage == TranscriptionLanguageMode.autoStoredValue {
                    VStack(alignment: .leading, spacing: 4) {
                        if !isParakeetActive {
                            Text("Auto-detect lets you dictate in any language Whisper supports. Polish adapts to the language you speak.")
                        }
                        Text("Language support varies by model. Tap ⓘ on a model card in Models for details.")
                    }
                }
            }

            // Section 2: Clavier
            // All toggles are always visible — there's only one keyboard type now.
            Section {
                // Keyboard language: drives layout, key labels, and
                // autocorrect/prediction dictionaries. Moved here from the
                // Transcription section in #226 — it no longer drives STT by
                // itself (only when the transcription language is "Follow
                // keyboard language").
                Picker("Keyboard language", selection: $language) {
                    // Iterate over SupportedLanguage so adding a new language
                    // (German PR2, future onboardings) only requires the enum case.
                    ForEach(SupportedLanguage.allCases, id: \.rawValue) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .onChange(of: language) { _, newLang in
                    // The layout is NOT touched here anymore (#272): it belongs to the
                    // language being selected, and overwriting it is what made "English
                    // autocorrect on an AZERTY keyboard" unreachable. The Layout picker
                    // below now shows the new language's own layout instead.
                    //
                    // Routing through activate() keeps the legacy mirror in step — the
                    // @AppStorage write above has already stored the language, so this
                    // only adds the mirror.
                    if let lang = SupportedLanguage(rawValue: newLang) {
                        SupportedLanguage.activate(lang)
                    }
                }

                DefaultLayerPicker()

                Picker("Layout", selection: layoutSelection) {
                    // Iterate over LayoutType so adding a layout (QWERTZ in #151,
                    // any future one) only requires the enum case — the entries used
                    // to be hardcoded here and in the keyboard panel separately.
                    ForEach(LayoutType.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }

                // Sits under the Layout picker because it changes the same thing: the shape
                // of the key grid. It applies to every layout and every keyboard language —
                // a number row is a hardware habit, not a language one (#331).
                Toggle("Number row", isOn: $numberRowEnabled)

                Toggle("Haptic feedback", isOn: $hapticsEnabled)

                NavigationLink("Sounds") {
                    SoundSettingsView()
                }

                Toggle("Autocorrect", isOn: $autocorrectEnabled)

                // Reset the learned-words dictionary (#222). Words learned by
                // the keyboard bypass autocorrect forever, so users need a way
                // to recover from accidental learning (e.g. typos recorded
                // before the search-field learning gate existed).
                Button("Reset learned words", role: .destructive) {
                    // Sync from App Group first: words learned by the keyboard
                    // process since app launch aren't in this process's cache.
                    UserDictionary.shared.reload()
                    showResetDictionaryConfirmation = true
                }
                .confirmationDialog(
                    "Reset learned words?",
                    isPresented: $showResetDictionaryConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Forget \(UserDictionary.shared.count) learned words", role: .destructive) {
                        UserDictionary.shared.resetAll()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Words the keyboard learned from your typing will be forgotten and autocorrect will apply to them again.")
                }

                Toggle("Live Activity", isOn: $liveActivityEnabled)
                    .onChange(of: liveActivityEnabled) { _, enabled in
                        if !enabled {
                            LiveActivityManager.shared.stopStandbyActivity()
                        }
                    }
            } header: {
                Text("Keyboard")
            } footer: {
                // Only shown once the row is on: the keyboard drops it in landscape by
                // design (#331) and on iPad by design (#336), and without a word here either
                // one reads as a bug to the person who just turned it on.
                //
                // WHY one sentence covering both rather than a device-aware one, and why the
                // toggle stays visible on an iPad where it now does nothing: this target has
                // no device detection at all — `DeviceContext` and DeviceKit are linked to the
                // keyboard, not here, and `UIDevice.userInterfaceIdiom` reports `.phone` in
                // compatibility mode, which is the only way an iPad reaches this app. A second
                // copy of device detection in a second target, for a device class Dictus does
                // not target, costs more than a sentence that is simply true on both.
                if numberRowEnabled {
                    Text("The number row is shown on iPhone in portrait only.")
                }
                if !liveActivityEnabled {
                    Text("Dynamic Island and Lock Screen notification are disabled.")
                }
            }

            // Section 3: Pro Features.
            // Gated behind PremiumFlags.paywallVisible (#236): while hidden,
            // the app must look like there is no subscription at all — no
            // locked rows, no PRO pills, no navigation path to PaywallView.
            // Pro toggles are also hidden: no user can be Pro while the
            // paywall is unreachable (no ASC product exists yet, #215).
            if PremiumFlags.paywallVisible {
                Section("Pro Features") {
                    ForEach(ProFeature.allCases, id: \.self) { feature in
                        if proStatus.isProActive {
                            // Unlocked: show toggle
                            Toggle(isOn: Binding(
                                get: { AppGroup.defaults.bool(forKey: feature.settingsKey) },
                                set: { AppGroup.defaults.set($0, forKey: feature.settingsKey) }
                            )) {
                                HStack(spacing: 8) {
                                    Image(systemName: feature.icon)
                                        .foregroundColor(.dictusAccent)
                                    Text(LocalizedStringKey(feature.displayName))
                                }
                            }
                        } else {
                            // Locked: show lock + PRO pill, tap opens paywall
                            Button {
                                showPaywall = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: feature.icon)
                                        .foregroundColor(.secondary)
                                    Text(LocalizedStringKey(feature.displayName))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundColor(.dictusAccent)
                                        .accessibilityHidden(true)
                                    Text("PRO")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 2)
                                        .padding(.horizontal, 6)
                                        .background(Color.dictusAccent)
                                        .clipShape(Capsule())
                                        .accessibilityLabel("Pro feature")
                                    listDisclosureIndicator
                                }
                            }
                        }
                    }

                    // The fan's contents (#79). Subscribers only, and only when the
                    // feature toggle above is on: a mode list under a switched-off
                    // Smart Mode would arrange a fan the keyboard will not open.
                    //
                    // Deliberately NOT gated on device capability. The choice is
                    // durable and the fan is the keyboard's, not this device's — a
                    // user who arranges it here and changes phone next year should
                    // find their arrangement waiting. `SmartModeListView` says so on
                    // the screen instead of hiding the row.
                    if proStatus.isProActive && FeatureGate.isAvailable(.smartMode) {
                        NavigationLink {
                            SmartModeListView()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "list.bullet.indent")
                                    .foregroundColor(.dictusAccent)
                                Text("Keyboard modes")
                            }
                        }
                    }
                }
            }

            #if DEBUG
            // Section: Developer (visible ONLY in Debug builds — not in Release/TestFlight/App Store).
            // WHY #if DEBUG: Code inside is compile-time excluded from production builds.
            // Impossible to accidentally ship a toggle that logs user text.
            Section {
                Toggle("Autocorrect debug logs", isOn: $autocorrectDebugLogging)
                Toggle("Force Dictus Pro", isOn: $debugForceProActive)
                    .onChange(of: debugForceProActive) { _, forced in
                        // Apply immediately rather than at the next launch: the whole
                        // point is to flip entitlement while the keyboard is open.
                        proStatus.setProActive(forced)
                    }
            } header: {
                Text("Developer")
            } footer: {
                if autocorrectDebugLogging {
                    Text("Warning: logs contain typed words and corrections. Debug builds only.")
                        .foregroundColor(.orange)
                } else {
                    Text("Logs autocorrect decisions for debugging. Off by default.")
                }
            }
            #endif

            // Section 4: A propos
            Section("About") {
                LabeledContent("Version", value: appVersion)
                    .contentShape(Rectangle())
                    // Five quick taps reveals the polish debug ring. Replaces
                    // the previous 3-second long-press — taps are easier to
                    // perform on the device than holding still on a List row,
                    // and the secret-gesture posture stays the same.
                    .onTapGesture(count: 5) {
                        showPolishDebug = true
                    }

                // WHY Button instead of Link:
                // Link doesn't respond to ButtonStyle and gets no press highlight
                // in a List with .scrollContentBackground(.hidden). Using Button
                // with UIApplication.shared.open gives native row press feedback.
                Button {
                    // Force unwrap is safe: compile-time constant URL that cannot be malformed.
                    // swiftlint:disable:next force_unwrapping
                    UIApplication.shared.open(URL(string: "https://github.com/Pivii/dictus")!)
                } label: {
                    HStack {
                        Text("GitHub")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink("Licenses") {
                    LicensesView()
                }

                NavigationLink("Diagnostic") {
                    diagnosticView
                }

                NavigationLink("Debug Logs") {
                    DebugLogView()
                }

                Button {
                    exportLogs()
                } label: {
                    HStack {
                        Text("Export logs")
                        Spacer()
                        if isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .disabled(isExporting)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationDestination(isPresented: $showPolishDebug) {
            PolishDebugView()
        }
        .paywallCover(isPresented: $showPaywall)
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { isPresented in
                if !isPresented {
                    exportURL = nil
                }
            }
        )) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
    }

    // MARK: - Private

    /// The chevron `NavigationLink` draws on a List row, for rows that open a
    /// cover instead and therefore have to draw it themselves.
    private var listDisclosureIndicator: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// Export logs via iOS share sheet.
    ///
    /// WHY write to a temp file instead of sharing raw text:
    /// UIActivityViewController with a file URL shows the file name ("dictus-logs.txt")
    /// in the share sheet and lets the user save, AirDrop, or attach it to email/GitHub.
    /// Raw text sharing doesn't give a meaningful filename.
    /// WHY async with isExporting flag:
    /// Log gathering reads from disk and can take a moment on large log files.
    /// The spinner gives visual feedback that something is happening. The share
    /// sheet presentation must happen on the main thread (UIKit requirement).
    private func exportLogs() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            let start = CFAbsoluteTimeGetCurrent()
            let content = PersistentLog.exportContent()
            let duration = CFAbsoluteTimeGetCurrent() - start
            PersistentLog.log(.logExportCompleted(durationMs: Int(duration * 1000), sizeBytes: content.utf8.count))
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("dictus-logs.txt")
            try? content.write(to: tempURL, atomically: true, encoding: .utf8)

            await MainActor.run {
                isExporting = false
                exportURL = tempURL
            }
        }
    }

    /// Footer row under the polish toggle — surfaces the specific reason
    /// Apple Foundation Models is or isn't usable. When the state is `.available`
    /// no footer is shown (the toggle alone is enough).
    @ViewBuilder
    private var polishStateFooter: some View {
        let state = PolishAvailability.state
        if state != .available {
            VStack(alignment: .leading, spacing: 6) {
                Text(polishStateMessage(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if PolishAvailability.canOpenSystemSettings(for: state) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open iPhone Settings")
                            .font(.caption.bold())
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// User-facing explanation per availability state. Strings live in this
    /// view so Localizable.xcstrings can auto-detect them.
    private func polishStateMessage(for state: PolishAvailabilityState) -> String {
        switch state {
        case .available:
            return ""
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is required for polish. Enable it in iPhone Settings → Apple Intelligence & Siri. Apple requires Siri and your iPhone to use the same language — if Siri is in English and your iPhone is in French (or vice versa), Apple Intelligence stays off."
        case .modelNotReady:
            return "The Apple Intelligence model is downloading on your device. Try again in a few minutes."
        case .deviceNotEligible:
            return "Apple Intelligence isn't supported on this device. Polish requires an iPhone 15 Pro / 15 Pro Max or newer."
        case .osTooOld:
            return "Polish requires iOS 26 or later."
        case .sdkMissing:
            return "Polish isn't available in this build of Dictus."
        case .other(let reason):
            return "Apple Intelligence is unavailable (\(reason))."
        }
    }

    /// App version string from Info.plist — marketing version + build number.
    ///
    /// Format: "1.6.0 (10)" — lets testers report bugs against a specific build,
    /// since TestFlight ships multiple builds under the same marketing version.
    private var appVersion: String {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }

    /// Diagnostic detail view showing App Group health.
    ///
    /// WHY inline computation:
    /// DiagnosticDetailView requires a DiagnosticResult, which we compute
    /// on demand by running the diagnostic check. This is cheap (reads/writes
    /// a single UserDefaults key) and always shows fresh results.
    private var diagnosticView: some View {
        DiagnosticDetailView(result: AppGroupDiagnostic.run())
            .navigationTitle("Diagnostic")
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
