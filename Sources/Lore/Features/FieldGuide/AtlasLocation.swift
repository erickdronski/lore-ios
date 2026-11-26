import CoreLocation
import MapKit
import Observation

/// Only the in-memory map session holds this location. Authorization is
/// requested in response to the map's location button.
@Observable
final class AtlasLocation: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var active = false
    private(set) var status: CLAuthorizationStatus = .notDetermined
    private(set) var fix: CLLocation?
    private(set) var reduced = false
    private(set) var failed = false

    var denied: Bool { status == .denied || status == .restricted }
    var authorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    override init() {
        super.init()
        status = manager.authorizationStatus
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        manager.delegate = self
    }

    func start(request: Bool = false) {
        active = true
        failed = false
        status = manager.authorizationStatus
        reduced = manager.accuracyAuthorization == .reducedAccuracy
        if authorized {
            manager.startUpdatingLocation()
        } else if request && status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func stop() {
        active = false
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        reduced = manager.accuracyAuthorization == .reducedAccuracy
        if !authorized { fix = nil }
        if authorized && active { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard active, let latest = locations.last, latest.horizontalAccuracy >= 0,
              (-1...90).contains(-latest.timestamp.timeIntervalSinceNow) else { return }
        failed = false
        fix = latest
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if active { failed = true }
    }
}

struct AtlasMapPlace: Identifiable {
    let id = UUID()
    let item: MKMapItem
    var coordinate: CLLocationCoordinate2D { item.placemark.coordinate }
    var title: String { item.name ?? "Place in Apple Maps" }
}

@MainActor @Observable
final class AtlasAppleSearch {
    enum Status { case idle, loading, ready, empty, unavailable }
    private(set) var status: Status = .idle
    private(set) var places: [AtlasMapPlace] = []
    @ObservationIgnored private var pending: MKLocalSearch?
    @ObservationIgnored private var generation = UUID()

    func reset() {
        generation = UUID()
        pending?.cancel()
        pending = nil
        places = []
        status = .idle
    }

    func find(near coordinate: CLLocationCoordinate2D) async {
        reset()
        let token = generation
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: FieldGuideRegion.radius)
        let search = MKLocalSearch(request: request)
        pending = search
        status = .loading
        do {
            let response = try await search.start()
            guard generation == token else { return }
            places = response.mapItems.map { AtlasMapPlace(item: $0) }
            status = places.isEmpty ? .empty : .ready
        } catch {
            guard generation == token else { return }
            status = (error as? MKError)?.code == .placemarkNotFound ? .empty : .unavailable
        }
        pending = nil
    }
}
