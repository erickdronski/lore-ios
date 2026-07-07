import SwiftUI

/// The Layer-1 card (brand/DESIGN.md §7 `Card`): place name in display type,
/// year chip, the italic hook line, tag chips, and the dive affordance.
/// Renders from chunk-cached data only, identical online and offline.
struct PlaceCardView: View {
    let place: Place
    /// Open "Meet {City}" (the culture surface) for this place's city. Injected
    /// so the card never imports the tab structure; a no-op default keeps
    /// previews / standalone hosts working.
    var onMeetCity: (String) -> Void = { _ in }
    @State private var showDive = false
    @State private var showShare = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The shared-element morph namespace (LUXURY-MOTION §6): the medallion + the
    /// card surface morph between the Layer-1 card and the full dossier.
    @Namespace private var morph

    /// One shared id per place so the medallion morphs across the two headers.
    private var medallionID: String { "medallion-\(place.id)" }

    var body: some View {
        ZStack {
            // Layer-1 card, the surface the dossier *grows from*. It stays
            // mounted (scaled/faded back) beneath the dossier so the morph reads
            // as one continuous surface, not a cut to a new screen.
            layerOneCard
                .opacity(showDive ? 0 : 1)
                .scaleEffect(cardRestScale)
                .allowsHitTesting(!showDive)

            // The dossier, grown from the card. Same namespace ⇒ the medallion
            // morphs; the whole panel springs up on `spring.smooth`.
            if showDive {
                dossier
                    .transition(dossierTransition)
                    .zIndex(1)
            }
        }
        .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: showDive)
        .sheet(isPresented: $showShare) {
            PlaceShareSheet(place: place)
        }
    }

    // MARK: Layer-1 card

    private var layerOneCard: some View {
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
                        Haptics.play(.dossierOpen)
                        showDive = true
                    } label: {
                        // Background + tint live *inside* the label so the press
                        // scale (PressableStyle) lifts the whole capsule, not just
                        // the text sitting on a static pill.
                        HStack {
                            Image(systemName: "book.pages")
                            Text("Go deeper")
                                .font(LoreType.button)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(LoreColor.ink, in: Capsule())
                        .foregroundStyle(LoreColor.bone)
                    }
                    .buttonStyle(.pressable)

                    // Meet-the-City entry (task: expose from PlaceCard). Routes
                    // out to the culture surface for this place's city.
                    Button {
                        Haptics.play(.chipTap)
                        onMeetCity(place.city)
                    } label: {
                        HStack {
                            Image(systemName: "quote.bubble")
                            Text("Meet this city")
                                .font(LoreType.button)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .overlay(Capsule().strokeBorder(LoreColor.ink, lineWidth: 1.5))
                        .foregroundStyle(LoreColor.ink)
                    }
                    .buttonStyle(.pressable)
                }
                .padding(16)
            }
            .background(LoreColor.bone100)
        }
    }

    // MARK: Dossier (morph target)

    private var dossier: some View {
        ZStack(alignment: .top) {
            DiveView(place: place, morphNamespace: morph, medallionID: medallionID)

            HStack {
                // Dismiss affordance, springs the dossier back down into the card.
                Button {
                    showDive = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Close dossier"))

                Spacer()

                // Share the dossier (same poster composer as the card), so a
                // reader can post the deep dive without closing it first.
                Button {
                    Haptics.play(.chipTap)
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Share \(place.name)"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    /// The card rests slightly shrunk while the dossier is up, so the two
    /// surfaces read as depth (the card sits *behind*). No transform under
    /// Reduce Motion.
    private var cardRestScale: CGFloat {
        if reduceMotion { return 1 }
        return showDive ? 0.96 : 1
    }

    /// The dossier grows in from the card's scale; Reduce Motion is a crossfade.
    private var dossierTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.94).combined(with: .opacity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // The morph *source* medallion, carries the shared id so it becomes
            // the dossier header disc. Sized to the Layer-1 card's 34pt emoji.
            Text(place.displayEmoji)
                .font(.system(size: 34))
                .matchedGeometryEffect(id: medallionID, in: morph)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(LoreType.displayL)
                    .foregroundStyle(LoreColor.ink)
                Text(place.kind.capitalized)
                    .loreLabelStyle()
                    .foregroundStyle(LoreColor.ink600)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if let year = place.layer1?.yearBuilt {
                    YearChip(year: year)
                }
                shareButton
            }
        }
    }

    /// Share affordance (strategy synth: sharing is the growth engine, so it is
    /// a first-class, always-visible control on every place). Opens the poster
    /// composer for one-tap posting to Instagram / TikTok / X or Save Image.
    private var shareButton: some View {
        Button {
            Haptics.play(.chipTap)
            showShare = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LoreColor.ink)
                .frame(width: 36, height: 36)
                .background(LoreColor.bone200, in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Share \(place.name)"))
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
                // Height rolls up on first view (LUXURY-MOTION §5 tickers).
                NumericFactRow(label: "Height", value: Int(heightM), suffix: " m")
            }
        }
    }
}

/// A `FactRow` whose value is a number that counts up on first view, the
/// height/measurement ticker (LUXURY-MOTION §5). Same layout as `FactRow` so it
/// sits flush in the fact list. Reduce Motion shows the final value (no roll,
/// handled inside `CountUpText`).
struct NumericFactRow: View {
    let label: String
    let value: Int
    var suffix: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .loreLabelStyle()
                .foregroundStyle(LoreColor.ink600)
                .frame(width: 88, alignment: .leading)
            CountUpText.integer(value, suffix: suffix, font: LoreType.body)
                .foregroundStyle(LoreColor.ink)
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
