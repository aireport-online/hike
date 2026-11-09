import Foundation

/// A WGS84 position. Kept free of CoreLocation so the planning logic builds and tests anywhere.
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres (haversine).
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_008.8
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(a)))
    }

    /// Linear interpolation, accurate enough for the short segments of a hiking track.
    public func interpolated(to other: Coordinate, fraction: Double) -> Coordinate {
        Coordinate(
            latitude: latitude + (other.latitude - latitude) * fraction,
            longitude: longitude + (other.longitude - longitude) * fraction
        )
    }
}

/// A point on a track, with elevation in metres when the source provides it.
public struct TrackPoint: Hashable, Sendable {
    public var coordinate: Coordinate
    public var elevation: Double?

    public init(coordinate: Coordinate, elevation: Double? = nil) {
        self.coordinate = coordinate
        self.elevation = elevation
    }
}

/// Stored as `[lat, lon]` or `[lat, lon, ele]` — a track has thousands of points, so keys would
/// multiply the size of every saved route.
extension TrackPoint: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let latitude = try container.decode(Double.self)
        let longitude = try container.decode(Double.self)
        let elevation = container.isAtEnd ? nil : try container.decode(Double.self)
        self.init(coordinate: Coordinate(latitude: latitude, longitude: longitude), elevation: elevation)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(coordinate.latitude)
        try container.encode(coordinate.longitude)
        if let elevation {
            try container.encode(elevation)
        }
    }
}

public struct BoundingBox: Equatable, Sendable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init?(_ coordinates: [Coordinate]) {
        guard let first = coordinates.first else { return nil }
        minLatitude = first.latitude
        maxLatitude = first.latitude
        minLongitude = first.longitude
        maxLongitude = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }
    }

    public var center: Coordinate {
        Coordinate(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
    }
}
