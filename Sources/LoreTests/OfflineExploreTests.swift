import CoreLocation
import XCTest
@testable import Lore

final class OfflineExploreTests: XCTestCase {
    private func place(_ id: String, _ latitude: Double, _ longitude: Double) -> Place {
        Place(id: id, slug: id, name: id, kind: "building", lat: latitude, lng: longitude, city: "test")
    }

    func testLocalCandidatesIncludeBothSidesOfDatelineAndRespectActualRadius() {
        let fix = CLLocation(latitude: 0, longitude: 179.999)
        let places = [place("across", 0, -179.999), place("corner", 0.018, -179.983),
                      place("far", 0, 179), place("here", 0, 179.999)]
        let candidates = FieldGuideRegion.localCandidates(in: places, from: fix)
        XCTAssertEqual(Set(candidates.map(\.id)), ["across", "corner", "here"])
        let matches = BearingProjector.project(places: candidates, from: fix, heading: 90, fovDegrees: 50,
                                              maxDistance: FieldGuideRegion.radius)
        XCTAssertEqual(matches.map(\.id), ["here", "across"])
        XCTAssertEqual(matches[1].distance, 223, accuracy: 3)
    }

    func testLocalCandidatesIncludePolarNeighborsAcrossLongitudes() {
        let fix = CLLocation(latitude: 89.997, longitude: 0)
        let target = place("polar", 89.997, 180)
        XCTAssertLessThan(fix.distance(from: target.location), FieldGuideRegion.radius)
        XCTAssertEqual(FieldGuideRegion.localCandidates(in: [target], from: fix).map(\.id), ["polar"])
    }

    func testAheadRejectsUncertainHeadingsPitchAndLandmarksInsideGPSAccuracy() {
        let fix = CLLocation(latitude: 0, longitude: 0)
        let places = [place("here", 0, 0), place("too-close", 0.0001, 0), place("north", 0.002, 0),
                      place("east", 0, 0.001), place("south", -0.001, 0)]
        let matches = BearingProjector.project(places: places, from: fix, heading: 0, fovDegrees: 50)
        let heading = ScannerHeadingSample(degrees: 0, accuracy: 4, timestamp: Date())
        XCTAssertEqual(FieldGuideRegion.ahead(in: matches, heading: heading, pitch: 0, horizontalAccuracy: 20)?.id, "north")
        XCTAssertNil(FieldGuideRegion.ahead(in: matches, heading: nil, pitch: 0, horizontalAccuracy: 20))
        XCTAssertNil(FieldGuideRegion.ahead(in: matches, heading: heading, pitch: -65, horizontalAccuracy: 20))
        XCTAssertNil(FieldGuideRegion.ahead(in: matches, heading: heading, pitch: 0, horizontalAccuracy: 250))
        for accuracy in [-1.0, 30, .nan] {
            let imprecise = ScannerHeadingSample(degrees: 0, accuracy: accuracy, timestamp: Date())
            XCTAssertNil(FieldGuideRegion.usableHeading(imprecise))
        }
    }
}
