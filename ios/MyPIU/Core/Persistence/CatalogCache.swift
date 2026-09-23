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
        let scope: String
        let query: String
        let version: PIUGameVersion
        var songs: [CatalogSong]
        let nextCursor: String?
        var total: Int
        let filterOptions: CatalogFilterOptions
        let cachedAt: Date
    }

    private static let schemaVersion = 3
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

    func load(query: String, version: PIUGameVersion, scope: String) -> CachedListing? {
        let query = normalizedQuery(query)
        guard let entry = readStore().entries.first(where: {
            $0.scope == scope && $0.query == query && $0.version == version
        }) else {
            return nil
        }
        return CachedListing(
            listing: CatalogListing(
                songs: entry.songs,
                nextCursor: entry.nextCursor,
                total: entry.total,
                filterOptions: entry.filterOptions
            ),
            cachedAt: entry.cachedAt
        )
    }

    func save(
        _ listing: CatalogListing,
        query: String,
        version: PIUGameVersion,
        scope: String,
        now: Date = Date()
    ) throws {
        let query = normalizedQuery(query)
        var store = readStore()
        store.entries.removeAll { $0.scope == scope && $0.query == query && $0.version == version }
        store.entries.append(
            Entry(
                scope: scope,
                query: query,
                version: version,
                songs: listing.songs,
                nextCursor: listing.nextCursor,
                total: listing.total,
                filterOptions: listing.filterOptions,
                cachedAt: now
            )
        )
        store.entries.sort { $0.cachedAt > $1.cachedAt }
        store.entries = Array(store.entries.prefix(Self.maximumEntries))

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(store).write(to: cacheURL, options: .atomic)
    }

    func setFavorite(
        _ isFavorite: Bool,
        forSlug slug: String,
        version: PIUGameVersion,
        scope: String
    ) throws {
        var store = readStore()
        var didChange = false

        if isFavorite {
            let previousCount = store.entries.count
            store.entries.removeAll {
                $0.scope == scope
                    && $0.version == version
                    && $0.query == "favorites"
            }
            didChange = store.entries.count != previousCount
        }

        for entryIndex in store.entries.indices
        where store.entries[entryIndex].scope == scope
            && store.entries[entryIndex].version == version {
            guard let songIndex = store.entries[entryIndex].songs.firstIndex(where: { $0.slug == slug }) else {
                continue
            }
            if !isFavorite, store.entries[entryIndex].query == "favorites" {
                store.entries[entryIndex].songs.remove(at: songIndex)
                store.entries[entryIndex].total = max(0, store.entries[entryIndex].total - 1)
            } else {
                store.entries[entryIndex].songs[songIndex].isFavorite = isFavorite
            }
            didChange = true
        }

        guard didChange else { return }
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
