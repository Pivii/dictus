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
    @State private var selectedProductID = ProProductID.yearly

    /// Whether the user can still claim the yearly intro offer (7-day trial).
    /// The offer exists in configuration for everyone, but StoreKit grants it
    /// once per Apple ID. Defaults to false so the CTA never over-promises.
    @State private var isEligibleForTrial = false

    /// Shows the thank-you screen after a successful purchase or restore.
    @State private var showPurchaseSuccess = false

    /// Drives the staged entrance animation of the thank-you screen elements.
    @State private var successEntrance = false

    /// Product matching the current selection. Nil disables the CTA.
    ///
    /// WHY no fallback here: it used to degrade to `products.first` when the
    /// selected plan had not loaded, which made the CTA charge a plan that no
    /// row showed as selected — every circle empty while the button read
    /// "S'abonner pour 4,99 €/mois" and charging it did exactly that. With
    /// three plans the gap between the intended and the charged price reaches
    /// 45 €. `reconcileSelection()` moves the selection onto a product that
    /// exists instead, so the checked row, the CTA and the charge never
    /// disagree.
    private var selectedProduct: Product? {
        subscriptionManager.products.first { $0.id == selectedProductID }
    }

    /// Move the selection onto a plan that actually loaded.
    ///
    /// WHY it is needed at all: `selectedProductID` is fixed before the fetch,
    /// so a plan that fails to load leaves it pointing at nothing while the
    /// user sees no checked row.
    ///
    /// WHY the cheapest rather than a preference order: `products` is sorted
    /// ascending by price, so a failed fetch can only ever demote the user to a
    /// cheaper plan. Falling onto the lifetime because the yearly went missing
    /// would put a 79,99 € one-off under a button the user thought said 39,99 €.
    private func reconcileSelection() {
        guard selectedProduct == nil,
              let cheapest = subscriptionManager.products.first else { return }
        selectedProductID = cheapest.id
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
                    // Plan selector: yearly (preselected), monthly and lifetime
                    planSelector
                    // Subscribe CTA following the selected plan
                    subscribeCTA
                    // Reassurance following the selected plan
                    reassuranceLabel
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
        .toolbar { closeButton }
        .task {
            // Retry the product fetch if the launch-time load came back empty,
            // so a transient failure doesn't leave the CTA stuck on "...".
            if subscriptionManager.products.isEmpty {
                await subscriptionManager.loadProducts()
            }
            reconcileSelection()
            // Configuration describes the trial for everyone; eligibility is
            // per Apple ID. Ask StoreKit rather than assuming.
            if let subscription = subscriptionManager.yearlyProduct?.subscription {
                isEligibleForTrial = await subscription.isEligibleForIntroOffer
            }
        }
        // Products can also land after this view appears: the launch-time fetch
        // started in SubscriptionManager.init and may finish at any point.
        .onChange(of: subscriptionManager.products.map(\.id)) { _, _ in
            reconcileSelection()
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
        .alert("Purchase Error", isPresented: showErrorAlert) {
            Button("OK") { subscriptionManager.resetState() }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Close

    /// Dismisses the cover. Absent while the thank-you screen is up, so the
    /// only way forward from it is Continue — a cover has no swipe-back to
    /// serve as the escape hatch a pushed screen had.
    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !showPurchaseSuccess {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Close")
            }
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

                if !feature.isSupportedByThisDevice {
                    unsupportedNotice
                }
            }

            Spacer()
        }
        .padding(12)
        .dictusGlass()
        // Dimmed, not hidden, and not disabled: the card is still a truthful part of
        // what Pro contains, and the sentence under it is the point.
        .opacity(feature.isSupportedByThisDevice ? 1 : 0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: feature))
    }

    /// The line that makes a paywall honest on a device that cannot run the feature
    /// (#79).
    ///
    /// **This is a review risk before it is a UX one.** Apple Foundation Models needs
    /// an iPhone 15 Pro or later on iOS 26; Dictus supports iOS 17 up, so most of the
    /// installed base is in this state permanently, and #268 closed the only
    /// alternative backend `wontfix`. A reviewer on a device without Apple
    /// Intelligence, facing a paywall that advertises a feature their hardware cannot
    /// deliver, is a rejection for misleading metadata — and the App Review device on
    /// #207 was an iPad Air.
    ///
    /// WHY the card is marked rather than removed, which #79 left open: a paywall
    /// that silently contains different things on different phones is one nobody can
    /// screenshot for review or reason about in a support thread, and a user who
    /// upgrades their iPhone would never learn the feature had been there all along.
    /// Marking says the same true thing to everyone. Pro still sells on History and
    /// Vocabulary, which is exactly what #79 decided.
    private var unsupportedNotice: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))

            Text("Requires Apple Intelligence (iPhone 15 Pro or later, iOS 26)")
                .font(.dictusCaption)
                .lineLimit(2)
        }
        .foregroundColor(.secondary)
        .padding(.top, 2)
    }

    private func accessibilityLabel(for feature: ProFeature) -> String {
        guard let notice = feature.unsupportedNotice else {
            return "\(feature.displayName): \(feature.paywallDescription)"
        }
        return "\(feature.displayName): \(feature.paywallDescription). \(notice)"
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
    /// The lifetime comes last: it is the plan that needs the most reading,
    /// and its scope footnote closes the group.
    private var planSelector: some View {
        VStack(spacing: 12) {
            if let yearly = subscriptionManager.yearlyProduct {
                planCard(
                    product: yearly,
                    title: "Yearly",
                    subtitle: perMonthEquivalent(for: yearly),
                    badge: discountBadgeText
                )
            }
            if let monthly = subscriptionManager.monthlyProduct {
                planCard(
                    product: monthly,
                    title: "Monthly",
                    subtitle: nil,
                    badge: nil
                )
            }
            if let lifetime = subscriptionManager.lifetimeProduct {
                planCard(
                    product: lifetime,
                    title: "Lifetime",
                    subtitle: founderOfferLabel,
                    badge: nil
                )
                lifetimeScopeFootnote
            }
        }
    }

    /// What the lifetime purchase covers, verbatim from the #350 decision.
    ///
    /// WHY it always renders next to the row, rather than behind a disclosure
    /// or only during the founder window: a promise cannot be narrowed after
    /// someone has bought against it, so the boundary has to be visible before
    /// the first sale.
    ///
    /// WHY the boundary is drawn at who pays to run the feature, not at where
    /// it runs: a feature pointed at a server the user provides costs the
    /// project nothing recurring and belongs inside a one-off purchase, while
    /// anything on Dictus infrastructure carries a per-user marginal cost that
    /// a single payment cannot fund. "Local" only approximated that line.
    private var lifetimeScopeFootnote: some View {
        Text("The lifetime purchase covers every current and future Pro feature that runs on your device or on a server you provide. Any feature relying on Dictus infrastructure is a separate offering.")
            .font(.dictusCaption)
            .foregroundColor(.secondary)
            // Long copy inside a VStack of fixed-height cards: without this it
            // is truncated to a single line instead of wrapping.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    /// Founder-window line under the lifetime price, e.g. "Founder offer until
    /// 12 September 2026."
    ///
    /// WHY nil rather than a placeholder while the window is unscheduled: the
    /// end date is only knowable once the first Pro release is scheduled
    /// (#79), and an announcement missing its date is worse than none.
    ///
    /// WHY it goes through `LifetimeFounderWindow` rather than reading the
    /// constant directly: the build outlives the window. The price rises in
    /// App Store Connect on the announced day, but a user who has not updated
    /// keeps running this build, and the line has to retire itself rather than
    /// contradict the price shown right above it.
    ///
    /// WHY it names no later price, although "79,99 € ensuite" was the approved
    /// wording and is the more persuasive line: StoreKit gives us the *current*
    /// price in the buyer's own currency through `displayPrice`, but the future
    /// price is not a product yet, so it could only be written into the string —
    /// and a US buyer would read $54.99 on the row with "79,99 € afterwards"
    /// underneath, a currency they will never be charged in. The amount on a
    /// non-euro storefront is not ours to state either: App Store Connect
    /// derives it from Apple's price matrix and readjusts it as rates move. For
    /// a window lasting weeks, being correct everywhere beats being persuasive.
    /// The deadline carries the scarcity, and the rise is visible on the row
    /// itself once it happens.
    ///
    /// The alternative considered and deliberately not built, still open: a
    /// second, never-offered StoreKit product holding the future price, so that
    /// `displayPrice` would render it in the right currency everywhere. It
    /// burns a permanent product identifier for a line that shows for weeks.
    ///
    /// Either way this announces a future increase and not a reduction, which
    /// is what keeps it clear of the Omnibus directive (art. L.112-1-1): a
    /// struck-through reference price would have to have actually been charged
    /// in the previous 30 days, and 79,99 € never was.
    private var founderOfferLabel: Text? {
        guard let end = LifetimeFounderWindow.announcedEnd() else { return nil }
        let date = end.formatted(.dateTime.day().month(.wide).year())
        return Text("Founder offer until \(date).")
    }

    private func planCard(
        product: Product,
        title: LocalizedStringKey,
        subtitle: Text?,
        badge: String?
    ) -> some View {
        let isSelected = product.id == selectedProductID
        return Button {
            selectedProductID = product.id
        } label: {
            // Name and price share one line, so a plan with nothing more to say
            // — the monthly, the lifetime outside its founder window — is a
            // single-line row. Stacking them cost two rows for every plan and
            // left a wide empty column on the right; with three plans that ran
            // the CTA off the bottom of a 6.1-inch screen.
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.dictusBody.weight(.semibold))

                        // Next to the name rather than out by the price: it
                        // qualifies the plan, and the right edge belongs to the
                        // number the user is comparing.
                        if let badge {
                            Text(verbatim: badge)
                                .font(.dictusCaption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.dictusSuccess, in: Capsule())
                                .foregroundColor(.white)
                        }
                    }
                    if let subtitle {
                        subtitle
                            .font(.dictusCaption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 8)

                // The bare amount, with no period suffix: the row's own title
                // already says Yearly / Monthly / Lifetime, and repeating it
                // here was what broke the column. Right-aligning three prices
                // only lines them up if they end on the same token; "39,99 €/an"
                // next to "4,99 €/mois" and "79,99 €" ends on three different
                // ones, so the amounts — the only part being compared — each
                // started at a different x. Ending every row on "€" fixes that,
                // and monospaced digits then hold the digit columns themselves
                // in line across rows of unequal length.
                //
                // `priceLabel(for:)` keeps the period for the CTA, where the
                // sentence has no title to lean on.
                Text(verbatim: product.displayPrice)
                    .font(.dictusSubheading.monospacedDigit())
                    // The price is what the row exists to compare, so it must
                    // not wrap or shrink away when a long plan name and a badge
                    // share the line.
                    .lineLimit(1)
                    .layoutPriority(1)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .dictusAccent : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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

    /// A plan's price carrying its own period, e.g. "39,99 €/an" — or, for the
    /// lifetime non-consumable, "79,99 €" with no period at all.
    ///
    /// Used by the CTA only. The plan rows show the bare amount, because their
    /// titles already name the period and repeating it there cost the price
    /// column its alignment.
    ///
    /// WHY derived from `Product.subscription` rather than from an identifier:
    /// the chain this replaces tested for the yearly ID and fell through to
    /// "/month" for everything else, so the one-off lifetime would have been
    /// advertised as a monthly plan (#350). Any period Dictus does not sell —
    /// a weekly plan, or one of App Store Connect's 3- and 6-month durations —
    /// shows the bare price: less informative, never false. `ProPlanPeriod`
    /// owns that rule so it can be tested.
    private func priceLabel(for product: Product) -> Text {
        let period = product.subscription?.subscriptionPeriod
        switch ProPlanPeriod.resolve(
            unit: period.map { Self.planUnit(for: $0.unit) },
            value: period?.value ?? 0
        ) {
        case .yearly: return Text("\(product.displayPrice)/year")
        case .monthly: return Text("\(product.displayPrice)/month")
        case .unlabelled: return Text(verbatim: product.displayPrice)
        }
    }

    /// Maps StoreKit's period unit onto the one DictusCore reasons about.
    ///
    /// WHY the indirection: the keyboard extension links DictusCore and must
    /// not link StoreKit, so the rule deciding the suffix cannot name
    /// StoreKit's types. This mapping is the only place the two meet.
    private static func planUnit(for unit: Product.SubscriptionPeriod.Unit) -> ProSubscriptionUnit {
        switch unit {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .year: return .year
        @unknown default: return .unknown
        }
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

    /// CTA label follows the selected plan. Price, period and trial duration
    /// come from the StoreKit Product; nothing is hardcoded.
    ///
    /// WHY the sentence wraps `priceLabel(for:)` instead of spelling a period
    /// out per branch: the period belongs to the price, so one localized
    /// sentence serves every plan and there is no branch left to fall through.
    private var ctaLabel: Text {
        guard let product = selectedProduct else { return Text(verbatim: "...") }
        let price = priceLabel(for: product)

        // No `subscription` means a non-consumable, and "Subscribe" would
        // misdescribe a purchase that never renews.
        guard let subscription = product.subscription else {
            return Text("Buy for \(price)")
        }

        // Ask this product for its offer rather than assuming which plan
        // carries one. Configuration puts the trial on the yearly plan today
        // (#215); the CTA should follow the configuration, not a memory of it.
        if isEligibleForTrial,
           let offer = subscription.introductoryOffer,
           offer.paymentMode == .freeTrial,
           let days = trialDays(for: offer) {
            return Text("\(days) days free, then \(price)")
        }
        return Text("Subscribe for \(price)")
    }

    /// Fine print under the CTA, following the selected plan: "Cancel anytime"
    /// describes a subscription and would misdescribe the one-off lifetime.
    /// Falls back to the subscription wording while nothing has loaded, which
    /// is the state the CTA itself shows as "...".
    private var reassuranceLabel: Text {
        guard let product = selectedProduct, product.subscription == nil else {
            return Text("Cancel anytime")
        }
        return Text("One-time purchase")
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
