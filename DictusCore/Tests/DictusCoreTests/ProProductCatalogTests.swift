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
        XCTAssertEqual(ProProductID.lifetime, "solutions.pivi.dictus.pro.lifetime")
    }

    func testEveryIdentifierIsRequestedFromStoreKit() {
        // A product missing from `all` is never fetched, so its plan row never
        // renders — the exact shape of the gap this suite exists to catch, and
        // the one the lifetime fell into (#350).
        XCTAssertEqual(
            ProProductID.all,
            [ProProductID.monthly, ProProductID.yearly, ProProductID.lifetime]
        )
    }

    // MARK: - Local StoreKit configuration

    func testConfigurationDefinesEveryRequestedIdentifier() throws {
        let config = try storeKitConfiguration()
        XCTAssertEqual(
            Set(config.subscriptions.keys).union(config.nonConsumables.keys),
            ProProductID.all,
            "The local StoreKit configuration and ProProductID must describe the same catalogue"
        )
    }

    func testLifetimeIsANonConsumableOutsideTheSubscriptionGroup() throws {
        let config = try storeKitConfiguration()
        let lifetime = try XCTUnwrap(config.nonConsumables[ProProductID.lifetime])
        XCTAssertEqual(lifetime["type"] as? String, "NonConsumable")
        // No `subscription` on the StoreKit product is what makes the paywall
        // drop the period suffix and say "Buy" instead of "Subscribe" (#350).
        XCTAssertNil(config.subscriptions[ProProductID.lifetime])
        XCTAssertNil(lifetime["recurringSubscriptionPeriod"])
        XCTAssertNil(lifetime["subscriptionGroupID"])
    }

    func testSubscriptionPeriodsMatchThePricingDecision() throws {
        let config = try storeKitConfiguration()
        let monthly = try XCTUnwrap(config.subscriptions[ProProductID.monthly])
        let yearly = try XCTUnwrap(config.subscriptions[ProProductID.yearly])
        XCTAssertEqual(monthly["recurringSubscriptionPeriod"] as? String, "P1M")
        XCTAssertEqual(yearly["recurringSubscriptionPeriod"] as? String, "P1Y")
    }

    func testTrialIsOnTheYearlyPlanOnly() throws {
        // A non-consumable cannot carry an introductory offer at all, so the
        // absence below is structural rather than a configuration choice.
        let config = try storeKitConfiguration()
        XCTAssertNotNil(config.subscriptions[ProProductID.yearly]?["introductoryOffer"] as? [String: Any])
        XCTAssertNil(config.subscriptions[ProProductID.monthly]?["introductoryOffer"] as? [String: Any])
        XCTAssertNil(config.nonConsumables[ProProductID.lifetime]?["introductoryOffer"])
    }

    func testPricesMatchThePricingDecision() throws {
        // #54: 4,99 € monthly, 39,99 € yearly, 49,99 € lifetime during the
        // founder window. The lifetime goes to 79,99 € afterwards, which is an
        // App Store Connect change and never a change to this file.
        let config = try storeKitConfiguration()
        XCTAssertEqual(config.subscriptions[ProProductID.monthly]?["displayPrice"] as? String, "4.99")
        XCTAssertEqual(config.subscriptions[ProProductID.yearly]?["displayPrice"] as? String, "39.99")
        XCTAssertEqual(config.nonConsumables[ProProductID.lifetime]?["displayPrice"] as? String, "49.99")
    }

    // MARK: - Helpers

    private struct StoreKitConfiguration {
        /// Products inside a subscription group, keyed by product ID.
        let subscriptions: [String: [String: Any]]
        /// Top-level products (consumables and non-consumables), keyed by product ID.
        let nonConsumables: [String: [String: Any]]
    }

    /// Parses the StoreKit configuration the app actually ships.
    ///
    /// WHY reach across targets through `#filePath` rather than copying the
    /// file into test resources: a copy would drift, and drift is precisely the
    /// failure this checks for. The path is resolved from this source file, so
    /// it holds wherever the suite runs; if the configuration moves, the test
    /// fails loudly with the path it looked at.
    private func storeKitConfiguration(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> StoreKitConfiguration {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DictusCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // DictusCore
            .deletingLastPathComponent()  // repo root
        let url = repoRoot
            .appendingPathComponent("DictusApp/Subscription/StoreKitConfig.storekit")

        guard let data = try? Data(contentsOf: url) else {
            XCTFail("StoreKit configuration not found at \(url.path)", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            file: file, line: line
        )

        let groups = root["subscriptionGroups"] as? [[String: Any]] ?? []
        let subscriptions = groups
            .flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        let topLevel = root["products"] as? [[String: Any]] ?? []

        return StoreKitConfiguration(
            subscriptions: Self.keyedByProductID(subscriptions),
            nonConsumables: Self.keyedByProductID(topLevel)
        )
    }

    private static func keyedByProductID(_ products: [[String: Any]]) -> [String: [String: Any]] {
        products.reduce(into: [:]) { result, product in
            if let id = product["productID"] as? String { result[id] = product }
        }
    }
}
