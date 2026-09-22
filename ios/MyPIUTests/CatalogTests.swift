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
