// DictusApp/Views/PaywallView.swift
// Full-screen paywall pushed via NavigationStack with feature cards, CTA, and beta variant.
import SwiftUI
import StoreKit
import DictusCore

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var proStatus: ProStatusManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero title
                Text("Dictus Pro")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundColor(.dictusAccent)
                    .padding(.top, 32)

                // Feature cards (3 cards: Smart Mode, History, Vocabulary)
                VStack(spacing: 16) {
                    ForEach(ProFeature.allCases, id: \.self) { feature in
                        featureCard(feature)
                    }
                }

                if ProConfig.effectiveBeta {
                    // Beta banner replaces purchase flow
                    betaBanner
                } else if proStatus.isProActive {
                    // Already subscribed
                    alreadyProBanner
                } else {
                    // Subscribe CTA with localized price
                    subscribeCTA
                    // "Cancel anytime" reassurance
                    Text("Cancel anytime")
                        .font(.dictusCaption)
                        .foregroundColor(.secondary)
                }

                // Bottom links: Restore + ToS + Privacy
                bottomLinks
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 16)
        }
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle("Dictus Pro")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: subscriptionManager.purchaseState) { _, newState in
            // Auto-dismiss paywall after successful purchase
            if newState == .success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            }
        }
        .alert("Purchase Error", isPresented: showErrorAlert) {
            Button("OK") { subscriptionManager.resetState() }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Feature Card

    /// Feature card with SF Symbol icon, title, and description.
    /// Non-interactive (informational only per UI-SPEC).
    private func featureCard(_ feature: ProFeature) -> some View {
        HStack(spacing: 16) {
            Image(systemName: feature.icon)
                .font(.title2)
                .foregroundColor(iconColor(for: feature))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(feature.displayName))
                    .font(.dictusSubheading)
                Text(LocalizedStringKey(feature.paywallDescription))
                    .font(.dictusBody)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(16)
        .dictusGlass()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.displayName): \(feature.paywallDescription)")
    }

    /// Icon color per feature (UI-SPEC: Smart Mode = purple, others = accent highlight).
    private func iconColor(for feature: ProFeature) -> Color {
        switch feature {
        case .smartMode: return .dictusSmartMode
        case .history, .vocabulary: return .dictusAccentHighlight
        }
    }

    // MARK: - Beta Banner

    private var betaBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundColor(.dictusSuccess)

            VStack(alignment: .leading, spacing: 4) {
                Text("All Pro features free during beta")
                    .font(.dictusSubheading)
                Text("Thank you for testing Dictus!")
                    .font(.dictusCaption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .dictusGlass()
    }

    // MARK: - Already Pro Banner

    private var alreadyProBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.dictusSuccess)

            Text("Dictus Pro Active")
                .font(.dictusSubheading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .dictusGlass()
    }

    // MARK: - Subscribe CTA

    private var subscribeCTA: some View {
        Button {
            Task {
                if let product = subscriptionManager.products.first {
                    await subscriptionManager.purchase(product)
                }
            }
        } label: {
            Group {
                if subscriptionManager.purchaseState == .purchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    // Price from StoreKit (never hardcoded)
                    Text("Subscribe — \(subscriptionManager.products.first?.displayPrice ?? "...")/month")
                        .font(.dictusSubheading)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.dictusAccent)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(GlassPressStyle())
        .disabled(subscriptionManager.products.isEmpty || subscriptionManager.purchaseState == .purchasing)
        .opacity(subscriptionManager.products.isEmpty ? 0.5 : 1.0)
        .accessibilityLabel("Subscribe to Dictus Pro for \(subscriptionManager.products.first?.displayPrice ?? "unknown price") per month")
    }

    // MARK: - Bottom Links

    private var bottomLinks: some View {
        VStack(spacing: 8) {
            if !ProConfig.effectiveBeta {
                Button("Restore purchases") {
                    Task { await subscriptionManager.restorePurchases() }
                }
                .font(.dictusCaption)
                .accessibilityLabel("Restore previous purchases")
            }

            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://dictus.app/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://dictus.app/privacy")!)
            }
            .font(.dictusCaption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Error Handling

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: {
                if case .failed = subscriptionManager.purchaseState { return true }
                return false
            },
            set: { _ in }
        )
    }

    private var errorMessage: String {
        if case .failed(let msg) = subscriptionManager.purchaseState {
            return msg
        }
        return "An error occurred."
    }
}
