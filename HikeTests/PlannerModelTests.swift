import HikeCore
import XCTest
@testable import Hike

/// Routes every leg as a straight climb of 200 m, without a network.
private actor StubService: RoutingService {
    var calls: [(Coordinate, Coordinate)] = []
    var failing = false
    func setFailing(_ value: Bool) { failing = value }
    func route(from: Coordinate, to: Coordinate) async throws -> [TrackPoint] {
        calls.append((from, to))
        try await Task.sleep(nanoseconds: 5_000_000)
        if failing { throw RoutingError.noRouteFound }
        return (0...4).map { step in
            TrackPoint(coordinate: from.interpolated(to: to, fraction: Double(step) / 4), elevation: 1000 + Double(step) * 50)
        }
    }
}

@MainActor
final class PlannerModelTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("planner-\(UUID().uuidString)")
    private let a = Coordinate(latitude: 46.00, longitude: 8.00)
    private let b = Coordinate(latitude: 46.02, longitude: 8.00)
    private let c = Coordinate(latitude: 46.04, longitude: 8.00)

    private func makeModel(_ service: StubService) -> PlannerModel {
        PlannerModel(service: service, store: RouteStore(directory: directory))
    }

    private func settle(_ model: PlannerModel) async throws {
        for _ in 0..<400 where model.isRouting { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertFalse(model.isRouting, "routing did not finish")
    }

    func testPlanningARouteBuildsTrackAndStats() async throws {
        let service = StubService()
        let model = makeModel(service)
        XCTAssertFalse(model.isComplete)
        model.addWaypoint(a)
        XCTAssertFalse(model.isRouting)
        XCTAssertTrue(model.hasUnsavedChanges)
        model.addWaypoint(b)
        XCTAssertTrue(model.isRouting)
        XCTAssertEqual(model.segments.map(\.kind), [.pending])
        model.addWaypoint(c)
        try await settle(model)

        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.segments.map(\.kind), [.trail, .trail])
        XCTAssertEqual(model.stats.distance, a.distance(to: c), accuracy: 1)
        // Each stub leg climbs 1000 -> 1200, so the joint between them drops 200.
        XCTAssertEqual(model.stats.ascent, 400)
        XCTAssertEqual(model.stats.descent, 200)
        XCTAssertEqual(model.profile.count, 9)           // joint point counted once
        let calls = await service.calls.count
        XCTAssertEqual(calls, 2)

        model.scrubDistance = model.stats.distance / 2
        XCTAssertEqual(try XCTUnwrap(model.scrubCoordinate).latitude, 46.02, accuracy: 1e-4)
    }

    func testMovingAWaypointOnlyRefetchesItsLegsAndUndoNeedsNoNetwork() async throws {
        let service = StubService()
        let model = makeModel(service)
        for coordinate in [a, b, c] { model.addWaypoint(coordinate) }
        try await settle(model)
        let end = model.waypoints[2]
        model.selectedWaypointID = end.id
        model.moveWaypoint(id: end.id, to: Coordinate(latitude: 46.05, longitude: 8.01))
        try await settle(model)
        var calls = await service.calls.count
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(model.selectedWaypointID, end.id)

        model.undo()
        XCTAssertFalse(model.isRouting)
        XCTAssertTrue(model.isComplete)
        calls = await service.calls.count
        XCTAssertEqual(calls, 3)

        model.removeWaypoint(id: end.id)
        XCTAssertNil(model.selectedWaypointID)
        XCTAssertEqual(model.waypoints.count, 2)
    }

    func testFailedLegShowsErrorAndCanFallBackToStraightLine() async throws {
        let service = StubService()
        let model = makeModel(service)
        model.addWaypoint(a)
        model.addWaypoint(b)
        try await settle(model)
        await service.setFailing(true)
        model.addWaypoint(c)
        try await settle(model)

        XCTAssertEqual(model.routingError, .noRouteFound)
        XCTAssertFalse(model.isComplete)
        XCTAssertEqual(model.segments.map(\.kind), [.trail, .failed])
        // A further edit must not hammer the server with the leg that is known to fail.
        let before = await service.calls.count
        model.legMode = .straight
        model.addWaypoint(a)
        try await settle(model)
        let after = await service.calls.count
        XCTAssertEqual(before, after)
        model.undo()

        model.useStraightLinesForFailedLegs()
        try await settle(model)
        XCTAssertNil(model.routingError)
        XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.segments.map(\.kind), [.trail, .straight])

        // Retrying after the server recovers routes the leg over paths again.
        model.undo()
        await service.setFailing(false)
        model.retryFailedLegs()
        try await settle(model)
        XCTAssertEqual(model.segments.map(\.kind), [.trail, .trail])
    }

    func testSaveReopenAndExport() async throws {
        let service = StubService()
        let model = makeModel(service)
        for coordinate in [a, b, c] { model.addWaypoint(coordinate) }
        try await settle(model)
        // The name comes from reverse geocoding the start, or the plain fallback without a network.
        let name = await model.suggestedName()
        XCTAssertTrue(name.hasPrefix("Wandeling"), name)
        model.save(name: "  Testtocht  ")
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(model.currentRouteName, "Testtocht")
        XCTAssertEqual(model.savedRoutes.count, 1)
        let distance = model.stats.distance

        // Saving again updates the same route rather than adding a copy.
        model.closeLoop()
        try await settle(model)
        XCTAssertTrue(model.isLoop)
        XCTAssertTrue(model.hasUnsavedChanges)
        model.save(name: "Testtocht")
        XCTAssertEqual(model.savedRoutes.count, 1)

        // A fresh launch reads the route from disk and shows it without any routing request.
        let offline = StubService()
        await offline.setFailing(true)
        let relaunched = makeModel(offline)
        let saved = try XCTUnwrap(relaunched.savedRoutes.first)
        relaunched.open(saved)
        XCTAssertFalse(relaunched.isRouting)
        XCTAssertTrue(relaunched.isComplete)
        XCTAssertFalse(relaunched.hasUnsavedChanges)
        XCTAssertGreaterThan(relaunched.stats.distance, distance)
        if case .fit(let coordinates)? = relaunched.camera?.request {
            XCTAssertFalse(coordinates.isEmpty)
        } else {
            XCTFail("expected the map to fit the route")
        }

        // Reversing reuses the known track.
        relaunched.reverseRoute()
        XCTAssertFalse(relaunched.isRouting)
        XCTAssertTrue(relaunched.isComplete)
        let offlineCalls = await offline.calls.count
        XCTAssertEqual(offlineCalls, 0)

        // GPX export round-trips through the importer.
        let url = try XCTUnwrap(relaunched.exportCurrentRoute())
        XCTAssertEqual(url.lastPathComponent, "Testtocht.gpx")
        relaunched.startNewRoute()
        XCTAssertTrue(relaunched.waypoints.isEmpty)
        XCTAssertTrue(relaunched.importGPX(from: url))
        XCTAssertEqual(relaunched.savedRoutes.count, 2)
        XCTAssertEqual(relaunched.currentRouteName, "Testtocht")
        XCTAssertEqual(relaunched.waypoints.count, 2)
        XCTAssertTrue(relaunched.isComplete)

        XCTAssertFalse(relaunched.importGPX(from: directory.appendingPathComponent("bestaat-niet.gpx")))
        XCTAssertNotNil(relaunched.alertMessage)

        relaunched.delete(try XCTUnwrap(relaunched.savedRoutes.first { $0.id == relaunched.currentRouteID }))
        XCTAssertEqual(relaunched.savedRoutes.count, 1)
        XCTAssertNil(relaunched.currentRouteName)
    }

    func testSearchPinBecomesWaypoint() async throws {
        let model = makeModel(StubService())
        model.show(Place(name: "Refuge", detail: "", coordinate: b, kind: .hut))
        XCTAssertEqual(model.searchPin?.title, "Refuge")
        XCTAssertEqual(model.camera?.request, .center(b, meters: 4000))
        model.addSearchPinToRoute()
        XCTAssertNil(model.searchPin)
        XCTAssertEqual(model.waypoints.map(\.coordinate), [b])
    }
}
