// DictusApp/Polish/PolishMetricsRing.swift
import Foundation
import DictusCore

/// DictusApp's view of the polish debug ring: a memory cache for the debug screen,
/// plus the retention and clearing the app alone performs.
///
/// The file itself, its format and its append primitive live in
/// `PolishEventStore` (DictusCore), because since #361 the keyboard extension
/// appends to the same file. What stayed here is everything the keyboard must not
/// do: bootstrap (a read of the seven-day window), prune, and clear. Keeping the
/// destructive operations single-writer is what lets two processes share the file
/// without a locking story beyond the coordinated append.
public actor PolishMetricsRing: PolishEventSink {

    /// In-memory cap for the UI snapshot. The full 7-day window stays on disk.
    private static let memoryCacheLimit = 200

    private var memoryCache: [PolishDebugEntry] = []
    private var bootstrapped = false

    public init() {}

    // MARK: - PolishEventSink

    public func record(_ entry: PolishDebugEntry) async {
        await bootstrapIfNeeded()
        memoryCache.append(entry)
        if memoryCache.count > Self.memoryCacheLimit {
            memoryCache.removeFirst(memoryCache.count - Self.memoryCacheLimit)
        }
        PolishEventStore.append(entry)
    }

    // MARK: - Debug screen

    /// Most recent entries (capped at `memoryCacheLimit`) for the debug UI.
    ///
    /// Read from disk rather than served straight from the cache since #361: the
    /// keyboard's events never pass through this process, so a cache built from
    /// what the app itself recorded would show an empty screen on a device where
    /// every dictation goes through the keyboard — which is every normal device.
    public func snapshot() async -> [PolishDebugEntry] {
        await bootstrapIfNeeded()
        memoryCache = Array(PolishEventStore.readAll(applyingRetention: true)
            .suffix(Self.memoryCacheLimit))
        return memoryCache
    }

    /// All entries within the 7-day retention window — used by the JSON export.
    /// Reads from disk to bypass the memory cap.
    public func allEntries() async -> [PolishDebugEntry] {
        await bootstrapIfNeeded()
        return PolishEventStore.readAll(applyingRetention: true)
    }

    /// Total entries within the retention window. Cheap-enough disk read.
    public func storedCount() async -> Int {
        await bootstrapIfNeeded()
        return PolishEventStore.readAll(applyingRetention: true).count
    }

    public func clear() async {
        memoryCache.removeAll()
        PolishEventStore.clear()
    }

    // MARK: - Bootstrap

    private func bootstrapIfNeeded() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        PolishEventStore.pruneOldEntries()
        let recent = PolishEventStore.readAll(applyingRetention: true)
        memoryCache = Array(recent.suffix(Self.memoryCacheLimit))
    }
}
