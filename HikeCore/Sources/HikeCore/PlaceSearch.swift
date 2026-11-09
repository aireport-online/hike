import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Place: Hashable, Identifiable, Sendable {
    public enum Kind: Sendable {
        case peak, water, hut, settlement, other
    }

    public var name: String
    /// Town, region and country, for telling apart places with the same name.
    public var detail: String
    public var coordinate: Coordinate
    public var kind: Kind

    public var id: String { "\(name)|\(coordinate.latitude)|\(coordinate.longitude)" }

    public init(name: String, detail: String, coordinate: Coordinate, kind: Kind) {
        self.name = name
        self.detail = detail
        self.coordinate = coordinate
        self.kind = kind
    }
}

public enum PlaceSearchError: Error, Equatable, LocalizedError {
    case unavailable

    public var errorDescription: String? {
        "Zoeken lukt nu niet. Controleer je internetverbinding en probeer het opnieuw."
    }
}

/// Place search on OpenStreetMap data via Photon. Unlike address geocoders it knows peaks, lakes,
/// passes and mountain huts by their local names, which is what a hike is usually planned around.
public struct PhotonClient: Sendable {
    public static let publicServer = URL(string: "https://photon.komoot.io/api/")!
    /// West, south, east, north: Iceland to the Urals, the Canaries' latitude to the North Cape.
    public static let europe = "-25,34,45,72"

    private let baseURL: URL
    private let http: HTTPClient
    private let userAgent: String

    public init(
        baseURL: URL = PhotonClient.publicServer,
        http: HTTPClient = URLSessionHTTPClient(),
        userAgent: String = "Hike-iOS/1.0"
    ) {
        self.baseURL = baseURL
        self.http = http
        self.userAgent = userAgent
    }

    func request(query: String, near: Coordinate?, limit: Int) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "bbox", value: Self.europe)
        ]
        if let near {
            items.append(URLQueryItem(name: "lat", value: String(format: "%.4f", near.latitude)))
            items.append(URLQueryItem(name: "lon", value: String(format: "%.4f", near.longitude)))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Places in Europe matching `query`, those close to `near` first.
    public func search(_ query: String, near: Coordinate? = nil, limit: Int = 12) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let response: (data: Data, status: Int)
        do {
            response = try await http.get(request(query: trimmed, near: near, limit: limit))
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw PlaceSearchError.unavailable
        }
        guard response.status == 200 else { throw PlaceSearchError.unavailable }
        return try Self.parse(response.data)
    }

    private struct GeoJSON: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                var name: String?
                var street: String?
                var housenumber: String?
                var city: String?
                var county: String?
                var state: String?
                var country: String?
                var osm_key: String?
                var osm_value: String?
            }
            struct Geometry: Decodable {
                var coordinates: [Double]
            }
            var properties: Properties
            var geometry: Geometry
        }
        var features: [Feature]
    }

    static func parse(_ data: Data) throws -> [Place] {
        guard let geoJSON = try? JSONDecoder().decode(GeoJSON.self, from: data) else {
            throw PlaceSearchError.unavailable
        }
        var seen = Set<String>()
        return geoJSON.features.compactMap { feature -> Place? in
            let properties = feature.properties
            guard feature.geometry.coordinates.count >= 2 else { return nil }
            let street = [properties.street, properties.housenumber].compactMap { $0 }.joined(separator: " ")
            guard let name = properties.name ?? (street.isEmpty ? nil : street) else { return nil }

            var parts: [String] = []
            for part in [properties.city, properties.county, properties.state, properties.country] {
                if let part, part != name, !parts.contains(part) {
                    parts.append(part)
                }
            }
            // Town, region, country is enough; the county in between only adds length.
            if parts.count > 3 { parts.remove(at: 1) }

            let place = Place(
                name: name,
                detail: parts.joined(separator: ", "),
                coordinate: Coordinate(latitude: feature.geometry.coordinates[1], longitude: feature.geometry.coordinates[0]),
                kind: kind(key: properties.osm_key, value: properties.osm_value)
            )
            // The same lake or village often comes back as both an area and a point.
            let signature = "\(place.name)|\(place.detail)|\(place.kind)"
            return seen.insert(signature).inserted ? place : nil
        }
    }

    private static func kind(key: String?, value: String?) -> Place.Kind {
        switch (key, value) {
        case ("natural", "peak"), ("natural", "volcano"), ("natural", "saddle"), ("mountain_pass", _):
            return .peak
        case ("natural", "water"), ("water", _), ("waterway", _), ("natural", "glacier"), ("natural", "spring"):
            return .water
        case ("tourism", "alpine_hut"), ("tourism", "wilderness_hut"), ("amenity", "shelter"):
            return .hut
        case ("place", _), ("boundary", _):
            return .settlement
        default:
            return .other
        }
    }
}
