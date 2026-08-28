// DictusCore/Sources/DictusCore/History/TranscriptionHistoryStore.swift
// The saved dictations (#70): one JSON file in the App Group, loaded once.
import Foundation
import SwiftUI

/// Every dictation the user has made, newest first.
///
/// ### Why a JSON file and not SwiftData (#70, brief decision 1)
///
/// The repo has no persistence framework, and everything shared already goes
/// through the App Group container. SwiftData would add a model container, a
/// schema and a migration path for what is a flat list of at most a few hundred
/// short records, and it would have to be taught to live in a shared container so
/// the keyboard can read it later (premium search, #216).
///
/// ### Why DictusCore and not DictusApp
///
/// So the keyboard extension can read it later without a second implementation.
/// **It does not write it in this issue** — every mutation below runs in DictusApp,
/// which is also the only process that transcribes. That single-writer property is
/// what lets this file skip `NSFileCoordinator`, unlike `PolishEventStore`, which
/// really does have two writers. A second writer arriving later has to revisit this
/// paragraph, not just add a call.
///
/// ### Load once, write whole
///
/// `records` is the truth for the lifetime of the process; the file is read once,
/// in `init`, and rewritten in full on every mutation. At the cap that is 200 short
/// strings — cheap enough that the alternative (an append-only journal plus
/// compaction, which is what `PolishEventStore` needs for its two writers) buys
/// nothing here. The write is atomic, so a process killed mid-write leaves the
/// previous file rather than a truncated one.
///
/// WHY the read is eager and not deferred to the first access: `records` is
/// `@Published`, so it has to be a stored property, and a lazy load would have to
/// be triggered by something other than reading it — which means every reader,
/// SwiftUI bodies included, has to remember to call it first. One of them will not.
///
/// ### Privacy
///
/// This is a plaintext record of everything the user has ever dictated. It never
/// leaves the device — no cloud, no sync, no export in this issue — and Settings
/// carries a destructive row that empties it (brief decision 3). Audio is never
/// stored, and there is no path to it from here.
///
/// ### The entitlement gates growth, never removal
///
/// The history is a Pro feature (`HistoryAvailability`), so `append` refuses
/// without the entitlement and **nothing is stored for a non-subscriber** — not
/// stored and hidden, not stored at all.
///
/// `delete`, `delete(atOffsets:)`, `clear` and `updateText` are deliberately NOT
/// gated. A lapsed subscription must not imprison the data: whatever is already on
/// disk stays deletable by its owner for as long as it exists. Expressing that as
/// "the gate is on the one method that grows the file" makes it a property of the
/// type rather than a rule four call sites have to remember.
///
/// WHY the gate is here and not in `DictationHandoff`: `append` is the single point
/// every dictation of either origin passes, which is what
/// `SmartModeStore.resolveArmedMode()` is for #395's entitlement. A gate at the
/// call sites would be two copies today and would miss the third caller written
/// next year.
@MainActor
public final class TranscriptionHistoryStore: ObservableObject {

    /// The app-wide store. A singleton for the same reason `UserDictionary` is one:
    /// the in-memory copy IS the truth, so two instances would silently overwrite
    /// each other's writes.
    public static let shared = TranscriptionHistoryStore()

    /// Newest first. The order the history view renders directly — sorting at read
    /// time would re-sort 200 records on every SwiftUI body evaluation to answer a
    /// question the writer already knows the answer to.
    @Published public private(set) var records: [TranscriptionRecord]

    /// Maximum number of saved dictations (brief decision 2).
    ///
    /// WHY a cap and not an expiry: the oldest entry falls off when the 201st
    /// arrives, and nothing vanishes on its own. A transcription that disappeared
    /// three months later would read as a bug rather than as a policy, and there is
    /// no UI in this issue that would explain it.
    public static let maxRecords = 200

    static let fileName = "transcription_history.json"

    /// Where the records live, or nil when the App Group container is unreachable —
    /// which on device means the entitlement is broken and nothing else works either.
    ///
    /// `nonisolated` so it can be the default argument of `init`, which runs before
    /// the instance exists and therefore outside the actor.
    nonisolated public static var defaultFileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    private let fileURL: URL?

