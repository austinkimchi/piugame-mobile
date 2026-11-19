import Foundation
import XCTest
@testable import MyPIU

@MainActor
final class PerformanceSessionsTests: XCTestCase {
    func testRetainsHistoryDuringRefreshAndTransientFailure() async {
        let model = PerformanceSessionsModel()
        await model.refresh(scope: "account:one") { _ in self.page("cached", next: 20) }
        let request = PendingSessionPage()
        let refresh = Task { await model.refresh(scope: "account:one", loadPage: request.load) }
        await request.waitUntilStarted()
        XCTAssertEqual(model.sessions.map(\.id), ["cached"])
        XCTAssertTrue(model.isRefreshing)
        request.finish(.failure(URLError(.timedOut)))
        await refresh.value
        XCTAssertEqual(model.sessions.map(\.id), ["cached"])
        XCTAssertEqual(model.nextOffset, 20)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNotNil(model.error)
    }

    func testReplacedRefreshCannotOverwriteNewerSameAccountResult() async {
        let model = PerformanceSessionsModel()
        let request = PendingSessionPage()
        let old = Task { await model.refresh(scope: "account:one", loadPage: request.load) }
        await request.waitUntilStarted()
        await model.refresh(scope: "account:one") { _ in self.page("new") }
        request.finish(.success(page("old")))
        await old.value
        XCTAssertEqual(model.sessions.map(\.id), ["new"])
        XCTAssertFalse(model.isRefreshing)
    }

    func testRefreshInvalidatesOutstandingPaginationWithoutMixingPages() async {
        let model = PerformanceSessionsModel()
        await model.refresh(scope: "account:one") { _ in self.page("first", next: 20) }
        let request = PendingSessionPage()
        let old = Task { await model.loadMore(loadPage: request.load) }
        await request.waitUntilStarted()
        await model.refresh(scope: "account:one") { _ in self.page("replacement", next: 40) }
        request.finish(.success(page("stale-page", next: 60)))
        await old.value
        XCTAssertEqual(model.sessions.map(\.id), ["replacement"])
        XCTAssertEqual(model.nextOffset, 40)
        XCTAssertFalse(model.isLoadingMore)
    }

    func testSignOutClearsPrivateHistoryAndRejectsLateSameAccountResponse() async {
        let model = PerformanceSessionsModel()
        await model.refresh(scope: "account:one") { _ in self.page("private") }
        let request = PendingSessionPage()
        let old = Task { await model.refresh(scope: "account:one", loadPage: request.load) }
        await request.waitUntilStarted()
        model.updateScope("public")
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNil(model.scope)
        XCTAssertFalse(model.hasLoaded)
        await model.refresh(scope: "account:one") { _ in self.page("new-login") }
        request.finish(.success(page("old-login")))
        await old.value
        XCTAssertEqual(model.sessions.map(\.id), ["new-login"])
    }

    func testCancellationEndsLoadingAndAllowsRetry() async {
        let model = PerformanceSessionsModel()
        let request = PendingSessionPage()
        let old = Task { await model.refresh(scope: "account:one", loadPage: request.load) }
        await request.waitUntilStarted()
        old.cancel()
        request.finish(.failure(CancellationError()))
        await old.value
        XCTAssertFalse(model.isRefreshing)
        XCTAssertNil(model.error)
        await model.refresh(scope: "account:one") { _ in self.page("retry") }
        XCTAssertEqual(model.sessions.map(\.id), ["retry"])
    }

    func testPaginationDeduplicatesAndRejectsBackwardCursor() async {
        let model = PerformanceSessionsModel()
        let first = page("first", next: 20)
        await model.refresh(scope: "account:one") { _ in first }
        await model.loadMore { offset in
            XCTAssertEqual(offset, 20)
            return MyPIUPerformanceSessionsPage(
                sessions: first.sessions + self.page("second").sessions,
                nextOffset: 10
            )
        }
        XCTAssertEqual(model.sessions.map(\.id), ["first", "second"])
        XCTAssertNil(model.nextOffset)
        await model.loadMore { _ in XCTFail("No cursor must mean no request"); return first }
    }

    func testPaginationIsDeduplicatedAndFailureKeepsRowsForManualRetry() async {
        let model = PerformanceSessionsModel()
        await model.refresh(scope: "account:one") { _ in self.page("first", next: 20) }
        let request = PendingSessionPage()
        let loading = Task { await model.loadMore(loadPage: request.load) }
        await request.waitUntilStarted()
        await model.loadMore { _ in XCTFail("Only one page request may run"); return self.page("bad") }
        request.finish(.failure(URLError(.notConnectedToInternet)))
        await loading.value
        XCTAssertEqual(model.sessions.map(\.id), ["first"])
        XCTAssertNotNil(model.paginationError)
        XCTAssertFalse(model.isLoadingMore)
        await model.loadMore { _ in self.page("second") }
        XCTAssertEqual(model.sessions.map(\.id), ["first", "second"])
        XCTAssertNil(model.paginationError)
    }

    func testPublicScopeMakesNoPrivateRequestAndEmptyResultsRemainLoaded() async {
        let model = PerformanceSessionsModel()
        await model.refresh(scope: "public") { _ in XCTFail("Private request while signed out"); return self.page("bad") }
        XCTAssertFalse(model.isRefreshing)
        await model.refresh(scope: "account:one") { _ in MyPIUPerformanceSessionsPage(sessions: [], nextOffset: nil) }
        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.sessions.isEmpty)
        model.invalidate()
        XCTAssertEqual(model.revision, 1)
        XCTAssertTrue(model.hasLoaded)
    }

    private func page(_ id: String, next: Int? = nil) -> MyPIUPerformanceSessionsPage {
        MyPIUPerformanceSessionsPage(sessions: [MyPIUPerformanceSession(
            id: id, arcadeName: nil,
            summary: .init(
                playCount: 1, clearCount: 1, failedCount: 0, stageBreakCount: 0,
                averageScore: 900000, bestScore: 900000, distinctCharts: 1,
                startedAt: "2026-11-19T10:00:00Z", endedAt: "2026-11-19T11:00:00Z", durationMinutes: 60
            ), plays: []
        )], nextOffset: next)
    }
}

/// Deliberately ignores cancellation to prove generation checks reject late callbacks.
@MainActor
private final class PendingSessionPage {
    private var continuation: CheckedContinuation<MyPIUPerformanceSessionsPage, Error>?

    func load(_ offset: Int) async throws -> MyPIUPerformanceSessionsPage {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        for _ in 0..<1000 {
            if continuation != nil { return }
            await Task.yield()
        }
        XCTFail("Request did not start")
    }

    func finish(_ result: Result<MyPIUPerformanceSessionsPage, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
