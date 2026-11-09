import XCTest
@testable import HikeCore

/// Talks to the real public services. Skipped unless HIKE_LIVE_TESTS=1, so the normal test run
/// needs no network and puts no load on volunteer-run servers.
final class LiveServiceTests: XCTestCase {
    private func requireLive() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HIKE_LIVE_TESTS"] == "1", "set HIKE_LIVE_TESTS=1 to run")
    }

    func testRoutesAHikeInTheAlpsWithElevation() async throws {
        try requireLive()
        // Chamonix to the Lac Blanc hut: a classic climb of roughly 1300 m.
        let chamonix = Coordinate(latitude: 45.9237, longitude: 6.8694)
        let lacBlanc = Coordinate(latitude: 45.9817, longitude: 6.8919)
        let provider = LegProvider(service: BRouterClient())
        let points = try await provider.points(for: LegKey(from: chamonix, to: lacBlanc, mode: .trail))
        let stats = RouteStats(points: points)
        print("live route: \(points.count) points, \(HikeFormat.distance(stats.distance)), up \(Int(stats.ascent)) m, down \(Int(stats.descent)) m, \(HikeFormat.duration(stats.duration()))")
        XCTAssertGreaterThan(points.count, 50)
        XCTAssertGreaterThan(stats.distance, 7_000)
        XCTAssertLessThan(stats.distance, 20_000)
        XCTAssertGreaterThan(stats.ascent, 1_000)
        XCTAssertEqual(try XCTUnwrap(stats.maxElevation), 2_350, accuracy: 150)
        XCTAssertLessThan(try XCTUnwrap(points.first).coordinate.distance(to: chamonix), 200)
    }

    func testRoutesAcrossEurope() async throws {
        try requireLive()
        let client = BRouterClient()
        let walks: [(String, Coordinate, Coordinate)] = [
            ("Noorwegen, Preikestolen", Coordinate(latitude: 58.9905, longitude: 6.1383), Coordinate(latitude: 58.9864, longitude: 6.1904)),
            ("Madeira, Pico do Arieiro", Coordinate(latitude: 32.7356, longitude: -16.9289), Coordinate(latitude: 32.7594, longitude: -16.9424)),
            ("Kreta, Samaria", Coordinate(latitude: 35.3080, longitude: 23.9180), Coordinate(latitude: 35.2330, longitude: 23.9620))
        ]
        for (name, from, to) in walks {
            let points = try await client.route(from: from, to: to)
            let stats = RouteStats(points: points)
            print("live \(name): \(HikeFormat.distance(stats.distance)), up \(Int(stats.ascent)) m, down \(Int(stats.descent)) m")
            XCTAssertGreaterThan(stats.distance, 2_000, name)
            XCTAssertNotNil(stats.maxElevation, name)
        }
    }

    func testPointAtSeaIsReportedAsNotOnMap() async throws {
        try requireLive()
        let sea = Coordinate(latitude: 55.0, longitude: 3.0)
        do {
            _ = try await BRouterClient().route(from: sea, to: Coordinate(latitude: 55.0, longitude: 3.1))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? RoutingError, .pointNotOnMap)
        }
    }

    func testFindsAMountainHutByName() async throws {
        try requireLive()
        let places = try await PhotonClient().search("Refuge du Lac Blanc", near: Coordinate(latitude: 45.98, longitude: 6.89))
        print("live search: \(places.prefix(3).map { "\($0.name) (\($0.detail))" })")
        let hut = try XCTUnwrap(places.first { $0.kind == .hut })
        XCTAssertLessThan(hut.coordinate.distance(to: Coordinate(latitude: 45.9817, longitude: 6.8919)), 500)
    }
}
