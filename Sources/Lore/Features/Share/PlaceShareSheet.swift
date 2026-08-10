import SwiftUI
import UIKit

/// The share surface for a place (strategy synth: "share cards are the #1 build
/// priority; the app is a content engine"). Shows a live preview of the
/// `LoreShareCard`, a story/post format toggle, and a single Share button that
/// hands the rendered image + caption to the system share sheet (Instagram,
/// TikTok, Messages, X, Save Image, ...). Presented as a `.sheet` from any
/// place surface (PlaceCardView today, DiveView next).
struct PlaceShareSheet: View {
    let place: Place

    @Environment(\.dismiss) private var dismiss
    @State private var format: LoreShareCard.Format = .story
    @State private var activityItems: [Any]?
    @State private var isPreparing = false
    @State private var shareError: String?
    @State private var heroImage: UIImage?
    @State private var heroImageResolved = false
    @State private var heroImageTask: Task<UIImage?, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                formatPicker

                // Live preview of the exact card that will be exported, scaled
                // to fit the sheet width.
                GeometryReader { geo in
                    let target = format.size
                    let scale = min(
                        (geo.size.width) / target.width,
                        (geo.size.height) / target.height
                    )
                    LoreShareCard(place: place, format: format, heroImage: heroImage)
                        .frame(width: target.width, height: target.height)
                        .scaleEffect(scale)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .shadow(color: LoreColor.ink.opacity(0.35), radius: 24, x: 0, y: 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Preview of the \(format.accessibilityName) share card for \(place.name)")
                }
                .frame(maxHeight: .infinity)

                shareButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .background(LoreColor.bone100)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: activityBinding) {
                if let activityItems {
                    ActivityView(items: activityItems)
                        .presentationDetents([.medium, .large])
                }
            }
            .alert("Couldn't prepare this card", isPresented: errorBinding) {
                Button("Try again") { Task { await present() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(shareError ?? "Lore couldn't render the share image.")
            }
            .task(id: place.id) {
                await prepareHeroImageIfNeeded()
            }
        }
    }

    private var formatPicker: some View {
        Picker("Format", selection: $format) {
            Text("Story").tag(LoreShareCard.Format.story)
            Text("Post").tag(LoreShareCard.Format.square)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var shareButton: some View {
        Button {
            Haptics.play(.chipTap)
            Task { await present() }
        } label: {
            HStack(spacing: 8) {
                if isPreparing {
                    ProgressView()
                        .tint(LoreColor.bone)
                    Text("Preparing card")
                } else {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share this place")
                }
            }
            .font(LoreType.button)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(LoreColor.ink, in: Capsule())
            .foregroundStyle(LoreColor.bone)
        }
        .buttonStyle(.pressable)
        .disabled(isPreparing)
    }

    private var activityBinding: Binding<Bool> {
        Binding(get: { activityItems != nil }, set: { if !$0 { activityItems = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )
    }

    /// Render the card and hand [image, caption, link] to the system share sheet.
    @MainActor
    private func present() async {
        guard !isPreparing else { return }
        isPreparing = true
        shareError = nil
        defer { isPreparing = false }

        // Let the preparing state paint before ImageRenderer performs its
        // synchronous main-actor layout work.
        await Task.yield()
        await prepareHeroImageIfNeeded()
        guard let image = ShareCardRenderer.loreCard(place, format: format, heroImage: heroImage) else {
            shareError = "Lore couldn't render this card. Try another format or try again."
            return
        }
        activityItems = [image, ShareCaption.text(for: place), ShareCaption.url(for: place)]
    }

    @MainActor
    private func prepareHeroImageIfNeeded() async {
        if heroImageResolved { return }

        if let existing = heroImageTask {
            let image = await existing.value
            guard !Task.isCancelled else { return }
            heroImage = image
            heroImageResolved = true
            heroImageTask = nil
            return
        }

        let task = Task { await ShareHeroImageLoader.image(for: place) }
        heroImageTask = task
        let image = await task.value
        guard !Task.isCancelled else { return }
        heroImage = image
        heroImageResolved = true
        heroImageTask = nil
    }
}

/// Caption + web link that ride along with the shared image. The route resolves
/// the place on Lore's living map today and can become a universal link later.
/// No em/en dashes anywhere (project rule).
enum ShareCaption {
    static func text(for place: Place) -> String {
        let city = place.city.replacingOccurrences(of: "-", with: " ").capitalized
        var lines = ["\(place.name) · \(city)"]
        if let hook = place.teaser?.trimmingCharacters(in: .whitespacesAndNewlines), !hook.isEmpty {
            lines.append(hook)
        }
        lines.append("Every place has a story. Discovered with Lore.")
        return lines.joined(separator: "\n\n")
    }

    static func url(for place: Place) -> URL {
        Config.placeShareURL(slug: place.slug)
    }
}

/// Thin SwiftUI bridge to `UIActivityViewController` so a place card can share
/// an image + caption + link with one call. Excludes surfaces that make no
/// sense for a poster (assign-to-contact, print).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = [.assignToContact, .print, .addToReadingList]
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

enum ShareHeroImageLoader {
    static func image(for place: Place) async -> UIImage? {
        guard let title = cleanTitle(place.wikipediaTitle),
              let remote = await WikipediaService.shared.portraitURL(for: title) else { return nil }
        let resolved = PackImageStore.localURL(for: remote) ?? remote

        do {
            let data: Data
            if resolved.isFileURL {
                data = try Data(contentsOf: resolved)
            } else {
                let (loaded, response) = try await URLSession.shared.data(from: resolved)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    return nil
                }
                data = loaded
            }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    private static func cleanTitle(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
