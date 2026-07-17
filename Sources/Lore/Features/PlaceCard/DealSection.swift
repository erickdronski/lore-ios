import SwiftUI

/// "Plan your visit" — real, curator-checked ways to experience a place,
/// grouped into a small set of tasteful families (tours, stay, dine, getting
/// around, staying connected). This is an explorer's concierge note, NOT an ad
/// grid: quiet glyphs, plain labels, one honest line per offer. Self-hides when
/// there is nothing real to show. Free users see the *shape* of what's here —
/// which families exist and the true count — behind a single soft lock; Plus
/// taps out to the real marketplace page.
///
/// Honesty rules embodied here: every merchant is named ("via …"), a price is
/// only shown when it was truly checked (with its date), and `match_note`
/// states HOW the offer relates to this place. Nothing is invented or estimated.
struct DealSection: View {
    let placeID: String

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var deals: [Deal] = []
    @State private var showPaywall = false

    var body: some View {
        Group {
            if deals.isEmpty {
                // Zero-size anchor so `.task` fires even while empty — an
                // absent view never appears, and a task that never runs could
                // never discover the offers (same trap as TravelerLoreSection).
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

    /// Offers folded into their families, in the app's stable order.
    private var grouped: [(category: OfferCategory, offers: [Deal])] {
        Dictionary(grouping: deals, by: { $0.offerCategory })
            .map { (category: $0.key, offers: $0.value) }
            .sorted { $0.category.order < $1.category.order }
    }

    /// The distinct families present — drives the free teaser's preview chips.
    private var families: [OfferCategory] {
        var seen = Set<OfferCategory>()
        return deals.compactMap { deal in
            let c = deal.offerCategory
            return seen.insert(c).inserted ? c : nil
        }.sorted { $0.order < $1.order }
    }

    // MARK: Plus — the grouped concierge panel

    private var section: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLAN YOUR VISIT")
                        .loreLabelStyle()
                        .foregroundStyle(LoreColor.brass700)
                    Text("Curated ways to experience this place")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(LoreColor.brass700)
            }
            ForEach(grouped, id: \.category.id) { group in
                VStack(alignment: .leading, spacing: 8) {
                    categoryHeader(group.category, count: group.offers.count)
                    ForEach(group.offers) { deal in
                        DealRow(deal: deal)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 16))
    }

    private func categoryHeader(_ category: OfferCategory, count: Int) -> some View {
        HStack(spacing: 7) {
            Image(systemName: category.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LoreColor.brass700)
                .frame(width: 16)
            Text(category.label.uppercased())
                .font(LoreType.micro).tracking(0.5)
                .foregroundStyle(LoreColor.ink)
            Spacer()
            if count > 1 {
                Text("\(count)")
                    .font(LoreType.micro)
                    .foregroundStyle(LoreColor.ink600)
            }
        }
    }

    // MARK: Free — the honest, tasteful teaser

    /// Shows the *shape* of the value (which families are here + the true
    /// count) without revealing the offers, behind one soft lock. No prices,
    /// no pressure — a quiet promise that pays for itself.
    private var lockedTeaser: some View {
        Button {
            showPaywall = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15))
                        .foregroundStyle(LoreColor.brass700)
                    Text(deals.count == 1
                         ? "1 curated offer here"
                         : "\(deals.count) curated offers here")
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.ink)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LoreColor.ink600)
                }
                // Preview the families — a quiet row of glyphs shows there are
                // tours, a place to stay, a table to book… just not the
                // specifics. Icon-only so it never truncates and stays premium;
                // the subcopy below names them in words.
                HStack(spacing: 7) {
                    ForEach(families.prefix(7)) { family in
                        Image(systemName: family.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LoreColor.brass700)
                            .frame(width: 30, height: 30)
                            .background(LoreColor.bone50, in: Circle())
                            .overlay(Circle().strokeBorder(LoreColor.brass700.opacity(0.25), lineWidth: 1))
                            .accessibilityLabel(Text(family.teaserWord))
                    }
                }
                Text("Real tours, stays and tables for the places you explore — named, checked, and yours with Lore+.")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LoreColor.brass700.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("\(deals.count) curated offers on this place, a Lore Plus feature"))
    }
}

// MARK: - Shared row

/// One offer, shared by the place card's grouped panel and the city rail.
/// Taps out to the real marketplace page; the merchant is always named and a
/// price is only shown when it was genuinely checked. A quiet leading glyph
/// carries the family so the row still reads on its own in the city rail.
struct DealRow: View {
    let deal: Deal

    @Environment(\.openURL) private var openURL

    private var hasPrice: Bool { deal.priceOriginal != nil || deal.priceDeal != nil }

    var body: some View {
        Button {
            Haptics.play(.chipTap)
            if let url = deal.dealURL { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: deal.offerCategory.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LoreColor.brass700)
                    .frame(width: 22, height: 22)
                    .background(LoreColor.bone50, in: Circle())
                    .overlay(Circle().strokeBorder(LoreColor.brass700.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(deal.title)
                            .font(LoreType.display(size: 14, weight: .semibold))
                            .foregroundStyle(LoreColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(LoreColor.brass700)
                    }
                    if hasPrice {
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
                        }
                    }
                    if let note = deal.matchNote {
                        Text(note)
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        Text(deal.sourceLabel)
                            .font(LoreType.micro)
                            .foregroundStyle(LoreColor.ink600)
                        if let checked = deal.checkedLabel {
                            Text("· \(checked)")
                                .font(LoreType.micro)
                                .foregroundStyle(LoreColor.ink600)
                        }
                    }
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoreColor.bone50, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("\(deal.title), \(deal.sourceLabel), opens in browser"))
    }
}
