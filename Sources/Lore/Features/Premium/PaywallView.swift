import SwiftUI
import UIKit
import Observation
import StoreKit

/// The Lore+ paywall (brand/DESIGN.md §7 `DiveSheet`/paywall row + §6 "Paywall
/// enter": skeleton cross-fades at reveal.bloom, no bounce, no shimmer). Ink
/// background so the camera/world recedes, a brass-sheen hero, the honest
/// free-vs-plus table, and the monthly / annual choice with an App Store offer.
///
/// The purchase runs through **StoreKit 2** (`StoreKitService`); Lore's Apple
/// transaction verifier remains the server authority for cloud-gated access.
/// Localized prices come only from loaded `Product`s, never a hardcoded storefront assumption.
/// Trial copy requires both a real free-trial offer and Apple Account
/// eligibility, and derives the duration from StoreKit.
///
/// Presentation contract: present in a `.sheet`; the caller passes the
/// `EntitlementStore`, the `StoreKitService`, and an `AuthService` (for the
/// access token / user id) so a completed purchase can optimistically flip
/// `isPlus` and then reconcile.
struct PaywallView: View {
    /// The store to update on a successful purchase (optimistic + refresh).
    let entitlements: EntitlementStore
    /// The StoreKit 2 client path, products, purchase, restore, eligibility.
    let store: StoreKitService
    /// Auth for the access token (refresh) and user id (optimistic row).
    let auth: AuthService
    /// Optional context line, "Unlock this tour", "Keep reading", so the
    /// paywall knows what brought the user here. Purely for the subhead.
    var context: PaywallContext = .general

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = PaywallModel()
    /// Content cross-fades in (reveal.bloom feel, no bounce/shimmer per §6).
    @State private var appeared = false
    @State private var showManageSubscriptions = false
    @State private var showSignIn = false

    var body: some View {
        ZStack {
            LoreColor.ink950.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    hero
                    // A current member sees only the acknowledgement, never the
                    // plan picker / feature table / trial fine print.
                    if !entitlements.isPlus {
                        valueHighlights
                        planPicker
                        featureTable
                        tripPassSection
                    }
                    purchaseButton
                    if !entitlements.isPlus {
                        finePrint
                    }
                    legalLinks
                }
                .padding(20)
                .padding(.bottom, 12)
            }
            .opacity(appeared ? 1 : 0)
            .animation(
                UIAccessibility.isReduceMotionEnabled
                    ? .easeInOut(duration: LoreMotion.reducedDuration)
                    : .easeInOut(duration: LoreMotion.bloomDuration),
                value: appeared
            )

