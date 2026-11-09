import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HikeCore

/// A real (shortened) answer from brouter.de for a walk in Amsterdam. Note the trailing points
/// without elevation: the service omits it where it has no height data.
private let brouterResponse = """
{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"creator":"BRouter-1.7.11-beta",
"name":"brouter_hiking-mountain_0","track-length":"209","filtered ascend":"0","plain-ascend":"0",
"total-time":"149","total-energy":"1957","cost":"240","messages":[["Longitude","Latitude","Elevation"],
["4895862","52370229","1"]],"times":[0,18.583,21.467]},"geometry":{"type":"LineString","coordinates":[
[4.895458,52.370117,1.0],[4.895635,52.370325,1.0],[4.895689,52.370303,1.25],[4.895826,52.370245,1.75],
[4.895862,52.370229,1.5],[4.895907,52.3702,1.5],[4.896009,52.370165,1.0],[4.896816,52.37002,1.0],
[4.897298,52.369932],[4.897406,52.369925],[4.897208,52.369718],[4.896996,52.3695]]}}]}
"""

private final class StubHTTP: HTTPClient, @unchecked Sendable {
    var result: Result<(data: Data, status: Int), Error>
    private(set) var requests: [URLRequest] = []

    init(status: Int = 200, body: String = brouterResponse) {
        result = .success((Data(body.utf8), status))
    }

    func get(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        requests.append(request)
        return try result.get()
    }
}

final class BRouterClientTests: XCTestCase {
    private let from = Coordinate(latitude: 52.3702, longitude: 4.8952)
    private let to = Coordinate(latitude: 52.3695, longitude: 4.897)

    func testParsesTrackWithElevations() async throws {
        let points = try await BRouterClient(http: StubHTTP()).route(from: from, to: to)
        XCTAssertEqual(points.count, 12)
        XCTAssertEqual(points[0].coordinate, Coordinate(latitude: 52.370117, longitude: 4.895458))
        XCTAssertEqual(points[3].elevation, 1.75)
        XCTAssertNil(points[11].elevation)
        // The service reports 209 m for this track.
        XCTAssertEqual(RouteStats(points: points).distance, 209, accuracy: 3)
    }

    func testRequestAsksForHikingProfileInLongitudeLatitudeOrder() async throws {
        let http = StubHTTP()
        _ = try await BRouterClient(http: http).route(from: from, to: to)
        let request = try XCTUnwrap(http.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.host, "brouter.de")
        XCTAssertEqual(query["lonlats"], "4.895200,52.370200|4.897000,52.369500")
        XCTAssertEqual(query["profile"], "hiking-mountain")
        XCTAssertEqual(query["format"], "geojson")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
    }

    private func error(status: Int, body: String) async -> RoutingError? {
        do {
            _ = try await BRouterClient(http: StubHTTP(status: status, body: body)).route(from: from, to: to)
            return nil
        } catch {
            return error as? RoutingError
        }
    }

    func testMapsServerErrorsToMeaningfulCases() async {
        // Bodies as the public server sends them.
        let notMapped = await error(status: 400, body: "from-position not mapped in existing datafile\n")
        XCTAssertEqual(notMapped, .pointNotOnMap)
        let busy = await error(status: 403, body: "Please, retry later!")
        XCTAssertEqual(busy, .serverBusy)
        let island = await error(status: 400, body: "target island detected for section 0")
        XCTAssertEqual(island, .noRouteFound)
        let watchdog = await error(status: 400, body: "operation killed by thread-priority-watchdog after 60 seconds")
        XCTAssertEqual(watchdog, .legTooLong)
        let empty = await error(status: 500, body: "")
        XCTAssertEqual(empty, .server("HTTP 500"))
        let garbage = await error(status: 200, body: "<html>not json</html>")
        XCTAssertEqual(garbage, .invalidResponse)
    }

    func testNetworkFailureIsReportedAsOffline() async {
        let http = StubHTTP()
        http.result = .failure(URLError(.notConnectedToInternet))
        do {
            _ = try await BRouterClient(http: http).route(from: from, to: to)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? RoutingError, .offline)
        }
    }

    func testEveryErrorHasADutchMessage() {
        let errors: [RoutingError] = [
            .pointNotOnMap, .noRouteFound, .legTooLong, .serverBusy, .offline, .server("x"), .invalidResponse
        ]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }
}

private actor CountingService: RoutingService {
    private(set) var calls = 0
    private var failuresLeft: Int

    init(failures: Int = 0) {
        failuresLeft = failures
    }

    func route(from: Coordinate, to: Coordinate) async throws -> [TrackPoint] {
        calls += 1
        try await Task.sleep(nanoseconds: 20_000_000)
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw RoutingError.serverBusy
        }
        return [
            TrackPoint(coordinate: from, elevation: 10),
            TrackPoint(coordinate: from.interpolated(to: to, fraction: 0.5), elevation: 20),
            TrackPoint(coordinate: to, elevation: 30)
        ]
    }
}

final class LegProviderTests: XCTestCase {
    private let a = Coordinate(latitude: 46.0, longitude: 8.0)
    private let b = Coordinate(latitude: 46.1, longitude: 8.1)

    func testFetchesEachLegOnlyOnce() async throws {
        let service = CountingService()
        let provider = LegProvider(service: service)
        let key = LegKey(from: a, to: b, mode: .trail)

        async let first = provider.points(for: key)
        async let second = provider.points(for: key)
        let results = try await [first, second]
        XCTAssertEqual(results[0], results[1])
        XCTAssertEqual(results[0].count, 3)

        _ = try await provider.points(for: key)
        let calls = await service.calls
        XCTAssertEqual(calls, 1)
    }

    func testStraightLegsNeedNoNetwork() async throws {
        let service = CountingService()
        let provider = LegProvider(service: service)
        let points = try await provider.points(for: LegKey(from: a, to: b, mode: .straight))
        XCTAssertEqual(points.map(\.coordinate), [a, b])
        let calls = await service.calls
        XCTAssertEqual(calls, 0)
    }

    func testFailedLegIsRetriedNextTime() async throws {
        let service = CountingService(failures: 1)
        let provider = LegProvider(service: service)
        let key = LegKey(from: a, to: b, mode: .trail)
        do {
            _ = try await provider.points(for: key)
            XCTFail("expected the first attempt to fail")
        } catch {
            XCTAssertEqual(error as? RoutingError, .serverBusy)
        }
        let points = try await provider.points(for: key)
        XCTAssertEqual(points.count, 3)
    }

    func testSeededLegsAreServedFromCache() async throws {
        let service = CountingService()
        let provider = LegProvider(service: service)
        let key = LegKey(from: a, to: b, mode: .trail)
        let saved = [TrackPoint(coordinate: a, elevation: 1), TrackPoint(coordinate: b, elevation: 2)]
        await provider.seed(key, points: saved)
        let points = try await provider.points(for: key)
        XCTAssertEqual(points, saved)
        let calls = await service.calls
        XCTAssertEqual(calls, 0)
    }
}
