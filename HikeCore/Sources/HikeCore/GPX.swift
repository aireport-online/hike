import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct GPXDocument: Equatable, Sendable {
    public var name: String?
    public var points: [TrackPoint]

    public init(name: String?, points: [TrackPoint]) {
        self.name = name
        self.points = points
    }
}

public enum GPXError: Error, Equatable, LocalizedError {
    case unreadable
    case noTrack

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Dit bestand is geen leesbaar GPX-bestand."
        case .noTrack:
            return "Dit GPX-bestand bevat geen route of track."
        }
    }
}

public enum GPX {
    /// GPX 1.1 with a single track, readable by Komoot, Garmin, Wikiloc, OsmAnd and the like.
    public static func string(name: String, points: [TrackPoint], date: Date = Date()) -> String {
        let timestamp = ISO8601DateFormatter().string(from: date)
        let escapedName = escape(name)
        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"Hike\" xmlns=\"http://www.topografix.com/GPX/1/1\">",
            "  <metadata>",
            "    <name>\(escapedName)</name>",
            "    <time>\(timestamp)</time>",
            "  </metadata>",
            "  <trk>",
            "    <name>\(escapedName)</name>",
            "    <trkseg>"
        ]
        lines.reserveCapacity(points.count + 16)
        for point in points {
            let position = String(format: "lat=\"%.6f\" lon=\"%.6f\"", point.coordinate.latitude, point.coordinate.longitude)
            if let elevation = point.elevation {
                lines.append("      <trkpt \(position)><ele>\(String(format: "%.1f", elevation))</ele></trkpt>")
            } else {
                lines.append("      <trkpt \(position)/>")
            }
        }
        lines.append(contentsOf: ["    </trkseg>", "  </trk>", "</gpx>", ""])
        return lines.joined(separator: "\n")
    }

    public static func data(for route: HikeRoute) -> Data {
        Data(string(name: route.name, points: route.points, date: route.updatedAt).utf8)
    }

    /// Reads the track of a GPX file; falls back to its planned route (`rte`) when it has no track.
    public static func parse(_ data: Data) throws -> GPXDocument {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw GPXError.unreadable }
        let points = delegate.trackPoints.isEmpty ? delegate.routePoints : delegate.trackPoints
        guard points.count >= 2 else { throw GPXError.noTrack }
        let name = delegate.trackName ?? delegate.routeName ?? delegate.metadataName
        return GPXDocument(name: name, points: points)
    }

    /// A file name that is safe on every platform the GPX might be shared to.
    public static func fileName(for routeName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let cleaned = String(routeName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "Wandeling" : cleaned) + ".gpx"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var trackPoints: [TrackPoint] = []
        var routePoints: [TrackPoint] = []
        var trackName: String?
        var routeName: String?
        var metadataName: String?

        private var path: [String] = []
        private var text = ""
        private var pending: TrackPoint?

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let element = elementName.lowercased()
            path.append(element)
            text = ""
            if element == "trkpt" || element == "rtept" {
                if let latitude = attributeDict["lat"].flatMap(Double.init),
                   let longitude = attributeDict["lon"].flatMap(Double.init),
                   (-90...90).contains(latitude), (-180...180).contains(longitude) {
                    pending = TrackPoint(coordinate: Coordinate(latitude: latitude, longitude: longitude))
                } else {
                    pending = nil
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let element = elementName.lowercased()
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let parent = path.dropLast().last

            switch element {
            case "ele":
                if parent == "trkpt" || parent == "rtept" {
                    pending?.elevation = Double(value)
                }
            case "trkpt":
                if let pending { trackPoints.append(pending) }
                pending = nil
            case "rtept":
                if let pending { routePoints.append(pending) }
                pending = nil
            case "name" where !value.isEmpty:
                if parent == "trk", trackName == nil {
                    trackName = value
                } else if parent == "rte", routeName == nil {
                    routeName = value
                } else if parent == "metadata" {
                    metadataName = value
                }
            default:
                break
            }

            if !path.isEmpty { path.removeLast() }
            text = ""
        }
    }
}
