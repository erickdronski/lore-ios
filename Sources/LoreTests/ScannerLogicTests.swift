import XCTest
import CoreLocation
@testable import Lore

/// Unit tests for the scanner's pure honesty math, the logic that decides
/// whether a pin would be a lie. These lock in the audit-fixed defects: the
/// footprint width (was doubled), the Tier A/B/A hysteresis recovery (a
/// confirmed lock used to flicker), and the NaN gaze guard. All the logic under
/// test is framework-light value code, so it runs without the AR stack.
final class ScannerLogicTests: XCTestCase {

    // MARK: - BearingProjector

    func testBearingDueNorthAndEast() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let north = CLLocationCoordinate2D(latitude: 1, longitude: 0)
        let east = CLLocationCoordinate2D(latitude: 0, longitude: 1)
        XCTAssertEqual(BearingProjector.bearing(from: origin, to: north), 0, accuracy: 0.5)
        XCTAssertEqual(BearingProjector.bearing(from: origin, to: east), 90, accuracy: 0.5)
    }

    func testAngleDeltaWrapsToShortestSignedArc() {
        XCTAssertEqual(BearingProjector.angleDelta(10, 350), 20, accuracy: 0.001)
        XCTAssertEqual(BearingProjector.angleDelta(350, 10), -20, accuracy: 0.001)
        XCTAssertEqual(BearingProjector.angleDelta(0, 180), 180, accuracy: 0.001)
    }

    func testScreenFractionCentersAtHalf() {
        XCTAssertEqual(BearingProjector.screenFraction(delta: 0, fovDegrees: 60), 0.5, accuracy: 0.001)
        XCTAssertEqual(BearingProjector.screenFraction(delta: 30, fovDegrees: 60), 1.0, accuracy: 0.001)
        XCTAssertEqual(BearingProjector.screenFraction(delta: -30, fovDegrees: 60), 0.0, accuracy: 0.001)
    }

    func testDistanceLabel() {
        XCTAssertEqual(BearingProjector.distanceLabel(meters: 604), "600 m")
        XCTAssertEqual(BearingProjector.distanceLabel(meters: 1200), "1.2 km")
    }

    // MARK: - ScannerRanking scoring

    func testGazeScoreCenterEdgeAndNaNGuard() {
        XCTAssertEqual(ScannerRanking.gazeScore(screenFraction: 0.5), 1, accuracy: 0.001)
        XCTAssertEqual(ScannerRanking.gazeScore(screenFraction: 0.0), 0, accuracy: 0.001)
        // Audit fix: a degenerate/behind-camera projection scores 0, never NaN
        // (NaN used to poison the ranking sort).
        XCTAssertEqual(ScannerRanking.gazeScore(screenFraction: .nan), 0, accuracy: 0.001)
    }

    func testProximityFalloff() {
        XCTAssertEqual(ScannerRanking.proximityScore(distance: 0), 1, accuracy: 0.001)
        XCTAssertEqual(ScannerRanking.proximityScore(distance: 300), 0.3679, accuracy: 0.01)
    }

    // MARK: - Footprint width (the honesty-math fix)

    func testFootprintWidthIsFullWidthNotDoubled() {
        // Statues and murals are points: a ~4 m width means they can never earn
        // a coarse-mode lock (Tier A needs sigma < half of this).
        XCTAssertEqual(ScannerRanking.footprintWidth(for: place(kind: "statue")), 4, accuracy: 0.001)
        XCTAssertEqual(ScannerRanking.footprintWidth(for: place(kind: "mural")), 4, accuracy: 0.001)
        // Willis-class (~442 m tall) reads ~62 m WIDE, not ~124 m: the old code
        // doubled this, tolerating 2x the lateral error before locking.
        XCTAssertEqual(ScannerRanking.footprintWidth(for: place(kind: "building", height: 442)), 61.88, accuracy: 0.5)
        // A building with no known height clamps to the 12 m floor.
        XCTAssertEqual(ScannerRanking.footprintWidth(for: place(kind: "building", height: nil)), 12, accuracy: 0.001)
    }

    // MARK: - Tier hysteresis (the A/B/A recovery fix)

    func testTierAConfirmsThenSurvivesBFlicker() {
        let s = ScannerRanking.TierStabilizer(confirmMs: 400, holdMs: 650)
        // A raw Tier A shows as a bearing chip until it has persisted.
        XCTAssertEqual(s.stabilize(id: "x", raw: .a, now: 0), .b)
        XCTAssertEqual(s.stabilize(id: "x", raw: .a, now: 200), .b)
        // Confirmed after the 400 ms window: a real lock.
        XCTAssertEqual(s.stabilize(id: "x", raw: .a, now: 450), .a)
        // One jitter frame of raw B inside the hold window keeps the lock.
        XCTAssertEqual(s.stabilize(id: "x", raw: .b, now: 500), .a)
        // THE FIX: when raw recovers to A it stays locked, instead of dropping
        // to a fresh 400 ms re-confirm (the A->B->A flicker the hold exists to kill).
        XCTAssertEqual(s.stabilize(id: "x", raw: .a, now: 550), .a)
    }

    func testTierADemotesAfterSustainedLoss() {
        let s = ScannerRanking.TierStabilizer(confirmMs: 400, holdMs: 650)
        _ = s.stabilize(id: "y", raw: .a, now: 0)
        XCTAssertEqual(s.stabilize(id: "y", raw: .a, now: 500), .a)
        // Raw B past the hold window demotes honestly (stickiness never wins).
        XCTAssertEqual(s.stabilize(id: "y", raw: .b, now: 1300), .b)
    }

    // MARK: - Narration honesty

    @MainActor
    func testHookTextBuildsFromFactsWithoutInvention() {
        // No authored hook: an honest orienting line from the place's own name,
        // never fabricated history.
        let line = NarrationService.hookText(for: place(kind: "building"),
                                             register: "You're standing in front of")
        XCTAssertEqual(line, "You're standing in front of Test.")
    }

    // MARK: - Helpers

    private func place(kind: String, height: Double? = nil) -> Place {
        Place(id: "t", slug: "t", name: "Test", kind: kind, lat: 0, lng: 0,
              heightM: height, city: "test", layer1: nil, tags: [], emoji: nil)
    }
}
