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
}
