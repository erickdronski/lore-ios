import SwiftUI
import UIKit

/// A frozen scanner frame plus the place it was locked on, ready to become a
/// shareable AR postcard. Identifiable so it drives a `.sheet(item:)`.
struct CapturedShot: Identifiable {
    let id = UUID()
    let image: UIImage
    let place: Place?
    let city: String
}

/// The AR postcard composer (strategy synth, Phase 2 "magic capture"): the real
/// camera frame + the Lore lower-third, the un-fakeable hero image an audio or
/// text competitor structurally cannot produce. Shows the composited postcard
/// and shares it as a 1080x1920 image + caption to IG/TikTok/X/Save.
struct ARCaptureSheet: View {
    let shot: CapturedShot

    @Environment(\.dismiss) private var dismiss
    @State private var activityItems: [Any]?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                GeometryReader { geo in
                    let target = ARPostcard.size
                    let scale = min(geo.size.width / target.width, geo.size.height / target.height)
                    ARPostcard(shot: shot)
                        .frame(width: target.width, height: target.height)
                        .scaleEffect(scale)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .shadow(color: LoreColor.ink.opacity(0.4), radius: 24, x: 0, y: 12)
                }
                .frame(maxHeight: .infinity)

                shareButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
            .padding(.top, 14)
            .background(LoreColor.ink950)
            .navigationTitle("Your capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(LoreColor.bone)
                }
            }
            .toolbarBackground(LoreColor.ink950, for: .navigationBar)
            .sheet(isPresented: activityBinding) {
                if let activityItems {
                    ActivityView(items: activityItems).presentationDetents([.medium, .large])
                }
            }
        }
    }

    private var shareButton: some View {
        Button {
            Haptics.play(.badgeEarned)
            present()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Share your capture").font(LoreType.button)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(LoreColor.amber, in: Capsule())
            .foregroundStyle(LoreColor.ink)
        }
        .buttonStyle(.pressable)
    }

    private var activityBinding: Binding<Bool> {
        Binding(get: { activityItems != nil }, set: { if !$0 { activityItems = nil } })
    }

    @MainActor
    private func present() {
        guard let image = ShareCardRenderer.image(ARPostcard(shot: shot), size: ARPostcard.size) else { return }
        var items: [Any] = [image]
        let city = shot.city.replacingOccurrences(of: "-", with: " ").capitalized
        if let place = shot.place {
            items.append("\(place.name) · \(city)\n\nSeen through Lore. Every place has a story.")
            items.append(ShareCaption.url(for: place))
        } else {
            items.append("\(city) through Lore. Every place has a story.")
            items.append(Config.webURL)
        }
        activityItems = items
    }
}

/// The composited postcard surface: the frozen camera frame filling a 9:16
/// canvas, a bottom Ink gradient so the type stays legible over any scene, and
/// the Lore lower-third carrying the fixed Amber "LORE." beacon.
struct ARPostcard: View {
    let shot: CapturedShot

    static let size = CGSize(width: 360, height: 640)

    private var cityLabel: String {
        shot.city.replacingOccurrences(of: "-", with: " ").capitalized
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: shot.image)
                .resizable()
                .scaledToFill()
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()

            LinearGradient(
                colors: [.clear, .clear, LoreColor.ink950.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )

            lowerThird
                .padding(22)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    private var lowerThird: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LORE.")
                    .font(.system(size: 15, weight: .heavy)).tracking(2)
                    .foregroundStyle(LoreColor.amber)
                if let place = shot.place {
                    Text(place.name)
                        .font(LoreType.display(size: 30, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text("Seen in \(cityLabel)")
                        .font(.system(size: 12, weight: .semibold)).tracking(1)
                        .foregroundStyle(LoreColor.bone.opacity(0.7))
                } else {
                    Text(cityLabel)
                        .font(LoreType.display(size: 30, weight: .semibold))
                        .foregroundStyle(LoreColor.bone)
                    Text("Every place has a story")
                        .font(LoreType.display(size: 13, weight: .medium).italic())
                        .foregroundStyle(LoreColor.bone.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            if let place = shot.place {
                Text(place.displayEmoji)
                    .font(.system(size: 30))
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(LoreColor.ink.opacity(0.55)))
                    .overlay(Circle().strokeBorder(LoreColor.amber.opacity(0.6), lineWidth: 1.5))
            }
        }
    }
}
