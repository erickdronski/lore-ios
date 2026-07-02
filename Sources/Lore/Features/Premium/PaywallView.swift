import SwiftUI
import UIKit
import Observation

/// The Lore+ paywall (brand/DESIGN.md §7 `DiveSheet`/paywall row + §6 "Paywall
/// enter": skeleton cross-fades at reveal.bloom, no bounce, no shimmer). Ink
/// background so the camera/world recedes, a brass-sheen hero, the honest
/// free-vs-plus table, and the monthly / annual choice with the 7-day trial.
///
/// Prices are locked in docs/00-DECISIONS.md §7: **$4.99/mo, $29.99/yr, 7-day
/// free trial.** The store products themselves come from RevenueCat at P1
/// (docs/00 §2 names RevenueCat for payments); this screen renders the offer
/// and calls a purchase stub. When the SDK lands, swap `PaywallModel.purchase`
/// for a real `Purchases.shared` call, keep everything else.
///
/// Presentation contract: present in a `.sheet`; the caller passes the
/// `EntitlementStore` and an `AuthService` (for the access token / user id) so
/// a completed purchase can optimistically flip `isPlus` and then reconcile.
struct PaywallView: View {
    /// The store to update on a successful purchase (optimistic + refresh).
    let entitlements: EntitlementStore
    /// Auth for the access token (refresh) and user id (optimistic row).
    let auth: AuthService
    /// Optional context line — "Unlock this tour", "Keep reading" — so the
    /// paywall knows what brought the user here. Purely for the subhead.
    var context: PaywallContext = .general

    @Environment(\.dismiss) private var dismiss
    @State private var model = PaywallModel()
    /// Content cross-fades in (reveal.bloom feel, no bounce/shimmer per §6).
    @State private var appeared = false

    var body: some View {
        ZStack {
            LoreColor.ink950.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    hero
                    planPicker
                    featureTable
                    purchaseButton
                    finePrint
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
        .onAppear { appeared = true }
        .task {
            // Reflect any membership the user already has (e.g. re-opened the
            // paywall) so the CTA reads "You're a member" rather than selling.
            await entitlements.refresh(accessToken: auth.session?.accessToken)
        }
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
                .foregroundStyle(LoreColor.ink600)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    // MARK: Plan picker (monthly / annual)

    private var planPicker: some View {
        VStack(spacing: 10) {
            ForEach(PaywallModel.Plan.allCases) { plan in
                PlanRow(
                    plan: plan,
                    selected: model.selectedPlan == plan
                ) {
                    Haptics.play(.chipTap)
                    model.selectedPlan = plan
                }
            }
        }
    }

    // MARK: Free vs. Lore+ table

    private var featureTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text("What you get")
                    .font(LoreType.label)
                    .tracking(0.6)
                    .foregroundStyle(LoreColor.ink600)
                Spacer()
                Text("Free")
                    .font(LoreType.label).tracking(0.6)
                    .foregroundStyle(LoreColor.ink600)
                    .frame(width: 52)
                Text("Lore+")
                    .font(LoreType.label).tracking(0.6)
                    .foregroundStyle(LoreColor.brass300)
                    .frame(width: 52)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ForEach(FeatureComparison.all) { row in
                Divider().overlay(LoreColor.ink700)
                FeatureRow(row: row)
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
            // Already a member — no sell, just acknowledge.
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                Text(entitlements.isTrialing ? "You're on the Lore+ trial" : "You're a Lore+ member")
                    .font(LoreType.button)
            }
            .foregroundStyle(LoreColor.successDark)
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
                                    Text("Start 7-day free trial")
                                        .font(LoreType.button)
                                    Text(model.selectedPlan.ctaSubtitle)
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
                .disabled(model.isPurchasing)

                Button("Restore purchases") {
                    Task { await restore() }
                }
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
                .disabled(model.isPurchasing)

                if let error = model.purchaseError {
                    Text(error)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.errorDark)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var finePrint: some View {
        Text(
            "7 days free, then \(model.selectedPlan.priceLine). Cancel anytime in "
            + "Settings. Your free daily dives and unlimited scanning never expire."
        )
        .font(LoreType.caption)
        .foregroundStyle(LoreColor.ink600)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
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
                        .frame(width: 32, height: 32)
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
        let succeeded = await model.purchase()
        guard succeeded else { return }
        // Optimistically flip to Lore+ (trialing) so the gate reopens now; the
        // server webhook writes the real row, and `refresh` reconciles.
        if let userID = auth.session?.user.id {
            entitlements.applyLocalPurchase(userID: userID, trialing: true)
        }
        await entitlements.refresh(accessToken: auth.session?.accessToken)
        Haptics.play(.badgeEarned)  // the unlock is a reward moment
        dismiss()
    }

    private func restore() async {
        let restored = await model.restore()
        if restored {
            await entitlements.refresh(accessToken: auth.session?.accessToken)
            dismiss()
        }
    }
}

/// What brought the user to the paywall — tunes the subhead only.
enum PaywallContext {
    case general
    case fourthDive
    case tours
    case audio
    case offline

    var subhead: String {
        switch self {
        case .general:
            return "Unlimited deep dives, curated walks, offline cities, and audio narration."
        case .fourthDive:
            return "You've read your three free dives today. Lore+ opens every dossier, all day, every day."
        case .tours:
            return "Curated walking tours, plus unlimited dives, offline cities, and audio."
        case .audio:
            return "Let the docent read to you, plus unlimited dives, tours, and offline cities."
        case .offline:
            return "Download whole cities for the trip, plus unlimited dives, tours, and audio."
        }
    }
}

// MARK: - Plan row

private struct PlanRow: View {
    let plan: PaywallModel.Plan
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? LoreColor.brass300 : LoreColor.ink600)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(LoreType.button)
                            .foregroundStyle(LoreColor.bone)
                        if let badge = plan.savingsBadge {
                            Text(badge)
                                .font(LoreType.label).tracking(0.4)
                                .foregroundStyle(LoreColor.ink)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(BrassSheenSurface(shape: Capsule(), sweepOnAppear: false))
                        }
                    }
                    Text(plan.priceLine)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plan.title), \(plan.priceLine)")
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

    /// The honest table, straight from docs/00 §7.
    static let all: [FeatureComparison] = [
        .init(label: "Unlimited scanning", free: .yes, plus: .yes),
        .init(label: "Layer-1 story cards", free: .yes, plus: .yes),
        .init(label: "Deep dives", free: .text("3/day"), plus: .yes),
        .init(label: "Curated walking tours", free: .no, plus: .yes),
        .init(label: "Offline city packs", free: .no, plus: .yes),
        .init(label: "Audio narration", free: .no, plus: .yes),
        .init(label: "Early-access cities", free: .no, plus: .yes),
        .init(label: "Contribute & earn badges", free: .yes, plus: .yes),
    ]
}

