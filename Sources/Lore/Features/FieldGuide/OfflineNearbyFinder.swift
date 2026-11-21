import AVFoundation
import CoreLocation
import SwiftUI

/// Uses the existing scanner pose and local camera preview. User position and
/// camera frames never enter the catalog or any remote identification endpoint.
struct OfflineNearbyFinder: View {
    let places: [Place]
    let onOpen: (Place) -> Void
    let browseMap: () -> Void

    @State private var pose: LocationHeadingProvider?
    @State private var camera: ScannerCameraService?
    @State private var cameraIssue: String?
    @State private var isVisible = false
    @State private var requestedLocation = false
    @State private var requestedCamera = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let pose {
                    ScannerHeadingOrientationReader { pose.updateHeadingOrientation($0) }
                        .frame(width: 0, height: 0).accessibilityHidden(true)
                    TimelineView(.periodic(from: .now, by: 2)) { time in
                        localResults(pose, now: time.date)
                    }
                } else {
                    Label("Look around you", systemImage: "location.north.circle")
                        .font(LoreType.display(size: 29))
                    Text("Use your location to find landmarks within 2.5 km. Turn toward one to see what lies ahead.")
                    Button {
                        requestedLocation = true
                        startLocation()
                    } label: {
                        Text("Use my location").foregroundStyle(.white)
                    }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("atlas.finder.enable")
                    Button("Browse the city map", action: browseMap)
                }
            }
            .frame(maxWidth: 680, alignment: .leading).padding().frame(maxWidth: .infinity)
        }
        .onAppear {
            isVisible = true
            if requestedLocation { startLocation() }
        }
        .onDisappear { isVisible = false; stopSensors() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { stopSensors() }
            if phase == .active && isVisible && requestedLocation { startLocation() }
        }
    }

    @ViewBuilder
    private func localResults(_ pose: LocationHeadingProvider, now: Date) -> some View {
        if pose.authorizationStatus == .denied || pose.authorizationStatus == .restricted {
            unavailable("Location access is off", message: "Allow location in Settings to find nearby landmarks.")
        } else if pose.isAuthorized && !pose.hasPreciseLocation {
            unavailable("Precise location is off", message: "Landmark bearings need a precise location.")
        } else if let fix = pose.freshLocation(now: now) {
            let heading = pose.freshHeading(now: now)
            let matches = BearingProjector.project(places: FieldGuideRegion.localCandidates(in: places, from: fix),
                                                   from: fix, heading: heading?.degrees ?? 0,
                                                   fovDegrees: 50, maxDistance: FieldGuideRegion.radius)
            if matches.isEmpty {
                unavailable("No bundled landmarks nearby",
                            message: "There are no places in the guide within 2.5 km of your current location.",
                            settings: false)
            } else {
                let usableHeading = FieldGuideRegion.usableHeading(heading)
                let ahead = FieldGuideRegion.ahead(in: matches, heading: usableHeading,
                                                   pitch: pose.cameraPitchDeg, horizontalAccuracy: fix.horizontalAccuracy)
                viewfinder(ahead: ahead, heading: usableHeading, pitch: pose.cameraPitchDeg)
                Text("Nearby landmarks").font(.headline)
                ForEach(matches.prefix(12)) { match in
                    Button { onOpen(match.place) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin").foregroundStyle(LoreColor.brass700)
                            VStack(alignment: .leading) {
                                Text(match.place.name).font(.system(.headline, design: .serif))
                                Text(match.distanceLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        } else {
            Text("Finding your location").font(.headline)
            Text("Move outdoors for a more accurate fix. You can also explore any included city.")
            Button("Browse the city map", action: browseMap)
        }
    }

    private func viewfinder(ahead: ProjectedPlace?, heading: ScannerHeadingSample?, pitch: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                LoreColor.ink900
                if let camera { CameraPreviewView(camera: camera); ScannerReticle(isLocked: false) }
                if camera == nil {
                    CompassRing(headingDegrees: heading?.degrees ?? -1)
                }
            }
            .frame(maxWidth: .infinity).frame(height: camera == nil ? 110 : 210)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            if let ahead {
                Button { onOpen(ahead.place) } label: {
                    Label("Ahead · \(ahead.place.name)", systemImage: "location.north.fill")
                        .font(.headline)
                }
                Text("Approximate bearing · \(ahead.distanceLabel)").font(.caption)
            } else if heading == nil {
                Text("Compass direction unavailable. The closest landmarks are listed below.")
            } else if let pitch, abs(pitch) > 55 {
                Text("Hold your phone upright to find places ahead.")
            } else {
                Text("Turn slowly to find a landmark ahead.")
            }
            if let cameraIssue {
                Text(cameraIssue).font(.footnote).foregroundStyle(.secondary)
            }
            Button(camera == nil ? "Show camera view" : "Hide camera view") {
                if camera == nil { requestedCamera = true; startCamera() }
                else { stopCamera(); requestedCamera = false }
            }.buttonStyle(.bordered)
                .accessibilityHint("Overlays direction hints on a live camera preview. Images stay on this device.")
        }
        .onDisappear { stopCamera(); requestedCamera = false }
    }

    private func unavailable(_ title: String, message: String, settings: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(LoreType.display(size: 25))
            Text(message)
            if settings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
            }
            Button("Browse the city map", action: browseMap).buttonStyle(.bordered)
        }.onAppear { stopCamera(); requestedCamera = false }
    }

    private func startLocation() {
        guard isVisible, scenePhase == .active else { return }
        if pose == nil {
            let provider = LocationHeadingProvider()
            pose = provider
            provider.start()
        }
    }

    private func startCamera() {
        guard isVisible, scenePhase == .active, requestedCamera else { return }
        let service = ScannerCameraService()
        service.onPermissionDenied = { [weak service] in
            guard let service, camera === service else { return }
            stopCamera()
            requestedCamera = false
            cameraIssue = "Camera access is off. The compass and nearby list still work."
        }
        service.onUnavailable = { [weak service] message in
            guard let service, camera === service else { return }
            stopCamera()
            requestedCamera = false
            cameraIssue = message
        }
        cameraIssue = nil
        camera = service
        service.start(requestPermissionIfNeeded: true)
    }

    private func stopCamera() {
        camera?.onPermissionDenied = nil
        camera?.onUnavailable = nil
        camera?.stop()
        camera = nil
    }

    private func stopSensors() {
        stopCamera()
        requestedCamera = false
        pose?.stop()
        pose = nil
    }
}

