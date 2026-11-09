import Foundation

/// The waypoints of the route being planned, with undo. Pure state: fetching the track between
/// waypoints is `LegProvider`'s job.
public struct RoutePlan: Equatable, Sendable {
    public private(set) var waypoints: [Waypoint]
    private var undoStack: [[Waypoint]] = []

    public init(waypoints: [Waypoint] = []) {
        self.waypoints = waypoints
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var isEmpty: Bool { waypoints.isEmpty }

    /// True when the route ends where it started.
    public var isLoop: Bool {
        guard waypoints.count >= 3, let first = waypoints.first, let last = waypoints.last else { return false }
        return first.coordinate == last.coordinate
    }

    public var legKeys: [LegKey] {
        guard waypoints.count >= 2 else { return [] }
        return (1..<waypoints.count).map { index in
            LegKey(
                from: waypoints[index - 1].coordinate,
                to: waypoints[index].coordinate,
                mode: waypoints[index].mode
            )
        }
    }

    @discardableResult
    public mutating func append(_ coordinate: Coordinate, mode: LegMode = .trail) -> Waypoint {
        let waypoint = Waypoint(coordinate: coordinate, mode: mode)
        commit(waypoints + [waypoint])
        return waypoint
    }

    public mutating func move(id: Waypoint.ID, to coordinate: Coordinate) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }),
              waypoints[index].coordinate != coordinate else { return }
        var updated = waypoints
        updated[index].coordinate = coordinate
        commit(updated)
    }

    public mutating func remove(id: Waypoint.ID) {
        guard let index = waypoints.firstIndex(where: { $0.id == id }) else { return }
        var updated = waypoints
        updated.remove(at: index)
        commit(updated)
    }

    /// Changes how the stretch arriving at each of the given waypoints is drawn.
    public mutating func setMode(_ mode: LegMode, forLegsEndingAt ids: Set<Waypoint.ID>) {
        var updated = waypoints
        for index in updated.indices where ids.contains(updated[index].id) {
            updated[index].mode = mode
        }
        guard updated != waypoints else { return }
        commit(updated)
    }

    /// Walks the same route in the opposite direction, keeping each stretch's mode.
    public mutating func reverse() {
        guard waypoints.count >= 2 else { return }
        let count = waypoints.count
        var updated = Array(waypoints.reversed())
        for index in 1..<count {
            updated[index].mode = waypoints[count - index].mode
        }
        updated[0].mode = .trail
        commit(updated)
    }

    /// Adds a final waypoint on the start, turning the route into a round trip.
    public mutating func closeLoop(mode: LegMode = .trail) {
        guard waypoints.count >= 2, !isLoop, let first = waypoints.first else { return }
        append(first.coordinate, mode: mode)
    }

    public mutating func clear() {
        guard !waypoints.isEmpty else { return }
        commit([])
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        waypoints = previous
    }

    private mutating func commit(_ updated: [Waypoint]) {
        undoStack.append(waypoints)
        if undoStack.count > 100 {
            undoStack.removeFirst()
        }
        waypoints = updated
    }
}