            closeButton
        }
        .presentationDragIndicator(.visible)
        .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
        .sheet(isPresented: $showSignIn) {
            SignInView()
        }
        .onAppear {
            appeared = true
            model.store = store
        }
        .task {
            // Ensure the model has the store even if `.task` beats `.onAppear`.
            model.store = store
            // Load real StoreKit products (localized prices) + intro-offer
            // eligibility so the plan rows and CTA are truthful.
            await reloadStore()
            // Reflect any membership the user already has (e.g. re-opened the
            // paywall) so the CTA reads "You're a member" rather than selling.
            let token = await auth.validAccessToken()
            await entitlements.refresh(accessToken: token)
        }
    }

    private func reloadStore(force: Bool = false) async {
        await store.loadProducts(force: force)
        model.reconcileSelection()
        await model.refreshEligibility()
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 12) {
            ZStack {
                BrassSheenSurface(shape: RoundedRectangle(cornerRadius: 20))
                    .frame(width: 72, height: 72)
                Image(systemName: "plus.diamond.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(LoreColor.ink)
            }
            .padding(.top, 12)

            Text("Lore+")
                .font(LoreType.displayXL)
                .foregroundStyle(LoreColor.bone)

            Text(context.subhead)
                .font(LoreType.body)
                .foregroundStyle(LoreColor.bone.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(.top, 20)
    }

    private var valueHighlights: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                valueHighlight("Go deeper", icon: "books.vertical.fill", detail: "Unlimited dossiers")
                valueHighlight("Walk hands-free", icon: "headphones", detail: "Narrated tours")
                valueHighlight("Follow the route", icon: "figure.walk", detail: "Walking guides")
            }

            VStack(spacing: 10) {
                valueHighlight("Go deeper", icon: "books.vertical.fill", detail: "Unlimited dossiers")
                valueHighlight("Walk hands-free", icon: "headphones", detail: "Narrated tours")
                valueHighlight("Follow the route", icon: "figure.walk", detail: "Walking guides")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lore plus highlights")
    }

    private func valueHighlight(_ title: String, icon: String, detail: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LoreColor.brass300)
            Text(title)
                .font(LoreType.label)
                .foregroundStyle(LoreColor.bone)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.78))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .padding(.horizontal, 8)
        .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    // MARK: Plan picker (monthly / annual)

    private var availablePlans: [PaywallModel.Plan] {
        PaywallModel.Plan.allCases.filter { store.product(for: $0.productID) != nil }
    }

    @ViewBuilder
    private var planPicker: some View {
        if store.isLoadingProducts && availablePlans.isEmpty {
            VStack(spacing: 10) {
                ForEach([PaywallModel.Plan.annual, .monthly]) { plan in
                    PlanRow(
                        plan: plan,
                        priceLine: "Loading App Store price",
                        badge: nil,
                        selected: false,
                        enabled: false,
                        onTap: {}
                    )
                }
            }
            .accessibilityLabel("Loading membership options from the App Store")
        } else if availablePlans.isEmpty {
            storeUnavailableCard
        } else {
            VStack(spacing: 10) {
                ForEach(availablePlans) { plan in
                    PlanRow(
                        plan: plan,
                        priceLine: model.displayPriceLine(for: plan) ?? "Price unavailable",
                        badge: model.badge(for: plan),
                        selected: model.selectedPlan == plan,
                        enabled: true
                    ) {
                        Haptics.play(.chipTap)
                        Task { await model.select(plan) }
                    }
                }
            }
        }
    }

    private var storeUnavailableCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(LoreColor.brass300)
            Text("App Store options unavailable")
                .font(LoreType.button)
                .foregroundStyle(LoreColor.bone)
            Text(store.lastError ?? "Lore couldn't load localized membership options.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.78))
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await reloadStore(force: true) }
            }
            .font(LoreType.button)
            .foregroundStyle(LoreColor.brass300)
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    // MARK: Free vs. Lore+ table

    private var featureTable: some View {
        VStack(spacing: 0) {
            // Header row
            if dynamicTypeSize.isAccessibilitySize {
                Text("What you get")
                    .font(LoreType.label)
                    .tracking(0.6)
                    .foregroundStyle(LoreColor.bone.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                HStack {
                    Text("What you get")
                        .font(LoreType.label)
                        .tracking(0.6)
                        .foregroundStyle(LoreColor.bone.opacity(0.78))
                    Spacer()
                    Text("Free")
                        .font(LoreType.label).tracking(0.6)
                        .foregroundStyle(LoreColor.bone.opacity(0.78))
                        .frame(width: 52)
                    Text("Lore+")
                        .font(LoreType.label).tracking(0.6)
                        .foregroundStyle(LoreColor.brass300)
                        .frame(width: 52)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            ForEach(FeatureComparison.all) { row in
                Divider().overlay(LoreColor.ink700)
                FeatureRow(row: row, usesExpandedLayout: dynamicTypeSize.isAccessibilitySize)
            }
        }
        .background(LoreColor.ink800, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(LoreColor.ink700, lineWidth: 1)
        )
    }

    // MARK: Purchase CTA

    @ViewBuilder
    private var purchaseButton: some View {
        if entitlements.isPlus {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(entitlements.isTrialing ? "Your Lore+ trial is active" : "Your Lore+ access is active")
                        .font(LoreType.button)
                }
                .foregroundStyle(LoreColor.successDark)

                if store.hasFamilySharedAccess {
                    Label("Shared with you through Apple Family Sharing", systemImage: "person.2.fill")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.82))
                } else if entitlements.isUsingCachedEntitlement {
                    Label("Using a recently verified membership while offline", systemImage: "checkmark.icloud")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.82))
                }

                switch store.accessKind {
                case .subscription:
                    Button("Manage or cancel subscription") {
                        showManageSubscriptions = true
                    }
                    .font(LoreType.button)
                    .foregroundStyle(LoreColor.brass300)
                    .frame(minHeight: 44)
                    Text("Cancellation is handled by Apple. Access continues through the paid period shown in your Apple Account.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.72))
                        .multilineTextAlignment(.center)
                case .lifetime:
                    Text("Lifetime access is a one-time purchase and does not renew.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.78))
                case .tripPass:
                    Text(tripPassStatusText)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.78))
                case .none:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        } else {
            VStack(spacing: 10) {
                Button {
                    Task { await purchase() }
                } label: {
                    ZStack {
                        BrassSheenSurface(shape: RoundedRectangle(cornerRadius: 16))
                        Group {
                            if model.isPurchasing {
                                ProgressView()
                                    .tint(LoreColor.ink)
                            } else {
                                VStack(spacing: 2) {
                                    // Always the real plan copy. This used to read
                                    // "Sign in to continue" when signed out, which
                                    // is the forced-registration paywall App Review
                                    // rejected under 5.1.1(v). Only promise the
                                    // trial when the user is actually eligible for
                                    // the intro offer (docs/16 §1).
                                    Text(model.ctaTitle)
                                        .font(LoreType.button)
                                    Text(model.ctaSubtitle)
                                        .font(LoreType.caption)
                                        .opacity(0.85)
                                }
                                .foregroundStyle(LoreColor.ink)
                            }
                        }
                    }
                    .frame(height: 56)
                }
                .buttonStyle(.plain)
                .disabled(!model.canPurchaseSelectedPlan)
                .opacity(model.canPurchaseSelectedPlan ? 1 : 0.62)
                .accessibilityLabel(model.purchaseAccessibilityLabel)
                .accessibilityHint("Apple shows a confirmation sheet before any purchase is completed")

                // Restore is always available: it is an Apple-ID operation, and
                // hiding it from signed-out users left a reinstalling buyer with
                // no way back to access they already paid for (5.1.1(v)).
                Button("Restore purchases") {
                    Task { await restore() }
                }
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.72))
                .disabled(model.isPurchasing)
                .frame(minHeight: 44)

                // Registration is OFFERED, never required — Apple's own remedy:
                // "explain to the user that registering will enable them to
                // access the purchased content from any of their supported
                // devices and provide them a way to register at any time."
                if !auth.isSignedIn {
                    Button("Sign in to sync Lore+ across your devices") {
                        showSignIn = true
                    }
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.72))
                    .frame(minHeight: 44)
                    .accessibilityHint("Optional. You can buy and use Lore plus without an account.")
                }

                if store.productLoadState == .partial, let message = store.lastError {
                    Text(message)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.78))
                        .multilineTextAlignment(.center)
                }

                if let error = model.purchaseError {
                    Text(error)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.errorDark)
                        .multilineTextAlignment(.center)
                }

                if let notice = model.purchaseNotice {
                    Text(notice)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.82))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var tripPassStatusText: String {
        guard let expiry = store.tripPassExpiresAt else {
            return "Your trip pass is active and does not auto-renew."
        }
        return "Your trip pass is active until \(expiry.formatted(date: .abbreviated, time: .shortened)) and does not auto-renew."
    }

    /// A non-renewing "just visiting" option for one-trip users (the beta-fleet's
    /// #1 pricing recommendation). Hidden until the pass products exist in App
    /// Store Connect, `product(for:)` is nil otherwise, so shipping this ahead of
    /// the ASC products is safe (the section simply doesn't render).
    @ViewBuilder
    private var tripPassSection: some View {
        let pass72 = store.product(for: StoreKitService.ProductID.pass72h)
        let pass7 = store.product(for: StoreKitService.ProductID.pass7d)
        if pass72 != nil || pass7 != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("JUST VISITING?")
                    .font(LoreType.label).tracking(0.6)
                    .foregroundStyle(LoreColor.bone.opacity(0.72))
                Text("A one-time pass. Everything in Lore+ for your trip, no subscription.")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.bone.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if let p = pass72 { passButton(title: "72-hour pass", price: p.displayPrice, id: p.id) }
                    if let p = pass7 { passButton(title: "7-day pass", price: p.displayPrice, id: p.id) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func passButton(title: String, price: String, id: String) -> some View {
        Button {
            Task { await purchase(productID: id) }
        } label: {
            VStack(spacing: 4) {
                Text(title).font(LoreType.button).foregroundStyle(LoreColor.bone)
                Text(price).font(LoreType.caption).foregroundStyle(LoreColor.bone.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 16).fill(LoreColor.ink800))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LoreColor.ink700, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(model.isPurchasing)
        .opacity(model.isPurchasing ? 0.6 : 1)
        .accessibilityLabel("\(title), \(price)")
    }

    private var finePrint: some View {
        Text(model.finePrintText)
        .font(LoreType.caption)
        .foregroundStyle(LoreColor.bone.opacity(0.72))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
    }

    /// Functional Terms of Use + Privacy Policy links, required on the purchase
    /// screen for auto-renewable subscriptions (App Store Review 3.1.2).
    private var legalLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                Link("Terms of Use", destination: ProfileSupportLinks.terms)
                Text("·").foregroundStyle(LoreColor.ink700)
                Link("Privacy Policy", destination: ProfileSupportLinks.privacy)
            }
            VStack(spacing: 10) {
                Link("Terms of Use", destination: ProfileSupportLinks.terms)
                Link("Privacy Policy", destination: ProfileSupportLinks.privacy)
            }
        }
        .font(LoreType.caption)
        .tint(LoreColor.brass300)
        .padding(.top, 2)
        .frame(minHeight: 44)
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                        .frame(width: 44, height: 44)
                        .background(LoreColor.ink800, in: Circle())
                }
                .padding(16)
                .accessibilityLabel("Close")
            }
            Spacer()
        }
    }

    // MARK: Actions

    private func purchase() async {
        await purchase(productID: model.selectedPlan.productID)
    }

    private func purchase(productID: String) async {
        guard store.product(for: productID) != nil else {
            _ = await model.purchase(productID: productID)
            UIAccessibility.post(
                notification: .announcement,
                argument: model.purchaseError ?? "That option isn't available from the App Store right now."
            )
            return
        }
        // Lore+ is NOT account-based content: StoreKit grants it to the Apple ID,
        // and `EntitlementStore.isPlus` unions the on-device
        // `Transaction.currentEntitlements` read, so a signed-out buyer is fully
        // unlocked. Requiring registration first was App Review guideline
        // 5.1.1(v) — "Apps cannot require user registration prior to allowing
        // access to app content and features that are not associated
        // specifically to the user" — and is why 1.1 was rejected. Signing in is
        // now offered (to sync across devices), never required.
        let userID = auth.session?.user.id
        store.accountUUID = userID.flatMap { UUID(uuidString: $0) }
        let outcome = await model.purchase(productID: productID)
        switch outcome {
        case .success:
            // Access comes only from verified StoreKit or server state. Do not
            // synthesize an open-ended grant from the purchase sheet's outcome.
            let token = await auth.validAccessToken()
            await store.refreshEntitlements()
            await entitlements.refresh(accessToken: token)
            guard store.hasActiveEntitlement || entitlements.isPlus else {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Purchase recorded by Apple. Lore plus will refresh when entitlement verification completes."
                )
                return
            }
            Haptics.play(.badgeEarned)  // the unlock is a reward moment
            UIAccessibility.post(notification: .announcement, argument: "Lore plus unlocked")
            dismiss()
        case .pending:
            // Ask-to-Buy / SCA, the grant arrives later via Transaction.updates.
            // Leave the sheet up with the model's informational message.
            UIAccessibility.post(
                notification: .announcement,
                argument: "Purchase pending Apple approval. Lore plus will unlock automatically when approved."
            )
        case .userCancelled:
            break  // no-op, no error
        case .inProgress:
            break
        case .failed:
            UIAccessibility.post(notification: .announcement, argument: model.purchaseError)
        }
    }

    private func restore() async {
        // Restore is an Apple-ID operation and must work signed out: a buyer who
        // reinstalls has to recover access without first creating an account
        // (guideline 5.1.1(v)). Previously this bounced to the sign-in sheet and
        // the button was hidden entirely when signed out.
        // Bind the id first: on `auth.session?.user.id` the optional chain makes
        // `.flatMap` resolve to String's Sequence flatMap (over Characters),
        // not Optional's, which does not compile.
        let restoreUserID = auth.session?.user.id
        store.accountUUID = restoreUserID.flatMap { UUID(uuidString: $0) }
        let outcome = await model.restore()
        if case .restored = outcome {
            let token = await auth.validAccessToken()
            await entitlements.refresh(accessToken: token)
            UIAccessibility.post(notification: .announcement, argument: "Purchases restored. Lore plus is active.")
            dismiss()
        } else if let error = model.purchaseError {
            UIAccessibility.post(notification: .announcement, argument: error)
        }
    }
}

