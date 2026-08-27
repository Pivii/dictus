// DictusCore/Tests/DictusCoreTests/Polish/PolishGuardrailTests.swift
import XCTest
@testable import DictusCore

final class PolishGuardrailTests: XCTestCase {

    func testLightAcceptsIdenticalLength() {
        XCTAssertTrue(PolishGuardrail.accepts(raw: "hello world", polished: "hello world", mode: .natural))
    }

    func testLightAcceptsLowerBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 50)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .natural))
    }

    func testLightAcceptsUpperBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 200)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .natural))
    }

    func testLightRejectsBelowLowerBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 49)
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .natural))
    }

    func testLightRejectsAboveUpperBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 201)
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .natural))
    }

    func testRepairAcceptsLowerBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 30)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .repair))
    }

    func testRepairAcceptsUpperBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 300)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .repair))
    }

    func testRepairRejectsBelowLowerBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 29)
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .repair))
    }

    func testRepairRejectsAboveUpperBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 301)
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .repair))
    }

    func testEmptyRawAcceptsOnlyEmptyPolished() {
        XCTAssertTrue(PolishGuardrail.accepts(raw: "", polished: "", mode: .natural))
        XCTAssertTrue(PolishGuardrail.accepts(raw: "", polished: "", mode: .repair))
        XCTAssertFalse(PolishGuardrail.accepts(raw: "", polished: "x", mode: .natural))
        XCTAssertFalse(PolishGuardrail.accepts(raw: "", polished: "x", mode: .repair))
    }

    // MARK: - Language-match guardrail

    func testLanguageMatchAcceptsFrenchOutputForFrenchTarget() {
        let polished = "Bonjour, comment allez-vous aujourd’hui ? J’espère que tout va bien."
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: polished, target: .french))
    }

    func testLanguageMatchAcceptsEnglishOutputForEnglishTarget() {
        let polished = "Hello, how are you doing today? I hope everything is going well."
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: polished, target: .english))
    }

    /// The exact failure mode observed in production logs: target=fr, model
    /// emitted a chat reply in English. Must reject.
    func testLanguageMatchRejectsEnglishChatReplyForFrenchTarget() {
        let polished = "I'll ensure accurate transcription of the input despite the English words."
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(polished: polished, target: .french))
    }

    func testLanguageMatchRejectsFrenchOutputForEnglishTarget() {
        let polished = "Bonjour, je vais bien aujourd’hui et j’espère que vous allez bien aussi."
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(polished: polished, target: .english))
    }

    /// NLLanguageRecognizer is unreliable on very short outputs — pass them.
    func testLanguageMatchPassesShortOutputs() {
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: "Hi.", target: .french))
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: "Ok.", target: .english))
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: "", target: .french))
    }

    // MARK: - Auto-mode language-match guardrail (#239)

    /// Auto mode ratio band mirrors Natural: light corrections only.
    func testAutoAcceptsNaturalBandAndRejectsOutside() {
        let raw = String(repeating: "a", count: 100)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: String(repeating: "a", count: 50), mode: .auto))
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: String(repeating: "a", count: 200), mode: .auto))
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: String(repeating: "a", count: 49), mode: .auto))
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: String(repeating: "a", count: 201), mode: .auto))
    }

    func testAutoLanguageMatchAcceptsSameLanguageAsInput() {
        let polished = "Allora domani andiamo al mare, se il tempo è bello. Ci vediamo alle nove."
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: polished, inputLanguageCode: "it"))
    }

    /// The #239 device failure mode: English speech, French keyboard, polish
    /// translated into French. With the input code as reference the translated
    /// output must be rejected.
    func testAutoLanguageMatchRejectsTranslationDrift() {
        let polished = "Salut, tu viens à la réunion demain matin ? Je crois qu’on commence à neuf heures."
        XCTAssertFalse(PolishGuardrail.detectedLanguageMatches(polished: polished, inputLanguageCode: "en"))
    }

    func testAutoLanguageMatchAcceptsChineseRoundTrip() {
        let polished = "我觉得我们明天再讨论这个问题吧，然后周五之前把版本发出去。"
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: polished, inputLanguageCode: "zh-Hans"))
    }

    func testAutoLanguageMatchPassesShortOutputs() {
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: "Ok.", inputLanguageCode: "it"))
        XCTAssertTrue(PolishGuardrail.detectedLanguageMatches(polished: "", inputLanguageCode: "en"))
    }

    // MARK: - Codable roundtrip

    /// Round-trip every Outcome through JSON. Required because the persistent
    /// `PolishMetricsRing` encodes events as JSON Lines on disk; a regression
    /// in Codable conformance would silently lose data on the next app launch.
    func testPolishMetricsRoundTripJSON() throws {
        let original = PolishMetrics(
            engine: "apple-fm",
            mode: .repair,
            targetLanguage: .french,
            detectedLanguage: "en",
            rawCharCount: 42,
            polishedCharCount: 48,
            latencyMs: 1234,
            outcome: .success
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(PolishMetrics.self, from: data)

        XCTAssertEqual(decoded.engine, original.engine)
        XCTAssertEqual(decoded.mode, original.mode)
        XCTAssertEqual(decoded.targetLanguage, original.targetLanguage)
        XCTAssertEqual(decoded.detectedLanguage, original.detectedLanguage)
        XCTAssertEqual(decoded.rawCharCount, original.rawCharCount)
        XCTAssertEqual(decoded.polishedCharCount, original.polishedCharCount)
        XCTAssertEqual(decoded.latencyMs, original.latencyMs)
        XCTAssertEqual(decoded.outcome, original.outcome)
    }

    /// nil mode (skipped events) and nil detectedLanguage (gibberish) must survive.
    func testPolishMetricsRoundTripJSONWithNilFields() throws {
        let original = PolishMetrics(
            engine: "passthrough",
            mode: nil,
            targetLanguage: .english,
            detectedLanguage: nil,
            rawCharCount: 0,
            polishedCharCount: 0,
            latencyMs: 0,
            outcome: .skipped
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PolishMetrics.self, from: data)
        XCTAssertNil(decoded.mode)
        XCTAssertNil(decoded.detectedLanguage)
        XCTAssertEqual(decoded.outcome, .skipped)
    }
}
