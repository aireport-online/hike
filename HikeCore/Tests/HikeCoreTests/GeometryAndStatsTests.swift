import XCTest
@testable import HikeCore

final class GeometryAndStatsTests: XCTestCase {
    private let amsterdam = Coordinate(latitude: 52.3702, longitude: 4.8952)
    private let utrecht = Coordinate(latitude: 52.0907, longitude: 5.1214)

    func testHaversineDistanceMatchesKnownDistance() {
        // Amsterdam Dam to Utrecht Dom is about 34.7 km as the crow flies.
        XCTAssertEqual(amsterdam.distance(to: utrecht), 34_700, accuracy: 300)
        XCTAssertEqual(amsterdam.distance(to: amsterdam), 0)
    }

    func testOneDegreeOfLatitudeIsAbout111Kilometres() {
        let a = Coordinate(latitude: 46, longitude: 8)
        let b = Coordinate(latitude: 47, longitude: 8)
        XCTAssertEqual(a.distance(to: b), 111_195, accuracy: 50)
    }

    func testBoundingBox() throws {
        let box = try XCTUnwrap(BoundingBox([amsterdam, utrecht]))
        XCTAssertEqual(box.minLatitude, 52.0907)
        XCTAssertEqual(box.maxLongitude, 5.1214)
        XCTAssertEqual(box.center.latitude, (52.3702 + 52.0907) / 2, accuracy: 1e-9)
        XCTAssertNil(BoundingBox([]))
    }

    /// Points 100 m apart heading north, with the given elevations.
    private func track(_ elevations: [Double?]) -> [TrackPoint] {
        elevations.enumerated().map { index, elevation in
            TrackPoint(
                coordinate: Coordinate(latitude: 46 + Double(index) * 0.0008993, longitude: 8),
                elevation: elevation
            )
        }
    }

    func testStatsSumDistanceAscentAndDescent() {
        let stats = RouteStats(points: track([1000, 1050, 1100, 1060, 1200]))
        XCTAssertEqual(stats.distance, 400, accuracy: 1)
        XCTAssertEqual(stats.ascent, 240)
        XCTAssertEqual(stats.descent, 40)
        XCTAssertEqual(stats.minElevation, 1000)
        XCTAssertEqual(stats.maxElevation, 1200)
    }

    func testStatsIgnoreElevationNoise() {
        // Wobbles of a few metres on a flat walk must not add up to a climb.
        let stats = RouteStats(points: track([2, 5, 1, 6, 0, 4, 2, 7, 3]))
        XCTAssertEqual(stats.ascent, 0)
        XCTAssertEqual(stats.descent, 0)
    }

    func testStatsCountSlowClimbMadeOfSmallSteps() {
        let stats = RouteStats(points: track((0...50).map { Double($0) * 4 }))
        XCTAssertEqual(stats.ascent, 200, accuracy: 10)
    }

    func testStatsHandleMissingElevations() {
        let stats = RouteStats(points: track([nil, 100, nil, 150, nil]))
        XCTAssertEqual(stats.distance, 400, accuracy: 1)
        XCTAssertEqual(stats.ascent, 50)
        XCTAssertEqual(RouteStats(points: track([nil, nil])).maxElevation, nil)
        XCTAssertEqual(RouteStats(points: []), .empty)
    }

    func testDurationFollowsSignpostRule() {
        // 12 km flat: 3 hours.
        let flat = RouteStats(distance: 12_000, ascent: 0, descent: 0, minElevation: nil, maxElevation: nil)
        XCTAssertEqual(flat.duration(), 3 * 3600, accuracy: 1)
        // 8 km with 900 m up: 2 h horizontal, 3 h vertical -> 3 + 1 = 4 hours.
        let climb = RouteStats(distance: 8_000, ascent: 900, descent: 0, minElevation: nil, maxElevation: nil)
        XCTAssertEqual(climb.duration(), 4 * 3600, accuracy: 1)
        XCTAssertEqual(climb.duration(pace: .relaxed), 5 * 3600, accuracy: 1)
        XCTAssertLessThan(climb.duration(pace: .brisk), climb.duration())
    }

    func testGeometryFindsPositionAlongTrack() throws {
        let geometry = RouteGeometry(points: track([100, 110, 120, 130, 140]))
        XCTAssertEqual(geometry.totalDistance, 400, accuracy: 1)
        let halfway = try XCTUnwrap(geometry.coordinate(atDistance: 150))
        XCTAssertEqual(halfway.latitude, 46 + 1.5 * 0.0008993, accuracy: 1e-5)
        XCTAssertEqual(geometry.coordinate(atDistance: -5), geometry.points.first?.coordinate)
        XCTAssertEqual(geometry.coordinate(atDistance: 9999), geometry.points.last?.coordinate)
        XCTAssertNil(RouteGeometry(points: []).coordinate(atDistance: 10))
    }

    func testElevationProfileIsThinnedAndKeepsEnds() {
        let geometry = RouteGeometry(points: track((0..<1000).map { Double($0) }))
        let profile = geometry.elevationProfile(maxSamples: 100)
        XCTAssertEqual(profile.count, 100)
        XCTAssertEqual(profile.first?.elevation, 0)
        XCTAssertEqual(profile.last?.elevation, 999)
        XCTAssertEqual(profile.map(\.distance), profile.map(\.distance).sorted())
    }

    func testElevationProfileSkipsRepeatedJointPoints() {
        // Two legs share their joint point; the profile must not contain it twice.
        let first = track([100, 110])
        let geometry = RouteGeometry(points: first + [first[1]] + track([100, 110, 120]).suffix(1))
        let distances = geometry.elevationProfile().map(\.distance)
        XCTAssertEqual(Set(distances).count, distances.count)
        XCTAssertFalse(RouteGeometry(points: track([nil, nil])).hasElevation)
    }

    func testFormatting() {
        XCTAssertEqual(HikeFormat.distance(850), "850 m")
        XCTAssertEqual(HikeFormat.distance(12_440), "12,4 km")
        XCTAssertEqual(HikeFormat.distance(123_600), "124 km")
        XCTAssertEqual(HikeFormat.elevation(1249.6), "1250 m")
        XCTAssertEqual(HikeFormat.duration(40 * 60), "40 min")
        XCTAssertEqual(HikeFormat.duration(3 * 3600), "3 u")
        XCTAssertEqual(HikeFormat.duration(3 * 3600 + 26 * 60), "3 u 25 min")
        XCTAssertEqual(HikeFormat.duration(60), "5 min")
    }

    func testTokensSeparateFiguresFromUnits() {
        XCTAssertEqual(HikeFormat.tokens("12,4 km").map(\.text), ["12,4", "km"])
        XCTAssertEqual(HikeFormat.tokens("12,4 km").map(\.isFigure), [true, false])
        XCTAssertEqual(HikeFormat.tokens("2 u 5 min").map(\.isFigure), [true, false, true, false])
        XCTAssertEqual(HikeFormat.tokens("↑ 850 m").map(\.isFigure), [false, true, false])
        XCTAssertTrue(HikeFormat.tokens("").isEmpty)
    }
}