/// What brought the user to the paywall, tunes the subhead only.
enum PaywallContext {
    case general
    case fourthDive
    case tours
    case audio
    case scanner

    var subhead: String {
        switch self {
        case .general:
            return "Unlimited deep dives, curated walking tours, and audio narration."
        case .fourthDive:
            return "You've read your three free dives today. Lore+ opens every dossier, all day, every day."
        case .tours:
            return "Curated walking tours, plus unlimited dives and audio narration."
        case .audio:
            return "Let the docent read to you, plus unlimited dives and curated walking tours."
        case .scanner:
            return "Identify a landmark from one photo when on-device scanning needs help."
        }
    }
}

// MARK: - Plan row

private struct PlanRow: View {
    let plan: PaywallModel.Plan
    /// Localized price from StoreKit, or a loading placeholder on a disabled row.
    let priceLine: String
    let badge: String?
    let selected: Bool
    let enabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? LoreColor.brass300 : LoreColor.bone.opacity(0.72))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(LoreType.button)
                            .foregroundStyle(LoreColor.bone)
                        if let badge {
                            Text(badge)
                                .font(LoreType.label).tracking(0.4)
                                .foregroundStyle(LoreColor.ink)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(BrassSheenSurface(shape: Capsule(), sweepOnAppear: false))
                        }
                    }
                    Text(priceLine)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.bone.opacity(0.72))
                }
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? LoreColor.ink800 : LoreColor.ink900)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        selected ? LoreColor.brass300 : LoreColor.ink700,
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.72)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.title), \(priceLine)")
        .accessibilityHint(enabled ? "Selects this Lore plus plan" : "Waiting for the App Store price")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Feature table rows

