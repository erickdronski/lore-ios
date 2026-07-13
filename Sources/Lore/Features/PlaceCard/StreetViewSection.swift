import CoreLocation
import SwiftUI

/// "See it in Street View" — a real across-the-street Google Street View of the
/// place, fetched through the `streetview` Supabase Edge Function.
///
/// The Google Maps key stays server-side (Supabase Vault); the app only ever
/// talks to our proxy, which pulls the nearest OUTDOOR pano ~100m back and aims
/// the camera at the building (the "facade" trick, DESIGN/verification notes).
/// Honest by construction: where Google has no outdoor view the proxy returns
/// 204 and this section simply doesn't appear, never a placeholder or a
/// fabricated image. Google's attribution is baked into the returned frame.
struct StreetViewSection: View {
    let coordinate: CLLocationCoordinate2D

    @Environment(\.openURL) private var openURL
    @State private var image: UIImage?
    @State private var phase: Phase = .loading

    private enum Phase { case loading, loaded, hidden }

    /// Opens the full interactive Google Street View at this spot so the reader
    /// can look around themselves (and reach it even when our static preview
    /// framing isn't perfect for a tall facade).
    private var streetViewURL: URL? {
        URL(string: "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=\(coordinate.latitude),\(coordinate.longitude)")
    }

    var body: some View {
        content
            .task(id: "\(coordinate.latitude),\(coordinate.longitude)") { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .hidden:
            EmptyView()
        case .loading:
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("dossier.streetView")).font(LoreType.displayM).foregroundStyle(LoreColor.bone)
                RoundedRectangle(cornerRadius: 16)
                    .fill(LoreColor.ink800)
                    .frame(height: 220)
                    .overlay(ProgressView().tint(LoreColor.brass))
            }
        case .loaded:
            if let image {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t("dossier.streetView")).font(LoreType.displayM).foregroundStyle(LoreColor.bone)
                    Button {
                        if let url = streetViewURL { openURL(url) }
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(alignment: .bottomTrailing) {
                                // A clear "this opens Street View" affordance.
                                HStack(spacing: 5) {
                                    Image(systemName: "figure.walk")
                                    Text("Explore")
                                        .font(LoreType.button)
                                }
                                .foregroundStyle(LoreColor.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(12)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(LoreColor.brass.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Open in Street View")
                    Text("Tap to look around in Street View.")
                        .font(LoreType.caption)
                        .foregroundStyle(LoreColor.ink600)
                }
            }
        }
    }

    private func load() async {
        phase = .loading
        var comps = URLComponents(
            url: Config.functionsURL.appending(path: "streetview"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lng", value: String(coordinate.longitude)),
        ]
        guard let url = comps?.url else { phase = .hidden; return }

        var request = URLRequest(url: url)
        // Harmless if the proxy is public; keeps parity with the rest of the API.
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200,
                let ui = UIImage(data: data)
            else {
                phase = .hidden          // 204 / error: no honest view, so nothing shows
                return
            }
            image = ui
            phase = .loaded
        } catch {
            phase = .hidden
        }
    }
}
