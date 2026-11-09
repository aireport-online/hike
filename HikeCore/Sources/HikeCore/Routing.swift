import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum RoutingError: Error, Equatable, Sendable {
    /// A waypoint is too far from any path in the map data (open sea, outside coverage).
    case pointNotOnMap
    /// The points are not connected by walkable paths.
    case noRouteFound
    /// The stretch is too long for the routing service to compute in time.
    case legTooLong
    /// The public routing server is refusing requests for now.
    case serverBusy
    case offline
    case server(String)
    case invalidResponse
}

extension RoutingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .pointNotOnMap:
            return "Er ligt geen pad in de buurt van dit punt. Zet het punt dichter bij een pad of gebruik een rechte lijn."
        case .noRouteFound:
            return "Geen wandelroute gevonden tussen deze punten. Probeer een rechte lijn voor dit stuk."
        case .legTooLong:
            return "Dit stuk is te lang om in één keer te berekenen. Zet tussenpunten dichter bij elkaar."
        case .serverBusy:
            return "De routeserver is druk of het stuk is te lang. Probeer het zo opnieuw of zet een tussenpunt."
        case .offline:
            return "Geen internetverbinding. Routes berekenen kan alleen online."
        case .server(let message):
            return "De routeserver gaf een fout: \(message)"
        case .invalidResponse:
            return "Onverwacht antwoord van de routeserver."
        }
    }
}

/// Minimal HTTP seam so the routing client can be tested without a network.
public protocol HTTPClient: Sendable {
    func get(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        // dataTask rather than the async API: the latter is not on every Foundation this builds for.
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data, http.statusCode))
                } else {
                    continuation.resume(throwing: RoutingError.invalidResponse)
                }
            }
            task.resume()
        }
    }
}

public protocol RoutingService: Sendable {
    /// The walkable track from `from` to `to`, with elevations.
    func route(from: Coordinate, to: Coordinate) async throws -> [TrackPoint]
}

/// Hiking routes from BRouter, which routes over OpenStreetMap paths worldwide and returns
/// elevations with the track. The public server needs no key but is a shared, volunteer-run
/// service: requests are one leg at a time and cached by `LegProvider`.
public struct BRouterClient: RoutingService {
    public static let publicServer = URL(string: "https://brouter.de/brouter")!

    private let baseURL: URL
    private let profile: String
    private let http: HTTPClient
    private let userAgent: String

    public init(
        baseURL: URL = BRouterClient.publicServer,
        profile: String = "hiking-mountain",
        http: HTTPClient = URLSessionHTTPClient(),
        userAgent: String = "Hike-iOS/1.0"
    ) {
        self.baseURL = baseURL
        self.profile = profile
        self.http = http
        self.userAgent = userAgent
    }

    func request(from: Coordinate, to: Coordinate) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let lonlats = [from, to]
            .map { String(format: "%.6f,%.6f", $0.longitude, $0.latitude) }
            .joined(separator: "|")
        components.queryItems = [
            URLQueryItem(name: "lonlats", value: lonlats),
            URLQueryItem(name: "profile", value: profile),
            URLQueryItem(name: "alternativeidx", value: "0"),
            URLQueryItem(name: "format", value: "geojson")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 45
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    public func route(from: Coordinate, to: Coordinate) async throws -> [TrackPoint] {
        let response: (data: Data, status: Int)
        do {
            response = try await http.get(request(from: from, to: to))
        } catch let error as RoutingError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw RoutingError.legTooLong
            case .cancelled:
                throw CancellationError()
            default:
                throw RoutingError.offline
            }
        } catch {
            throw RoutingError.offline
        }

        guard response.status == 200 else {
            throw Self.error(status: response.status, body: String(decoding: response.data, as: UTF8.self))
        }
        return try Self.parse(response.data)
    }

    static func error(status: Int, body: String) -> RoutingError {
        let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = message.lowercased()
        if lowercased.contains("not mapped") {
            return .pointNotOnMap
        }
        if lowercased.contains("island") || lowercased.contains("no track found") {
            return .noRouteFound
        }
        if lowercased.contains("watchdog") || lowercased.contains("timeout") || lowercased.contains("killed") {
            return .legTooLong
        }
        if status == 403 || status == 429 || status == 503 {
            return .serverBusy
        }
        return .server(message.isEmpty ? "HTTP \(status)" : String(message.prefix(200)))
    }

    private struct GeoJSON: Decodable {
        struct Feature: Decodable {
            struct Geometry: Decodable {
                var coordinates: [[Double]]
            }
            var geometry: Geometry
        }
        var features: [Feature]
    }

    static func parse(_ data: Data) throws -> [TrackPoint] {
        guard let geoJSON = try? JSONDecoder().decode(GeoJSON.self, from: data),
              let coordinates = geoJSON.features.first?.geometry.coordinates else {
            throw RoutingError.invalidResponse
        }
        // GeoJSON order is longitude, latitude, then elevation.
        let points: [TrackPoint] = coordinates.compactMap { values in
            guard values.count >= 2 else { return nil }
            return TrackPoint(
                coordinate: Coordinate(latitude: values[1], longitude: values[0]),
                elevation: values.count >= 3 ? values[2] : nil
            )
        }
        guard points.count >= 2 else { throw RoutingError.invalidResponse }
        return points
    }
}
