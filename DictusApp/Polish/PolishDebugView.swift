// DictusApp/Polish/PolishDebugView.swift
import SwiftUI
import UIKit
import DictusCore

/// Hidden screen surfacing recent polish invocations. Reached by long-pressing
/// the Version row in Settings for 3 seconds. Round-1 debugging tool — no
/// analytics, no shipping in product UX. Events persist in the App Group
/// container for 7 days so cold-start tests survive an app kill.
struct PolishDebugView: View {

    @State private var entries: [PolishDebugEntry] = []
    @State private var storedCount: Int = 0
    @State private var selectedEntry: PolishDebugEntry?
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var isExporting = false

    var body: some View {
        List {
            if !entries.isEmpty {
                Section {
                    BreakdownRow(entries: entries)
                } header: {
                    Text("Outcomes (\(entries.count) shown)")
                } footer: {
                    if storedCount > entries.count {
                        Text("\(storedCount) total events persisted (last 7 days). Export ships the full window.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Persisted in App Group for 7 days. Export ships the full window.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
                Menu {
                    Button {
                        Task { await handleExport() }
                    } label: {
                        Label("Export JSON…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(storedCount == 0 || isExporting)
                    Button(role: .destructive) {
                        Task {
                            await PolishCoordinator.shared.clearMetricsRing()
                            await refresh()
                        }
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(storedCount == 0)
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            NavigationStack {
                EntryDetailView(entry: entry)
            }
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { if !$0 { exportURL = nil } }
        )) {
            if let exportURL {
                PolishExportShareSheet(items: [exportURL])
            }
        }
        .alert("Export failed",
               isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
               ),
               actions: { Button("OK", role: .cancel) { exportError = nil } },
               message: { Text(exportError ?? "") })
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func handleExport() async {
        guard !isExporting else { return }
        isExporting = true
        // Pull the full 7-day window from disk, not just the in-memory cache.
        let allEntries = await PolishCoordinator.shared.metricsAllEntries()
        do {
            exportURL = try PolishDebugExporter.writeToTempFile(entries: allEntries)
        } catch {
            exportError = error.localizedDescription
        }
        isExporting = false
    }

    private func refresh() async {
        entries = await PolishCoordinator.shared.metricsSnapshot()
        storedCount = await PolishCoordinator.shared.metricsStoredCount()
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
                if let stt = entry.metrics.sttModelID {
                    Text("stt=\(stt)")
                }
                Text("det=\(entry.metrics.detectedLanguage ?? "-")")
                Text("\(entry.metrics.latencyMs)ms")
                Text("\(entry.metrics.rawCharCount)→\(entry.metrics.polishedCharCount)")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
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
                LabeledValue("stt engine", entry.metrics.sttEngine ?? "-")
                LabeledValue("stt model", entry.metrics.sttModelID ?? "-")
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

// MARK: - Share sheet wrapper

private struct PolishExportShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Outcome display helpers

private extension PolishMetrics.Outcome {
    static var allDisplayCases: [PolishMetrics.Outcome] {
        [.success, .rejectedGuardrail, .skipped, .skippedShort, .skippedAutoMode, .cancelled, .engineFailed]
    }

    var shortLabel: String {
        switch self {
        case .success: return "success"
        case .rejectedGuardrail: return "rejected"
        case .skipped: return "skipped"
        case .skippedShort: return "short"
        case .skippedAutoMode: return "auto"
        case .cancelled: return "cancelled"
        case .engineFailed: return "failed"
        }
    }

    var tintColor: Color {
        switch self {
        case .success: return .green
        case .rejectedGuardrail, .skipped, .skippedShort, .skippedAutoMode: return .orange
        case .cancelled, .engineFailed: return .red
        }
    }
}
