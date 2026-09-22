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
}

struct CatalogListing: Equatable, Sendable {
    private(set) var songs: [CatalogSong] = []
    private(set) var nextCursor: String?
    private(set) var total = 0

    var hasMore: Bool { nextCursor != nil }

    init(songs: [CatalogSong] = [], nextCursor: String? = nil, total: Int = 0) {
        self.songs = songs
        self.nextCursor = nextCursor
        self.total = total
    }

    mutating func replace(with page: CatalogSearchPage) {
        songs = page.songs
        nextCursor = page.nextCursor
        total = page.total
    }

    mutating func append(_ page: CatalogSearchPage, requestedCursor: String) {
        var knownSlugs = Set(songs.map(\.slug))
        songs.append(contentsOf: page.songs.filter { knownSlugs.insert($0.slug).inserted })
        nextCursor = page.nextCursor == requestedCursor ? nil : page.nextCursor
        total = page.total
    }

    @discardableResult
    mutating func setFavorite(_ isFavorite: Bool, forSlug slug: String) -> Bool {
        guard let index = songs.firstIndex(where: { $0.slug == slug }) else { return false }
        songs[index].isFavorite = isFavorite
        return true
    }
}

private func resolvedMyPIUURL(_ value: String?) -> URL? {
    guard let value, !value.isEmpty else { return nil }
    return URL(string: value, relativeTo: MyPIUAPIClient.productionBaseURL)?.absoluteURL
}
