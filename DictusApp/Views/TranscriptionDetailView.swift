// DictusApp/Views/TranscriptionDetailView.swift
// One saved dictation in full, with the two things you do with text you got back.
import SwiftUI
import DictusCore

/// The full text of a saved dictation, with copy and share (#70).
///
/// WHY the text is selectable as well as copyable: the card truncates at two lines,
/// so this screen is where a long dictation is read — and often only part of it is
/// wanted. A copy button that can only take the whole thing makes the user paste and
/// then delete.
struct TranscriptionDetailView: View {

    let record: TranscriptionRecord

    @State private var showCopiedFeedback = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metadataRow

                Text(record.text)
                    .font(.dictusBody)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
                    .dictusGlass()

                actions
            }
            .padding()
        }
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle("Transcription")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        HStack(spacing: 6) {
            Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
            Text("·")
            Text(record.languageBadge)
            Text("·")
            Text(record.durationLabel)
            Spacer()
        }
        .font(.dictusCaption)
        .foregroundColor(.secondary)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                UIPasteboard.general.string = record.text
                HapticFeedback.recordingStopped()
                showCopiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopiedFeedback = false
                }
            } label: {
                Label(
                    showCopiedFeedback ? "Copied!" : "Copy",
                    systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity)
                .padding()
                .background(showCopiedFeedback ? Color.dictusSuccess : Color.dictusAccent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(GlassPressStyle())
            .animation(.easeOut(duration: 0.2), value: showCopiedFeedback)

            // ShareLink rather than the UIActivityViewController wrapper the log
            // export uses: that one exists because it shares a file URL and needs the
            // file name to survive. This shares a string, which ShareLink handles on
            // its own from iOS 16.
            ShareLink(item: record.text) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.dictusAccent)
                    .dictusGlass(in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(GlassPressStyle())
        }
    }
}

#Preview {
    NavigationStack {
        TranscriptionDetailView(record: TranscriptionRecord(
            text: "Bonjour, ceci est un test de dictée.",
            language: "fr",
            durationSeconds: 12,
            sttProvider: SpeechEngine.whisperKit.rawValue
        ))
    }
}
