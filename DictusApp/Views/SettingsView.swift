// DictusApp/Views/SettingsView.swift
// iOS-style grouped settings list with preferences persisted via App Group.
import SwiftUI
import UIKit
import DictusCore

/// Settings screen with 3 sections: Transcription, Clavier, À propos.
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

    // MARK: - Preferences (App Group persisted)

    @AppStorage(SharedKeys.language, store: UserDefaults(suiteName: AppGroup.identifier))
    private var language = "fr"

    @AppStorage(SharedKeys.keyboardLayout, store: UserDefaults(suiteName: AppGroup.identifier))
    private var keyboardLayout = "azerty"

    @AppStorage(SharedKeys.hapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var hapticsEnabled = true

    /// WHY default true: Most users expect autocorrect to be active by default.
    /// Power users who find it annoying can toggle it off here.
    @AppStorage(SharedKeys.autocorrectEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var autocorrectEnabled = true

    /// Tracks log export async operation for spinner display.
    @State private var isExporting = false

    // MARK: - Body

    var body: some View {
        List {
            // Section 1: Transcription
            Section {
                Picker("Langue", selection: $language) {
                    Text("Français").tag("fr")
                    Text("English").tag("en")
                }
            } header: {
                Text("Transcription")
            }

            // Section 2: Clavier
            // All toggles are always visible — there's only one keyboard type now.
            Section("Clavier") {
                DefaultLayerPicker()

                Picker("Disposition", selection: $keyboardLayout) {
                    Text("AZERTY").tag("azerty")
                    Text("QWERTY").tag("qwerty")
                }

                Toggle("Retour haptique", isOn: $hapticsEnabled)

                NavigationLink("Sons") {
                    SoundSettingsView()
                }

                Toggle("Correction automatique", isOn: $autocorrectEnabled)
            }

            // Section 3: A propos
            Section("À propos") {
                LabeledContent("Version", value: appVersion)

                // WHY Button instead of Link:
                // Link doesn't respond to ButtonStyle and gets no press highlight
                // in a List with .scrollContentBackground(.hidden). Using Button
                // with UIApplication.shared.open gives native row press feedback.
                Button {
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

                NavigationLink("Licences") {
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
                        Text("Exporter les logs")
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
        .navigationTitle("Réglages")
    }

    // MARK: - Private

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
        isExporting = true
        Task {
            let content = PersistentLog.exportContent()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("dictus-logs.txt")
            try? content.write(to: tempURL, atomically: true, encoding: .utf8)

            await MainActor.run {
                isExporting = false

                // Present UIActivityViewController via the connected window scene.
                // WHY this approach: SwiftUI doesn't have a native share sheet API.
                // We use UIApplication.shared.connectedScenes to find the active window
                // and present from its root view controller.
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let root = scene.windows.first?.rootViewController else { return }

                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                root.present(activityVC, animated: true)
            }
        }
    }

    /// App version string from Info.plist.
    ///
    /// WHY Bundle.main.infoDictionary:
    /// This reads CFBundleShortVersionString (marketing version like "1.0")
    /// directly from the compiled Info.plist. It updates automatically when
    /// the version is bumped in Xcode project settings.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Diagnostic detail view showing App Group health.
    ///
    /// WHY inline computation:
    /// DiagnosticDetailView requires a DiagnosticResult, which we compute
    /// on demand by running the diagnostic check. This is cheap (reads/writes
    /// a single UserDefaults key) and always shows fresh results.
    private var diagnosticView: some View {
        let result = AppGroupDiagnostic.run()
        return DiagnosticDetailView(result: result)
            .navigationTitle("Diagnostic")
    }
}