/// One line of the free-vs-plus comparison.
struct FeatureComparison: Identifiable {
    let id = UUID()
    let label: String
    /// Free-column cell: `true` = check, `false` = dash, or a short string
    /// (e.g. "3/day").
    let free: Cell
    /// Lore+ column is always a check in this table (everything free has, plus
    /// unlocks fully), but modeled for flexibility.
    let plus: Cell

    enum Cell {
        case yes
        case no
        case text(String)
    }

    /// The honest table mirrors the App Store / Terms benefit language:
    /// deep dives, walking tours, and narration. Feature-specific gates can
    /// still explain scoped extras where the user encounters them.
    static let all: [FeatureComparison] = [
        .init(label: "Unlimited scanning", free: .yes, plus: .yes),
        .init(label: "Layer-1 story cards", free: .yes, plus: .yes),
        .init(label: "Deep dives", free: .text("3/day"), plus: .yes),
        // Free users DO get the free curated tours (roughly half the catalogue
        // is is_premium=false); Plus unlocks the premium walks + audio. Saying
        // "free: no" here undersold the free tier — keep it honest.
        .init(label: "Curated walking tours", free: .text("Free"), plus: .text("All")),
        .init(label: "Audio narration", free: .no, plus: .yes),
        .init(label: "Auto-play walking guide", free: .no, plus: .yes),
        .init(label: "Visit journal & badges", free: .yes, plus: .yes),
    ]
}

