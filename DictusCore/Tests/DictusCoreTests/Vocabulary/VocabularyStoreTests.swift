// DictusCore/Tests/DictusCoreTests/Vocabulary/VocabularyStoreTests.swift
// The 200-entry cap, the entitlement gate, and Reset vocabulary (#80 decision 10).
import XCTest
@testable import DictusCore

@MainActor
final class VocabularyStoreTests: XCTestCase {

    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocabulary-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        super.tearDown()
    }

    private func makeStore(entitled: Bool = true) -> VocabularyStore {
        VocabularyStore(fileURL: fileURL, isEntitled: { entitled })
    }

    private func entry(_ term: String, _ variants: [String] = []) -> VocabularyEntry {
        guard let entry = VocabularyEntry(term: term, variants: variants) else {
            XCTFail("entry \(term) should be constructible")
            return VocabularyEntry(term: "fallback")! // swiftlint:disable:this force_unwrapping
        }
        return entry
    }

    // MARK: - The 200-entry limit

    func testTwoHundredEntriesFitAndTheTwoHundredAndFirstIsRefused() {
        let store = makeStore()
        for index in 0..<VocabularyStore.maxEntries {
            XCTAssertTrue(store.add(entry("Term\(index)")), "entry \(index) should be accepted")
        }
        XCTAssertEqual(store.count, VocabularyStore.maxEntries)
        XCTAssertTrue(store.isFull)
        XCTAssertFalse(store.add(entry("OneTooMany")))
        XCTAssertEqual(store.count, VocabularyStore.maxEntries)
    }

    func testTheCapRefusesRatherThanEvicting() {
        // Unlike the history, which drops its oldest record: a term that vanished on
        // its own would stop correcting text with nothing on screen to say why.
        let store = makeStore()
        for index in 0..<VocabularyStore.maxEntries { store.add(entry("Term\(index)")) }
        store.add(entry("OneTooMany"))
        XCTAssertTrue(store.entries.contains { $0.term == "Term0" })
        XCTAssertFalse(store.entries.contains { $0.term == "OneTooMany" })
    }

    // MARK: - The entitlement

    func testAddIsRefusedWithoutTheEntitlement() {
        let store = makeStore(entitled: false)
        XCTAssertFalse(store.add(entry("Kubernetes")))
        XCTAssertTrue(store.isEmpty)
    }

    func testRemovalIsNeverGated() {
        // A lapsed subscription must not imprison the data, the rule
        // `HistoryAvailability.clearRowIsVisible` states for the history.
        let seeding = makeStore()
        seeding.add(entry("Kubernetes"))
        seeding.add(entry("Parakeet"))

        let lapsed = VocabularyStore(fileURL: fileURL, isEntitled: { false })
        XCTAssertEqual(lapsed.count, 2)
        lapsed.delete(id: lapsed.entries[0].id)
        XCTAssertEqual(lapsed.count, 1)
        lapsed.resetAll()
        XCTAssertTrue(lapsed.isEmpty)
    }

    // MARK: - Duplicates

    func testTheSameCanonicalTermCannotBeStoredTwiceWhateverTheCase() {
        let store = makeStore()
        XCTAssertTrue(store.add(entry("Kubernetes")))
        XCTAssertFalse(store.add(entry("kubernetes")))
        XCTAssertEqual(store.count, 1)
    }

    func testContainsCanExcludeTheEntryBeingEdited() {
        let store = makeStore()
        store.add(entry("Kubernetes"))
        let stored = store.entries[0]
        XCTAssertTrue(store.contains(term: "Kubernetes"))
        XCTAssertFalse(store.contains(term: "Kubernetes", excluding: stored.id))
    }

    // MARK: - Persistence

    func testEntriesSurviveAcrossInstances() {
        let writer = makeStore()
        writer.add(entry("Kubernetes", ["cubernetes"]))
        let reader = makeStore()
        XCTAssertEqual(reader.entries.map(\.term), ["Kubernetes"])
        XCTAssertEqual(reader.entries.first?.variants, ["cubernetes"])
    }

    func testResetVocabularyEmptiesTheFileAndNotOnlyTheMemory() {
        let store = makeStore()
        store.add(entry("Kubernetes", ["cubernetes"]))
        store.resetAll()
        XCTAssertTrue(makeStore().isEmpty, "the next process must not find the old list")
    }

    func testACorruptFileReadsAsAnEmptyVocabulary() {
        try? Data("not json at all".utf8).write(to: fileURL)
        XCTAssertTrue(makeStore().isEmpty)
    }

    func testAnEntryThatBreaksTheLimitsIsDroppedAtLoadAndTheRestSurvives() {
        let long = String(repeating: "a", count: VocabularyEntry.maxFieldLength + 1)
        let json = """
        [{"id":"\(UUID().uuidString)","term":"\(long)","variants":[],\
        "isEnabled":true,"dateAdded":"2026-09-07T10:00:00Z"},
         {"id":"\(UUID().uuidString)","term":"Kubernetes","variants":["cubernetes"],\
        "isEnabled":true,"dateAdded":"2026-09-07T10:00:00Z"}]
        """
        try? Data(json.utf8).write(to: fileURL)
        XCTAssertEqual(makeStore().entries.map(\.term), ["Kubernetes"])
    }

    func testTheStoreLivesInTheAppGroupContainerBesideTheHistory() {
        // The reason is #428: shared `UserDefaults` survives a reinstall with no way
        // out, and a corrupted vocabulary would too. A file has Reset vocabulary.
        XCTAssertEqual(VocabularyStore.fileName, "vocabulary.json")
        XCTAssertEqual(
            VocabularyStore.defaultFileURL?.deletingLastPathComponent(),
            TranscriptionHistoryStore.defaultFileURL?.deletingLastPathComponent()
        )
    }

    // MARK: - Mutation

    func testUpdateKeepsThePositionAndTheDate() {
        let store = makeStore()
        store.add(entry("Alpha"))
        store.add(entry("Beta"))
        let target = store.entries[1]
        guard let edited = VocabularyEntry(
            term: "Alpha", variants: ["alfa"], id: target.id, dateAdded: target.dateAdded
        ) else { return XCTFail("edited entry should be constructible") }
        store.update(edited)
        XCTAssertEqual(store.entries.map(\.term), ["Beta", "Alpha"])
        XCTAssertEqual(store.entries[1].variants, ["alfa"])
        XCTAssertEqual(store.entries[1].dateAdded, target.dateAdded)
    }

    func testTogglingAnEntryOffKeepsItStored() {
        let store = makeStore()
        store.add(entry("Kubernetes", ["cubernetes"]))
        store.update(store.entries[0].enabled(false))
        XCTAssertEqual(store.count, 1)
        XCTAssertFalse(store.entries[0].isEnabled)
        XCTAssertEqual(makeStore().entries.first?.isEnabled, false)
    }

    func testDeletingByOffsetsMatchesTheListsOwnSwipe() {
        let store = makeStore()
        store.add(entry("Alpha"))
        store.add(entry("Beta"))
        store.add(entry("Gamma"))
        store.delete(atOffsets: IndexSet(integer: 0))
        XCTAssertEqual(store.entries.map(\.term), ["Beta", "Alpha"])
    }
}
