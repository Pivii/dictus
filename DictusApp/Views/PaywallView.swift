// DictusApp/Views/PaywallView.swift
// Full-screen paywall pushed via NavigationStack: hero, feature cards, plan selector, CTA.
import SwiftUI
import StoreKit
import DictusCore

struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var proStatus: ProStatusManager
    @Environment(\.dismiss) private var dismiss

    /// Selected plan, tracked by product ID (never by array index: StoreKit's
    /// product order is unspecified). Yearly is preselected per the pricing
    /// decision on #78, true from the first frame with no load-completion hook.
    @State private var selectedProductID = SubscriptionManager.yearlyProductID

    /// Whether the user can still claim the yearly intro offer (7-day trial).
    /// The offer exists in configuration for everyone, but StoreKit grants it
    /// once per Apple ID. Defaults to false so the CTA never over-promises.
    @State private var isEligibleForTrial = false

    /// Shows the thank-you screen after a successful purchase or restore.
    @State private var showPurchaseSuccess = false

    /// Drives the staged entrance animation of the thank-you screen elements.
    @State private var successEntrance = false

    /// Product matching the current selection, degrading to whatever loaded
    /// if the selected one is unavailable. Nil disables the CTA.
    private var selectedProduct: Product? {
        subscriptionManager.products.first { $0.id == selectedProductID }
            ?? subscriptionManager.products.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                heroSection

                // Feature cards (3 cards: Smart Mode, History, Vocabulary)
                VStack(spacing: 10) {
                    ForEach(ProFeature.allCases, id: \.self) { feature in
                        featureCard(feature)
                    }
                }

                if proStatus.isProActive {
                    // Already subscribed
                    alreadyProBanner
                } else {
                    // Plan selector: yearly (preselected) and monthly cards
                    planSelector
                    // Subscribe CTA following the selected plan
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
        // Empty bar title: the hero's gradient title is the screen title.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Retry the product fetch if the launch-time load came back empty,
            // so a transient failure doesn't leave the CTA stuck on "...".
            if subscriptionManager.products.isEmpty {
                await subscriptionManager.loadProducts()
            }
            // Configuration describes the trial for everyone; eligibility is
            // per Apple ID. Ask StoreKit rather than assuming.
            if let subscription = subscriptionManager.yearlyProduct?.subscription {
                isEligibleForTrial = await subscription.isEligibleForIntroOffer
            }
        }
        .onChange(of: subscriptionManager.purchaseState) { _, newState in
            // Celebrate instead of silently ejecting the user who just paid:
            // the thank-you screen takes over and Continue dismisses.
            if newState == .success {
                withAnimation(.easeOut(duration: 0.25)) {
                    showPurchaseSuccess = true
                }
            }
        }
        .overlay {
            if showPurchaseSuccess {
                purchaseSuccessView
                    .transition(.opacity)
            }
        }
        // The only way forward from the thank-you screen is Continue
        // (edge swipe-back still works as an escape hatch).
        .navigationBarBackButtonHidden(showPurchaseSuccess)
        .alert("Purchase Error", isPresented: showErrorAlert) {
            Button("OK") { subscriptionManager.resetState() }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Hero

    /// Brand hero: app-icon style tile (fixed dark gradient from the brand
    /// kit) with a blue glow, and the tagline. The screen title comes from
    /// the navigation bar, so the hero repeats no text.
    /// Glow uses the double-shadow pattern (tight + wide) from SwipeBackOverlayView.
    private var heroSection: some View {
        VStack(spacing: 12) {
            // Forcing the dark color scheme keeps DictusLogo's side bars
            // white on the dark tile in light mode too, matching the app icon.
            DictusLogo(height: 48)
                .environment(\.colorScheme, .dark)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: 0x0D2040), Color(hex: 0x071020)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: Color.dictusAccent.opacity(0.7), radius: 10)
                .shadow(color: Color.dictusAccent.opacity(0.4), radius: 20)

            Text("Dictus Pro")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.dictusGradientStart, .dictusGradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Your voice, unlimited")
                .font(.dictusBody)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Feature Card

    /// Feature card with SF Symbol icon, title, and description.
    /// Non-interactive (informational only per UI-SPEC). Compact metrics so
    /// the plan cards stay above the fold on a 6.1-inch screen.
    private func featureCard(_ feature: ProFeature) -> some View {
        HStack(spacing: 12) {
            Image(systemName: feature.icon)
                .font(.title3)
                .foregroundColor(iconColor(for: feature))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(feature.displayName))
                    .font(.dictusBody.weight(.semibold))
                Text(LocalizedStringKey(feature.paywallDescription))
                    .font(.dictusCaption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(12)
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

    // MARK: - Plan Selector

    /// Yearly card first, matching its preselection. Each card renders only
    /// if its product loaded, so a partial fetch degrades instead of crashing.
    private var planSelector: some View {
        VStack(spacing: 12) {
            if let yearly = subscriptionManager.yearlyProduct {
                planCard(
                    product: yearly,
                    title: "Yearly",
                    priceText: Text("\(yearly.displayPrice)/year"),
                    subtitle: perMonthEquivalent(for: yearly),
                    badge: discountBadgeText
                )
            }
            if let monthly = subscriptionManager.monthlyProduct {
                planCard(
                    product: monthly,
                    title: "Monthly",
                    priceText: Text("\(monthly.displayPrice)/month"),
                    subtitle: nil,
                    badge: nil
                )
            }
        }
    }

    private func planCard(
        product: Product,
        title: LocalizedStringKey,
        priceText: Text,
        subtitle: Text?,
        badge: String?
    ) -> some View {
        let isSelected = product.id == selectedProductID
        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dictusBody.weight(.semibold))
                    priceText
                        .font(.dictusBody)
                        .foregroundColor(.secondary)
                    if let subtitle {
                        subtitle
                            .font(.dictusCaption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let badge {
                    Text(verbatim: badge)
                        .font(.dictusCaption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.dictusSuccess, in: Capsule())
                        .foregroundColor(.white)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .dictusAccent : .secondary)
            }
            .padding(14)
            .foregroundColor(.primary)
            .dictusGlass()
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.dictusAccent : .clear, lineWidth: 2)
            )
            // Make the whole card tappable: without an explicit content
            // shape, hit-testing only registers on rendered content (text,
            // icons), not on the Spacer or transparent background areas.
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(GlassPressStyle(pressedScale: 0.97))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }

    /// Per-month equivalent under the yearly price, e.g. "Soit 3,33 € par mois".
    /// WHY priceFormatStyle: it carries the product's own currency and locale,
    /// so the divided price is formatted exactly like displayPrice.
    private func perMonthEquivalent(for yearly: Product) -> Text {
        let perMonth = yearly.priceFormatStyle.format(yearly.price / Decimal(12))
        return Text("That's \(perMonth) per month")
    }

    /// Discount badge, e.g. "-33 %". Computed from live prices so a price
    /// change in App Store Connect can never make the badge lie. Nil (hidden)
    /// when either product is missing or the discount is not positive.
    private var discountBadgeText: String? {
        guard let yearly = subscriptionManager.yearlyProduct,
              let monthly = subscriptionManager.monthlyProduct,
              monthly.price > 0 else { return nil }
        let ratio = 1 - (yearly.price / (monthly.price * 12))
        let percent = (ratio as NSDecimalNumber).doubleValue
        guard percent > 0 else { return nil }
        let formatted = percent.formatted(
            .percent.precision(.fractionLength(0)).sign(strategy: .never)
        )
        return "-" + formatted
    }

    // MARK: - Subscribe CTA

    private var subscribeCTA: some View {
        Button {
            Task {
                if let product = selectedProduct {
                    await subscriptionManager.purchase(product)
                }
            }
        } label: {
            Group {
                if subscriptionManager.purchaseState == .purchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    ctaLabel
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
        .disabled(selectedProduct == nil || subscriptionManager.purchaseState == .purchasing)
        .opacity(selectedProduct == nil ? 0.5 : 1.0)
        .accessibilityLabel(ctaLabel)
    }

    /// CTA label follows the selected plan. Prices and trial duration come
    /// from the StoreKit Product; nothing is hardcoded.
    private var ctaLabel: Text {
        guard let product = selectedProduct else { return Text(verbatim: "...") }
        if product.id == SubscriptionManager.yearlyProductID {
            if isEligibleForTrial,
               let offer = product.subscription?.introductoryOffer,
               offer.paymentMode == .freeTrial,
               let days = trialDays(for: offer) {
                return Text("\(days) days free, then \(product.displayPrice)/year")
            }
            return Text("Subscribe for \(product.displayPrice)/year")
        }
        return Text("Subscribe for \(product.displayPrice)/month")
    }

    /// Trial length in days. StoreKit expresses the 7-day trial as 1 week;
    /// convert so the CTA reads "7 days free" as designed. Returns nil for
    /// month/year units so the caller falls back to the plain subscribe
    /// label rather than showing awkward copy.
    private func trialDays(for offer: Product.SubscriptionOffer) -> Int? {
        switch offer.period.unit {
        case .day: return offer.period.value
        case .week: return offer.period.value * 7
        default: return nil
        }
    }

    // MARK: - Bottom Links

    // Apple requires functional Terms of Use and Privacy Policy links for
    // auto-renewable subscriptions (guideline 3.1.2). Force unwrap is safe:
    // compile-time constant URLs that cannot be malformed.
    // swiftlint:disable:next force_unwrapping
    private static let termsURL = URL(string: "https://getdictus.com/terms")!
    // swiftlint:disable:next force_unwrapping
    private static let privacyURL = URL(string: "https://getdictus.com/privacy")!

    private var bottomLinks: some View {
        VStack(spacing: 8) {
            // Hidden while Pro is active: Apple requires a restore mechanism
            // to exist (guideline 3.1.1), not to be shown to subscribers.
            if !proStatus.isProActive {
                Button("Restore purchases") {
                    Task { await subscriptionManager.restorePurchases() }
                }
                .font(.dictusCaption)
                .accessibilityLabel("Restore previous purchases")
            }

            HStack(spacing: 16) {
                Link("Terms of Service", destination: Self.termsURL)
                Link("Privacy Policy", destination: Self.privacyURL)
            }
            .font(.dictusCaption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Purchase Success

    /// Thank-you screen shown after a successful purchase or restore.
    /// Staged entrance: the checkmark springs in first, then the texts rise
    /// with small delays, then the Continue button. Each element animates on
    /// the same trigger with its own delay, which reads as one choreography.
    private var purchaseSuccessView: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.white, Color.dictusSuccess)
                .shadow(color: Color.dictusSuccess.opacity(0.6), radius: 12)
                .shadow(color: Color.dictusSuccess.opacity(0.3), radius: 28)
                .scaleEffect(successEntrance ? 1 : 0.4)
                .opacity(successEntrance ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.6), value: successEntrance)

            Text("Welcome to Dictus Pro")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.dictusGradientStart, .dictusGradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 28)
                .opacity(successEntrance ? 1 : 0)
                .offset(y: successEntrance ? 0 : 12)
                .animation(.easeOut(duration: 0.35).delay(0.2), value: successEntrance)

            Text("All Pro features are now unlocked. Thank you for your support.")
                .font(.dictusBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 24)
                .opacity(successEntrance ? 1 : 0)
                .offset(y: successEntrance ? 0 : 12)
                .animation(.easeOut(duration: 0.35).delay(0.3), value: successEntrance)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.dictusSubheading)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.dictusAccent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(GlassPressStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .opacity(successEntrance ? 1 : 0)
            .animation(.easeOut(duration: 0.35).delay(0.45), value: successEntrance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dictusBackground.ignoresSafeArea())
        .onAppear {
            successEntrance = true
            // UIKit generator instead of SwiftUI sensoryFeedback: the state
            // change happens while the StoreKit payment sheet still holds
            // scene focus, where sensoryFeedback is silently dropped. The
            // delay lands the haptic as the checkmark spring settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                HapticFeedback.textInserted()
            }
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
