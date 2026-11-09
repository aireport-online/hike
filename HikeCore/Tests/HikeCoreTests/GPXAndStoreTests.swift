import XCTest
@testable import HikeCore

final class GPXTests: XCTestCase {
    private let points = [
        TrackPoint(coordinate: Coordinate(latitude: 45.923700, longitude: 6.869400), elevation: 1035.5),
        TrackPoint(coordinate: Coordinate(latitude: 45.930000, longitude: 6.880000), elevation: 1210),
        TrackPoint(coordinate: Coordinate(latitude: 45.940000, longitude: 6.890000), elevation: nil)
    ]

    func testWrittenGPXReadsBackIdentically() throws {
        let text = GPX.string(name: "Chamonix & <Lac Blanc>", points: points)
        let document = try GPX.parse(Data(text.utf8))
        XCTAssertEqual(document.name, "Chamonix & <Lac Blanc>")
        XCTAssertEqual(document.points, points)
    }

    func testReadsTrackFromAnotherAppsFile() throws {
        // Multiple segments, extensions and waypoints, as exported by common hiking apps.
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="OtherApp" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>Bestandsnaam</name></metadata>
          <wpt lat="47.0" lon="11.0"><ele>900</ele><name>Hut</name></wpt>
          <trk>
            <name>Stubaier Höhenweg</name>
            <trkseg>
              <trkpt lat="47.10" lon="11.30"><ele>1700.2</ele><time>2026-07-01T08:00:00Z</time></trkpt>
              <trkpt lat="47.11" lon="11.31"><ele>1750</ele><extensions><hr>120</hr></extensions></trkpt>
            </trkseg>
            <trkseg>
              <trkpt lat="47.12" lon="11.32"></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let document = try GPX.parse(Data(gpx.utf8))
        XCTAssertEqual(document.name, "Stubaier Höhenweg")
        XCTAssertEqual(document.points.count, 3)
        XCTAssertEqual(document.points[0].elevation, 1700.2)
        XCTAssertEqual(document.points[1].coordinate, Coordinate(latitude: 47.11, longitude: 11.31))
        XCTAssertNil(document.points[2].elevation)
    }

    func testFallsBackToPlannedRouteWhenThereIsNoTrack() throws {
        let gpx = """
        <gpx version="1.1"><rte><name>Plan</name>
        <rtept lat="52.1" lon="5.1"/><rtept lat="52.2" lon="5.2"><ele>12</ele></rtept></rte></gpx>
        """
        let document = try GPX.parse(Data(gpx.utf8))
        XCTAssertEqual(document.name, "Plan")
        XCTAssertEqual(document.points.map(\.elevation), [nil, 12])
    }

    func testRejectsFilesWithoutUsableTrack() {
        XCTAssertThrowsError(try GPX.parse(Data("dit is geen xml".utf8))) { error in
            XCTAssertEqual(error as? GPXError, .unreadable)
        }
        let onlyWaypoints = "<gpx><wpt lat=\"1\" lon=\"2\"/></gpx>"
        XCTAssertThrowsError(try GPX.parse(Data(onlyWaypoints.utf8))) { error in
            XCTAssertEqual(error as? GPXError, .noTrack)
        }
        let badCoordinates = "<gpx><trk><trkseg><trkpt lat=\"x\" lon=\"2\"/><trkpt lat=\"95\" lon=\"2\"/></trkseg></trk></gpx>"
        XCTAssertThrowsError(try GPX.parse(Data(badCoordinates.utf8)))
    }

    func testFileNameIsSafe() {
        XCTAssertEqual(GPX.fileName(for: "Chamonix → Lac Blanc"), "Chamonix - Lac Blanc.gpx")
        XCTAssertEqual(GPX.fileName(for: "a/b:c"), "a-b-c.gpx")
        XCTAssertEqual(GPX.fileName(for: "  "), "Wandeling.gpx")
    }

    func testImportedTrackBecomesRouteWithStartAndEnd() throws {
        let route = try XCTUnwrap(HikeRoute(name: "Import", importedTrack: points))
        XCTAssertEqual(route.waypoints.map(\.coordinate), [points[0].coordinate, points[2].coordinate])
        XCTAssertEqual(route.points, points)
        XCTAssertNil(HikeRoute(name: "Leeg", importedTrack: [points[0]]))
    }

    func testLongRecordedTrackIsThinnedButKeepsItsEnds() throws {
        let recorded = (0..<20_000).map { index in
            TrackPoint(coordinate: Coordinate(latitude: 46 + Double(index) * 0.00001, longitude: 8), elevation: Double(index))
        }
        let route = try XCTUnwrap(HikeRoute(name: "Opname", importedTrack: recorded))
        XCTAssertEqual(route.points.count, HikeRoute.maxImportedPoints)
        XCTAssertEqual(route.points.first, recorded.first)
        XCTAssertEqual(route.points.last, recorded.last)
        XCTAssertEqual(route.stats.distance, RouteStats(points: recorded).distance, accuracy: 1)
    }
}

final class RouteStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hike-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func route(_ name: String, updated: TimeInterval) -> HikeRoute {
        let a = Coordinate(latitude: 46, longitude: 8)
        let b = Coordinate(latitude: 46.01, longitude: 8.01)
        return HikeRoute(
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: updated),
            waypoints: [Waypoint(coordinate: a), Waypoint(coordinate: b, mode: .straight)],
            legs: [RouteLeg(mode: .straight, points: [TrackPoint(coordinate: a, elevation: 500), TrackPoint(coordinate: b)])]
        )
    }

    func testSavedRoutesComeBackNewestFirst() throws {
        let store = RouteStore(directory: directory)
        XCTAssertTrue(store.all().isEmpty)
        let older = route("Oud", updated: 1_700_000_100)
        let newer = route("Nieuw", updated: 1_700_000_200)
        try store.save(older)
        try store.save(newer)

        // A second store on the same directory sees what the first one wrote.
        let reloaded = RouteStore(directory: directory).all()
        XCTAssertEqual(reloaded, [newer, older])
    }

    func testSavingAgainReplacesAndDeleteRemoves() throws {
        let store = RouteStore(directory: directory)
        var saved = route("Eerste naam", updated: 1_700_000_100)
        try store.save(saved)
        saved.name = "Nieuwe naam"
        try store.save(saved)
        XCTAssertEqual(store.all().map(\.name), ["Nieuwe naam"])

        try store.delete(id: saved.id)
        try store.delete(id: saved.id)
        XCTAssertTrue(store.all().isEmpty)
    }

    func testCorruptFileDoesNotHideOtherRoutes() throws {
        let store = RouteStore(directory: directory)
        try store.save(route("Goed", updated: 1_700_000_100))
        try Data("kapot".utf8).write(to: directory.appendingPathComponent("\(UUID().uuidString).json"))
        XCTAssertEqual(store.all().map(\.name), ["Goed"])
    }

    func testTrackPointsAreStoredCompactly() throws {
        let data = try JSONEncoder().encode([
            TrackPoint(coordinate: Coordinate(latitude: 46.5, longitude: 8.25), elevation: 500),
            TrackPoint(coordinate: Coordinate(latitude: 46.5, longitude: 8.25))
        ])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[[46.5,8.25,500],[46.5,8.25]]")
    }
}
