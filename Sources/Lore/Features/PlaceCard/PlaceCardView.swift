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
    /// Open straight to the dossier on appear. Used only by the App Store
    /// screenshot pipeline (`ScreenshotSupport` "dive" stage) so a capture can
    /// land on the deep dive without a tap; defaults off for every real
    /// presentation.
    var autoDive: Bool = false
    @State private var showDive = false
    @State private var showShare = false

    /// The reader's own layer: log the visit and write their lore right here,
    /// where the place's story lives (owner ask: "their lore is an extension
    /// of the place"). History loads on appear; the editor is the Journal's.
    @Environment(VisitStore.self) private var visits
    @State private var showLoreEditor = false
    @State private var showSignIn = false

    /// The place's lead photo (TestFlight feedback: "photo of the place should
    /// be in the first tile"). Resolved from the dive's `media.wikipedia_title`
    /// through the same Wikipedia summary API the culture portraits use; the
    /// hero self-hides on a confirmed miss so a place without a photo leaves no
    /// empty frame.
    @State private var heroURL: URL?
    @State private var heroResolved = false
    /// The place's dive, loaded once for both the hero photo and a story teaser
    /// that fills the card for free users (TestFlight feedback: "wasted real
    /// estate, fill the white space below with more fun").
    @State private var dive: Dive?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Layer-1 card, the surface the dossier *grows from*. It stays
            // mounted (scaled/faded back) beneath the dossier so the morph reads
            // as one continuous surface, not a cut to a new screen.
            layerOneCard
                .opacity(showDive ? 0 : 1)
                .scaleEffect(cardRestScale)
                .allowsHitTesting(!showDive)

            // The dossier springs up on `spring.smooth`. (No shared-element
            // medallion morph: pinning a matchedGeometryEffect disc across a
            // scrolling dossier left the emoji floating over the narrative + the
            // Read more button. The dossier medallion now lives in its own header
            // and scrolls with the content.)
            if showDive {
                dossier
                    .transition(dossierTransition)
                    .zIndex(1)
            }
        }
        .animation(LoreSpring.smooth(reduceMotion: reduceMotion), value: showDive)
        .onAppear {
            // Screenshot pipeline only: land directly on the dossier.
            if autoDive && !showDive { showDive = true }
        }
        .sheet(isPresented: $showShare) {
            PlaceShareSheet(place: place)
        }
        // The user's journal entries, so `yourLore` can render this place's note
        // + photos the moment the card opens (cheap: one RLS-scoped GET).
        .task(id: place.id) { await visits.loadHistory() }
        .sheet(isPresented: $showLoreEditor) {
            NoteEditorSheet(entry: loreEntry) { note in
                Task { await visits.saveNote(placeID: place.id, note: note) }
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInView()
                .presentationDetents([.large])
        }
    }

    // MARK: Your lore (the reader's own layer on this place)

    /// This place's entry in the user's visit history, once loaded.
    private var myEntry: VisitLogEntry? {
        visits.visitHistory.first { $0.placeID == place.id }
    }

    /// The entry the editor opens with: the real history row when it exists,
    /// otherwise a local stub for a just-logged visit whose history row hasn't
    /// landed yet (the save PATCHes by place_id either way).
    private var loreEntry: VisitLogEntry {
        myEntry ?? VisitLogEntry(
            placeID: place.id,
            visitedAt: "",
            note: nil,
            photos: nil,
            visitID: nil,
            isPublic: nil,
            status: nil,
            place: .init(name: place.name, emoji: place.displayEmoji, city: place.city, kind: place.kind)
        )
    }

    /// The user's own note + photos, rendered as part of the place. Shows only
    /// once they've logged the visit; empty-state copy invites the first note.
    @ViewBuilder
    private var yourLore: some View {
        if visits.hasVisited(place.id) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("YOUR LORE")
                        .loreLabelStyle()
                        .foregroundStyle(LoreColor.brass700)
                    Spacer()
                    Button {
                        Haptics.play(.chipTap)
                        showLoreEditor = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: (myEntry?.note?.isEmpty == false) ? "square.and.pencil" : "plus.circle")
                                .font(.system(size: 13, weight: .semibold))
                            Text((myEntry?.note?.isEmpty == false) ? "Edit" : "Add")
                                .font(LoreType.button)
                        }
                        .foregroundStyle(LoreColor.brass700)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(Text("Write your own lore for \(place.name)"))
                }
                if let note = myEntry?.note, !note.isEmpty {
                    Text(note)
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("You were here. Add what you saw, who you were with, what it meant — it becomes part of this place's story.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let paths = myEntry?.photoPaths, !paths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(paths, id: \.self) { path in
                                JournalPhotoThumb(path: path, size: 84)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(LoreColor.brass700.opacity(0.25), lineWidth: 1)
            )
        }
    }

    // MARK: Layer-1 card

    private var layerOneCard: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroPhoto

                    header

                    if let hook = place.layer1?.hook {
                        Text(hook)
                            .font(LoreType.hook)
                            .foregroundStyle(LoreColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    factChips

                    storyTeaser

                    // Log-the-visit + the reader's own lore, together: the
                    // toggle records "I was here", and once logged the note +
                    // photos render as part of the place itself.
                    HStack {
                        Spacer(minLength: 0)
                        VisitToggle(place: place, source: .map, onNeedsSignIn: { showSignIn = true })
                        Spacer(minLength: 0)
                    }

                    yourLore

                    // Other travelers' opt-in shared lore (moderated view;
                    // report/block per row). Self-hides when nobody has shared.
                    TravelerLoreSection(placeID: place.id, onNeedsSignIn: { showSignIn = true })

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

    // MARK: Story teaser

    /// A few lines of the dive narrative, filling the card with real content for
    /// free users; the Go deeper button opens the full dossier. Self-hides when
    /// there is no dive.
    @ViewBuilder
    private var storyTeaser: some View {
        if let narrative = dive?.narrative, !narrative.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("THE STORY")
                    .loreLabelStyle()
                    .foregroundStyle(LoreColor.brass700)
                Text(narrative)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(LoreColor.bone200, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: Hero photo

    /// The place's lead image at the top of the card. Shows a shimmer while it
    /// resolves, cross-fades to the photo, and collapses cleanly if the place
    /// has no image. Kept to the light-card surface (no dark "Gallery" heading).
    @ViewBuilder
    private var heroPhoto: some View {
        if !heroResolved || heroURL != nil {
            BlurUpAsyncImage(url: heroURL)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                // Slow ambient drift on the hero (Reduce-Motion static). A
                // fully-built effect that rendered nowhere; gives the arrival
                // card the premium "the photo is alive" feel.
                .kenBurns()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .loreElevation(.elev1)
                .accessibilityLabel(Text("Photo of \(place.name)"))
                .task(id: place.id) { await resolveHero() }
        }
    }

    /// Fetch the place's dive to read its curated `wikipedia_title`, then resolve
    /// that to a photo URL. A miss (no dive, no title, or no image) leaves
    /// `heroURL` nil and marks the hero resolved so it hides.
    private func resolveHero() async {
        heroResolved = false
        let loaded = (try? await LoreAPI.shared.dive(placeID: place.id)) ?? nil
        dive = loaded
        if let title = loaded?.media.wikipediaTitle, !title.isEmpty {
            heroURL = await WikipediaService.shared.portraitURL(for: title)
        }
        heroResolved = true
    }

    // MARK: Dossier (morph target)

    private var dossier: some View {
        ZStack(alignment: .top) {
            // Skip the shared-element morph when auto-opening (screenshot
            // pipeline): the Layer-1 card never lays out, so its medallion has no
            // geometry to hand off and the dossier's `matchedGeometryEffect`
            // receiver would float over the narrative. Nil namespace = the
            // medallion just appears in its correct header slot.
            DiveView(place: place)

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
