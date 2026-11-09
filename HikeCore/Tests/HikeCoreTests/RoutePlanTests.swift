import XCTest
@testable import HikeCore

final class RoutePlanTests: XCTestCase {
    private let a = Coordinate(latitude: 46.0, longitude: 8.0)
    private let b = Coordinate(latitude: 46.1, longitude: 8.1)
    private let c = Coordinate(latitude: 46.2, longitude: 8.2)

    func testAppendBuildsLegKeysBetweenConsecutiveWaypoints() {
        var plan = RoutePlan()
        XCTAssertTrue(plan.legKeys.isEmpty)
        plan.append(a)
        XCTAssertTrue(plan.legKeys.isEmpty)
        plan.append(b)
        plan.append(c, mode: .straight)
        XCTAssertEqual(plan.legKeys, [
            LegKey(from: a, to: b, mode: .trail),
            LegKey(from: b, to: c, mode: .straight)
        ])
    }

    func testMoveChangesOnlyTheAdjacentLegs() {
        var plan = RoutePlan()
        plan.append(a)
        let middle = plan.append(b)
        plan.append(c)
        let moved = Coordinate(latitude: 46.15, longitude: 8.05)
        plan.move(id: middle.id, to: moved)
        XCTAssertEqual(plan.legKeys.map(\.from), [a, moved])
        XCTAssertEqual(plan.legKeys.map(\.to), [moved, c])
        XCTAssertEqual(plan.waypoints[1].id, middle.id)
    }

    func testRemoveJoinsNeighbours() {
        var plan = RoutePlan()
        plan.append(a)
        let middle = plan.append(b)
        plan.append(c)
        plan.remove(id: middle.id)
        XCTAssertEqual(plan.legKeys, [LegKey(from: a, to: c, mode: .trail)])
    }

    func testReverseKeepsEachStretchInItsMode() {
        var plan = RoutePlan()
        plan.append(a)
        plan.append(b, mode: .straight)
        plan.append(c, mode: .trail)
        let before = plan.legKeys
        plan.reverse()
        XCTAssertEqual(plan.waypoints.map(\.coordinate), [c, b, a])
        XCTAssertEqual(plan.legKeys, before.reversed().map(\.reversed))
    }

    func testSetModeSwitchesOnlyTheChosenLegs() {
        var plan = RoutePlan()
        plan.append(a)
        let second = plan.append(b)
        plan.append(c)
        plan.setMode(.straight, forLegsEndingAt: [second.id])
        XCTAssertEqual(plan.legKeys.map(\.mode), [.straight, .trail])
        plan.setMode(.straight, forLegsEndingAt: [second.id])
        plan.undo()
        XCTAssertEqual(plan.legKeys.map(\.mode), [.trail, .trail])
    }

    func testCloseLoopReturnsToStartOnce() {
        var plan = RoutePlan()
        plan.append(a)
        plan.append(b)
        XCTAssertFalse(plan.isLoop)
        plan.closeLoop()
        XCTAssertTrue(plan.isLoop)
        XCTAssertEqual(plan.waypoints.count, 3)
        plan.closeLoop()
        XCTAssertEqual(plan.waypoints.count, 3)
    }

    func testUndoWalksBackThroughEveryEdit() {
        var plan = RoutePlan()
        XCTAssertFalse(plan.canUndo)
        plan.append(a)
        let second = plan.append(b)
        plan.move(id: second.id, to: c)
        plan.clear()
        XCTAssertTrue(plan.isEmpty)

        plan.undo()
        XCTAssertEqual(plan.waypoints.map(\.coordinate), [a, c])
        plan.undo()
        XCTAssertEqual(plan.waypoints.map(\.coordinate), [a, b])
        plan.undo()
        plan.undo()
        XCTAssertTrue(plan.isEmpty)
        XCTAssertFalse(plan.canUndo)
        plan.undo()
        XCTAssertTrue(plan.isEmpty)
    }

    func testNoOpEditsDoNotPolluteUndo() {
        var plan = RoutePlan()
        let first = plan.append(a)
        plan.move(id: first.id, to: a)
        plan.remove(id: UUID())
        plan.reverse()
        plan.undo()
        XCTAssertTrue(plan.isEmpty)
    }
}
