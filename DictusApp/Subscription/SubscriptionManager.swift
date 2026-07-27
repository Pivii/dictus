// DictusApp/Subscription/SubscriptionManager.swift
// StoreKit 2 subscription management: product fetch, purchase, restore, transaction listener.
import Foundation
import StoreKit
import DictusCore

/// Compile-time visibility flags for premium UI (issue #236).
///
/// WHY a compile-time constant instead of remote config:
/// No Pro feature exists yet (#79) and App Store Connect setup is pending (#215),
/// so the paywall would render with empty prices. A single `static let` is enough
/// to hide every entry point (Home banner, Settings Pro section, locked rows)
/// while keeping all subscription code compiled and intact.
///
/// Re-enable: flip `paywallVisible` to `true` in the PR that ships the first
/// real Pro feature, once #215 (ASC setup) is done. See #79/#215/#216.
///
/// WHY an enum with no cases: a caseless enum can never be instantiated,
/// making it a pure namespace for static constants (common Swift pattern).
enum PremiumFlags {
    /// Controls whether users can see and reach the paywall.
    /// `false` = the app looks like there is no subscription at all.
    static let paywallVisible = false
}

/// Manages all StoreKit 2 interactions for the Dictus Pro subscription.
///
/// WHY @MainActor:
/// StoreKit 2 purchase() returns on the calling actor. Since SwiftUI views
/// observe @Published properties, keeping everything on MainActor avoids
/// cross-actor data races and explicit DispatchQueue.main.async calls.
///
/// WHY a single class for all StoreKit logic:
/// Dictus has one subscription group with two plans (monthly and yearly).
/// A single manager handles product fetch, purchase, restore, and
/// transaction listening for both. No need for abstraction layers.
@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseState: PurchaseState = .idle

    /// Product IDs matching App Store Connect configuration.
    /// WHY static constants: PaywallView looks products up by ID (never by
    /// array index, since StoreKit's fetch order is unspecified) to preselect
    /// the yearly plan and label the CTA per plan.
    static let monthlyProductID = "solutions.pivi.dictus.pro.monthly"
    static let yearlyProductID = "solutions.pivi.dictus.pro.yearly"

    private let productIDs: Set<String> = [
        SubscriptionManager.monthlyProductID,
        SubscriptionManager.yearlyProductID
    ]

    var monthlyProduct: Product? { products.first { $0.id == Self.monthlyProductID } }
    var yearlyProduct: Product? { products.first { $0.id == Self.yearlyProductID } }

    private var transactionListener: Task<Void, Never>?
    private let proStatus: ProStatusManager

    init(proStatus: ProStatusManager) {
        self.proStatus = proStatus
        // Start listening IMMEDIATELY at init — before any view renders.
        // WHY: If user purchased on another device or subscription renewed
        // while the app was killed, Transaction.updates delivers those
        // transactions on next launch. Missing them = stale Pro status.
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        // Check current entitlements on launch (passive, no sign-in prompt)
        Task { await updateProStatus() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Public API

    /// Fetch subscription products from App Store / StoreKit Config.
    ///
    /// Safe to call repeatedly: PaywallView retries on appear when the launch
    /// fetch came back empty (e.g. store not ready during cold start).
    func loadProducts() async {
        do {
            // Sort by ascending price so array order is deterministic —
            // Product.products(for:) returns results in unspecified order.
            products = try await Product.products(for: productIDs)
                .sorted { $0.price < $1.price }
            // An unknown product ID returns an empty array WITHOUT throwing —
            // the signature of a missing StoreKit configuration. Log it so the
            // dead "..." CTA is diagnosable from exported logs.
            if products.isEmpty {
                PersistentLog.log(.subscriptionError(
                    action: "loadProducts",
                    error: "empty result (StoreKit configuration missing or product ID unknown)"
                ))
            }
        } catch {
            PersistentLog.log(.subscriptionError(action: "loadProducts", error: error.localizedDescription))
        }
    }

    /// Purchase the Pro subscription.
    ///
    /// WHY separate purchaseState enum:
    /// The paywall CTA button shows different states (loading spinner, error).
    /// Using an enum makes the view layer's switch statement exhaustive.
    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateProStatus()
                await transaction.finish()
                purchaseState = .success
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .pending
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
            PersistentLog.log(.subscriptionError(action: "purchase", error: error.localizedDescription))
        }
    }

    /// Restore purchases — contacts Apple servers. Only call from explicit user tap.
    ///
    /// WHY not called on launch:
    /// AppStore.sync() may trigger a sign-in prompt. Only invoke from
    /// the "Restore purchases" button tap to avoid unexpected prompts.
    func restorePurchases() async {
        purchaseState = .purchasing
        do {
            try await AppStore.sync()
            await updateProStatus()
            purchaseState = proStatus.isProActive ? .success : .idle
        } catch {
            purchaseState = .failed(error.localizedDescription)
            PersistentLog.log(.subscriptionError(action: "restore", error: error.localizedDescription))
        }
    }

    /// Reset purchaseState to idle — called by PaywallView after dismissing error alerts.
    func resetState() {
        purchaseState = .idle
    }

    // MARK: - Private

    /// Listen for transaction updates (renewals, refunds, family sharing changes).
    ///
    /// WHY Task.detached:
    /// Transaction.updates is an AsyncSequence that runs indefinitely.
    /// Using Task.detached ensures it doesn't inherit the caller's actor
    /// context, preventing potential deadlocks. We hop back to MainActor
    /// for status updates via the @MainActor class annotation.
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await self?.updateProStatus()
                    await transaction.finish()
                }
            }
        }
    }

    /// Scan current entitlements to determine Pro status.
    ///
    /// WHY Transaction.currentEntitlements instead of storing expiry dates:
    /// StoreKit 2 manages all subscription state internally. currentEntitlements
    /// returns only active, non-revoked transactions. No manual expiry tracking needed.
    private func updateProStatus() async {
        var isActive = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? result.payloadValue,
               transaction.revocationDate == nil {
                isActive = true
            }
        }
        proStatus.setProActive(isActive)
    }

    /// Verify transaction signature (StoreKit 2 does this automatically).
    ///
    /// WHY checkVerified wrapper:
    /// payloadValue already verifies the JWS signature. This wrapper makes
    /// the verification step explicit in the purchase flow and provides
    /// a single point to handle verification failures.
    private func checkVerified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw error
        }
    }
}

/// Purchase flow state for PaywallView CTA button rendering.
enum PurchaseState: Equatable {
    case idle
    case purchasing
    case pending
    case success
    case failed(String)

    static func == (lhs: PurchaseState, rhs: PurchaseState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.purchasing, .purchasing),
             (.pending, .pending), (.success, .success):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}
