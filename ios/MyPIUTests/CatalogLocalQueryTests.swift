import XCTest
@testable import MyPIU

final class CatalogLocalQueryTests: XCTestCase {
    private struct Fixture: Decodable {
        let snapshot: PublicCatalogSnapshot
        let cases: [Case]
        struct Case: Decodable {
            let name: String
            let query: String
            let folders: [String]?
            let series: [String]?
            let levels: [String]?
            let charts: [String]?
            let levelMode: String
            let sortBy: CatalogSortOption
            let sortDirection: CatalogSortDirection
            let expectedSlugs: [String]
            let expectedOptions: CatalogFilterOptions
            var filters: CatalogFilters {
                CatalogFilters(folders: folders ?? [], series: series ?? [], levels: levels ?? [], charts: charts ?? [],
                               levelMode: levelMode == "and" ? .and : .or, sortBy: sortBy, sortDirection: sortDirection)
            }
        }
    }
    private func fixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: data("catalog-local-query"))
    }
    private func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json", subdirectory: "test-fixtures"))
        return try Data(contentsOf: url)
    }

    func testSharedWebParityForLiteralTextLevelsIntersectionsAndEverySort() throws {
        let fixture = try fixture()
        XCTAssertEqual(fixture.cases.count, 42)
        for item in fixture.cases {
            let page = try CatalogLocalQuery.page(snapshot: fixture.snapshot, overlay: nil, query: item.query, filters: item.filters)
            XCTAssertEqual(page.songs.map(\.slug), item.expectedSlugs, item.name)
            XCTAssertEqual(page.filterOptions, item.expectedOptions, item.name)
            XCTAssertEqual(page.total, page.songs.count)
            XCTAssertNil(page.nextCursor)
        }
    }

    func testAllSixteenOrderedRecommendationModesKeepIdentityAndFavorites() throws {
        let snapshot = try fixture().snapshot
        let selections: [[String]] = [[], ["singles"], ["doubles"], ["co-op"], ["singles", "doubles"], ["doubles", "singles"],
            ["singles", "co-op"], ["co-op", "singles"], ["doubles", "co-op"], ["co-op", "doubles"],
            ["singles", "doubles", "co-op"], ["singles", "co-op", "doubles"], ["doubles", "singles", "co-op"],
            ["doubles", "co-op", "singles"], ["co-op", "singles", "doubles"], ["co-op", "doubles", "singles"]]
        let expectedKeys = ["all", "S", "D", "C", "SD", "DS", "SC", "CS", "DC", "CD", "SDC", "SCD", "DSC", "DCS", "CSD", "CDS"]
        let recommendations = Dictionary(uniqueKeysWithValues: expectedKeys.map { ($0, Optional("hint-\($0)")) })
        let overlay = MobileCatalogOverlay(schemaVersion: 1, version: "phoenix2", favoriteSlugs: ["all"], recommendations: ["all": recommendations])
        for (charts, key) in zip(selections, expectedKeys) {
            XCTAssertEqual(CatalogLocalQuery.modeKey(charts), key)
            let page = try CatalogLocalQuery.page(snapshot: snapshot, overlay: overlay, query: "", filters: CatalogFilters(charts: charts))
            let song = try XCTUnwrap(page.songs.first { $0.slug == "all" })
            XCTAssertTrue(song.isFavorite)
            XCTAssertEqual(song.recommendedChartToken, "hint-\(key)")
        }
        XCTAssertEqual(CatalogLocalQuery.modeKey(["doubles", "doubles", "singles"]), "DS")
        XCTAssertTrue(snapshot.defaultPage.songs.allSatisfy { !$0.isFavorite && $0.recommendedChartToken == nil })
        XCTAssertThrowsError(try CatalogLocalQuery.page(snapshot: snapshot,
            overlay: MobileCatalogOverlay(schemaVersion: 1, version: "phoenix", favoriteSlugs: [], recommendations: [:]), query: "", filters: .empty))
    }

    func testSharedAliasFixturePreservesOfficialTitlesAndOtherArtists() throws {
        struct AliasFixture: Decodable {
            struct Song: Decodable { let title: String; let artist: String; let slug: String }
            struct Case: Decodable { let query: String; let expectedSlugs: [String] }
            let songs: [Song]; let cases: [Case]
        }
        let alias = try JSONDecoder().decode(AliasFixture.self, from: data("catalog-search-aliases"))
        let songs = alias.songs.map { PublicCatalogSong(songKey: $0.slug, slug: $0.slug, title: $0.title, artist: $0.artist,
            version: "phoenix2", supportedVersions: ["phoenix2"], imageUrl: nil, bpm: nil, chartSummary: [], folder: nil,
            folderPosition: nil, series: nil, tags: [], isPremium: false) }
        let snapshot = PublicCatalogSnapshot(schemaVersion: 1, selectedVersion: "phoenix2", view: "supported", total: songs.count, filterOptions: .empty, songs: songs)
        for item in alias.cases {
            let page = try CatalogLocalQuery.page(snapshot: snapshot, overlay: nil, query: item.query, filters: .empty)
            XCTAssertEqual(Set(page.songs.map(\.slug)), Set(item.expectedSlugs), item.query)
            for song in page.songs { XCTAssertEqual(song.title, songs.first { $0.slug == song.slug }?.title) }
        }
        for feed in ["favorites", " RECOMMENDATION ", "Recent"] { XCTAssertFalse(CatalogLocalQuery.isOrdinary(feed)) }
        XCTAssertTrue(CatalogLocalQuery.isOrdinary("recent remix"))
    }
}