/// Excludes distant cities before invoking Core Location's geodesic distance
/// calculation. The final radius check is always BearingProjector's actual distance.
enum FieldGuideRegion {
    static let radius: CLLocationDistance = 2_500
    static func localCandidates(in places: [Place], from location: CLLocation) -> [Place] {
        let latitude = location.coordinate.latitude
        // A degree of latitude is at least 110 km. Use the most poleward edge
        // of the window for longitude, including locations across ±180°.
        let dLat = radius / 110_000
        let edge = min(90, abs(latitude) + dLat)
        let dLon = min(180, dLat / max(0.000001, cos(edge * .pi / 180)))
        return places.filter {
            abs($0.lat - latitude) <= dLat &&
                abs(BearingProjector.angleDelta($0.lng, location.coordinate.longitude)) <= dLon
        }
    }

    static func usableHeading(_ heading: ScannerHeadingSample?) -> ScannerHeadingSample? {
        guard let heading, (0...25).contains(heading.accuracy) else { return nil }
        return heading
    }

    static func ahead(in matches: [ProjectedPlace], heading: ScannerHeadingSample?, pitch: Double?, horizontalAccuracy: Double) -> ProjectedPlace? {
        guard usableHeading(heading) != nil, abs(pitch ?? 0) <= 55 else { return nil }
        return matches.filter { $0.isInView && !$0.isAtLocation && $0.distance > horizontalAccuracy }
            .min { abs($0.delta) < abs($1.delta) }
    }
}
