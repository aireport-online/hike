import Foundation

/// Fetches and remembers the track for each leg, so a route edit only asks the routing service
/// for stretches it has not seen before and never asks twice for the same one at once.
public actor LegProvider {
    private let service: RoutingService
    private var cache: [LegKey: [TrackPoint]] = [:]
    private var inFlight: [LegKey: Task<[TrackPoint], Error>] = [:]

    public init(service: RoutingService) {
        self.service = service
    }

    public func cached(_ key: LegKey) -> [TrackPoint]? {
        cache[key]
    }

    /// Stores a track that is already known, e.g. from a saved or imported route.
    public func seed(_ key: LegKey, points: [TrackPoint]) {
        cache[key] = points
    }

    public func points(for key: LegKey) async throws -> [TrackPoint] {
        if let cached = cache[key] {
            return cached
        }
        if key.mode == .straight {
            let points = [TrackPoint(coordinate: key.from), TrackPoint(coordinate: key.to)]
            cache[key] = points
            return points
        }
        if let running = inFlight[key] {
            return try await running.value
        }

        let service = self.service
        let task = Task { try await service.route(from: key.from, to: key.to) }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let points = try await task.value
        cache[key] = points
        return points
    }
}
