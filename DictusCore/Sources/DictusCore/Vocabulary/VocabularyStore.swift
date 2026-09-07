// DictusCore/Sources/DictusCore/Vocabulary/VocabularyStore.swift
// The user's vocabulary: one JSON file in the App Group (#80 decision 10).
import Foundation
import SwiftUI

/// Every term the user taught Dictus, newest first.
///
/// ### Why a file and not App Group `UserDefaults` (#80 decision 10)
///
/// #428 is the reason, and it is worth stating in full because the alternative looks
/// cheaper: `dictus.modelLoadState = "loading"` stuck in shared `UserDefaults` locked
/// the whole app six launches running, and reinstalling did not clear it — the App
/// Group container survives a reinstall, measured on 2026-08-26 across six
/// reinstalls and a TestFlight build. A corrupted vocabulary would survive exactly
/// the same way, and a user with no way out. A file is inspectable, removable in one
/// action, and **Reset vocabulary** is that action.
///
/// The shape is `TranscriptionHistoryStore`'s, deliberately: same container, same
/// load-once/write-whole discipline, same atomic write, same injectable URL for
/// tests. Two files with the same lifecycle should not have two implementations.
///
/// ### Single writer
///
/// Every mutation below runs in DictusApp, which is the only process with a
/// vocabulary screen. The keyboard extension **reads** — `PolishGlossary` asks it for
/// the user's terms while building a prompt — and never writes, which is what lets
/// this file skip `NSFileCoordinator`, exactly as the history does. A second writer
/// arriving later has to revisit this paragraph, not just add a call.
///
/// ### The entitlement gates growth, never removal
///
/// `add` refuses without the Pro entitlement, on the model of
/// `TranscriptionHistoryStore.append`. `delete`, `update` and `resetAll` are
/// ungated: a lapsed subscription must not imprison data the user can no longer see.
@MainActor
public final class VocabularyStore: ObservableObject {

    /// The app-wide store. A singleton for the reason `TranscriptionHistoryStore` is
    /// one: the in-memory copy IS the truth, so two instances would silently
    /// overwrite each other's writes.
    public static let shared = VocabularyStore()

    /// Newest first, the order the list renders directly.
    @Published public private(set) var entries: [VocabularyEntry]

    /// Maximum number of entries (#80 decision 10).
    ///
    /// WHY a refusal and not an eviction, which is what the history does: a
    /// transcription that falls off the end of a log is a record the user is not
    /// looking for, but a vocabulary term that vanished would stop correcting text
    /// with nothing on screen to say why. The 201st add is refused and the sheet
    /// says so.
    public static let maxEntries = 200

    /// `nonisolated` so `defaultFileURL`, which is itself nonisolated because it is
    /// the default argument of `init`, can name it.
    nonisolated static let fileName = "vocabulary.json"

    /// Where the entries live, or nil when the App Group container is unreachable —
    /// which on device means the entitlement is broken and nothing else works either.
    ///
    /// `nonisolated` so it can be the default argument of `init`, which runs before
    /// the instance exists and therefore outside the actor.
    nonisolated public static var defaultFileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent(fileName)
    }

    private let fileURL: URL?

    /// The Pro gate, read at each call rather than captured once: an entitlement can
    /// lapse while the process lives.
    private let isEntitled: () -> Bool

    /// - Parameters:
    ///   - fileURL: the backing file. Defaults to the App Group container; the tests
    ///     pass a temporary path so they exercise the real read/write path without a
    ///     shared container.
    ///   - isEntitled: injected so the tests can drive both directions. Nobody can be
    ///     a subscriber on a device until #279 opens the paywall, so a gate reachable
    ///     only through `FeatureGate` would be a gate only one half of which anyone
    ///     could exercise.
    init(fileURL: URL? = VocabularyStore.defaultFileURL,
         isEntitled: @escaping () -> Bool = { VocabularyAvailability.isEntitled }) {
        self.fileURL = fileURL
        self.isEntitled = isEntitled
        self.entries = Self.read(from: fileURL)
    }

    // MARK: - Reading

    public var count: Int { entries.count }

    public var isEmpty: Bool { entries.isEmpty }

    public var isFull: Bool { entries.count >= Self.maxEntries }

    // MARK: - Writing

    /// Store a term, or refuse.
    ///
    /// Refused without the entitlement, at the cap, and when the term duplicates one
    /// already stored — two entries claiming the same canonical spelling would make
    /// the list unreadable and buy nothing the variants of one entry do not.
    @discardableResult
    public func add(_ entry: VocabularyEntry) -> Bool {
        guard isEntitled(), !isFull else { return false }
        guard !contains(term: entry.term) else { return false }
        entries.insert(entry, at: 0)
        persist()
        return true
    }

    /// Whether a canonical spelling is already stored, ignoring case.
    /// `excluding` skips one entry, so the edit sheet does not collide with itself.
    public func contains(term: String, excluding id: UUID? = nil) -> Bool {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.contains { $0.id != id && $0.term.lowercased() == needle }
    }

    /// Replace an entry in place, keeping its position and its `dateAdded`.
    /// Ungated: it cannot grow the file.
    public func update(_ entry: VocabularyEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        guard entries[index] != entry else { return }
        entries[index] = entry
        persist()
    }

    public func delete(id: UUID) {
        let remaining = entries.filter { $0.id != id }
        guard remaining.count != entries.count else { return }
        entries = remaining
        persist()
    }

    /// Delete by row offsets, for `List`'s own swipe-to-delete.
    public func delete(atOffsets offsets: IndexSet) {
        guard !offsets.isEmpty else { return }
        entries.remove(atOffsets: offsets)
        persist()
    }

    /// **Reset vocabulary** (#80 decision 10), on the model of #287's "Reset learned
    /// words": the one action that empties the list, and the exit from a file that
    /// would otherwise survive a reinstall.
    public func resetAll() {
        guard !entries.isEmpty else { return }
        entries = []
        persist()
    }

    /// Re-read the file. The app's own screen is the only writer, so this exists for
    /// the same reason `UserDictionary.reload()` does: a settings screen opened after
    /// something else touched the container should not show a stale list.
    public func reload() {
        entries = Self.read(from: fileURL)
    }

    // MARK: - Disk

    private func persist() {
        Self.write(entries, to: fileURL)
    }

    /// The cross-process read. `nonisolated` and static because its callers are the
    /// replacement pass and the polish glossary, neither of which is on the main
    /// actor and one of which runs inside the keyboard extension.
    nonisolated public static func loadEntries(
        from url: URL? = VocabularyStore.defaultFileURL
    ) -> [VocabularyEntry] {
        read(from: url)
    }

    nonisolated static func read(from url: URL?) -> [VocabularyEntry] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        // A file that will not decode is treated as an empty vocabulary rather than
        // as a fatal error, and an entry that violates the limits is dropped rather
        // than trusted: this file is hand-editable by anyone with the container, and
        // an over-long needle would cost a full scan of every transcript.
        let decoded = (try? decoder.decode([VocabularyEntry].self, from: data)) ?? []
        return decoded.filter { $0.isValid }
    }

    nonisolated static func write(_ entries: [VocabularyEntry], to url: URL?) {
        guard let url, let data = try? encoder.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Shared so the writer and the reader cannot drift on the date strategy, which
    /// is the one disagreement that would silently drop every entry.
    nonisolated static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    nonisolated static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
