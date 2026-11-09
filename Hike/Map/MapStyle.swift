import Foundation

/// A raster tile server in the usual z/x/y scheme.
struct TileSource: Equatable {
    let id: String
    /// URL with `{s}`, `{z}`, `{x}` and `{y}` placeholders.
    let template: String
    let subdomains: [String]
    /// Deepest zoom level the server has tiles for.
    let maxZoom: Int

    func url(x: Int, y: Int, z: Int) -> URL? {
        var text = template
            .replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(y))
        if !subdomains.isEmpty {
            // Chosen by tile rather than at random, so a tile always has the same URL and
            // is found again in the cache.
            text = text.replacingOccurrences(of: "{s}", with: subdomains[abs(x + y) % subdomains.count])
        }
        return URL(string: text)
    }

    static let openTopoMap = TileSource(
        id: "opentopomap",
        template: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
        subdomains: ["a", "b", "c"],
        maxZoom: 17
    )

    static let openStreetMap = TileSource(
        id: "openstreetmap",
        template: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
        subdomains: [],
        maxZoom: 19
    )

    /// Transparent overlay with signposted hiking routes: GR paths, E-paths, national and local trails.
    static let waymarkedHiking = TileSource(
        id: "waymarked-hiking",
        template: "https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png",
        subdomains: [],
        maxZoom: 17
    )
}

enum MapStyle: String, CaseIterable, Identifiable {
    case topo
    case street
    case apple
    case satellite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topo: return "Topografisch"
        case .street: return "OpenStreetMap"
        case .apple: return "Apple Kaarten"
        case .satellite: return "Satelliet"
        }
    }

    var subtitle: String {
        switch self {
        case .topo: return "Hoogtelijnen, paden en hutten"
        case .street: return "Gedetailleerde paden, ook ver ingezoomd"
        case .apple: return "Snel en rustig kaartbeeld"
        case .satellite: return "Luchtfoto's met plaatsnamen"
        }
    }

    /// Tiles that replace Apple's map, or nil when Apple's own map is the base.
    var tileSource: TileSource? {
        switch self {
        case .topo: return .openTopoMap
        case .street: return .openStreetMap
        case .apple, .satellite: return nil
        }
    }

    func attribution(showsTrails: Bool) -> String? {
        var parts: [String] = []
        switch self {
        case .topo:
            parts.append("© OpenStreetMap, SRTM · OpenTopoMap (CC-BY-SA)")
        case .street:
            parts.append("© OpenStreetMap-bijdragers")
        case .apple, .satellite:
            break
        }
        if showsTrails {
            parts.append("Routes: Waymarked Trails")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
