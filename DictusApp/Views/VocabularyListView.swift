// DictusApp/Views/VocabularyListView.swift
// The one screen custom vocabulary gets (issue #80, decision 11).
import SwiftUI
import DictusCore

/// The user's terms: what they are called, what the engine writes instead.
///
/// ### One screen, not two (#80 decision 11)
///
/// An entry is a term plus its variants, and splitting "manage terms" from "manage
/// replacements" would ask the user to hold a distinction the data does not make.
/// The list edits both; the add sheet asks two questions.
///
/// ### Why the second field is optional
///
/// A term alone is not inert: it joins the polish glossary, which tells the model to
/// spell it exactly as written (`PolishGlossary.activePromptBlock`). That is what
/// makes the paywall sentence — "Teach Dictus your technical terms" — true for
/// someone who knows the spelling they want but not yet the shape the engine
/// produces instead.
struct VocabularyListView: View {

    @StateObject private var store = VocabularyStore.shared

    /// The entry being added or edited, or nil when the sheet is closed.
    @State private var editing: VocabularyEditorSubject?

    /// Confirmation for the destructive reset, on the model of "Reset learned words".
    @State private var showResetConfirmation = false

    var body: some View {
        List {
            Section {
                if store.isEmpty {
                    Text("No terms yet. Add the words Dictus gets wrong.")
                        .font(.dictusCaption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.entries) { entry in
                        row(entry)
                    }
                    .onDelete(perform: store.delete(atOffsets:))
                }
            } header: {
                Text("Your terms")
            } footer: {
                Text("Dictus rewrites these in your transcriptions, before anything else reads them.")
            }

            Section {
                Button {
                    editing = .new
                } label: {
                    Label("Add a term", systemImage: "plus")
                }
                .disabled(store.isFull)
            } footer: {
                if store.isFull {
                    Text("You have reached the limit of \(VocabularyStore.maxEntries) terms. Delete one to add another.")
                }
            }

            if !store.isEmpty {
                Section {
                    Button("Reset vocabulary", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Vocabulary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !store.isEmpty {
                EditButton()
            }
        }
        .sheet(item: $editing) { subject in
            NavigationStack {
                VocabularyEditorView(subject: subject)
            }
        }
        .confirmationDialog(
            "Reset vocabulary?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget \(store.count) terms", role: .destructive) {
                store.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every term and every variant will be deleted. Your transcriptions will no longer be corrected.")
        }
    }

    /// One term. Tapping opens the editor; the trailing switch is the per-entry
    /// disable (#80 decision 8), which keeps the entry while stopping its rewrites.
    private func row(_ entry: VocabularyEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                editing = .existing(entry)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.term)
                        .foregroundColor(.primary)
                    if !entry.variants.isEmpty {
                        Text(entry.variantsLine)
                            .font(.dictusCaption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { entry.isEnabled },
                set: { store.update(entry.enabled($0)) }
            ))
            .labelsHidden()
            .accessibilityLabel(Text(entry.term))
        }
    }
}

/// What the editor sheet is working on. `Identifiable` so `sheet(item:)` can drive
/// it, and an enum rather than an optional entry plus a boolean because "adding" and
/// "editing nothing" are the same state in that spelling and behave differently.
enum VocabularyEditorSubject: Identifiable {
    case new
    case existing(VocabularyEntry)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let entry): return entry.id.uuidString
        }
    }

    var entry: VocabularyEntry? {
        switch self {
        case .new: return nil
        case .existing(let entry): return entry
        }
    }
}

/// The add and edit sheet: two fields, and nothing else (#80).
struct VocabularyEditorView: View {

    let subject: VocabularyEditorSubject

    @StateObject private var store = VocabularyStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var term: String
    @State private var variantsLine: String

    init(subject: VocabularyEditorSubject) {
        self.subject = subject
        _term = State(initialValue: subject.entry?.term ?? "")
        _variantsLine = State(initialValue: subject.entry?.variantsLine ?? "")
    }

    /// What the two fields would produce, or nil when the term is empty or too long.
    /// Building the real entry rather than validating a copy of its rules keeps the
    /// Save button and the model from ever disagreeing.
    private var candidate: VocabularyEntry? {
        VocabularyEntry(
            term: term,
            variants: VocabularyEntry.variants(fromLine: variantsLine),
            isEnabled: subject.entry?.isEnabled ?? true,
            id: subject.entry?.id ?? UUID(),
            dateAdded: subject.entry?.dateAdded ?? Date()
        )
    }

    private var duplicatesAnotherTerm: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && store.contains(term: term, excluding: subject.entry?.id)
    }

    private var canSave: Bool {
        candidate != nil && !duplicatesAnotherTerm
    }

    var body: some View {
        Form {
            Section {
                TextField("Which term?", text: $term)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } footer: {
                if duplicatesAnotherTerm {
                    Text("This term is already in your vocabulary.")
                        .foregroundColor(.red)
                } else {
                    Text("The spelling Dictus should write.")
                }
            }

            Section {
                TextField("How does Dictus write it instead?", text: $variantsLine)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } footer: {
                Text("Optional, separated by commas. Leave it empty if you do not know yet.")
            }
        }
        .navigationTitle(subject.entry == nil ? "New term" : "Edit term")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
    }

    private func save() {
        guard let candidate else { return }
        if subject.entry == nil {
            store.add(candidate)
        } else {
            store.update(candidate)
        }
        dismiss()
    }
}
