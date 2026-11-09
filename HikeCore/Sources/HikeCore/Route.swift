import Foundation

/// How the stretch leading up to a waypoint is drawn.
public enum LegMode: String, Codable, Sendable, CaseIterable {
    /// Follows paths and trails via the routing service.
    case trail
    /// A straight line, for off-trail stretches or places the map data does not cover.
    case straight
}

public struct Waypoint: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var coordinate: Coordinate
    /// Mode of the leg that arrives at this waypoint. Ignored for the first waypoint.
    public var mode: LegMode

    public init(id: UUID = UUID(), coordinate: Coordinate, mode: LegMode = .trail) {
        self.id = id
        self.coordinate = coordinate
        self.mode = mode
    }
}

/// Identifies one stretch between two consecutive waypoints. Legs are fetched and cached by key,
/// so editing a route only recomputes the stretches that actually changed.
public struct LegKey: Hashable, Sendable {
    public var from: Coordinate
    public var to: Coordinate
    public var mode: LegMode

    public init(from: Coordinate, to: Coordinate, mode: LegMode) {
        self.from = from
        self.to = to
        self.mode = mode
    }

    public var reversed: LegKey {
        LegKey(from: to, to: from, mode: mode)
    }
}

public struct RouteLeg: Codable, Hashable, Sendable {
    public var mode: LegMode
    public var points: [TrackPoint]

    public init(mode: LegMode, points: [TrackPoint]) {
        self.mode = mode
        self.points = points
    }
}

/// A saved hike: the waypoints the user placed plus the computed track between them.
public struct HikeRoute: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var waypoints: [Waypoint]
    /// `legs[i]` connects `waypoints[i]` to `waypoints[i + 1]`.
    public var legs: [RouteLeg]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        waypoints: [Waypoint],
        legs: [RouteLeg]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.waypoints = waypoints
        self.legs = legs
    }

    public var points: [TrackPoint] {
        legs.flatMap(\.points)
    }

    public var stats: RouteStats {
        RouteStats(points: points)
    }
}

extension HikeRoute {
    /// Recorded tracks can hold a point per second; beyond this many the map and the saved file
    /// get slow without the line looking any different.
    public static let maxImportedPoints = 5000

    /// Wraps an imported track as a route with a start and an end waypoint.
    public init?(name: String, importedTrack track: [TrackPoint], now: Date = Date()) {
        var points = track
        if points.count > Self.maxImportedPoints {
            let step = Double(points.count - 1) / Double(Self.maxImportedPoints - 1)
            points = (0..<Self.maxImportedPoints).map { track[Int((Double($0) * step).rounded())] }
        }
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        self.init(
            name: name,
            createdAt: now,
            updatedAt: now,
            waypoints: [
                Waypoint(coordinate: first.coordinate),
                Waypoint(coordinate: last.coordinate)
            ],
            legs: [RouteLeg(mode: .trail, points: points)]
        )
    }
}
