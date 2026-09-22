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
        XCTAssertTrue(page.songs.first?.isFavorite == true)
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

    func testCatalogListingUpdatesFavoriteBySlug() throws {
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        var listing = CatalogListing()
        listing.replace(with: page)

        XCTAssertTrue(listing.setFavorite(false, forSlug: "battle-no-1"))
        XCTAssertFalse(listing.songs.first?.isFavorite == true)
        XCTAssertFalse(listing.setFavorite(false, forSlug: "missing-song"))
    }

    func testCatalogCacheSeparatesVersionsAndNormalizesQueries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        var listing = CatalogListing()
        listing.replace(with: page)
        let cachedAt = Date(timeIntervalSince1970: 1_790_035_200)

        try await cache.save(
            listing,
            query: "  BATTLE  ",
            version: .phoenix2,
            scope: "account:one",
            now: cachedAt
        )

        let cached = await cache.load(query: "battle", version: .phoenix2, scope: "account:one")
        let otherVersion = await cache.load(query: "battle", version: .phoenix, scope: "account:one")
        let otherAccount = await cache.load(query: "battle", version: .phoenix2, scope: "account:two")
        XCTAssertEqual(cached?.listing, listing)
        XCTAssertEqual(cached?.cachedAt, cachedAt)
        XCTAssertNil(otherVersion)
        XCTAssertNil(otherAccount)
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
                scope: "public",
                now: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let oldest = await cache.load(query: "query-0", version: .phoenix2, scope: "public")
        let newest = await cache.load(query: "query-12", version: .phoenix2, scope: "public")
        XCTAssertNil(oldest)
        XCTAssertEqual(newest?.listing.songs.first?.slug, "battle-no-1")
    }

    func testCatalogCachePropagatesFavoriteWithinAccountAndVersion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        var listing = CatalogListing()
        listing.replace(with: page)
        try await cache.save(listing, query: "one", version: .phoenix2, scope: "account:one")
        try await cache.save(listing, query: "two", version: .phoenix2, scope: "account:one")
        try await cache.save(listing, query: "one", version: .phoenix, scope: "account:one")
        try await cache.save(listing, query: "one", version: .phoenix2, scope: "account:two")

        try await cache.setFavorite(
            false,
            forSlug: "battle-no-1",
            version: .phoenix2,
            scope: "account:one"
        )

        let firstQuery = await cache.load(query: "one", version: .phoenix2, scope: "account:one")
        let secondQuery = await cache.load(query: "two", version: .phoenix2, scope: "account:one")
        let otherVersion = await cache.load(query: "one", version: .phoenix, scope: "account:one")
        let otherAccount = await cache.load(query: "one", version: .phoenix2, scope: "account:two")
        XCTAssertEqual(firstQuery?.listing.songs.first?.isFavorite, false)
        XCTAssertEqual(secondQuery?.listing.songs.first?.isFavorite, false)
        XCTAssertEqual(otherVersion?.listing.songs.first?.isFavorite, true)
        XCTAssertEqual(otherAccount?.listing.songs.first?.isFavorite, true)
    }

    @MainActor
    func testLoadedCatalogSkipsDuplicateMountRequestButReloadsForAnotherAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        let catalog = SongCatalogModel(cache: CatalogCache(directory: directory))
        var requestCount = 0
        let search: SongCatalogModel.CatalogSearch = { _, _, _ in
            requestCount += 1
            return page
        }

        await catalog.loadIfNeeded(
            query: "battle",
            version: .phoenix2,
            cacheScope: "account:one",
            debounce: false,
            using: search
        )
        await catalog.loadIfNeeded(
            query: "battle",
            version: .phoenix2,
            cacheScope: "account:one",
            debounce: false,
            using: search
        )
        XCTAssertEqual(requestCount, 1)

        await catalog.loadIfNeeded(
            query: "battle",
            version: .phoenix2,
            cacheScope: "account:two",
            debounce: false,
            using: search
        )
        XCTAssertEqual(requestCount, 2)
    }

    @MainActor
    func testCanceledDebounceDoesNotMarkTheNewQueryAsLoaded() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        let catalog = SongCatalogModel(cache: CatalogCache(directory: directory))
        var requestedQueries: [String] = []
        let search: SongCatalogModel.CatalogSearch = { query, _, _ in
            requestedQueries.append(query)
            return page
        }

        await catalog.loadIfNeeded(
            query: "old",
            version: .phoenix2,
            debounce: false,
            using: search
        )
        let debounced = Task { @MainActor in
            await catalog.reload(
                query: "new",
                version: .phoenix2,
                debounce: true,
                using: search
            )
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        debounced.cancel()
        await debounced.value

        await catalog.loadIfNeeded(
            query: "new",
            version: .phoenix2,
            debounce: false,
            using: search
        )
        XCTAssertEqual(requestedQueries, ["old", "new"])
    }

    @MainActor
    func testFavoriteUpdateUsesServerStateAndPersistsOnlyAfterSuccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        let catalog = SongCatalogModel(cache: cache)
        await catalog.loadIfNeeded(
            query: "battle",
            version: .phoenix2,
            cacheScope: "account:one",
            debounce: false,
            using: { _, _, _ in page }
        )
        let song = try XCTUnwrap(catalog.listing.songs.first)
        var request: (slug: String, saved: Bool, version: PIUGameVersion)?

        await catalog.setFavorite(false, for: song) { slug, saved, version in
            request = (slug, saved, version)
            return false
        }

        XCTAssertEqual(request?.slug, "battle-no-1")
        XCTAssertEqual(request?.saved, false)
        XCTAssertEqual(request?.version, .phoenix2)
        XCTAssertEqual(catalog.listing.songs.first?.isFavorite, false)
        XCTAssertNil(catalog.favoriteError)
        let cached = await cache.load(
            query: "battle",
            version: .phoenix2,
            scope: "account:one"
        )
        XCTAssertEqual(cached?.listing.songs.first?.isFavorite, false)
    }

    @MainActor
    func testSuccessfulFavoriteUpdateSurvivesQueryReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        let catalog = SongCatalogModel(cache: cache)
        let search: SongCatalogModel.CatalogSearch = { _, _, _ in page }
        await catalog.loadIfNeeded(
            query: "battle",
            version: .phoenix2,
            cacheScope: "account:one",
            debounce: false,
            using: search
        )
        let song = try XCTUnwrap(catalog.listing.songs.first)

        await catalog.setFavorite(false, for: song) { _, _, _ in
            await catalog.reload(
                query: "another query",
                version: .phoenix2,
                cacheScope: "account:one",
                debounce: false,
                using: search
            )
            return false
        }

        XCTAssertEqual(catalog.listing.songs.first?.isFavorite, false)
        let originalQuery = await cache.load(
            query: "battle",
            version: .phoenix2,
            scope: "account:one"
        )
        let currentQuery = await cache.load(
            query: "another query",
            version: .phoenix2,
            scope: "account:one"
        )
        XCTAssertEqual(originalQuery?.listing.songs.first?.isFavorite, false)
        XCTAssertEqual(currentQuery?.listing.songs.first?.isFavorite, false)
    }

    @MainActor
    func testStaleReloadCannotOverwriteConfirmedFavorite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        let catalog = SongCatalogModel(cache: cache)
        await catalog.loadIfNeeded(
            query: "battle",
            version: .phoenix2,
            cacheScope: "account:one",
            debounce: false,
            using: { _, _, _ in page }
        )
        let song = try XCTUnwrap(catalog.listing.songs.first)
        let favoriteGate = TestGate<Bool>()
        let reloadGate = TestGate<CatalogSearchPage>()

        let favoriteTask = Task { @MainActor in
            await catalog.setFavorite(false, for: song) { _, _, _ in
                await favoriteGate.wait()
            }
        }
        await favoriteGate.waitUntilOccupied()
        let reloadTask = Task { @MainActor in
            await catalog.reload(
                query: "refreshed",
                version: .phoenix2,
                cacheScope: "account:one",
                debounce: false,
                using: { _, _, _ in await reloadGate.wait() }
            )
        }
        await reloadGate.waitUntilOccupied()

        await favoriteGate.open(false)
        await favoriteTask.value
        await reloadGate.open(page)
        await reloadTask.value

        XCTAssertEqual(catalog.listing.songs.first?.isFavorite, false)
        let cached = await cache.load(
            query: "refreshed",
            version: .phoenix2,
            scope: "account:one"
        )
        XCTAssertEqual(cached?.listing.songs.first?.isFavorite, false)
    }

    @MainActor
    func testConfirmedFavoriteCanSynchronizeSeparateCatalogModels() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        let firstCatalog = SongCatalogModel(cache: cache)
        let secondCatalog = SongCatalogModel(cache: cache)
        let search: SongCatalogModel.CatalogSearch = { _, _, _ in page }
        await firstCatalog.loadIfNeeded(
            query: "battle",
            version: .phoenix2,
            cacheScope: "account:one",
            debounce: false,
            using: search
        )
        await secondCatalog.loadIfNeeded(
            query: "recommendation",
            version: .phoenix2,
            cacheScope: "account:one",
            debounce: false,
            using: search
        )

        await firstCatalog.applyConfirmedFavorite(
            false,
            slug: "battle-no-1",
            version: .phoenix2,
            cacheScope: "account:one"
        )
        await secondCatalog.applyConfirmedFavorite(
            false,
            slug: "battle-no-1",
            version: .phoenix2,
            cacheScope: "account:one"
        )

        XCTAssertEqual(firstCatalog.listing.songs.first?.isFavorite, false)
        XCTAssertEqual(secondCatalog.listing.songs.first?.isFavorite, false)
    }

    @MainActor
    func testFailedFavoriteUpdateRollsBackWithoutChangingCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        let catalog = SongCatalogModel(cache: cache)
        let search: SongCatalogModel.CatalogSearch = { _, _, _ in page }
        await catalog.loadIfNeeded(
            query: "battle",
            version: .phoenix2,
            cacheScope: "account:one",
            debounce: false,
            using: search
        )
        let song = try XCTUnwrap(catalog.listing.songs.first)

        await catalog.setFavorite(false, for: song) { _, _, _ in
            await catalog.loadMoreIfNeeded(after: song)
            throw FavoriteTestError.failed
        }

        XCTAssertEqual(catalog.listing.songs.first?.isFavorite, true)
        XCTAssertEqual(catalog.favoriteError, "The favorite update failed.")
        let cached = await cache.load(
            query: "battle",
            version: .phoenix2,
            scope: "account:one"
        )
        XCTAssertEqual(cached?.listing.songs.first?.isFavorite, true)
    }

    @MainActor
    func testFailedFavoriteUpdateRollsBackAfterQueryReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let page = try JSONDecoder().decode(CatalogSearchPage.self, from: Data(Self.fixture.utf8))
        let catalog = SongCatalogModel(cache: cache)
        let search: SongCatalogModel.CatalogSearch = { _, _, _ in page }
        await catalog.loadIfNeeded(
            query: "battle",
            version: .phoenix2,
            cacheScope: "account:one",
            debounce: false,
            using: search
        )
        let song = try XCTUnwrap(catalog.listing.songs.first)

        await catalog.setFavorite(false, for: song) { _, _, _ in
            await catalog.reload(
                query: "another query",
                version: .phoenix2,
                cacheScope: "account:one",
                debounce: false,
                using: search
            )
            throw FavoriteTestError.failed
        }

        XCTAssertEqual(catalog.listing.songs.first?.isFavorite, true)
        XCTAssertEqual(catalog.favoriteError, "The favorite update failed.")
        let cached = await cache.load(
            query: "another query",
            version: .phoenix2,
            scope: "account:one"
        )
        XCTAssertEqual(cached?.listing.songs.first?.isFavorite, true)
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
          "isFavorite": true,
          "recommendedChartToken": "S19"
        }
      ],
      "nextCursor": "Mg",
      "total": 654,
      "filterOptions": {"folders": [], "series": [], "levels": [], "charts": []}
    }
    """
}

private enum FavoriteTestError: LocalizedError {
    case failed

    var errorDescription: String? { "The favorite update failed." }
}

private actor TestGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var bufferedValue: Value?
    private var occupancyWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async -> Value {
        if let bufferedValue {
            self.bufferedValue = nil
            return bufferedValue
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            occupancyWaiters.forEach { $0.resume() }
            occupancyWaiters.removeAll()
        }
    }

    func waitUntilOccupied() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            occupancyWaiters.append(continuation)
        }
    }

    func open(_ value: Value) {
        guard let continuation else {
            bufferedValue = value
            return
        }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}
