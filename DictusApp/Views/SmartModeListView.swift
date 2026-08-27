// DictusApp/Views/SmartModeListView.swift
// Choosing which Smart Modes the keyboard's long-press fan holds (issue #79).
import SwiftUI
import DictusCore

/// The mode list: which modes are in the keyboard's fan, and in what order.
///
/// ### Why pinning exists at all
///
/// The fan is not the catalogue. It holds Normal plus the modes the user pinned,
/// and it holds four entries because that is what fits above 44 pt on the smallest
/// supported screen — see `SmartModeFanLayout`. The catalogue is five modes today
/// (Notes and four translation targets) and grows with #269, so a choice has to be
/// made somewhere. It is made here rather than in the keyboard because the keyboard
/// has 52 pt of chrome and no room for a settings screen, and because this is a
/// decision taken once rather than during a dictation.
///
/// ### Order is the user's
///
/// `SmartModeStore.setPinned` preserves it and `SmartModeCatalogue.pinnedModes`
/// honours it, so the fan draws the rows in the order arranged here. That is worth a
/// drag handle: the fan deploys downward from a top-right mic and the nearest row is
/// the cheapest to reach, so which mode sits first is a real ergonomic choice.
struct SmartModeListView: View {

    /// The pinned identifiers, in order. Local state so a reorder is smooth, written
    /// through to the App Group on every change — there is no Save button, and a
    /// screen the user backs out of must not lose what they just arranged.
    @State private var pinnedIdentifiers: [String] = SmartModeStore.pinnedIdentifiers

    /// Whether this iPhone can run Smart Modes at all. Read once: it cannot change
    /// while this screen is open, short of an OS update.
    private let deviceIsCapable = SmartModeAvailability.deviceIsCapable

    private var pinnedModes: [SmartMode] {
        pinnedIdentifiers.compactMap(SmartModeCatalogue.mode(withIdentifier:))
    }

    private var unpinnedModes: [SmartMode] {
        SmartModeCatalogue.builtIns.filter { !pinnedIdentifiers.contains($0.id) }
    }

    private var isFull: Bool {
        pinnedIdentifiers.count >= SmartModeCatalogue.maximumPinnedModes
    }

    var body: some View {
        List {
            if !deviceIsCapable {
                Section {
                    unsupportedNotice
                }
            }

            Section {
                if pinnedModes.isEmpty {
                    Text("No modes pinned. The keyboard will offer only Normal.")
                        .font(.dictusCaption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(pinnedModes) { mode in
                        row(mode, isPinned: true)
                    }
                    .onMove(perform: move)
                }
            } header: {
                Text("In the keyboard fan")
            } footer: {
                Text(
                    "Hold the microphone on the keyboard to open these, then slide onto one. Up to \(SmartModeCatalogue.maximumPinnedModes), plus Normal."
                )
            }

            if !unpinnedModes.isEmpty {
                Section {
                    ForEach(unpinnedModes) { mode in
                        row(mode, isPinned: false)
                    }
                } header: {
                    Text("Other modes")
                } footer: {
                    if isFull {
                        Text("Remove one above to add another.")
                    }
                }
            }
        }
        .navigationTitle("Smart Modes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Only useful with something to reorder, and a lone EditButton over one
            // row reads as an unfinished screen.
            if pinnedModes.count > 1 {
                EditButton()
            }
        }
    }

    // MARK: - Rows

    private func row(_ mode: SmartMode, isPinned: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: mode.icon)
                .foregroundColor(isPinned ? .dictusSmartMode : .secondary)
                .frame(width: 24)

            Text(Self.listName(for: mode))
                .foregroundColor(.primary)

            Spacer()

            Button {
                toggle(mode, isPinned: isPinned)
            } label: {
                Image(systemName: isPinned ? "minus.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundColor(isPinned ? .secondary : .dictusAccent)
            }
            // `.borderless` and not `.plain`: inside a List row a plain button style
            // makes the whole row tappable, so a tap meant for the drag handle would
            // unpin instead.
            .buttonStyle(.borderless)
            .disabled(!isPinned && isFull)
            .opacity(!isPinned && isFull ? 0.35 : 1)
            .accessibilityLabel(
                isPinned
                    ? Text("Remove \(Self.listName(for: mode)) from the keyboard")
                    : Text("Add \(Self.listName(for: mode)) to the keyboard")
            )
        }
    }

    /// The line a device that cannot run Smart Modes is owed, on the screen where it
    /// would otherwise silently arrange a fan that never works (#79).
    ///
    /// The list stays usable underneath. The choice persists, and it becomes real the
    /// day the user changes phone — hiding it would mean losing the arrangement they
    /// made, for no gain.
    private var unsupportedNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.secondary)

            Text("Smart Modes need Apple Intelligence, which this iPhone does not support. Your choices are saved for a device that does.")
                .font(.dictusCaption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Editing

    /// The list name, which is deliberately not the fan's.
    ///
    /// `SmartModeCatalogue` names translation modes "→ EN" so one string fits a 46 pt
    /// fan row in every UI locale. That is right there and wrong in a settings list,
    /// where there is width to spare and an arrow with no verb reads as a glyph
    /// rather than a mode. The catalogue's own doc comment leaves this to the app.
    static func listName(for mode: SmartMode) -> String {
        guard mode.id.hasPrefix("translate.") else { return mode.localizedDisplayName }
        return "Translate \(mode.displayName)"
    }

    private func toggle(_ mode: SmartMode, isPinned: Bool) {
        var updated = pinnedIdentifiers
        if isPinned {
            updated.removeAll { $0 == mode.id }
        } else {
            guard updated.count < SmartModeCatalogue.maximumPinnedModes else { return }
            updated.append(mode.id)
        }
        apply(updated)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var updated = pinnedIdentifiers
        updated.move(fromOffsets: source, toOffset: destination)
        apply(updated)
    }

    /// Write through immediately.
    ///
    /// The store caps the list as well, and that duplication is deliberate: this
    /// screen enforces the cap so the user never sees a fourth row appear and vanish,
    /// and the store enforces it because it is the thing the keyboard reads.
    private func apply(_ identifiers: [String]) {
        pinnedIdentifiers = identifiers
        SmartModeStore.setPinned(identifiers)
    }
}