private struct FeatureRow: View {
    let row: FeatureComparison
    let usesExpandedLayout: Bool

    @ViewBuilder
    var body: some View {
        if usesExpandedLayout {
            VStack(alignment: .leading, spacing: 10) {
                Text(row.label)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone)
                HStack(spacing: 20) {
                    labeledCell("Free", value: row.free)
                    labeledCell("Lore+", value: row.plus, plus: true)
                }
            }
            .padding(16)
            .accessibilityElement(children: .combine)
        } else {
            HStack {
                Text(row.label)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.bone)
                Spacer()
                cell(row.free).frame(width: 52)
                cell(row.plus, plus: true).frame(width: 52)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func labeledCell(_ label: String, value: FeatureComparison.Cell, plus: Bool = false) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(LoreType.caption)
                .foregroundStyle(plus ? LoreColor.brass300 : LoreColor.bone.opacity(0.78))
            cell(value, plus: plus)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cell(_ value: FeatureComparison.Cell, plus: Bool = false) -> some View {
        switch value {
        case .yes:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(plus ? LoreColor.brass300 : LoreColor.successDark)
        case .no:
            Image(systemName: "minus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LoreColor.bone.opacity(0.72))
        case .text(let string):
            Text(string)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone.opacity(0.72))
        }
    }
}

// MARK: - Model (StoreKit 2 driven)

@Observable
@MainActor
final class PaywallModel {
    /// The two Lore+ SKUs (docs/00 §7), mapped to the real App Store Connect
    /// product identifiers in `StoreKitService.ProductID`.
    enum Plan: String, CaseIterable, Identifiable {
        case monthly
        case annual
        case lifetime

