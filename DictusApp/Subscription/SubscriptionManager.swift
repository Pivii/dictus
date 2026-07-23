// DictusApp/Subscription/SubscriptionManager.swift
// StoreKit 2 subscription management: product fetch, purchase, restore, transaction listener.
import Foundation
import StoreKit
import DictusCore

/// Manages all StoreKit 2 interactions for the Dictus Pro subscription.
///
/// WHY @MainActor:
/// StoreKit 2 purchase() returns on the calling actor. Since SwiftUI views
/// observe @Published properties, keeping everything on MainActor avoids
/// cross-actor data races and explicit DispatchQueue.main.async calls.
///
/// WHY a single class for all StoreKit logic:
/// Dictus has exactly one product (monthly subscription). A single manager
/// handles product fetch, purchase, restore, and transaction listening.
/// No need for abstraction layers or protocol-based architecture.
@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseState: PurchaseState = .idle

    /// Product ID matching App Store Connect configuration.
    /// WHY this specific format: Apple convention is reverse-domain + product type.
    private let productIDs: Set<String> = ["solutions.pivi.dictus.pro.monthly"]

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
    func loadProducts() async {
        do {
            products = try await Product.products(for: productIDs)
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
