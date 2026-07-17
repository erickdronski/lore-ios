import SwiftUI

/// Deals & discounts on a place (Lore+): real, curator-checked offers from
/// deal marketplaces (Groupon today), matched to this place — admission
/// included in a pass, or steps away. Self-hides when there is nothing real
/// to show. Free users see an honest locked teaser with the true deal count;
/// Plus taps out to the marketplace page in the browser.
///
/// Honesty rules embodied here: the marketplace is always named, the price
/// carries its checked date, and `match_note` states HOW the deal relates to
/// this place. No deal is ever invented, estimated, or shown past `active`.
struct DealSection: View {
    let placeID: String

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var deals: [Deal] = []
    @State private var showPaywall = false

    /// How many offers render inline before the count rolls up.
    private static let inlineCount = 3

    var body: some View {
        Group {
            if deals.isEmpty {
                // Zero-size anchor so `.task` fires even while empty — an
                // absent view never appears, and a task that never runs could
                // never discover the deals (same trap as TravelerLoreSection).
                Color.clear.frame(width: 0, height: 0)
            } else if entitlements.isPlus {
                section
            } else {
                lockedTeaser
            }
        }
        .task(id: placeID) { await load() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(entitlements: entitlements, store: store, auth: auth, context: .general)
        }
    }

    private func load() async {
        deals = (try? await LoreAPI.shared.deals(placeID: placeID)) ?? []
    }

    // MARK: Plus

    private var section: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DEALS & DISCOUNTS")
                    .loreLabelStyle()
                    .foregroundStyle(LoreColor.brass700)
                Spacer()
                if let checked = deals.first?.checkedLabel {
                    Text(checked)
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.ink600)
                }
            }
            ForEach(deals.prefix(Self.inlineCount)) { deal in
                DealRow(deal: deal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Free

    /// The honest teaser: the true count, the true source, and the lock.
    // (Rows shared with the city rail live below as `DealRow`.)
    private var lockedTeaser: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tag")
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(deals.count == 1
                         ? "A deal on this place"
                         : "\(deals.count) deals on this place")
                        .font(LoreType.button)
                    // Value-forward + source-agnostic: the deals come from many
                    // real marketplaces (named per-offer once unlocked), and the
                    // whole point is that they can outweigh the membership.
                    Text("Real, checked savings on the places you explore — the kind that pay Lore+ back. Unlock with a membership.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(LoreColor.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LoreColor.brass700.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Deals on this place, a Lore Plus feature"))
    }
}

// MARK: - Shared row

/// One offer row, shared by the place card's deal section and the city rail.
/// Taps out to the marketplace page; the marketplace is always named and the
/// price snapshot carries its checked date via the section header.
struct DealRow: View {
    let deal: Deal

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            Haptics.play(.chipTap)
            if let url = deal.dealURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(deal.merchant)
                        .font(LoreType.display(size: 14, weight: .semibold))
                        .foregroundStyle(LoreColor.ink)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LoreColor.brass700)
                }
                Text(deal.title)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let was = deal.priceOriginal {
                        Text(was)
                            .font(LoreType.caption)
                            .strikethrough()
                            .foregroundStyle(LoreColor.ink600)
                    }
                    if let now = deal.priceDeal {
                        Text(now)
                            .font(LoreType.display(size: 14, weight: .semibold))
                            .foregroundStyle(LoreColor.brass700)
                    }
                    if let discount = deal.discountLabel {
                        Text(discount)
                            .font(LoreType.micro)
                            .foregroundStyle(LoreColor.ink900)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(LoreColor.amber, in: Capsule())
                    }
                    Spacer()
                    Text(deal.sourceLabel)
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.ink600)
                }
                if let note = deal.matchNote {
                    Text(note)
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("\(deal.merchant): \(deal.title), opens \(deal.sourceLabel)"))
    }
}
