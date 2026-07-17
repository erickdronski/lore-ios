import SwiftUI

/// The city-wide deals rail (Lore+): passes and always-on bundles for the
/// selected city, from the ranked `city_deal_feed`. Lives on the Tours tab —
/// the "things to do here" home — right where someone planning a day wants it.
///
/// Same honesty contract as the place card's `DealSection`: self-hides when
/// the city has nothing real; free users see a locked teaser with the true
/// count; every offer names its marketplace and carries its checked date.
struct CityDealsSection: View {
    let city: String

    @Environment(EntitlementStore.self) private var entitlements
    @Environment(StoreKitService.self) private var store
    @Environment(AuthService.self) private var auth

    @State private var deals: [Deal] = []
    @State private var showPaywall = false

    /// "austin" → "Austin", "washington-dc" → "Washington Dc" is wrong, so
    /// keep it simple: capitalize words, special-case nothing (the header
    /// reads "DEALS IN AUSTIN" style anyway).
    private var cityLabel: String {
        city.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var body: some View {
        Group {
            if deals.isEmpty {
                // Zero-size anchor: `.task` must fire while empty or the rail
                // could never learn the city has offers (the empty-Group trap).
                Color.clear.frame(width: 0, height: 0)
            } else if entitlements.isPlus {
                section
            } else {
                lockedTeaser
            }
        }
        .task(id: city) { await load() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(entitlements: entitlements, store: store, auth: auth, context: .general)
        }
    }

    private func load() async {
        deals = (try? await LoreAPI.shared.cityDeals(city: city)) ?? []
    }

    // MARK: Plus

    private var section: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PASSES & DEALS · \(cityLabel.uppercased())")
                    .loreLabelStyle()
                    .foregroundStyle(LoreColor.brass700)
                Spacer()
                if let checked = deals.first?.checkedLabel {
                    Text(checked)
                        .font(LoreType.micro)
                        .foregroundStyle(LoreColor.ink600)
                }
            }
            ForEach(deals) { deal in
                DealRow(deal: deal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Free

    private var lockedTeaser: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tag")
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(deals.count == 1
                         ? "A city pass deal in \(cityLabel)"
                         : "\(deals.count) passes & deals in \(cityLabel)")
                        .font(LoreType.button)
                    Text("Real, checked savings on this city's passes and attractions — the kind that pay Lore+ back.")
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
        .accessibilityLabel(Text("Passes and deals in \(cityLabel), a Lore Plus feature"))
    }
}
