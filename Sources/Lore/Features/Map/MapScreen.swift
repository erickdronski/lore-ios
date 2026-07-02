import MapKit
import SwiftUI

/// The 2D living map — degraded-modes rung 3 surface (docs/05 §5) and the
/// App-Review-reviewable surface from anywhere on Earth (docs/10 §5 row 4).
/// MapKit at P0; the locked production stack is MapLibre GL Native +
/// OpenFreeMap PMTiles (docs/03 §2 `MapKitFallback`) — swap when tiles land.
struct MapScreen: View {
    @State private var model = MapScreenModel()
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 41.8825, longitude: -87.6285),
            span: MKCoordinateSpan(latitudeDelta: 0.045, longitudeDelta: 0.045)
        )
    )
    @State private var selectedPlaceID: String?

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selectedPlaceID) {
                ForEach(model.places) { place in
                    Annotation(place.name, coordinate: place.coordinate) {
                        PlacePinBadge(place: place)
                    }
                    .tag(place.id)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .overlay(alignment: .top) {
                if let status = model.statusLine {
                    StatusChip(text: status)
                        .padding(.top, 8)
                }
            }
            .sheet(item: selectedPlaceBinding) { place in
                PlaceCardView(place: place)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.regularMaterial)
                    .presentationCornerRadius(24)
            }
            .navigationTitle("Lore")
            .toolbarBackground(.hidden, for: .navigationBar)
            .task { await model.load() }
        }
    }

    /// Bridges Map's tag selection to a `.sheet(item:)` presentation.
    private var selectedPlaceBinding: Binding<Place?> {
        Binding(
            get: { model.places.first { $0.id == selectedPlaceID } },
            set: { newValue in selectedPlaceID = newValue?.id }
        )
    }
}

@Observable
@MainActor
final class MapScreenModel {
    var places: [Place] = []
    var errorMessage: String?
    private var loaded = false

    var statusLine: String? {
        if let errorMessage { return errorMessage }
        if !loaded { return "Loading the city…" }
        if places.isEmpty { return "No places published here yet" }
        return nil
    }

    func load() async {
        guard !loaded else { return }
        do {
            places = try await LoreAPI.shared.places()
            loaded = true
        } catch {
            errorMessage = "Offline — pull to retry"
        }
    }
}

/// The map pin: compound render per brand/DESIGN.md §4 — Amber fill, 1.5 pt
/// Ink stroke, Ink shadow (y1 / blur 3 / 35%) — with the place emoji badged
/// in the middle.
struct PlacePinBadge: View {
    let place: Place
    @State private var bloomed = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LoreColor.amber)
                .strokeBorder(LoreColor.ink, lineWidth: 1.5)
                .shadow(
                    color: LoreColor.ink.opacity(0.35),
                    radius: 3,
                    x: 0,
                    y: 1
                )
            Text(place.displayEmoji)
                .font(.system(size: 15))
        }
        .frame(width: 32, height: 32)
        .scaleEffect(bloomed ? 1.0 : 0.6)
        .opacity(bloomed ? 1.0 : 0.0)
        .onAppear {
            withAnimation(LoreMotion.bloom) { bloomed = true }
        }
        .accessibilityLabel(Text(place.name))
    }
}

/// Passive top strip — the only top-of-screen element (brand/DESIGN.md §7).
struct StatusChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LoreType.caption)
            .foregroundStyle(LoreColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }
}
