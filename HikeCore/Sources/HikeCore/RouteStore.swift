import Foundation

/// Saved routes as one JSON file each, in a directory of the app's documents.
public final class RouteStore {
    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    /// All saved routes, most recently changed first. Files that cannot be read are skipped
    /// rather than hiding every other route.
    public func all() -> [HikeRoute] {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> HikeRoute? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? Self.decoder.decode(HikeRoute.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ route: HikeRoute) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(route)
        try data.write(to: url(for: route.id), options: .atomic)
    }

    public func delete(id: UUID) throws {
        let url = url(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
