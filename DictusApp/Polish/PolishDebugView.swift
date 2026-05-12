// DictusApp/Polish/PolishDebugView.swift
import SwiftUI
import DictusCore

/// Hidden screen surfacing the last 50 polish invocations. Reached by long-pressing
/// the Version row in Settings for 3 seconds. Round-1 debugging tool — no disk
/// persistence, no analytics, no shipping in product UX.
struct PolishDebugView: View {

    @State private var entries: [PolishDebugEntry] = []
    @State private var selectedEntry: PolishDebugEntry?

    var body: some View {
        List {
            if !entries.isEmpty {
                Section("Outcomes (\(entries.count))") {
                    BreakdownRow(entries: entries)
                }
            }
            Section("Recent events") {
                if entries.isEmpty {
                    Text("No polish events yet. Toggle on, dictate something, then come back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries.reversed()) { entry in
                        EntryRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedEntry = entry }
                    }
                }
            }
        }
        .navigationTitle("Polish debug")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    Task {
                        await PolishCoordinator.shared.clearMetricsRing()
                        await refresh()
                    }
                }
                .disabled(entries.isEmpty)
            }
        }
        .sheet(item: $selectedEntry) { entry in
            NavigationStack {
                EntryDetailView(entry: entry)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        entries = await PolishCoordinator.shared.metricsSnapshot()
    }
}

// MARK: - Breakdown

private struct BreakdownRow: View {
    let entries: [PolishDebugEntry]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PolishMetrics.Outcome.allDisplayCases, id: \.self) { outcome in
                let count = entries.filter { $0.metrics.outcome == outcome }.count
                if count > 0 {
                    VStack(spacing: 2) {
                        Text("\(count)").font(.headline).foregroundStyle(outcome.tintColor)
                        Text(outcome.shortLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct EntryRow: View {
    let entry: PolishDebugEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.metrics.outcome.shortLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(entry.metrics.outcome.tintColor.opacity(0.15))
                    .foregroundStyle(entry.metrics.outcome.tintColor)
                    .clipShape(Capsule())
                if let mode = entry.metrics.mode {
                    Text(mode.rawValue).font(.caption2).foregroundStyle(.secondary)
                }
                Text(entry.metrics.targetLanguage.rawValue.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(entry.raw)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            HStack(spacing: 10) {
                Text(entry.metrics.engine)
                Text("det=\(entry.metrics.detectedLanguage ?? "-")")
                Text("\(entry.metrics.latencyMs)ms")
                Text("\(entry.metrics.rawCharCount)→\(entry.metrics.polishedCharCount)")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail sheet

private struct EntryDetailView: View {
    let entry: PolishDebugEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metaRow
                section("Raw STT output", text: entry.raw)
                section("Engine output",
                        text: entry.polished ?? "(engine did not run successfully)")
            }
            .padding()
        }
        .navigationTitle("Polish event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var metaRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.metrics.outcome.shortLabel)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(entry.metrics.outcome.tintColor.opacity(0.15))
                    .foregroundStyle(entry.metrics.outcome.tintColor)
                    .clipShape(Capsule())
                Spacer()
                Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                LabeledValue("engine", entry.metrics.engine)
                LabeledValue("mode", entry.metrics.mode?.rawValue ?? "-")
                LabeledValue("target", entry.metrics.targetLanguage.rawValue)
                LabeledValue("detected", entry.metrics.detectedLanguage ?? "-")
            }
            HStack(spacing: 12) {
                LabeledValue("latency", "\(entry.metrics.latencyMs) ms")
                LabeledValue("chars", "\(entry.metrics.rawCharCount) → \(entry.metrics.polishedCharCount)")
            }
        }
    }

    private func section(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            Text(text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced())
        }
    }
}

// MARK: - Outcome display helpers

private extension PolishMetrics.Outcome {
    static var allDisplayCases: [PolishMetrics.Outcome] {
        [.success, .rejectedGuardrail, .skipped, .cancelled, .engineFailed]
    }

    var shortLabel: String {
        switch self {
        case .success: return "success"
        case .rejectedGuardrail: return "rejected"
        case .skipped: return "skipped"
        case .cancelled: return "cancelled"
        case .engineFailed: return "failed"
        }
    }

    var tintColor: Color {
        switch self {
        case .success: return .green
        case .rejectedGuardrail, .skipped: return .orange
        case .cancelled, .engineFailed: return .red
        }
    }
}
