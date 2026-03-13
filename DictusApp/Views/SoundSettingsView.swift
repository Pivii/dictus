// DictusApp/Views/SoundSettingsView.swift
// Sound feedback settings sub-page: global toggle + 3 event sound pickers with preview.
import SwiftUI
import DictusCore

/// Settings sub-page for configuring recording sound feedback.
///
/// WHY a separate view (not inline in SettingsView):
/// Sound settings have 4 controls (toggle + 3 pickers with preview). Putting them
/// inline in SettingsView would make it too long. A NavigationLink to this sub-page
/// follows the iOS Settings pattern (e.g., Settings > Sounds & Haptics).
///
/// WHY @AppStorage with App Group store:
/// Same pattern as SettingsView -- preferences must be readable by both the main app
/// and the keyboard extension. @AppStorage with the shared suite handles cross-process
/// persistence automatically.
struct SoundSettingsView: View {

    // MARK: - Preferences (App Group persisted)

    @AppStorage(SharedKeys.soundFeedbackEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
    private var soundFeedbackEnabled = true

    @AppStorage(SharedKeys.recordStartSoundName, store: UserDefaults(suiteName: AppGroup.identifier))
    private var recordStartSoundName = "electronic_01a"

    @AppStorage(SharedKeys.recordStopSoundName, store: UserDefaults(suiteName: AppGroup.identifier))
    private var recordStopSoundName = "ui_chime_01"

    @AppStorage(SharedKeys.recordCancelSoundName, store: UserDefaults(suiteName: AppGroup.identifier))
    private var recordCancelSoundName = "electronic_02a"

    // MARK: - Body

    var body: some View {
        List {
            // Section 1: Global toggle
            Section {
                Toggle("Activer les sons", isOn: $soundFeedbackEnabled)
            } footer: {
                Text("Les sons respectent le bouton silencieux de l'iPhone.")
            }

            // Section 2: Start sound picker
            Section {
                soundPickerRow(
                    label: "Debut d'enregistrement",
                    selection: $recordStartSoundName
                )
            }
            .disabled(!soundFeedbackEnabled)

            // Section 3: Stop sound picker
            Section {
                soundPickerRow(
                    label: "Fin d'enregistrement",
                    selection: $recordStopSoundName
                )
            }
            .disabled(!soundFeedbackEnabled)

            // Section 4: Cancel sound picker
            Section {
                soundPickerRow(
                    label: "Annulation",
                    selection: $recordCancelSoundName
                )
            }
            .disabled(!soundFeedbackEnabled)
        }
        .scrollContentBackground(.hidden)
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle("Sons")
    }

    // MARK: - Private

    /// A row with a menu-style Picker and a preview play button.
    ///
    /// WHY HStack with Picker + Button:
    /// The Picker shows the currently selected sound in a compact menu.
    /// The play button lets users preview each sound without leaving the screen.
    /// This pattern is common in iOS sound settings (e.g., ringtone picker).
    ///
    /// WHY .menu picker style:
    /// Navigation-style pickers push a full-screen list, which feels heavy for
    /// selecting from a short list of sounds. Menu style shows a dropdown overlay
    /// that's faster to scan and dismiss.
    @ViewBuilder
    private func soundPickerRow(label: String, selection: Binding<String>) -> some View {
        HStack {
            Picker(label, selection: selection) {
                ForEach(SoundFeedbackService.availableSounds(), id: \.self) { name in
                    Text(SoundFeedbackService.displayName(for: name))
                        .tag(name)
                }
            }

            Spacer()

            Button {
                SoundFeedbackService.play(selection.wrappedValue)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
        }
    }
}
