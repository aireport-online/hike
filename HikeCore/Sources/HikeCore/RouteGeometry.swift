import Foundation

/// A track with cumulative distances, for the elevation profile and for finding the map position
/// that belongs to a spot on that profile.
public struct RouteGeometry: Equatable, Sendable {
    public struct Sample: Equatable, Sendable, Identifiable {
        public var distance: Double
        public var elevation: Double
        public var id: Double { distance }

        public init(distance: Double, elevation: Double) {
            self.distance = distance
            self.elevation = elevation
        }
    }

    public let points: [TrackPoint]
    /// `cumulativeDistances[i]` is the distance in metres from the start to `points[i]`.
    public let cumulativeDistances: [Double]

    public init(points: [TrackPoint]) {
        self.points = points
        var distances: [Double] = []
        distances.reserveCapacity(points.count)
        var total = 0.0
        for (index, point) in points.enumerated() {
            if index > 0 {
                total += points[index - 1].coordinate.distance(to: point.coordinate)
            }
            distances.append(total)
        }
        cumulativeDistances = distances
    }

    public var totalDistance: Double { cumulativeDistances.last ?? 0 }

    public var hasElevation: Bool {
        points.contains { $0.elevation != nil }
    }

    /// Elevation samples thinned to at most `maxSamples`, always keeping the first and last point.
    public func elevationProfile(maxSamples: Int = 400) -> [Sample] {
        var all: [Sample] = []
        var lastDistance = -1.0
        for (index, point) in points.enumerated() {
            guard let elevation = point.elevation else { continue }
            let distance = cumulativeDistances[index]
            // Leg joints repeat a point; a chart wants strictly increasing distances.
            guard distance > lastDistance else { continue }
            all.append(Sample(distance: distance, elevation: elevation))
            lastDistance = distance
        }
        guard all.count > maxSamples, maxSamples >= 2 else { return all }
        let step = Double(all.count - 1) / Double(maxSamples - 1)
        return (0..<maxSamples).map { all[Int((Double($0) * step).rounded())] }
    }

    /// The position on the track at `distance` metres from the start, clamped to the track.
    public func coordinate(atDistance distance: Double) -> Coordinate? {
        guard let first = points.first, let last = points.last else { return nil }
        if distance <= 0 { return first.coordinate }
        if distance >= totalDistance { return last.coordinate }

        var low = 0
        var high = cumulativeDistances.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if cumulativeDistances[middle] <= distance {
                low = middle
            } else {
                high = middle
            }
        }
        let span = cumulativeDistances[high] - cumulativeDistances[low]
        let fraction = span > 0 ? (distance - cumulativeDistances[low]) / span : 0
        return points[low].coordinate.interpolated(to: points[high].coordinate, fraction: fraction)
    }
}
