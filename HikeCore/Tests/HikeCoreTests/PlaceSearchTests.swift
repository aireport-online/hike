import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HikeCore

/// A real answer from photon.komoot.io for "lac blanc chamonix".
private let photonResponse = """
{"type":"FeatureCollection","features":[
{"type":"Feature","properties":{"osm_type":"R","osm_id":107981,"osm_key":"water","osm_value":"lake","type":"other",
"name":"Lac Blanc","city":"Chamonix-Mont-Blanc","county":"Haute-Savoie","state":"Auvergne-Rhône-Alpes",
"country":"France","postcode":"74400","countrycode":"FR","extent":[6.8878468,45.9836055,6.8914734,45.9810971]},
"geometry":{"type":"Point","coordinates":[6.8888588,45.9826205]}},
{"type":"Feature","properties":{"osm_type":"N","osm_id":10018640586,"osm_key":"water","osm_value":"lake",
"name":"Lac Blanc","city":"Chamonix-Mont-Blanc","county":"Haute-Savoie","state":"Auvergne-Rhône-Alpes",
"country":"France"},"geometry":{"type":"Point","coordinates":[6.8890924,45.9826522]}},
{"type":"Feature","properties":{"osm_type":"W","osm_id":262228030,"osm_key":"tourism","osm_value":"alpine_hut",
"type":"house","name":"Refuge du Lac Blanc","street":"Tour du Pays du Mont-Blanc","city":"Chamonix-Mont-Blanc",
"county":"Haute-Savoie","state":"Auvergne-Rhône-Alpes","country":"France"},
"geometry":{"type":"Point","coordinates":[6.8919009,45.9816856]}},
{"type":"Feature","properties":{"osm_key":"place","osm_value":"city","type":"city","name":"Utrecht",
"state":"Utrecht","country":"Nederland"},"geometry":{"type":"Point","coordinates":[5.1215634,52.0907006]}},
{"type":"Feature","properties":{"osm_key":"highway","osm_value":"path"},
"geometry":{"type":"Point","coordinates":[5.0,52.0]}}
]}
"""

private final class StubHTTP: HTTPClient, @unchecked Sendable {
    var status = 200
    var body = photonResponse
    var failure: Error?
    private(set) var requests: [URLRequest] = []

    func get(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        requests.append(request)
        if let failure { throw failure }
        return (Data(body.utf8), status)
    }
}

final class PhotonClientTests: XCTestCase {
    func testParsesPlacesWithKindAndReadableDetail() async throws {
        let places = try await PhotonClient(http: StubHTTP()).search("lac blanc chamonix")
        // The duplicate lake and the nameless path are dropped.
        XCTAssertEqual(places.map(\.name), ["Lac Blanc", "Refuge du Lac Blanc", "Utrecht"])
        XCTAssertEqual(places[0].kind, .water)
        XCTAssertEqual(places[0].detail, "Chamonix-Mont-Blanc, Auvergne-Rhône-Alpes, France")
        XCTAssertEqual(places[0].coordinate, Coordinate(latitude: 45.9826205, longitude: 6.8888588))
        XCTAssertEqual(places[1].kind, .hut)
        XCTAssertEqual(places[2].kind, .settlement)
        // "Utrecht, Utrecht, Nederland" would repeat the name.
        XCTAssertEqual(places[2].detail, "Nederland")
    }

    func testRequestIsLimitedToEuropeAndBiasedToTheMap() async throws {
        let http = StubHTTP()
        _ = try await PhotonClient(http: http).search(" zugspitze ", near: Coordinate(latitude: 47.4, longitude: 11))
        let url = try XCTUnwrap(http.requests.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["q"], "zugspitze")
        XCTAssertEqual(query["bbox"], "-25,34,45,72")
        XCTAssertEqual(query["lat"], "47.4000")
        XCTAssertEqual(query["lon"], "11.0000")
        // Photon rejects languages it does not index (Dutch among them), so none is sent.
        XCTAssertNil(query["lang"])
    }

    func testShortQueriesDoNotHitTheServer() async throws {
        let http = StubHTTP()
        let places = try await PhotonClient(http: http).search(" a ")
        XCTAssertTrue(places.isEmpty)
        XCTAssertTrue(http.requests.isEmpty)
    }

    func testFailuresBecomeUnavailable() async {
        let http = StubHTTP()
        http.status = 400
        do {
            _ = try await PhotonClient(http: http).search("utrecht")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? PlaceSearchError, .unavailable)
        }
        http.status = 200
        http.failure = URLError(.networkConnectionLost)
        do {
            _ = try await PhotonClient(http: http).search("utrecht")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? PlaceSearchError, .unavailable)
        }
    }
}
