import CoreLocation
import SwiftUI

/// The scanner viewfinder — **GPS + compass coarse mode**, rung 2 of the
/// degraded-modes ladder (docs/05 §5), matching the web scanner's behavior:
/// live camera preview with bearing-projected overlay chips.
///
/// The honesty contract from docs/05 §4 applies verbatim: at ±10–30 m /
/// ±10–25° we never make an on-building claim. Chips are *directional
/// labels* — name + arrow + distance — positioned by bearing within the
/// camera's FOV, with off-screen candidates pinned to the edges. Full VPS
/// (ARCore Geospatial + Streetscape Geometry, exact pins, occlusion, stack
/// UI) replaces this at P1; see `GeoScoutingService` for the hook.
struct ScannerScreen: View {
    @State private var model = ScannerModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CameraPreviewView(session: model.camera.session)
                    .ignoresSafeArea()

                overlayChips(width: proxy.size.width)

                VStack {
                    StatusChip(text: model.statusLine)
                        .padding(.top, 8)
                    Spacer()
                    nearbyRail
                }
            }
        }
        .background(LoreColor.ink950)
        .sheet(item: $model.selectedPlace) { place in
            PlaceCardView(place: place)
                .presentationDetents([.medium, .large])
                .presentationBackground(.regularMaterial)
                .presentationCornerRadius(24)
        }
        .task { await model.start() }
        .onDisappear { model.stopSensors() }
    }

    // MARK: In-view chips

    /// Chips for places inside the camera FOV, horizontally positioned by
    /// bearing delta. Capped at 6 — clutter control per brand rules
    /// (≤ 35% viewfinder coverage).
    @ViewBuilder
    private func overlayChips(width: CGFloat) -> some View {
        let inView = Array(model.projected.filter(\.isInView).prefix(6))
        ForEach(Array(inView.enumerated()), id: \.element.id) { index, projected in
            PlaceChip(projected: projected, showArrow: false)
                .position(
                    x: chipX(fraction: projected.screenFraction, width: width),
                    y: 140 + CGFloat(index) * 54
                )
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .onTapGesture {
                    model.selectedPlace = projected.place
                }
        }
    }

    private func chipX(fraction: Double, width: CGFloat) -> CGFloat {
        let clamped = min(max(fraction, 0.08), 0.92)
        return CGFloat(clamped) * width
    }

    // MARK: Edge rail

    /// Bottom rail of off-screen candidates, sorted by distance — the
    /// "Willis Tower ↖ 600 m" chips from docs/05 §5 rung 2.
    private var nearbyRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.projected.filter { !$0.isInView }.prefix(10))) { projected in
                    PlaceChip(projected: projected, showArrow: true)
                        .onTapGesture {
                            model.selectedPlace = projected.place
                        }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }
}

// MARK: - Chip

/// A scanner label chip: scrim-backed (never raw text on camera —
/// brand/DESIGN.md §4), emoji + name + arrow/distance caption.
struct PlaceChip: View {
    let projected: ProjectedPlace
    let showArrow: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(projected.place.displayEmoji)
                .font(.system(size: 13))
            Text(projected.place.name)
                .font(LoreType.button)
                .foregroundStyle(LoreColor.bone)
                .lineLimit(1)
            Text(caption)
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.amber)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LoreColor.scrimSky, in: Capsule())
        .overlay(
            Capsule().strokeBorder(LoreColor.amber.opacity(0.55), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "\(projected.place.name), \(projected.distanceLabel) away"
        ))
    }

    private var caption: String {
        showArrow
            ? "\(projected.arrow) \(projected.distanceLabel)"
            : projected.distanceLabel
    }
}

// MARK: - Model

@Observable
@MainActor
final class ScannerModel {
    let camera = ScannerCameraService()
    let pose = LocationHeadingProvider()
    let scouting = GeoScoutingService()

    private(set) var places: [Place] = []
    private(set) var projected: [ProjectedPlace] = []
    var selectedPlace: Place?

    private var loadError = false
    private var scoutedOnce = false
    private var projectionTask: Task<Void, Never>?

    var statusLine: String {
        if loadError { return "Offline — cached places only" }
        return pose.statusLine + scouting.statusSuffix
    }

    func start() async {
        camera.start()
        pose.start()
        startProjectionLoop()
        do {
            places = try await LoreAPI.shared.places()
        } catch {
            loadError = true
        }
    }

    func stopSensors() {
        camera.stop()
        pose.stop()
        projectionTask?.cancel()
        projectionTask = nil
    }

    /// Re-projects at ~5 Hz — well under the 10–15 Hz AR budget, plenty for
    /// compass-grade heading, cheap on battery (docs/05 §7).
    private func startProjectionLoop() {
        projectionTask?.cancel()
        projectionTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.reproject()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func reproject() {
        guard
            let location = pose.location,
            pose.headingDegrees >= 0
        else {
            projected = []
            return
        }

        if !scoutedOnce {
            scoutedOnce = true
            scouting.scout(coordinate: location.coordinate)
        }

        projected = BearingProjector.project(
            places: places,
            from: location,
            heading: pose.headingDegrees,
            fovDegrees: camera.horizontalFOVDegrees
        )
    }
}
