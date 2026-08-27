// DictusCore/Tests/DictusCoreTests/TranscriptionHistoryStoreTests.swift
// The history store (#70): the cap, the order, the deletes and the round trip.
//
// WHY a temporary file rather than the App Group container: the store's whole
// contract is "what you appended is what you read back after a relaunch", and a
// temp file exercises the real read/write path without depending on a shared
// container an unsigned test host may not have. Same seam PolishEventStoreTests uses.
import XCTest
@testable import DictusCore

@MainActor
final class TranscriptionHistoryStoreTests: XCTestCase {

    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeStore() -> TranscriptionHistoryStore {
        TranscriptionHistoryStore(fileURL: url)
    }

    private func record(_ text: String,
                        language: String = "fr",
                        duration: Int = 3,
                        at date: Date = Date()) -> TranscriptionRecord {
        TranscriptionRecord(
            text: text,
            language: language,
            durationSeconds: duration,
            createdAt: date,
            sttProvider: SpeechEngine.whisperKit.rawValue
        )
    }

    // MARK: - Order

    func testNewestRecordComesFirst() {
        let store = makeStore()
        store.append(record("un"))
        store.append(record("deux"))
        store.append(record("trois"))

        XCTAssertEqual(store.records.map(\.text), ["trois", "deux", "un"])
    }

    // MARK: - Cap

    func testCapDropsTheOldestRecord() {
        let store = makeStore()
        for index in 0..<TranscriptionHistoryStore.maxRecords {
            store.append(record("entry \(index)"))
        }
        XCTAssertEqual(store.records.count, TranscriptionHistoryStore.maxRecords)
        XCTAssertEqual(store.records.last?.text, "entry 0")

        store.append(record("overflow"))

        XCTAssertEqual(store.records.count, TranscriptionHistoryStore.maxRecords,
                       "The cap holds; the store never grows past it.")
        XCTAssertEqual(store.records.first?.text, "overflow")
        XCTAssertEqual(store.records.last?.text, "entry 1",
                       "FIFO: the oldest entry is the one that falls off.")
    }

    func testEmptyTextIsNotSaved() {
        let store = makeStore()
        XCTAssertNil(store.append(record("")))
        XCTAssertNil(store.append(record("   \n ")))
        XCTAssertTrue(store.records.isEmpty)
    }

    // MARK: - Update

    func testUpdateTextKeepsThePlaceAndTheDate() {
        let store = makeStore()
        let old = Date(timeIntervalSince1970: 1_000)
        guard let first = store.append(record("raw", at: old)) else {
            return XCTFail("The record was refused")
        }
        store.append(record("later"))

        store.updateText(id: first.id, to: "polished")

        XCTAssertEqual(store.records.map(\.text), ["later", "polished"])
        XCTAssertEqual(store.records.last?.createdAt, old)
        XCTAssertEqual(store.records.last?.id, first.id)
    }

    func testUpdateTextIgnoresAnUnknownRecord() {
        let store = makeStore()
        store.append(record("un"))

        store.updateText(id: UUID(), to: "ghost")

        XCTAssertEqual(store.records.map(\.text), ["un"],
                       "A record evicted or deleted in the meantime is not re-inserted.")
    }

    func testUpdateTextIgnoresEmptyText() {
        let store = makeStore()
        guard let saved = store.append(record("raw")) else {
            return XCTFail("The record was refused")
        }
        store.updateText(id: saved.id, to: "  ")
        XCTAssertEqual(store.records.first?.text, "raw")
    }

    // MARK: - Delete

    func testDeleteByIDRemovesOnlyThatRecord() {
        let store = makeStore()
        store.append(record("un"))
        guard let middle = store.append(record("deux")) else {
            return XCTFail("The record was refused")
        }
        store.append(record("trois"))

        store.delete(id: middle.id)

        XCTAssertEqual(store.records.map(\.text), ["trois", "un"])
    }

    func testDeleteByOffsetsRemovesTheSelectedRows() {
        let store = makeStore()
        store.append(record("un"))
        store.append(record("deux"))
        store.append(record("trois"))

        // Rows are newest first: offset 0 is "trois".
        store.delete(atOffsets: IndexSet(integer: 0))

        XCTAssertEqual(store.records.map(\.text), ["deux", "un"])
    }

    func testClearEmptiesEverything() {
        let store = makeStore()
        store.append(record("un"))
        store.append(record("deux"))

        store.clear()

        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(TranscriptionHistoryStore.read(from: url).count, 0,
                       "Clearing reaches the file, not only the memory copy.")
    }

    // MARK: - Persistence

