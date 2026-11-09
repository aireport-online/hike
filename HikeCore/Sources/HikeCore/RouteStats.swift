import Foundation

public enum Pace: String, Codable, Sendable, CaseIterable {
    case relaxed
    case normal
    case brisk

    /// Multiplier on the standard walking time.
    public var timeFactor: Double {
        switch self {
        case .relaxed: return 1.25
        case .normal: return 1.0
        case .brisk: return 0.8
        }
    }
}

public struct RouteStats: Equatable, Sendable {
    /// Metres along the track.
    public var distance: Double
    /// Total climb and drop in metres, ignoring wobbles smaller than the noise threshold.
    public var ascent: Double
    public var descent: Double
    public var minElevation: Double?
    public var maxElevation: Double?

    public static let empty = RouteStats(distance: 0, ascent: 0, descent: 0, minElevation: nil, maxElevation: nil)

    public init(distance: Double, ascent: Double, descent: Double, minElevation: Double?, maxElevation: Double?) {
        self.distance = distance
        self.ascent = ascent
        self.descent = descent
        self.minElevation = minElevation
        self.maxElevation = maxElevation
    }

    /// - Parameter noiseThreshold: elevation models are noisy; a change only counts once it
    ///   exceeds this many metres, otherwise flat walks appear to climb hundreds of metres.
    public init(points: [TrackPoint], noiseThreshold: Double = 10) {
        var distance = 0.0
        var ascent = 0.0
        var descent = 0.0
        var minElevation: Double?
        var maxElevation: Double?
        var reference: Double?
        var previous: Coordinate?

        for point in points {
            if let previous {
                distance += previous.distance(to: point.coordinate)
            }
            previous = point.coordinate

            guard let elevation = point.elevation else { continue }
            minElevation = min(minElevation ?? elevation, elevation)
            maxElevation = max(maxElevation ?? elevation, elevation)
            guard let current = reference else {
                reference = elevation
                continue
            }
            let change = elevation - current
            if change >= noiseThreshold {
                ascent += change
                reference = elevation
            } else if change <= -noiseThreshold {
                descent -= change
                reference = elevation
            }
        }

        self.init(distance: distance, ascent: ascent, descent: descent, minElevation: minElevation, maxElevation: maxElevation)
    }

    /// Walking time by the DIN 33466 rule used on Alpine signposts: 4 km/h on the flat, 300 m/h
    /// up and 500 m/h down; the smaller of the horizontal and vertical time counts for half.
    public func duration(pace: Pace = .normal) -> TimeInterval {
        let horizontal = distance / 4000
        let vertical = ascent / 300 + descent / 500
        let hours = max(horizontal, vertical) + min(horizontal, vertical) / 2
        return hours * 3600 * pace.timeFactor
    }
}
