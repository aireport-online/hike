import MapKit
import UIKit

/// Map tiles from a `TileSource`, kept on disk so areas viewed before still show without a
/// connection, and stretched from the deepest available level when zooming in further.
final class CachedTileOverlay: MKTileOverlay {
    private let source: TileSource

    /// How many levels past the server's deepest zoom the map may still be magnified.
    private static let overzoomLevels = 3

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MapTiles", isDirectory: true)
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            directory: directory
        )
        // Prefer a stored tile over the network: maps change slowly, and it keeps the load on the
        // volunteer-run tile servers low.
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpAdditionalHeaders = ["User-Agent": "Hike-iOS/1.0"]
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    init(source: TileSource, replacesMap: Bool) {
        self.source = source
        super.init(urlTemplate: nil)
        canReplaceMapContent = replacesMap
        minimumZ = 0
        maximumZ = source.maxZoom + Self.overzoomLevels
        tileSize = CGSize(width: 256, height: 256)
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let nativeZ = min(path.z, source.maxZoom)
        let shift = path.z - nativeZ
        guard let url = source.url(x: path.x >> shift, y: path.y >> shift, z: nativeZ) else {
            result(nil, URLError(.badURL))
            return
        }
        let task = Self.session.dataTask(with: url) { data, response, error in
            guard let data, error == nil, (response as? HTTPURLResponse)?.statusCode == 200 else {
                result(nil, error ?? URLError(.badServerResponse))
                return
            }
            if shift == 0 {
                result(data, nil)
            } else if let magnified = Self.magnify(data, shift: shift, x: path.x, y: path.y) {
                result(magnified, nil)
            } else {
                result(nil, URLError(.cannotDecodeContentData))
            }
        }
        task.resume()
    }

    /// Cuts the part of a parent tile that covers the requested deeper tile and scales it up.
    private static func magnify(_ data: Data, shift: Int, x: Int, y: Int) -> Data? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let divisions = 1 << shift
        let side = CGFloat(image.width) / CGFloat(divisions)
        let rect = CGRect(
            x: CGFloat(x & (divisions - 1)) * side,
            y: CGFloat(y & (divisions - 1)) * side,
            width: side,
            height: side
        )
        guard let cropped = image.cropping(to: rect) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            context.cgContext.interpolationQuality = .high
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