    /// Whether the user may store new dictations, read when `append` is called
    /// rather than captured once: an entitlement can lapse while the process lives.
    private let isEntitled: () -> Bool

    /// - Parameters:
    ///   - fileURL: the backing file. Defaults to the App Group container; the tests
    ///     pass a temporary path so they exercise the real read/write path without a
    ///     shared container.
    ///   - isEntitled: the Pro gate. Injected so the tests can drive both directions
    ///     — nobody can be a subscriber on a device until #215 opens the paywall, so
    ///     a gate only reachable through `FeatureGate` would be a gate only one half
    ///     of which anyone could ever exercise.
    init(fileURL: URL? = TranscriptionHistoryStore.defaultFileURL,
         isEntitled: @escaping () -> Bool = { HistoryAvailability.isEntitled }) {
        self.fileURL = fileURL
        self.isEntitled = isEntitled
        self.records = Self.read(from: fileURL)
    }

    // MARK: - Reading

    /// The number of saved dictations, for the Settings confirmation.
    public var count: Int { records.count }

    public var isEmpty: Bool { records.isEmpty }

    // MARK: - Writing

    /// Save a dictation, or refuse. Returns the record so the caller can update its
    /// text later, and nil when nothing was stored.
    ///
    /// Refused without the Pro entitlement, which is the whole gate for this
    /// feature — see the type's documentation. Refused for empty text too: a
    /// dictation that produced nothing is a failure the user already saw a sentence
    /// about (#313), and a blank card would be the second, quieter report of it.
    @discardableResult
    public func append(_ record: TranscriptionRecord) -> TranscriptionRecord? {
        guard isEntitled() else { return nil }
        guard !record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        records.insert(record, at: 0)
        if records.count > Self.maxRecords {
            records.removeLast(records.count - Self.maxRecords)
        }
        persist()
        return record
    }

    /// Replace the text of a record already saved, keeping its place and its date.
    ///
    /// **This is what a keyboard dictation needs.** The app writes the raw text down
    /// before the keyboard polishes it (#361: the raw is durable before any
    /// generation starts), and the keyboard reports what it actually typed seconds
    /// later. Appending a second record then would show the user one dictation
    /// twice; leaving the raw would show them text they never sent. A record whose
    /// id is gone — evicted by the cap, or deleted by the user in between — is left
    /// alone, which is why this returns nothing and never re-inserts.
    /// Ungated, unlike `append`: this can only ever touch a record that is already
    /// on disk, so it does not grow the history. Refusing it after a lapse between
    /// the hand-off and the keyboard reporting back would leave the raw text
    /// standing where the polished text belongs, which serves nobody.
    public func updateText(id: UUID, to newText: String) {
        guard !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        guard records[index].text != newText else { return }
        records[index] = records[index].withText(newText)
        persist()
    }

    public func delete(id: UUID) {
        let remaining = records.filter { $0.id != id }
        guard remaining.count != records.count else { return }
        records = remaining
        persist()
    }

    /// Delete by row offsets, for `List`'s own swipe-to-delete.
    public func delete(atOffsets offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        records.remove(atOffsets: offsets)
        persist()
    }

    /// Empty the history. The destructive Settings row (brief decision 3).
    public func clear() {
        guard !records.isEmpty else { return }
        records = []
        persist()
    }

    // MARK: - Disk

    private func persist() {
        Self.write(records, to: fileURL)
    }

    static func read(from url: URL?) -> [TranscriptionRecord] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        // A file that will not decode is treated as no history rather than as a
        // fatal error: this is a convenience feature, and the next append rewrites
        // the file whole. Nothing else in the app depends on it.
        return (try? decoder.decode([TranscriptionRecord].self, from: data)) ?? []
    }

    static func write(_ records: [TranscriptionRecord], to url: URL?) {
        guard let url, let data = try? encoder.encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Shared so the writer and the reader cannot drift on the date strategy, which
    /// is the one disagreement that would silently drop every record.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