        var id: String { rawValue }

        /// The App Store Connect / StoreKit product identifier (docs/16 §1).
        /// These are the live IDs the `StoreKit/Lore.storekit` file and ASC
        /// both define, not placeholders.
        var productID: String {
            switch self {
            case .monthly: return StoreKitService.ProductID.monthly
            case .annual: return StoreKitService.ProductID.annual
            case .lifetime: return StoreKitService.ProductID.lifetime
            }
        }

        var title: String {
            switch self {
            case .monthly: return "Monthly"
            case .annual: return "Annual"
            case .lifetime: return "Lifetime"
            }
        }

        /// The suffix appended to a localized `displayPrice` so the row reads
        /// "$5.99 / month" even when the number comes from StoreKit.
        var periodSuffix: String {
            switch self {
            case .monthly: return " / month"
            case .annual: return " / year"
            case .lifetime: return ""
            }
        }
    }

    /// The StoreKit 2 client path, injected from the view's `onAppear`. Nil in
    /// previews / before injection, the model shows an unavailable state rather
    /// than inventing a storefront price.
    var store: StoreKitService?

    var selectedPlan: Plan = .annual  // default to the better value
    private(set) var isPurchasing = false
    private(set) var purchaseError: String?
    private(set) var purchaseNotice: String?

    /// StoreKit-authoritative duration for an eligible free trial. Nil means the
    /// current product has no free trial or this Apple Account is ineligible.
    private(set) var trialDurationDescription: String?
    var isEligibleForTrial: Bool { trialDurationDescription != nil }
    private(set) var hasCheckedEligibility = false

    /// Reload intro-offer eligibility for the selected plan (call after products
    /// load, and whenever the plan changes if you want per-plan precision, the
    /// two products share a subscription group, so eligibility is the same).
    func refreshEligibility() async {
        hasCheckedEligibility = false
        guard let store, store.product(for: selectedPlan.productID) != nil else { return }
        // Lifetime is a non-consumable: no intro offer ever applies to it.
        guard selectedPlan != .lifetime else {
            trialDurationDescription = nil
            hasCheckedEligibility = true
            return
        }
        trialDurationDescription = await store.eligibleFreeTrialDescription(
            productID: selectedPlan.productID
        )
        hasCheckedEligibility = true
    }

    func select(_ plan: Plan) async {
        selectedPlan = plan
        await refreshEligibility()
    }

    func reconcileSelection() {
        guard let store else { return }
        if store.product(for: selectedPlan.productID) != nil { return }
        selectedPlan = [.annual, .monthly, .lifetime].first {
            store.product(for: $0.productID) != nil
        } ?? .annual
    }

    /// The CTA title. Lifetime is a one-time unlock; the subscriptions promise
    /// the trial only when the Apple ID is actually eligible.
    var ctaTitle: String {
        if selectedPlan == .lifetime { return "Unlock Lore+ forever" }
        if hasCheckedEligibility, isEligibleForTrial { return "Start free trial" }
        return hasCheckedEligibility ? "Subscribe with Apple" : "Continue with Apple"
    }

