import Foundation

enum CatalogChartMode: String, CaseIterable, Identifiable, Sendable {
    case single
    case double
    case coop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "Singles"
        case .double: "Doubles"
        case .coop: "Co-op"
        }
    }

    func contains(_ chartToken: String) -> Bool {
        switch self {
        case .single: chartToken.uppercased().hasPrefix("S")
        case .double: chartToken.uppercased().hasPrefix("D")
        case .coop: chartToken.uppercased().hasPrefix("C")
        }
    }
}

struct CatalogSong: Codable, Equatable, Hashable, Identifiable, Sendable {
    let slug: String
    let title: String
    let artist: String
    let supportedVersions: [String]
    let imagePath: String?
    let bpm: String?
    let chartSummary: [String]
    let folder: String?
    let series: String?
    let tags: [String]
    let isPremium: Bool
    var isFavorite: Bool
    let recommendedChartToken: String?

    var id: String { slug }

    var imageURL: URL? {
        resolvedMyPIUURL(imagePath)
    }

    var websiteURL: URL? {
        resolvedMyPIUURL("/songs/\(slug)")
    }

    func charts(for mode: CatalogChartMode) -> [String] {
        chartSummary.filter(mode.contains)
    }

    private enum CodingKeys: String, CodingKey {
        case slug
        case title
        case artist
        case supportedVersions
        case imagePath = "imageUrl"
        case bpm
        case chartSummary
        case folder
        case series
        case tags
        case isPremium
        case isFavorite
        case recommendedChartToken
    }
}

struct CatalogSearchPage: Codable, Equatable, Sendable {
    let songs: [CatalogSong]
    let nextCursor: String?
    let total: Int
    let filterOptions: CatalogFilterOptions

    init(
        songs: [CatalogSong],
        nextCursor: String?,
        total: Int,
        filterOptions: CatalogFilterOptions = .empty
    ) {
        self.songs = songs
        self.nextCursor = nextCursor
        self.total = total
        self.filterOptions = filterOptions
    }

    private enum CodingKeys: String, CodingKey {
        case songs
        case nextCursor
        case total
        case filterOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        songs = try container.decode([CatalogSong].self, forKey: .songs)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        total = try container.decode(Int.self, forKey: .total)
        filterOptions = try container.decodeIfPresent(CatalogFilterOptions.self, forKey: .filterOptions) ?? .empty
    }
}

struct CatalogFilterOptions: Codable, Equatable, Sendable {
    let folders: [String]
    let series: [String]
    let levels: [String]
    let charts: [String]

    static let empty = CatalogFilterOptions(folders: [], series: [], levels: [], charts: [])
}

enum CatalogLevelMode: String, CaseIterable, Identifiable, Sendable {
    case and
    case or

    var id: String { rawValue }
}

enum CatalogSortOption: String, CaseIterable, Codable, Identifiable, Sendable {
    case series
    case title
    case artist
    case folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .series: "Series"
        case .title: "Title"
        case .artist: "Artist"
        case .folder: "Folder"
        }
    }
}

enum CatalogSortDirection: String, CaseIterable, Codable, Identifiable, Sendable {
    case ascending = "asc"
    case descending = "desc"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }
}

struct CatalogFilters: Equatable, Hashable, Sendable {
    var folders: [String] = []
    var series: [String] = []
    var levels: [String] = []
    var charts: [String] = []
    var levelMode: CatalogLevelMode = .and
    var sortBy: CatalogSortOption = .series
    var sortDirection: CatalogSortDirection = .descending

    static let empty = CatalogFilters()

    var isEmpty: Bool {
        folders.isEmpty && series.isEmpty && levels.isEmpty && charts.isEmpty
    }

    var selectionCount: Int {
        folders.count + series.count + levels.count + charts.count
    }

    var usesDefaultSort: Bool {
        sortBy == .series && sortDirection == .descending
    }

    mutating func clearSelections() {
        folders = []
        series = []
        levels = []
        charts = []
        levelMode = .and
    }
}

struct CatalogListing: Equatable, Sendable {
    private(set) var songs: [CatalogSong] = []
    private(set) var nextCursor: String?
    private(set) var total = 0
    private(set) var filterOptions: CatalogFilterOptions = .empty

    var hasMore: Bool { nextCursor != nil }

    init(
        songs: [CatalogSong] = [],
        nextCursor: String? = nil,
        total: Int = 0,
        filterOptions: CatalogFilterOptions = .empty
    ) {
        self.songs = songs
        self.nextCursor = nextCursor
        self.total = total
        self.filterOptions = filterOptions
    }

    mutating func replace(with page: CatalogSearchPage) {
        songs = page.songs
        nextCursor = page.nextCursor
        total = page.total
        filterOptions = page.filterOptions
    }

    mutating func append(_ page: CatalogSearchPage, requestedCursor: String) {
        var knownSlugs = Set(songs.map(\.slug))
        songs.append(contentsOf: page.songs.filter { knownSlugs.insert($0.slug).inserted })
        nextCursor = page.nextCursor == requestedCursor ? nil : page.nextCursor
        total = page.total
        filterOptions = page.filterOptions
    }

    @discardableResult
    mutating func setFavorite(_ isFavorite: Bool, forSlug slug: String) -> Bool {
        guard let index = songs.firstIndex(where: { $0.slug == slug }) else { return false }
        songs[index].isFavorite = isFavorite
        return true
    }

    @discardableResult
    mutating func removeSong(slug: String) -> Bool {
        guard let index = songs.firstIndex(where: { $0.slug == slug }) else { return false }
        songs.remove(at: index)
        total = max(0, total - 1)
        return true
    }
}

private func resolvedMyPIUURL(_ value: String?) -> URL? {
    guard let value, !value.isEmpty else { return nil }
    return URL(string: value, relativeTo: MyPIUAPIClient.productionBaseURL)?.absoluteURL
}
