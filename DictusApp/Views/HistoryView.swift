// DictusApp/Views/HistoryView.swift
// The saved dictations, newest first, reached by swiping up from the home screen.
import SwiftUI
import DictusCore

/// The transcription history (#70): every saved dictation as a glass card.
///
/// WHY it is presented as a sheet by `HomeView` rather than pushed or given a tab:
/// the issue asks for a vertical transition out of the home screen and a swipe-down
/// back to it, and a sheet is both of those natively — including the interactive,
/// interruptible drag that a hand-rolled transition would have to reimplement. The
/// tab bar stays at three entries, which the brief is explicit about.
///
/// WHY a `List` and not a `ScrollView` of cards: swipe-to-delete is the interaction
/// the issue names, and `List` is the only thing on iOS that gives it — with the
/// right hit area, the right rubber-banding and the right row-removal animation. The
/// glass look survives it: clear row backgrounds, no separators, no list background.
struct HistoryView: View {

    @EnvironmentObject var history: TranscriptionHistoryStore
    @Environment(\.dismiss) private var dismiss

    /// The record whose full text is on screen, driving the push. Not a
    /// `NavigationLink` per row: the link would draw its own disclosure chevron
    /// outside the card and take the row's tap area away from the card itself.
    @State private var selection: TranscriptionRecord?

    var body: some View {
        NavigationStack {
            Group {
                if history.records.isEmpty {
                    emptyState
                } else {
                    recordList
                }
            }
            .background(Color.dictusBackground.ignoresSafeArea())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationDestination(item: $selection) { record in
                TranscriptionDetailView(record: record)
            }
        }
        // The grabber says the sheet is draggable, which is the same statement the
        // hint on the home screen makes about the swipe that opened it.
        .presentationDragIndicator(.visible)
    }

    // MARK: - List

    private var recordList: some View {
        List {
            ForEach(history.records) { record in
                Button {
                    selection = record
                } label: {
                    HistoryCard(record: record)
                }
                .buttonStyle(GlassPressStyle(pressedScale: 0.98))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        delete(record)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    // The long-press half of the issue's "long-press or swipe to
                    // delete", with the copy the detail screen also offers: a
                    // long-press that only ever destroys is a trap to open by accident.
                    Button {
                        UIPasteboard.general.string = record.text
                        HapticFeedback.recordingStopped()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        delete(record)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func delete(_ record: TranscriptionRecord) {
        withAnimation {
            history.delete(id: record.id)
        }
        HapticFeedback.recordingStopped()
    }

    // MARK: - Empty state

    /// Shown before the first dictation is saved. It names the action that fills the
    /// screen rather than only stating that it is empty, because on a fresh install
    /// this is the first thing the swipe-up hint leads to.
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 44))
                .foregroundColor(.dictusAccent.opacity(0.7))
            Text("No transcriptions yet")
                .font(.dictusSubheading)
            Text("Your dictations are saved here automatically. The last 200 are kept, on this device only.")
                .font(.dictusCaption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card

/// One saved dictation: two lines of the text, then the date, the language and how
/// long the recording was.
private struct HistoryCard: View {

    let record: TranscriptionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.text)
                .font(.dictusBody)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Text(dateLabel)
                Text("·")
                Text(record.languageBadge)
                Text("·")
                Text(record.durationLabel)
                Spacer()
            }
            .font(.dictusCaption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .dictusGlass()
    }

    /// Today reads as a time, this year as a day and month, anything older carries
    /// the year. Formatted by Foundation rather than by a string in the catalogue:
    /// the order of the parts and the month's abbreviation are the user's locale's
    /// business, not a translation.
    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(record.createdAt) {
            return record.createdAt.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDate(record.createdAt, equalTo: Date(), toGranularity: .year) {
            return record.createdAt.formatted(.dateTime.day().month(.abbreviated))
        }
        return record.createdAt.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

#Preview {
    HistoryView()
        .environmentObject(TranscriptionHistoryStore.shared)
}