    /// Localized price context beneath the CTA. Never repeat hardcoded USD when
    /// StoreKit has supplied the storefront's actual display price.
    var ctaSubtitle: String {
        guard let price = displayPriceLine(for: selectedPlan) else {
            return "Loading price from the App Store"
        }
        if selectedPlan == .lifetime { return "\(price) · one-time" }
        if hasCheckedEligibility, let duration = trialDurationDescription {
            return "\(duration) free, then \(price)"
        }
        return price
    }

    /// The fine print under the CTA, correct per plan (no trial/cancel language
    /// on the lifetime one-time purchase).
    var finePrintText: String {
        guard let price = displayPriceLine(for: selectedPlan) else {
            return "Pricing and purchase availability are provided by the App Store. No purchase can begin until your localized price loads."
        }
        if selectedPlan == .lifetime {
            return "\(price). One payment charged to your Apple Account at confirmation. This purchase does not renew."
        }
        let lead: String
        if hasCheckedEligibility, let duration = trialDurationDescription {
            lead = "\(duration.capitalized) free, then \(price). "
        } else {
            lead = "\(price). "
        }
        let renew = "Payment is charged to your Apple Account at confirmation. Auto-renews \(selectedPlan == .annual ? "yearly" : "monthly") unless canceled at least 24 hours before the current period ends."
        return lead + renew + " Manage or cancel in Apple Account subscriptions. Your free Lore access never expires."
    }

    /// Storefront-authoritative price. Nil is a first-class loading/unavailable
    /// state and disables purchase rather than substituting a US price.
    func displayPriceLine(for plan: Plan) -> String? {
        guard let product = store?.product(for: plan.productID) else { return nil }
        return product.displayPrice + plan.periodSuffix
    }

    func badge(for plan: Plan) -> String? {
        switch plan {
        case .monthly: return nil
        case .annual: return "Best value"
        case .lifetime: return "One-time"
        }
    }

    var canPurchaseSelectedPlan: Bool {
        guard !isPurchasing,
              let store,
              store.product(for: selectedPlan.productID) != nil
        else { return false }
        return AppStore.canMakePayments
    }

    var purchaseAccessibilityLabel: String {
        "\(ctaTitle). \(ctaSubtitle)."
    }

    /// Purchase the selected plan through StoreKit 2.
    func purchase() async -> StoreKitService.PurchaseOutcome {
        await purchase(productID: selectedPlan.productID)
    }

    /// Purchase a specific product. Trip passes use the same status handling as
    /// recurring and lifetime plans, including visible Ask-to-Buy pending state.
    func purchase(productID: String) async -> StoreKitService.PurchaseOutcome {
        guard !isPurchasing else { return .inProgress }
        guard let store else {
            purchaseError = "The store isn't available right now. Try again."
            return .failed(message: purchaseError!)
        }
        guard store.product(for: productID) != nil else {
            purchaseError = "That option isn't available from the App Store right now. No purchase was started."
            return .failed(message: purchaseError!)
        }
        isPurchasing = true
        purchaseError = nil
        purchaseNotice = nil
        defer { isPurchasing = false }

        let outcome = await store.purchase(productID: productID)
        switch outcome {
        case .failed(let message):
            purchaseError = message
        case .pending:
            purchaseNotice = "Purchase pending approval. Lore+ will unlock automatically when Apple completes it."
        case .success, .userCancelled, .inProgress:
            break
        }
        return outcome
    }

    /// Restore prior purchases via StoreKit 2 (`AppStore.sync()` +
    /// `Transaction.currentEntitlements`).
    func restore() async -> StoreKitService.RestoreOutcome {
        guard !isPurchasing else {
            return .failed(message: "Another App Store request is already in progress.")
        }
        guard let store else {
            purchaseError = "The store isn't available right now. Try again."
            return .failed(message: purchaseError!)
        }
        isPurchasing = true
        purchaseError = nil
        purchaseNotice = nil
        defer { isPurchasing = false }
        let outcome = await store.restore()
        switch outcome {
        case .restored:
            break
        case .nothingToRestore:
            purchaseError = "No previous membership found on this Apple ID."
        case .userCancelled:
            break
        case .failed(let message):
            purchaseError = message
        }
        return outcome
    }
}
