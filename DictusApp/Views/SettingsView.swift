// DictusApp/Views/SettingsView.swift
// iOS-style grouped settings list with preferences persisted via App Group.
import SwiftUI
import DictusCore

/// Settings screen with 3 sections: Transcription, Clavier, A propos.
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

    // MARK: - Body

    var body: some View {
        List {
            // Section 1: Transcription
            Section {
                Picker("Langue", selection: $language) {
                    Text("Francais").tag("fr")
                    Text("English").tag("en")
                }
            } header: {
                Text("Transcription")
            }
            .listRowBackground(Color.dictusAccent.opacity(0.05))

            // Section 2: Clavier
            Section("Clavier") {
                Picker("Disposition", selection: $keyboardLayout) {
                    Text("AZERTY").tag("azerty")
                    Text("QWERTY").tag("qwerty")
                }

                Toggle("Retour haptique", isOn: $hapticsEnabled)
            }
            .listRowBackground(Color.dictusAccent.opacity(0.05))

            // Section 3: A propos
            Section("A propos") {
                LabeledContent("Version", value: appVersion)

                Link(destination: URL(string: "https://github.com/Pivii/dictus")!) {
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
            }
            .listRowBackground(Color.dictusAccent.opacity(0.05))
        }
        .scrollContentBackground(.hidden)
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle("Reglages")
    }

    // MARK: - Private

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
