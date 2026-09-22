import XCTest
@testable import MyPIU

final class CatalogTests: XCTestCase {
    func testCatalogPageDecodesPublicSearchResponse() throws {
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))

        XCTAssertEqual(page.total, 654)
        XCTAssertEqual(page.nextCursor, "Mg")
        XCTAssertEqual(page.songs.first?.title, "BATTLE NO.1")
        XCTAssertEqual(page.songs.first?.chartSummary, ["S10", "S19", "D20", "C2"])
        XCTAssertTrue(page.songs.first?.isPremium == true)
    }

    func testCatalogURLsResolveAgainstProductionOrigin() throws {
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        let song = try XCTUnwrap(page.songs.first)

        XCTAssertEqual(song.imageURL?.absoluteString, "https://mypiu.austin.kim/assets/piu/song.png")
        XCTAssertEqual(song.websiteURL?.absoluteString, "https://mypiu.austin.kim/songs/battle-no-1")
    }

    func testChartGroupsKeepModesSeparate() throws {
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        let song = try XCTUnwrap(page.songs.first)

        XCTAssertEqual(song.charts(for: .single), ["S10", "S19"])
        XCTAssertEqual(song.charts(for: .double), ["D20"])
        XCTAssertEqual(song.charts(for: .coop), ["C2"])
    }

    func testPaginationDeduplicatesSongsAndStopsRepeatedCursor() throws {
        let first = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        var listing = CatalogListing()
        listing.replace(with: first)
        listing.append(first, requestedCursor: "Mg")

        XCTAssertEqual(listing.songs.map(\.slug), ["battle-no-1"])
        XCTAssertFalse(listing.hasMore)
    }

    func testCatalogCacheSeparatesVersionsAndNormalizesQueries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        var listing = CatalogListing()
        listing.replace(with: page)
        let cachedAt = Date(timeIntervalSince1970: 1_790_035_200)

        try await cache.save(listing, query: "  BATTLE  ", version: .phoenix2, now: cachedAt)

        let cached = await cache.load(query: "battle", version: .phoenix2)
        let otherVersion = await cache.load(query: "battle", version: .phoenix)
        XCTAssertEqual(cached?.listing, listing)
        XCTAssertEqual(cached?.cachedAt, cachedAt)
        XCTAssertNil(otherVersion)
    }

    func testCatalogCacheKeepsOnlyTheTwelveMostRecentListings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        var listing = CatalogListing()
        listing.replace(with: page)

        for index in 0..<13 {
            try await cache.save(
                listing,
                query: "query-\(index)",
                version: .phoenix2,
                now: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let oldest = await cache.load(query: "query-0", version: .phoenix2)
        let newest = await cache.load(query: "query-12", version: .phoenix2)
        XCTAssertNil(oldest)
        XCTAssertEqual(newest?.listing.songs.first?.slug, "battle-no-1")
    }

    private static let fixture = """
    {
      "songs": [
        {
          "slug": "battle-no-1",
          "title": "BATTLE NO.1",
          "artist": "TANO*C Sound Team",
          "supportedVersions": ["phoenix2", "phoenix"],
          "imageUrl": "/assets/piu/song.png",
          "bpm": "200",
          "chartSummary": ["S10", "S19", "D20", "C2"],
          "folder": "ORIGINAL",
          "series": "XX",
          "tags": ["intense"],
          "isPremium": true,
          "recommendedChartToken": "S19"
        }
      ],
      "nextCursor": "Mg",
      "total": 654,
      "filterOptions": {"folders": [], "series": [], "levels": [], "charts": []}
    }
    """
}
