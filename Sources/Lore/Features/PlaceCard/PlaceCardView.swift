import SwiftUI

/// The Layer-1 card (brand/DESIGN.md §7 `Card`): place name in display type,
/// year chip, the italic hook line, tag chips, and the dive affordance.
/// Renders from chunk-cached data only — identical online and offline.
struct PlaceCardView: View {
    let place: Place
    @State private var showDive = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let hook = place.layer1?.hook {
                        Text(hook)
                            .font(LoreType.hook)
                            .foregroundStyle(LoreColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    factChips

                    Button {
                        showDive = true
                    } label: {
                        HStack {
                            Image(systemName: "book.pages")
                            Text("Go deeper")
                                .font(LoreType.button)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                    }
                    .background(LoreColor.ink, in: Capsule())
                    .foregroundStyle(LoreColor.bone)
                }
                .padding(16)
            }
            .background(LoreColor.bone100)
            .navigationDestination(isPresented: $showDive) {
                DiveView(place: place)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(place.displayEmoji)
                .font(.system(size: 34))
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(LoreType.displayL)
                    .foregroundStyle(LoreColor.ink)
                Text(place.kind.capitalized)
                    .loreLabelStyle()
                    .foregroundStyle(LoreColor.ink600)
            }
            Spacer()
            if let year = place.layer1?.yearBuilt {
                YearChip(year: year)
            }
        }
    }

    @ViewBuilder
    private var factChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let architect = place.layer1?.architect {
                FactRow(label: "Architect", value: architect)
            }
            if let style = place.layer1?.style {
                FactRow(label: "Style", value: style)
            }
            if let heightM = place.heightM {
                FactRow(label: "Height", value: "\(Int(heightM)) m")
            }
        }
    }
}

struct YearChip: View {
    let year: Int

    var body: some View {
        Text(String(year))
            .font(LoreType.display(size: 15, weight: .medium))
            .foregroundStyle(LoreColor.brass700)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .loreLabelStyle()
                .foregroundStyle(LoreColor.ink600)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(LoreType.body)
                .foregroundStyle(LoreColor.ink)
        }
    }
}
