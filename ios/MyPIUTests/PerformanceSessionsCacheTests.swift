import Combine
import XCTest
@testable import MyPIU

@MainActor
final class PerformanceSessionsCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func context(account: String = "a", version: PIUGameVersion = .phoenix2,
                         token: String = "synthetic-token", origin: String = "https://example.test") -> PerformanceSessionsCacheContext {
        .init(origin: origin, accountID: account, version: version, token: token)
    }
    private func fixture(prefix: String = "fixture") throws -> MyPIUPerformanceSessionsPage {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "session-cache-page", withExtension: "json", subdirectory: "test-fixtures"))
        let json = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "fixture-", with: "\(prefix)-")
        return try JSONDecoder().decode(MyPIUPerformanceSessionsPage.self, from: Data(json.utf8))
    }
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testRoundTripRequiresExactOriginAccountTokenAndVersion() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PerformanceSessionsCache(directory: directory)
        let page = try fixture(), lease = PerformanceSessionsCacheLease()
        await cache.save(page, context: context(), lease: lease, now: now)
        let cached = await cache.load(context: context(), lease: lease, now: now)
        XCTAssertEqual(cached?.page, page)
        for other in [context(account: "b"), context(version: .phoenix), context(token: "new-token"), context(origin: "https://another.test")] {
            let wrong = await cache.load(context: other, lease: lease, now: now)
            XCTAssertNil(wrong)
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let bytes = try Data(contentsOf: XCTUnwrap(files.first))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("synthetic-token"))
    }

    func testExpiryFutureSchemaAndCorruptionAreCacheMisses() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PerformanceSessionsCache(directory: directory), lease = PerformanceSessionsCacheLease()
        await cache.save(try fixture(), context: context(), lease: lease, now: now)
        let expired = await cache.load(context: context(), lease: lease, now: now.addingTimeInterval(86_401))
        let future = await cache.load(context: context(), lease: lease, now: now.addingTimeInterval(-1))
        XCTAssertNil(expired); XCTAssertNil(future)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let unknown = await cache.load(context: context(), lease: lease, now: now)
        XCTAssertNil(unknown)
        try Data("{broken".utf8).write(to: file)
        let corrupt = await cache.load(context: context(), lease: lease, now: now)
        XCTAssertNil(corrupt)
        try Data(repeating: 120, count: PerformanceSessionsCache.maximumPageBytes + 1).write(to: file)
        let tooLarge = await cache.load(context: context(), lease: lease, now: now)
        XCTAssertNil(tooLarge)
    }

    func testUnknownOrMissingVersionAndOversizedPagesNeverPersist() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PerformanceSessionsCache(directory: directory), lease = PerformanceSessionsCacheLease()
        for version in [nil, "unknown", "phoenix"] as [String?] {
            var page = try fixture(); page.selectedVersion = version
            await cache.save(page, context: context(), lease: lease, now: now)
            let cached = await cache.load(context: context(), lease: lease, now: now)
            XCTAssertNil(cached)
        }
        let data = try JSONEncoder().encode(fixture())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        var plays = try XCTUnwrap(sessions[0]["plays"] as? [[String: Any]])
        plays[0]["songName"] = String(repeating: "x", count: PerformanceSessionsCache.maximumPageBytes)
        sessions[0]["plays"] = plays; json["sessions"] = sessions
        let oversized = try JSONDecoder().decode(MyPIUPerformanceSessionsPage.self, from: JSONSerialization.data(withJSONObject: json))
        await cache.save(oversized, context: context(), lease: lease, now: now)
        let cached = await cache.load(context: context(), lease: lease, now: now)
        XCTAssertNil(cached)
    }

    func testRetentionIsTwoVersionsForOneCurrentAccountAndInvalidLeaseCannotWrite() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PerformanceSessionsCache(directory: directory), lease = PerformanceSessionsCacheLease()
        let page = try fixture()
        await cache.save(page, context: context(), lease: lease, now: now)
        var phoenix = page; phoenix.selectedVersion = "phoenix"
        await cache.save(phoenix, context: context(version: .phoenix), lease: lease, now: now)
        var files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        XCTAssertEqual(files.count, 2)
        XCTAssertLessThanOrEqual(try files.reduce(0) { $0 + (try $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }, PerformanceSessionsCache.maximumTotalBytes)
        await cache.save(page, context: context(account: "b"), lease: lease, now: now)
        files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        lease.invalidate()
        await cache.clear()
        await cache.save(page, context: context(), lease: lease, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testColdCacheShowsRowsBeforeNetworkAndDisablesSavedCursor() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PerformanceSessionsCache(directory: directory)
        await cache.save(try fixture(), context: context(), lease: PerformanceSessionsCacheLease())
        let model = PerformanceSessionsModel(cache: cache), gate = SessionsCacheGate<MyPIUPerformanceSessionsPage>()
        defer { gate.finish(.failure(CancellationError())) }
        let saved = expectation(description: "Saved rows published")
        let observer = model.$savedAt.compactMap { $0 }.prefix(1).sink { _ in saved.fulfill() }
        defer { observer.cancel() }
        let operation = Task { await model.refresh(scope: "account:a", cacheContext: { self.context() }) { _ in try await gate.load() } }
        await fulfillment(of: [saved], timeout: 5)
        XCTAssertEqual(model.sessions.count, 20)
        XCTAssertNil(model.nextOffset)
        XCTAssertTrue(model.isRefreshing)
        await model.loadMore { _ in XCTFail("Saved cursor must not page"); return try self.fixture() }
        gate.finish(.failure(URLError(.timedOut)))
        await operation.value
        XCTAssertEqual(model.sessions.count, 20)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNotNil(model.error)
        XCTAssertNotNil(model.savedAt)
    }

    func testFreshNetworkWinsWhileIdentityValidationIsPending() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PerformanceSessionsCache(directory: directory)
        await cache.save(try fixture(), context: context(), lease: PerformanceSessionsCacheLease())
        let model = PerformanceSessionsModel(cache: cache), identity = SessionsCacheGate<PerformanceSessionsCacheContext?>()
        defer { identity.finish(.failure(CancellationError())) }
        let fresh = expectation(description: "Fresh network page published")
        let observer = model.$sessions.filter { $0.first?.id == "fresh-session-0" }.prefix(1).sink { _ in fresh.fulfill() }
        defer { observer.cancel() }
        let operation = Task {
            await model.refresh(scope: "account:a", cacheContext: { try await identity.load() }) { _ in try self.fixture(prefix: "fresh") }
        }
        await fulfillment(of: [fresh], timeout: 5)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(model.nextOffset, 20)
        XCTAssertNil(model.savedAt)
        identity.finish(.success(context()))
        await operation.value
        XCTAssertEqual(model.sessions.first?.id, "fresh-session-0")
        XCTAssertEqual(model.nextOffset, 20)
        let stored = await cache.load(context: context(), lease: PerformanceSessionsCacheLease())
        XCTAssertEqual(stored?.page.sessions.first?.id, "fresh-session-0")
    }

    func testLogoutAndImportRejectOldResponsesAndCannotRecreateCache() async throws {
        for logout in [false, true] {
            let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
            let cache = PerformanceSessionsCache(directory: directory), model = PerformanceSessionsModel(cache: cache)
            let gate = SessionsCacheGate<MyPIUPerformanceSessionsPage>()
            defer { gate.finish(.failure(CancellationError())) }
            let started = gate.started
            let operation = Task { await model.refresh(scope: "account:a", cacheContext: { self.context() }) { _ in try await gate.load() } }
            await fulfillment(of: [started], timeout: 5)
            if logout { model.updateScope(nil) } else { model.invalidate() }
            gate.finish(.success(try fixture(prefix: "old")))
            await operation.value
            XCTAssertTrue(model.sessions.isEmpty)
            XCTAssertFalse(model.isRefreshing)
            let cached = await cache.load(context: context(), lease: PerformanceSessionsCacheLease())
            XCTAssertNil(cached)
            if !logout {
                await model.refresh(scope: "account:a", cacheContext: { self.context() }) { _ in try self.fixture(prefix: "imported") }
                let imported = await cache.load(context: context(), lease: PerformanceSessionsCacheLease())
                XCTAssertEqual(imported?.page.sessions.first?.id, "imported-session-0")
            }
        }
    }

    func testDiskWriteFailureDoesNotHideFreshRowsOrKeepLoading() async throws {
        let file = directory(); defer { try? FileManager.default.removeItem(at: file) }
        try Data("fixture blocks directory creation".utf8).write(to: file)
        let model = PerformanceSessionsModel(cache: PerformanceSessionsCache(directory: file))
        await model.refresh(scope: "account:a", cacheContext: { self.context() }) { _ in try self.fixture(prefix: "fresh") }
        XCTAssertEqual(model.sessions.first?.id, "fresh-session-0")
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.error)
    }

    func testUnverifiedContextCannotReadOrPersistPrivateRows() async throws {
        let directory = directory(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PerformanceSessionsCache(directory: directory)
        await cache.save(try fixture(), context: context(), lease: PerformanceSessionsCacheLease())
        for verification in [nil, context(account: "b")] as [PerformanceSessionsCacheContext?] {
            let model = PerformanceSessionsModel(cache: cache)
            await model.refresh(scope: "account:a", cacheContext: { verification }) { _ in throw URLError(.notConnectedToInternet) }
            XCTAssertFalse(model.hasLoaded)
            XCTAssertTrue(model.sessions.isEmpty)
            XCTAssertFalse(model.isRefreshing)
        }
    }
}

@MainActor
private final class SessionsCacheGate<Value: Sendable> {
    let started = XCTestExpectation(description: "Fixture request started")
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?
    func load() async throws -> Value {
        started.fulfill()
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ result: Result<Value, Error>) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(with: result)
        continuation = nil
    }
}
