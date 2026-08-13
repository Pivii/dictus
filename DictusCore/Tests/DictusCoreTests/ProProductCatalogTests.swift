// DictusCore/Tests/DictusCoreTests/ProProductCatalogTests.swift
// Guards the Dictus Pro product catalogue: the identifiers the app asks
// StoreKit for, and the local StoreKit configuration it is tested against.
//
// WHY these are worth asserting: App Store Connect identifiers are permanent
// (#215). A typo cannot be corrected, only abandoned, and the failure mode is
// silent — `Product.products(for:)` returns an empty array for an unknown
// identifier without throwing. DictusApp has no test target, which is why the
// identifiers live in DictusCore.
import XCTest
@testable import DictusCore

final class ProProductCatalogTests: XCTestCase {

    // MARK: - Identifiers

    func testIdentifiersMatchTheAppStoreConnectDecision() {
        // Values from the product table in #215.
        XCTAssertEqual(ProProductID.monthly, "solutions.pivi.dictus.pro.monthly")
        XCTAssertEqual(ProProductID.yearly, "solutions.pivi.dictus.pro.yearly")
    }

    func testEveryIdentifierIsRequestedFromStoreKit() {
        // A product missing from `all` is never fetched, so its plan row never
        // renders — the exact shape of the gap this suite exists to catch.
        XCTAssertEqual(ProProductID.all, [ProProductID.monthly, ProProductID.yearly])
    }
}