    func testRecordsSurviveANewProcess() {
        let store = makeStore()
        store.append(record("un", language: "en", duration: 42))
        store.append(record("deux"))

        // A second store reading the same file is what a relaunch looks like.
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.records.map(\.text), ["deux", "un"])
        XCTAssertEqual(reloaded.records.last?.language, "en")
        XCTAssertEqual(reloaded.records.last?.durationSeconds, 42)
        XCTAssertEqual(reloaded.records.last?.sttProvider, SpeechEngine.whisperKit.rawValue)
    }

    func testDatesSurviveTheRoundTrip() throws {
        let store = makeStore()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        store.append(record("un", at: when))

        let reloaded = try XCTUnwrap(makeStore().records.first)
        XCTAssertEqual(reloaded.createdAt.timeIntervalSince1970,
                       when.timeIntervalSince1970,
                       accuracy: 1)
    }

    func testDeletionsSurviveANewProcess() {
        let store = makeStore()
        guard let first = store.append(record("un")) else {
            return XCTFail("The record was refused")
        }
        store.append(record("deux"))
        store.delete(id: first.id)

        XCTAssertEqual(makeStore().records.map(\.text), ["deux"])
    }

    func testACorruptFileReadsAsNoHistory() throws {
        try "not json at all".write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()

        XCTAssertTrue(store.records.isEmpty)
        // And it recovers: the next append rewrites the file whole.
        store.append(record("un"))
        XCTAssertEqual(makeStore().records.map(\.text), ["un"])
    }

    func testAMissingFileReadsAsNoHistory() {
        XCTAssertTrue(makeStore().records.isEmpty)
    }

    // MARK: - The record itself

    func testLanguageComesFromTheDictationPolicy() {
        let explicit = TranscriptionLanguagePolicy(
            mode: .explicit(.english), keyboardLanguage: .french,
            engine: .whisperKit, modelIdentifier: "m"
        )
        XCTAssertEqual(TranscriptionRecord.languageCode(for: explicit), "en",
                       "An explicit choice wins over the keyboard language.")

        let follow = TranscriptionLanguagePolicy(
            mode: .followKeyboard, keyboardLanguage: .german,
            engine: .whisperKit, modelIdentifier: "m"
        )
        XCTAssertEqual(TranscriptionRecord.languageCode(for: follow), "de")

        let auto = TranscriptionLanguagePolicy(
            mode: .autoDetect, keyboardLanguage: .french,
            engine: .parakeet, modelIdentifier: "m"
        )
        XCTAssertEqual(TranscriptionRecord.languageCode(for: auto),
                       TranscriptionRecord.autoDetectedCode,
                       "Auto-detect records no language rather than guessing the keyboard's.")
    }

    func testRecordFromPolicyCarriesTheEngineAndTheDuration() {
        let policy = TranscriptionLanguagePolicy(
            mode: .followKeyboard, keyboardLanguage: .spanish,
            engine: .parakeet, modelIdentifier: "m"
        )
        let made = TranscriptionRecord(text: "hola", policy: policy, duration: 12.6)

        XCTAssertEqual(made.language, "es")
        XCTAssertEqual(made.sttProvider, SpeechEngine.parakeet.rawValue)
        XCTAssertEqual(made.engine, .parakeet)
        XCTAssertEqual(made.durationSeconds, 13, "The duration is rounded, not truncated.")
    }

    func testDurationLabel() {
        XCTAssertEqual(record("x", duration: 0).durationLabel, "0s")
        XCTAssertEqual(record("x", duration: 12).durationLabel, "12s")
        XCTAssertEqual(record("x", duration: 59).durationLabel, "59s")
        XCTAssertEqual(record("x", duration: 60).durationLabel, "1m 00s")
        XCTAssertEqual(record("x", duration: 65).durationLabel, "1m 05s")
        XCTAssertEqual(record("x", duration: 605).durationLabel, "10m 05s")
    }

    func testLanguageBadge() {
        XCTAssertEqual(record("x", language: "fr").languageBadge, "FR")
        XCTAssertEqual(record("x", language: TranscriptionRecord.autoDetectedCode).languageBadge,
                       "AUTO")
    }

    func testAnUnknownLanguageOrEngineDoesNotBreakTheDecode() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","text":"hello","language":"xx",\
        "durationSeconds":3,"createdAt":"2026-08-27T10:00:00Z","sttProvider":"ZZ"}]
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()

        XCTAssertEqual(store.records.count, 1,
                       "A value no enum knows must not cost the user the record.")
        XCTAssertNil(store.records.first?.supportedLanguage)
        XCTAssertNil(store.records.first?.engine)
        XCTAssertEqual(store.records.first?.languageBadge, "XX")
    }
}
