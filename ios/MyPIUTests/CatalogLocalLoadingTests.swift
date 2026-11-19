import XCTest
@testable import MyPIU

final class CatalogLocalLoadingTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "catalog-local-query", withExtension: "json", subdirectory: "test-fixtures"))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        return try JSONSerialization.data(withJSONObject: object["snapshot"]!)
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func overlay(_ favorite: Bool = false, hint: String = "S17") -> MobileCatalogOverlay {
        MobileCatalogOverlay(schemaVersion: 1, version: "phoenix2", favoriteSlugs: favorite ? ["all"] : [], recommendations: ["all": ["all": hint, "DS": "D17"]])
    }

    @MainActor
    func testWarmTextSortAndFiltersUseNoNetworkAndKeepFavoriteAcrossQueries() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try fixture(), transport = LocalQueryCounter()
        let store = PublicCatalogStore(directory: directory.appendingPathComponent("public")) { request in
            await transport.increment()
            return (fixture, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: store)
        var overlays = 0, searches = 0
        await model.loadIfNeeded(query: "", version: .phoenix2, cacheScope: "account:a", debounce: false,
            using: { _, _, _ in searches += 1; return CatalogSearchPage(songs: [], nextCursor: nil, total: 0) },
            usingOverlay: { _ in overlays += 1; return self.overlay() })
        XCTAssertEqual(model.listing.total, 12)
        await model.applyConfirmedFavorite(true, slug: "all", version: .phoenix2, cacheScope: "account:a")
        await model.loadIfNeeded(query: "alpha", version: .phoenix2,
            filters: CatalogFilters(charts: ["doubles", "singles"], sortBy: .title, sortDirection: .ascending),
            cacheScope: "account:a", debounce: false)
        XCTAssertEqual(model.listing.songs.map(\.slug), ["all"])
        XCTAssertTrue(model.listing.songs[0].isFavorite)
        XCTAssertEqual(model.listing.songs[0].recommendedChartToken, "D17")
        await model.loadIfNeeded(query: "favorites", version: .phoenix2, cacheScope: "account:a", debounce: false)
        XCTAssertEqual(searches, 1, "Private feeds must stay server-owned")
        await model.loadIfNeeded(query: "", version: .phoenix2, cacheScope: "account:a", debounce: false)
        XCTAssertTrue(try XCTUnwrap(model.song(slug: "all")).isFavorite)
        XCTAssertEqual(overlays, 1)
        let count = await transport.count
        XCTAssertEqual(count, 1)
        // A failed refresh retains the same complete dataset, which still filters offline.
        await model.reload(query: "", version: .phoenix2, cacheScope: "account:a", debounce: false,
            usingOverlay: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertNotNil(model.refreshError)
        await model.loadIfNeeded(query: "key-single", version: .phoenix2, cacheScope: "account:a", debounce: false)
        XCTAssertEqual(model.listing.songs.map(\.slug), ["single"])
    }

    @MainActor
    func testFavoriteWriteWinsOverlayRefreshAndRemainsAfterLocalRefilter() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try fixture()
        let store = PublicCatalogStore(directory: directory.appendingPathComponent("public")) { request in
            (fixture, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: store)
        await model.reload(query: "", version: .phoenix2, cacheScope: "account:a", debounce: false, usingOverlay: { _ in self.overlay() })
        let gate = LocalQueryGate()
        let refresh = Task {
            await model.reload(query: "", version: .phoenix2, cacheScope: "account:a", debounce: false,
                usingOverlay: { _ in await gate.wait(); return self.overlay() })
        }
        await gate.waitForStart()
        await model.setFavorite(true, for: try XCTUnwrap(model.song(slug: "all")), using: { _, _, _ in true })
        await gate.release(); await refresh.value
        await model.loadIfNeeded(query: "alpha", version: .phoenix2, cacheScope: "account:a", debounce: false)
        XCTAssertTrue(try XCTUnwrap(model.song(slug: "all")).isFavorite)
    }

    @MainActor
    func testIdentityInvalidationRejectsLateOverlayAndClearsWarmPrivateDataset() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try fixture()
        let store = PublicCatalogStore(directory: directory.appendingPathComponent("public")) { request in
            (fixture, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: store)
        await model.reload(query: "", version: .phoenix2, cacheScope: "account:a", debounce: false, usingOverlay: { _ in self.overlay(true) })
        let gate = LocalQueryGate()
        let late = Task {
            await model.reload(query: "", version: .phoenix2, cacheScope: "account:a", debounce: false,
                usingOverlay: { _ in await gate.wait(); return self.overlay(true, hint: "old") })
        }
        await gate.waitForStart()
        model.invalidateAccount()
        XCTAssertTrue(model.listing.songs.isEmpty)
        await model.loadIfNeeded(query: "alpha", version: .phoenix2, cacheScope: "account:a", debounce: false,
            usingOverlay: { _ in self.overlay(false, hint: "new") })
        await gate.release(); await late.value
        XCTAssertFalse(try XCTUnwrap(model.song(slug: "all")).isFavorite)
        XCTAssertEqual(model.song(slug: "all")?.recommendedChartToken, "new")
        model.invalidateAccount()
        await model.loadIfNeeded(query: "alpha", version: .phoenix2, cacheScope: "public", debounce: false)
        XCTAssertTrue(model.listing.songs.allSatisfy { !$0.isFavorite && $0.recommendedChartToken == nil })
    }

    @MainActor
    func testImportInvalidationRefreshesHintsAnd404AloneAllowsLegacyFilteredSearch() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try fixture()
        let store = PublicCatalogStore(directory: directory.appendingPathComponent("public")) { request in
            (fixture, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: store)
        var count = 0
        let overlay: SongCatalogModel.CatalogOverlaySearch = { _ in count += 1; return self.overlay(hint: "hint-\(count)") }
        await model.loadIfNeeded(query: "", version: .phoenix2, cacheScope: "account:a", debounce: false, usingOverlay: overlay)
        model.invalidateCatalog()
        await model.loadIfNeeded(query: "alpha", version: .phoenix2, cacheScope: "account:a", debounce: false)
        XCTAssertEqual(model.song(slug: "all")?.recommendedChartToken, "hint-2")
        for status in [404, 503] {
            var fallback = 0
            await model.reload(query: "query-\(status)", version: .phoenix2, filters: CatalogFilters(sortBy: .title), cacheScope: "account:a", debounce: false,
                usingFiltered: { _, _, _, _ in fallback += 1; return CatalogSearchPage(songs: [], nextCursor: nil, total: 0) },
                usingOverlay: { _ in throw MyPIUAPIError.server(status: status, code: "test") })
            XCTAssertEqual(fallback, status == 404 ? 1 : 0)
        }
    }
}

private actor LocalQueryCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
private actor LocalQueryGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false
    func wait() async { started = true; await withCheckedContinuation { continuation = $0 } }
    func waitForStart() async { while !started { await Task.yield() } }
    func release() { continuation?.resume(); continuation = nil }
}
