import Foundation

actor CatalogCache {
    struct CachedListing: Equatable, Sendable {
        let listing: CatalogListing
        let cachedAt: Date
    }

    private struct Store: Codable {
        let schemaVersion: Int
        var entries: [Entry]
    }

    private struct Entry: Codable {
        let query: String
        let version: PIUGameVersion
        let songs: [CatalogSong]
        let nextCursor: String?
        let total: Int
        let cachedAt: Date
    }

    private static let schemaVersion = 1
    private static let maximumEntries = 12

    private let directory: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("MyPIU", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("MyPIU", isDirectory: true)
    }

    func load(query: String, version: PIUGameVersion) -> CachedListing? {
        let query = normalizedQuery(query)
        guard let entry = readStore().entries.first(where: { $0.query == query && $0.version == version }) else {
            return nil
        }
        return CachedListing(
            listing: CatalogListing(songs: entry.songs, nextCursor: entry.nextCursor, total: entry.total),
            cachedAt: entry.cachedAt
        )
    }

    func save(_ listing: CatalogListing, query: String, version: PIUGameVersion, now: Date = Date()) throws {
        let query = normalizedQuery(query)
        var store = readStore()
        store.entries.removeAll { $0.query == query && $0.version == version }
        store.entries.append(
            Entry(
                query: query,
                version: version,
                songs: listing.songs,
                nextCursor: listing.nextCursor,
                total: listing.total,
                cachedAt: now
            )
        )
        store.entries.sort { $0.cachedAt > $1.cachedAt }
        store.entries = Array(store.entries.prefix(Self.maximumEntries))

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(store).write(to: cacheURL, options: .atomic)
    }

    private var cacheURL: URL {
        directory.appendingPathComponent("catalog-v\(Self.schemaVersion).json")
    }

    private func readStore() -> Store {
        guard
            let data = try? Data(contentsOf: cacheURL),
            let store = try? decoder.decode(Store.self, from: data),
            store.schemaVersion == Self.schemaVersion
        else {
            return Store(schemaVersion: Self.schemaVersion, entries: [])
        }
        return store
    }

    private func normalizedQuery(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .lowercased()
    }
}
