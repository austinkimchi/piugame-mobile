import XCTest
@testable import MyPIU

final class PublicCatalogTests: XCTestCase {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static let fixture = #"{"schemaVersion":1,"selectedVersion":"phoenix2","view":"supported","total":1,"filterOptions":{"folders":[],"series":[],"levels":[],"charts":[]},"songs":[{"songKey":"one","slug":"one-phoenix2","title":"One","artist":"Artist","version":"phoenix2","supportedVersions":["phoenix","phoenix2"],"imageUrl":"/one.png","bpm":"180","chartSummary":["S19"],"folder":"Original","folderPosition":1,"series":"PHOENIX 2","tags":[],"isPremium":false,"isFavorite":true,"recommendedChartToken":"S19"}]}"#

    private static func response(_ request: URLRequest, status: Int = 200, etag: String? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                        headerFields: etag.map { ["ETag": $0] })!
    }

    func testSnapshotCacheRevalidatesWithETagWithoutCredentialsOrPrivateFields() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PublicCatalogStore(directory: directory) { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "MyPIU-iOS/0.1")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (Data(Self.fixture.utf8), Self.response(request, etag: "\"v1\""))
        }
        let first = try await store.refresh(version: .phoenix2)
        XCTAssertFalse(first.defaultPage.songs[0].isFavorite)
        XCTAssertNil(first.defaultPage.songs[0].recommendedChartToken)
        let saved = try String(contentsOf: directory.appendingPathComponent("phoenix2.json"), encoding: .utf8)
        XCTAssertFalse(saved.contains("isFavorite"))
        XCTAssertFalse(saved.contains("recommendedChartToken"))
        let restored = PublicCatalogStore(directory: directory) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"v1\"")
            return (Data(), Self.response(request, status: 304))
        }
        let cached = await restored.cached(version: .phoenix2)
        XCTAssertEqual(cached, first)
        let refreshed = try await restored.refresh(version: .phoenix2)
        XCTAssertEqual(refreshed, first)
        let otherVersion = await restored.cached(version: .phoenix)
        XCTAssertNil(otherVersion)
    }

    func testConcurrentReadersCoalesceAndCanceledReaderDoesNotCancelSharedDownload() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = CatalogTransportGate()
        let store = PublicCatalogStore(directory: directory) { request in
            await gate.wait()
            return (Data(Self.fixture.utf8), Self.response(request))
        }
        let first = Task { try await store.refresh(version: .phoenix2) }
        await gate.waitForStart()
        let second = Task { try await store.refresh(version: .phoenix2) }
        first.cancel()
        await gate.release()
        let result = try await second.value
        _ = try await first.value
        XCTAssertEqual(result.total, 1)
        let count = await gate.count
        XCTAssertEqual(count, 1)
    }

    func testIncompleteWrongViewAndDuplicateSnapshotsNeverReplaceValidCache() async throws {
        for invalid in [Self.fixture.replacingOccurrences(of: "\"total\":1", with: "\"total\":2"),
                        Self.fixture.replacingOccurrences(of: "\"view\":\"supported\"", with: "\"view\":\"removed\""),
                        Self.fixture.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")] {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = PublicCatalogStore(directory: directory) { request in
                (Data(invalid.utf8), Self.response(request))
            }
            do { _ = try await store.refresh(version: .phoenix2); XCTFail("Invalid snapshot accepted") }
            catch { }
            let cached = await store.cached(version: .phoenix2)
            XCTAssertNil(cached)
        }
    }

    func test304WithoutMatchingCompleteCacheFails() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PublicCatalogStore(directory: directory) { request in (Data(), Self.response(request, status: 304)) }
        do { _ = try await store.refresh(version: .phoenix2); XCTFail("304 without body/cache accepted") }
        catch { XCTAssertEqual(error as? PublicCatalogError, .invalidSnapshot) }
    }

    func testFailureRetainsCompleteOfflineSnapshot() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PublicCatalogStore(directory: directory) { request in (Data(Self.fixture.utf8), Self.response(request)) }
        let first = try await store.refresh(version: .phoenix2)
        let offline = PublicCatalogStore(directory: directory) { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await offline.refresh(version: .phoenix2); XCTFail("Offline request succeeded") } catch { }
        let retained = await offline.cached(version: .phoenix2)
        XCTAssertEqual(retained, first)
    }

    func testOverlayPreservesIdentityAndSelectedChartsWithoutMutatingPublicSnapshot() throws {
        let snapshot = try JSONDecoder().decode(PublicCatalogSnapshot.self, from: Data(Self.fixture.utf8))
        let overlay = try JSONDecoder().decode(MobileCatalogOverlay.self, from: Data(
            #"{"schemaVersion":1,"version":"phoenix2","favoriteSlugs":["one-phoenix2"],"recommendations":{"one-phoenix2":{"all":"S19","D":null}}}"#.utf8))
        let page = try overlay.applying(to: snapshot)
        XCTAssertEqual(page.songs[0].slug, "one-phoenix2")
        XCTAssertEqual(page.songs[0].chartSummary, ["S19"])
        XCTAssertTrue(page.songs[0].isFavorite)
        XCTAssertEqual(page.songs[0].recommendedChartToken, "S19")
        XCTAssertFalse(snapshot.defaultPage.songs[0].isFavorite)
    }

    func testDefaultSortUsesSeriesRankAndBinaryDescendingTies() throws {
        let source = try JSONDecoder().decode(PublicCatalogSnapshot.self, from: Data(Self.fixture.utf8)).songs[0]
        func song(_ slug: String, _ series: String?, _ position: Int?, _ title: String) -> CatalogSong {
            CatalogSong(slug: slug, title: title, artist: "A", supportedVersions: ["phoenix2"], imagePath: nil,
                        bpm: nil, chartSummary: source.chartSummary, folder: nil, folderPosition: position,
                        series: series, tags: [], isPremium: false, isFavorite: false, recommendedChartToken: nil)
        }
        let songs = [song("unknown", "Unknown", 99, "Z"), song("older", "XX", 2, "Z"),
                     song("null-position", "PHOENIX 2", nil, "Z"), song("upper", "PHOENIX 2", 1, "Z"),
                     song("lower", "PHOENIX 2", 1, "a"), song("position", "PHOENIX 2", 2, "A")]
        XCTAssertEqual(songs.sorted(by: PublicCatalogSnapshot.defaultOrder).map(\.slug),
                       ["position", "lower", "upper", "null-position", "older", "unknown"])
    }

    @MainActor
    func testSignedInSnapshotUsesTwoRequestsPreservesHintsAndDoesNotUseLegacySearch() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PublicCatalogStore(directory: directory.appendingPathComponent("public")) { request in
            (Data(Self.fixture.utf8), Self.response(request))
        }
        let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: store)
        var overlayCount = 0
        await model.loadIfNeeded(query: "", version: .phoenix2, cacheScope: "account:one", debounce: false,
            using: { _, _, _ in XCTFail("Legacy search used"); throw PublicCatalogError.invalidSnapshot },
            usingOverlay: { _ in
                overlayCount += 1
                return MobileCatalogOverlay(schemaVersion: 1, version: "phoenix2", favoriteSlugs: ["one-phoenix2"],
                                            recommendations: ["one-phoenix2": ["all": "S19"]])
            })
        XCTAssertEqual(model.state, .loaded)
        XCTAssertEqual(overlayCount, 1)
        XCTAssertTrue(model.listing.songs[0].isFavorite)
        XCTAssertEqual(model.listing.songs[0].recommendedChartToken, "S19")
    }
    @MainActor
    func testLegacyFirstPageIsVisibleBeforeLaterPagesFinish() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let song = try JSONDecoder().decode(PublicCatalogSnapshot.self, from: Data(Self.fixture.utf8)).defaultPage.songs[0]
        let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: nil)
        let gate = CatalogTransportGate()
        let task = Task {
            await model.reload(query: "", version: .phoenix2, cacheScope: "account:one", debounce: false,
                using: { _, cursor, _ in
                    if cursor == nil { return CatalogSearchPage(songs: [song], nextCursor: "two", total: 1) }
                    await gate.wait()
                    return CatalogSearchPage(songs: [], nextCursor: nil, total: 1)
                })
        }
        await gate.waitForStart()
        XCTAssertEqual(model.listing.songs, [song])
        XCTAssertEqual(model.state, .loading)
        await gate.release()
        await task.value
        XCTAssertEqual(model.state, .loaded)
    }

    @MainActor
    func testRepeatedCursorCannotBeSavedAsCompleteCatalog() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = CatalogCache(directory: directory)
        let song = try JSONDecoder().decode(PublicCatalogSnapshot.self, from: Data(Self.fixture.utf8)).defaultPage.songs[0]
        let model = SongCatalogModel(cache: cache, publicCatalog: nil)
        await model.reload(query: "", version: .phoenix2, cacheScope: "account:one", debounce: false,
            using: { _, _, _ in CatalogSearchPage(songs: [song], nextCursor: "again", total: 2) })
        XCTAssertNotNil(model.refreshError)
        XCTAssertEqual(model.listing.songs, [song])
        let cached = await cache.load(query: "", version: .phoenix2, scope: "account:one")
        XCTAssertNil(cached)
    }

    @MainActor
    func testRefreshFailureRetainsRowsAndReportsRetryableError() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try JSONDecoder().decode(PublicCatalogSnapshot.self, from: Data(Self.fixture.utf8)).defaultPage
        let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: nil)
        await model.reload(query: "", version: .phoenix2, cacheScope: "account:one", debounce: false,
                           using: { _, _, _ in page })
        await model.reload(query: "", version: .phoenix2, cacheScope: "account:one", debounce: false,
                           using: { _, _, _ in throw URLError(.notConnectedToInternet) })
        XCTAssertEqual(model.listing.songs, page.songs)
        XCTAssertEqual(model.state, .loaded)
        XCTAssertNotNil(model.refreshError)
    }

    @MainActor
    func testCanceledCurrentRequestStopsSpinnerAndNewAccountRejectsOldResponse() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try JSONDecoder().decode(PublicCatalogSnapshot.self, from: Data(Self.fixture.utf8)).defaultPage
        let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: nil)
        let gate = CatalogTransportGate()
        let old = Task {
            await model.reload(query: "old", version: .phoenix2, cacheScope: "account:old", debounce: false,
                               using: { _, _, _ in await gate.wait(); return page })
        }
        await gate.waitForStart()
        old.cancel()
        await gate.release()
        await old.value
        XCTAssertEqual(model.state, .idle)
        XCTAssertTrue(model.listing.songs.isEmpty)

        await model.reload(query: "new", version: .phoenix2, cacheScope: "account:new", debounce: false,
                           using: { _, _, _ in CatalogSearchPage(songs: [], nextCursor: nil, total: 0) })
        XCTAssertEqual(model.state, .loaded)
        XCTAssertTrue(model.listing.songs.isEmpty)
    }

    @MainActor
    func testInFlightOldAccountResponseCannotReplaceNewAccountListing() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try JSONDecoder().decode(PublicCatalogSnapshot.self, from: Data(Self.fixture.utf8)).defaultPage
        let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: nil)
        let gate = CatalogTransportGate()
        let old = Task {
            await model.reload(query: "old", version: .phoenix2, cacheScope: "account:old", debounce: false,
                               using: { _, _, _ in await gate.wait(); return page })
        }
        await gate.waitForStart()
        await model.reload(query: "new", version: .phoenix2, cacheScope: "account:new", debounce: false,
                           using: { _, _, _ in CatalogSearchPage(songs: [], nextCursor: nil, total: 0) })
        await gate.release()
        await old.value
        XCTAssertEqual(model.state, .loaded)
        XCTAssertTrue(model.listing.songs.isEmpty)
    }

    @MainActor
    func testOnlyMissingSnapshotEndpointFallsBackToLegacySearch() async throws {
        for status in [404, 503] {
            let directory = directory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = PublicCatalogStore(directory: directory.appendingPathComponent("public")) { request in
                (Data(), Self.response(request, status: status))
            }
            let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: store)
            var legacyCount = 0
            await model.loadIfNeeded(query: "", version: .phoenix2, cacheScope: "public", debounce: false,
                using: { _, _, _ in
                    legacyCount += 1
                    return CatalogSearchPage(songs: [], nextCursor: nil, total: 0)
                }, usingOverlay: { _ in XCTFail("Anonymous request used overlay"); throw CancellationError() })
            XCTAssertEqual(legacyCount, status == 404 ? 1 : 0)
            if status == 503 {
                guard case .failed = model.state else { return XCTFail("Unavailable API must report an error") }
            }
        }
    }

    @MainActor
    func testFavoriteMutationDuringOverlayLoadWinsOverOlderResponse() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PublicCatalogStore(directory: directory.appendingPathComponent("public")) { request in
            (Data(Self.fixture.utf8), Self.response(request))
        }
        let model = SongCatalogModel(cache: CatalogCache(directory: directory), publicCatalog: store)
        let gate = CatalogTransportGate()
        let load = Task {
            await model.loadIfNeeded(query: "", version: .phoenix2, cacheScope: "account:one", debounce: false,
                usingOverlay: { _ in
                    await gate.wait()
                    return MobileCatalogOverlay(schemaVersion: 1, version: "phoenix2", favoriteSlugs: [], recommendations: [:])
                })
        }
        await gate.waitForStart()
        await model.applyConfirmedFavorite(true, slug: "one-phoenix2", version: .phoenix2, cacheScope: "account:one")
        await gate.release()
        await load.value
        XCTAssertTrue(model.listing.songs[0].isFavorite)
    }

}

private actor CatalogTransportGate {
    private(set) var count = 0
    private var waiting: CheckedContinuation<Void, Never>?
    private var released = false
    private var startObservers: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        count += 1
        startObservers.forEach { $0.resume() }; startObservers = []
        if released { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func waitForStart() async {
        if count > 0 { return }
        await withCheckedContinuation { startObservers.append($0) }
    }
    func release() { released = true; waiting?.resume(); waiting = nil }
}
