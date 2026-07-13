import SwiftUI

/// A "meanwhile-nearby" story marker floating at its real spot in the
/// viewfinder (docs/12 §3.1): *"On this corner, 1934…"*. This is the life and
/// history of everything around you, the fire, the film shoot, the riot, the
/// invention that has no building of its own, so it renders as a *ghost of a
/// moment*, deliberately lighter than a place pin (a smaller disc, a dashed
/// tether) so it never competes with the primary resolve (docs/12 §3.1 layer 2).
///
/// Chrome over live camera: Amber/Ink/Bone only, scrim-backed text
/// (brand/DESIGN.md §4). Haunted moments (the opt-in night layer, §3.1 layer 3)
/// carry a distinct dimmer, cooler treatment, framed as reported legend.
struct StoryMarker: View {
    let projected: ProjectedStory
    var onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloomed = false

    private var isHaunted: Bool { projected.story.isHaunted }
    private var isHiddenFind: Bool { projected.story.isHiddenFind }

    var body: some View {
        VStack(spacing: 4) {
            // The tether disc, smaller than a place pin, dashed ring so it
            // reads as "a moment here", not "a building here". A hidden find
            // earns a solid amber ring + ✦: a secret worth walking to, still
            // lighter than any place pin.
            ZStack {
                Circle()
                    .fill(LoreColor.ink.opacity(isHaunted ? 0.55 : 0.72))
                    .frame(width: 26, height: 26)
                Circle()
                    .strokeBorder(
                        LoreColor.amber.opacity(isHaunted ? 0.5 : isHiddenFind ? 1.0 : 0.8),
                        style: isHiddenFind
                            ? StrokeStyle(lineWidth: 1.5)
                            : StrokeStyle(lineWidth: 1, dash: [3, 2])
                    )
                    .frame(width: 26, height: 26)
                Text(projected.story.displayEmoji)
                    .font(.system(size: 13))
                if isHiddenFind {
                    Text("✦")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LoreColor.amber)
                        .offset(x: 11, y: -11)
                }
            }

            // The one-line hook: "On this corner, 1934…", year + a taste of
            // the title, deliberately terse (the full narrative is the sheet).
            Text(hookLine)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.bone)
                .lineLimit(1)
                // Clamp the width so a long, undated story title truncates with
                // an ellipsis instead of running off the screen edge.
                .frame(maxWidth: 220)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (isHaunted ? LoreColor.scrimSky : LoreColor.scrimFacade),
                    in: Capsule()
                )
        }
        .scaleEffect(bloomed ? 1 : 0.6)
        .opacity(bloomed ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.16) : LoreMotion.bloom) {
                bloomed = true
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.play(.chipTap)
            onTap()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLine))
        .accessibilityAddTraits(.isButton)
    }

    /// "On this corner, 1934" style lead. Uses the curated `year_label` when
    /// present; drops the year clause entirely when a story has no date so we
    /// never render a dangling comma (brand/ELEVATION §1 dedash discipline).
    private var hookLine: String {
        let year = projected.story.displayYear
        if year.isEmpty {
            return projected.story.title
        }
        return "On this spot, \(year)"
    }

    private var accessibilityLine: String {
        let year = projected.story.displayYear
        let prefix = isHaunted ? "Reported legend. " : isHiddenFind ? "Hidden find. " : ""
        if year.isEmpty {
            return "\(prefix)\(projected.story.title), \(projected.distanceLabel) away"
        }
        return "\(prefix)\(projected.story.title), \(year), \(projected.distanceLabel) away"
    }
}

/// The full-story sheet reached by tapping a marker. Docent voice, one moment,
/// the narrative collapsed to a lead + Read more (brand/ELEVATION §5b density
/// rule) so the sheet opens on a taste, never a wall of text.
struct StorySheet: View {
    let story: Story
    @State private var expanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(story.displayEmoji)
                        .font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(story.title)
                            .font(LoreType.displayM)
                            .foregroundStyle(LoreColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !story.displayYear.isEmpty {
                            Text(story.displayYear)
                                .loreLabelStyle()
                                .foregroundStyle(LoreColor.brass700)
                        }
                    }
                    Spacer()
                }

                if story.isHaunted {
                    Text("REPORTED LEGEND")
                        .loreLabelStyle()
                        .foregroundStyle(LoreColor.ink600)
                }

                if story.isHiddenFind {
                    Text("✦ HIDDEN FIND")
                        .loreLabelStyle()
                        .foregroundStyle(LoreColor.brass700)
                }

                if let narrative = story.narrative, !narrative.isEmpty {
                    // Translated on-device into the reader's language, badged
                    // honestly, falling back to the English original (matches the
                    // dossier, so a scanner-discovered story isn't English-only).
                    LocalizedContent(source: narrative) { text, translated in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(text)
                                .font(LoreType.reader)
                                .foregroundStyle(LoreColor.ink)
                                .lineLimit(expanded ? nil : 3)
                                .fixedSize(horizontal: false, vertical: true)
                            if translated { TranslatedBadge() }
                        }
                    }

                    if !expanded {
                        Button(L10n.t("dossier.readMore")) {
                            withAnimation(LoreMotion.unfurl) { expanded = true }
                        }
                        .font(LoreType.button)
                        .foregroundStyle(LoreColor.brass700)
                    }
                }
            }
            .padding(16)
        }
        .background(LoreColor.bone100)
    }
}
