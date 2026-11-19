import Foundation

/// Public data has its own DTO and cache: account favorites/recommendations can never be written here.
struct PublicCatalogSong: Codable, Equatable, Sendable {
    let songKey: String
    let slug: String
    let title: String
    let artist: String
    let version: String
    let supportedVersions: [String]
    let imageUrl: String?
    let bpm: String?
    let chartSummary: [String]
    let folder: String?
    let folderPosition: Int?
    let series: String?
    let tags: [String]
    let isPremium: Bool

    var catalogSong: CatalogSong {
        CatalogSong(slug: slug, title: title, artist: artist, supportedVersions: supportedVersions,
                    imagePath: imageUrl, bpm: bpm, chartSummary: chartSummary, folder: folder,
                    folderPosition: folderPosition, series: series, tags: tags,
                    isPremium: isPremium, isFavorite: false, recommendedChartToken: nil)
    }
}

struct PublicCatalogSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedVersion: String
    let view: String
    let total: Int
    let filterOptions: CatalogFilterOptions
    let songs: [PublicCatalogSong]

    func validate(version: PIUGameVersion) throws {
        guard schemaVersion == 1, selectedVersion == version.rawValue, view == "supported",
              total == songs.count, Set(songs.map(\.slug)).count == total,
              songs.allSatisfy({ !$0.slug.isEmpty && !$0.songKey.isEmpty
                  && $0.supportedVersions.contains(version.rawValue) }) else {
            throw PublicCatalogError.invalidSnapshot
        }
    }

    var defaultPage: CatalogSearchPage {
        CatalogSearchPage(songs: songs.map(\.catalogSong).sorted(by: Self.defaultOrder),
                          nextCursor: nil, total: total, filterOptions: filterOptions)
    }

    // Matches the catalog's Mongo binary series-desc order, rather than the snapshot's slug order.
    static func defaultOrder(_ left: CatalogSong, _ right: CatalogSong) -> Bool {
        let ranks = ["1st", "nx", "fiesta", "prime", "prime2", "xx", "phoenix", "phoenix2"]
        func rank(_ value: String?) -> Int {
            ranks.firstIndex(of: (value ?? "").lowercased().replacingOccurrences(of: " ", with: "")) ?? -1
        }
        if rank(left.series) != rank(right.series) { return rank(left.series) > rank(right.series) }
        func compare(_ a: String?, _ b: String?) -> Int {
            if a == nil { return b == nil ? 0 : -1 }
            if b == nil { return 1 }
            let a = Array(a!.unicodeScalars.map(\.value)), b = Array(b!.unicodeScalars.map(\.value))
            return a == b ? 0 : (a.lexicographicallyPrecedes(b) ? -1 : 1)
        }
        let series = compare(left.series, right.series)
        if series != 0 { return series > 0 }
        if left.folderPosition != right.folderPosition {
            guard let a = left.folderPosition else { return false }
            guard let b = right.folderPosition else { return true }
            return a > b
        }
        let title = compare(left.title, right.title)
        if title != 0 { return title > 0 }
        return compare(left.artist, right.artist) > 0
    }
}

enum PublicCatalogError: LocalizedError, Equatable {
    case unavailable
    case invalidSnapshot
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable: "The catalog service is not available yet."
        case .invalidSnapshot: "The catalog response was incomplete. Please try again."
        case .http: "The catalog could not be refreshed. Please try again."
        }
    }
}

actor PublicCatalogStore {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let shared = PublicCatalogStore()
    private struct Entry: Codable, Sendable {
        let snapshot: PublicCatalogSnapshot
        let etag: String?
    }
    private let directory: URL
    private let baseURL: URL
    private let transport: Transport
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<PublicCatalogSnapshot, Error>] = [:]

    init(directory: URL? = nil, baseURL: URL = MyPIUAPIClient.productionBaseURL,
         transport: Transport? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyPIU/public-catalog-v1", isDirectory: true)
        self.baseURL = baseURL
        if let transport { self.transport = transport }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 45
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            self.transport = { request in
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw PublicCatalogError.invalidSnapshot }
                return (data, response)
            }
        }
    }

    func cached(version: PIUGameVersion) -> PublicCatalogSnapshot? {
        readEntry(version: version)?.snapshot
    }

    /// Coalesces Home artwork and Songs requests. Cancellation of one waiter doesn't cancel other readers.
    func refresh(version: PIUGameVersion) async throws -> PublicCatalogSnapshot {
        if let task = inFlight[version.rawValue] { return try await task.value }
        let task = Task { try await self.fetch(version: version) }
        inFlight[version.rawValue] = task
        defer { inFlight[version.rawValue] = nil }
        return try await task.value
    }

    private func fetch(version: PIUGameVersion) async throws -> PublicCatalogSnapshot {
        let cached = readEntry(version: version)
        var request = URLRequest(url: baseURL.appendingPathComponent("api/catalog/v1/\(version.rawValue)"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MyPIU-iOS/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue(cached?.etag, forHTTPHeaderField: "If-None-Match")
        let (data, response) = try await transport(request)
        if response.statusCode == 304 {
            guard let cached else { throw PublicCatalogError.invalidSnapshot }
            return cached.snapshot
        }
        if response.statusCode == 404 { throw PublicCatalogError.unavailable }
        guard response.statusCode == 200 else { throw PublicCatalogError.http(response.statusCode) }
        guard data.count <= 8 * 1024 * 1024 else { throw PublicCatalogError.invalidSnapshot }
        let snapshot = try JSONDecoder().decode(PublicCatalogSnapshot.self, from: data)
        try snapshot.validate(version: version)
        let entry = Entry(snapshot: snapshot, etag: response.value(forHTTPHeaderField: "ETag"))
        entries[version.rawValue] = entry
        // A read-only/full disk must not discard a successful network response.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(entry) { try? encoded.write(to: file(version), options: .atomic) }
        return snapshot
    }

    private func readEntry(version: PIUGameVersion) -> Entry? {
        if let entry = entries[version.rawValue] { return entry }
        guard let size = try? file(version).resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: file(version)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              (try? entry.snapshot.validate(version: version)) != nil else { return nil }
        entries[version.rawValue] = entry
        return entry
    }

    private func file(_ version: PIUGameVersion) -> URL {
        directory.appendingPathComponent("\(version.rawValue).json")
    }
}
