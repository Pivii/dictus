// DictusCore/Tests/DictusCoreTests/Polish/PolishGuardrailTests.swift
import XCTest
@testable import DictusCore

final class PolishGuardrailTests: XCTestCase {

    func testLightAcceptsIdenticalLength() {
        XCTAssertTrue(PolishGuardrail.accepts(raw: "hello world", polished: "hello world", mode: .light))
    }

    func testLightAcceptsLowerBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 50)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .light))
    }

    func testLightAcceptsUpperBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 200)
        XCTAssertTrue(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .light))
    }

    func testLightRejectsBelowLowerBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 49)
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .light))
    }

    func testLightRejectsAboveUpperBound() {
        let raw = String(repeating: "a", count: 100)
        let polished = String(repeating: "a", count: 201)
        XCTAssertFalse(PolishGuardrail.accepts(raw: raw, polished: polished, mode: .light))
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
        XCTAssertTrue(PolishGuardrail.accepts(raw: "", polished: "", mode: .light))
        XCTAssertTrue(PolishGuardrail.accepts(raw: "", polished: "", mode: .repair))
        XCTAssertFalse(PolishGuardrail.accepts(raw: "", polished: "x", mode: .light))
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
}
