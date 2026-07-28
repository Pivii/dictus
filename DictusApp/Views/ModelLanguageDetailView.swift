// DictusApp/Views/ModelLanguageDetailView.swift
// Per-model supported-languages detail sheet (issue #240).
import SwiftUI
import DictusCore

/// Curated language-support detail for one model, presented as a sheet from
/// the ⓘ affordance on a model card.
///
/// WHY a sheet instead of an inline list on the card (#240 locked decision):
/// Model cards are already dense (badges, gauges, states, overflow menu).
/// A dedicated scrollable sheet leaves room for per-language quality notes
/// and stays safe at large Dynamic Type sizes.
///
/// CONTENT (top to bottom):
/// - one-line coverage summary ("About 99 languages", "25 European languages")
/// - curated main languages, the four Dictus-tested ones first, with
///   per-tier quality notes where warranted (e.g. Chinese on small models)
/// - Whisper: a footer noting the ≈94-language long tail
/// - Parakeet: the full remaining documented list plus an explicit
///   "no Chinese / non-European languages" warning
struct ModelLanguageDetailView: View {
    let model: ModelInfo

    @Environment(\.dismiss) private var dismiss

    /// Convenience accessor for the curated metadata.
    private var support: ModelLanguageSupport { model.languageSupport }

    var body: some View {
        NavigationStack {
            List {
                // Coverage summary
                Section {
                    Label {
                        Text(support.coverage.localizedSummary)
                            .font(.dictusSubheading)
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(Color.dictusAccent)
                    }
                }

                // Curated main languages with optional quality notes
                Section {
                    ForEach(support.highlights, id: \.code) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ModelLanguageSupport.localizedLanguageName(for: entry.code))
                            if let note = entry.note {
                                Text(note.localizedText)
                                    .font(.dictusCaption)
                                    .foregroundStyle(noteColor(for: note))
                            }
                        }
                    }
                } header: {
                    Text("Main languages")
                } footer: {
                    if support.coverage == .whisperMultilingual {
                        // Whisper long tail: conveyed as a footer instead of
                        // listing ~94 rows nobody would scroll through.
                        Text("Plus about 94 other languages, with variable quality.")
                    }
                }

                // Parakeet: finite documented list — spell out the rest and
                // make the non-European exclusion explicit (#240 acceptance).
                if !support.additionalCodes.isEmpty {
                    Section {
                        Text(additionalLanguagesText)
                            .font(.dictusCaption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Also supported")
                    }
                }

                if support.coverage == .parakeetEuropean {
                    Section {
                        Label {
                            Text("This model does not support Chinese or other non-European languages.")
                                .font(.dictusCaption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.dictusBackground.ignoresSafeArea())
            .navigationTitle(model.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    /// Comma-joined localized names for the non-highlighted documented
    /// languages (Parakeet's remaining 21), sorted for stable reading order
    /// in the user's language.
    private var additionalLanguagesText: String {
        support.additionalCodes
            .map { ModelLanguageSupport.localizedLanguageName(for: $0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .joined(separator: ", ")
    }

    /// Warning-tinted color for caveat notes, secondary for positive ones.
    private func noteColor(for note: ModelLanguageSupport.QualityNote) -> Color {
        switch note {
        case .impreciseUpgradeRecommended:
            return .orange
        case .goodOnThisModel:
            return .secondary
        }
    }
}

#Preview("Whisper small") {
    ModelLanguageDetailView(model: ModelInfo.all[0])
}

#Preview("Parakeet") {
    ModelLanguageDetailView(
        model: ModelInfo.allIncludingDeprecated.first { $0.engine == .parakeet } ?? ModelInfo.all[0]
    )
}
