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
/// - Whisper: the complete tokenizer language list grouped by published
///   quality tier (design round, grounded in OpenAI's large-v3 FLEURS
///   results), each tier as flowing comma-separated text, plus a caveat
///   that tiers were measured on the large models
/// - Parakeet: the full remaining documented list ("Also supported"); the
///   25-language summary + exhaustive list convey the European-only limit
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
                }

                // Whisper: complete tokenizer language list grouped by
                // published quality tier (design round). Flowing text per
                // tier keeps ~100 languages scannable instead of 100 rows.
                ForEach(Array(support.tierGroups.enumerated()), id: \.offset) { index, group in
                    Section {
                        Text(joinedLanguageNames(for: group))
                            .font(.dictusCaption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text(localizedTierHeader(for: group.tier))
                    } footer: {
                        // Ground the tiers honestly: numbers come from the
                        // large models; the small ones degrade further.
                        if index == support.tierGroups.count - 1 {
                            Text("Quality measured on the large Whisper models. Smaller models are less accurate.")
                        }
                    }
                }

                // Parakeet: finite documented list — spell out the rest.
                // Together with the "25 European languages" summary this
                // conveys the European-only limit (design round dropped the
                // extra warning row as redundant).
                if !support.additionalCodes.isEmpty {
                    Section {
                        Text(additionalLanguagesText)
                            .font(.dictusCaption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Also supported")
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
        joinedNames(for: support.additionalCodes)
    }

    /// Comma-joined localized names for a Whisper quality tier.
    /// The highlighted languages (already shown with notes in the "Main
    /// languages" section) are filtered out so nothing appears twice.
    private func joinedLanguageNames(for group: ModelLanguageSupport.TierGroup) -> String {
        let highlighted = Set(support.highlights.map(\.code))
        return joinedNames(for: group.codes.filter { !highlighted.contains($0) })
    }

    /// Localize, sort by the user's language, and join with commas.
    private func joinedNames(for codes: [String]) -> String {
        codes
            .map { ModelLanguageSupport.localizedLanguageName(for: $0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .joined(separator: ", ")
    }

    /// Localized section header for a quality tier.
    private func localizedTierHeader(for tier: ModelLanguageSupport.QualityTier) -> String {
        switch tier {
        case .good:
            return String(localized: "Good quality")
        case .fair:
            return String(localized: "Fair quality")
        case .limited:
            return String(localized: "Limited quality")
        }
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
