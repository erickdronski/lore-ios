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
                    LoreShareCard(place: place, format: format)
                        .frame(width: target.width, height: target.height)
                        .scaleEffect(scale)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .shadow(color: LoreColor.ink.opacity(0.35), radius: 24, x: 0, y: 12)
                }
                .frame(maxHeight: .infinity)

                shareButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
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
            present()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Share this place")
                    .font(LoreType.button)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(LoreColor.ink, in: Capsule())
            .foregroundStyle(LoreColor.bone)
        }
        .buttonStyle(.pressable)
    }

    private var activityBinding: Binding<Bool> {
        Binding(get: { activityItems != nil }, set: { if !$0 { activityItems = nil } })
    }

    /// Render the card and hand [image, caption, link] to the system share sheet.
    @MainActor
    private func present() {
        guard let image = ShareCardRenderer.loreCard(place, format: format) else { return }
        activityItems = [image, ShareCaption.text(for: place), ShareCaption.url(for: place)]
    }
}

/// Caption + deep link that ride along with the shared image. The link uses the
/// getlore.app/p/{slug} universal-link shape (roadmap P1); it resolves to the
/// place in-app once Associated Domains + the web route land, and is a working
/// web link meanwhile. No em/en dashes anywhere (project rule).
enum ShareCaption {
    static func text(for place: Place) -> String {
        let city = place.city.replacingOccurrences(of: "-", with: " ").capitalized
        var lines = ["\(place.name) · \(city)"]
        if let hook = place.layer1?.hook, !hook.isEmpty { lines.append(hook) }
        lines.append("Every place has a story. Discovered with Lore.")
        return lines.joined(separator: "\n\n")
    }

    static func url(for place: Place) -> URL {
        URL(string: "https://getlore.app/p/\(place.slug)")
            ?? URL(string: "https://getlore.app")!
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