private struct FeatureRow: View {
    let row: FeatureComparison

    var body: some View {
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
                .foregroundStyle(LoreColor.ink600)
        case .text(let string):
            Text(string)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
    }
}

// MARK: - Model + purchase stub

@Observable
@MainActor
final class PaywallModel {
    /// The two Lore+ SKUs (docs/00 §7). Product identifiers are placeholders
    /// until the RevenueCat dashboard defines them.
    enum Plan: String, CaseIterable, Identifiable {
        case monthly
        case annual

        var id: String { rawValue }

        /// The RevenueCat / StoreKit product identifier.
        /// TODO(P1): confirm these match the App Store Connect + RevenueCat
        /// product IDs (docs/00 §2 names RevenueCat).
        var productID: String {
            switch self {
            case .monthly: return "app.lore.plus.monthly"
            case .annual: return "app.lore.plus.annual"
            }
        }

        var title: String {
            switch self {
            case .monthly: return "Monthly"
            case .annual: return "Annual"
            }
        }

        /// The price line, locked in docs/00 §7. TODO(P1): render the
        /// *localized* price from the fetched StoreKit product, not this
        /// hardcoded USD string.
        var priceLine: String {
            switch self {
            case .monthly: return "$4.99 / month"
            case .annual: return "$29.99 / year"
            }
        }

        /// Sub-line under the CTA after the trial ("then $4.99/mo").
        var ctaSubtitle: String {
            switch self {
            case .monthly: return "then $4.99/mo"
            case .annual: return "then $29.99/yr"
            }
        }

        /// The "save 50%" style badge on annual. $29.99 vs $59.88 ≈ 50% off.
        var savingsBadge: String? {
            switch self {
            case .monthly: return nil
            case .annual: return "Save 50%"
            }
        }
    }

    var selectedPlan: Plan = .annual  // default to the better value
    private(set) var isPurchasing = false
    private(set) var purchaseError: String?

    /// Purchase the selected plan.
    ///
    /// **RevenueCat-ready stub.** Today it simulates a successful purchase so
    /// the paywall flow, optimistic entitlement flip, and gate reopening can be
    /// exercised end-to-end without the SDK. It returns `true` on "success".
    ///
    /// TODO(P1): replace the body with the real purchase:
    /// ```swift
    /// // import RevenueCat
    /// let offerings = try await Purchases.shared.offerings()
    /// guard let package = offerings.current?.availablePackages
    ///         .first(where: { $0.storeProduct.productIdentifier == selectedPlan.productID })
    /// else { throw PurchaseError.noProduct }
    /// let result = try await Purchases.shared.purchase(package: package)
    /// return result.customerInfo.entitlements["lore_plus"]?.isActive == true
    /// ```
    /// The RevenueCat webhook writes the `entitlements` row server-side; the
    /// caller's `EntitlementStore.refresh` then reconciles. Keep the return
    /// contract (`Bool` success) so the paywall wiring is untouched.
    func purchase() async -> Bool {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        // --- STUB: simulate the store round-trip. Remove at P1. ---
        try? await Task.sleep(nanoseconds: 600_000_000)
        // Flip to `false` here to exercise the error branch during development.
        let simulatedSuccess = true
        if !simulatedSuccess {
            purchaseError = "That didn't go through. No charge was made, try again."
            return false
        }
        return true
        // --- end STUB ---
    }

    /// Restore prior purchases.
    ///
    /// TODO(P1): `let info = try await Purchases.shared.restorePurchases()` then
    /// `return info.entitlements["lore_plus"]?.isActive == true`.
    func restore() async -> Bool {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        try? await Task.sleep(nanoseconds: 400_000_000)
        // STUB: nothing to restore in the scaffold.
        purchaseError = "No previous membership found on this Apple ID."
        return false
    }
}
