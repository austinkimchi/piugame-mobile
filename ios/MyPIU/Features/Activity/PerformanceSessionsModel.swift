import Combine
import Foundation

/// Private session history lives only in memory and is discarded when the account changes.
@MainActor
final class PerformanceSessionsModel: ObservableObject {
    typealias Loader = @MainActor @Sendable (Int) async throws -> MyPIUPerformanceSessionsPage

    @Published private(set) var scope: String?
    @Published private(set) var sessions: [MyPIUPerformanceSession] = []
    @Published private(set) var nextOffset: Int?
    @Published private(set) var hasLoaded = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var paginationError: String?
    @Published private(set) var revision = 0

    private var generation = UUID()
    private var refreshTask: Task<MyPIUPerformanceSessionsPage, Error>?
    private var paginationTask: Task<MyPIUPerformanceSessionsPage, Error>?
    private var paginationID: UUID?

    func updateScope(_ newScope: String?) {
        let accountScope = newScope.flatMap { $0.hasPrefix("account:") ? $0 : nil }
        guard scope != accountScope else { return }
        generation = UUID()
        refreshTask?.cancel()
        paginationTask?.cancel()
        refreshTask = nil
        paginationTask = nil
        paginationID = nil
        scope = accountScope
        sessions = []
        nextOffset = nil
        hasLoaded = false
        isRefreshing = false
        isLoadingMore = false
        error = nil
        paginationError = nil
    }

    func invalidate() {
        revision += 1
    }

    func refresh(scope: String?, loadPage: @escaping Loader) async {
        updateScope(scope)
        guard self.scope != nil else { return }
        refreshTask?.cancel()
        paginationTask?.cancel()
        paginationTask = nil
        paginationID = nil
        isLoadingMore = false
        let requestID = UUID()
        generation = requestID
        isRefreshing = true
        error = nil
        paginationError = nil
        let task = Task { try await loadPage(0) }
        refreshTask = task
        defer {
            if generation == requestID {
                isRefreshing = false
                refreshTask = nil
            }
        }
        do {
            let page = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard generation == requestID else { return }
            var knownIDs = Set<String>()
            sessions = page.sessions.filter { knownIDs.insert($0.id).inserted }
            nextOffset = page.nextOffset.flatMap { $0 > 0 ? $0 : nil }
            hasLoaded = true
        } catch {
            guard generation == requestID, !Task.isCancelled, !task.isCancelled else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            self.error = error.localizedDescription
        }
    }

    func loadMore(loadPage: @escaping Loader) async {
        guard scope != nil, !isRefreshing, !isLoadingMore, let offset = nextOffset else { return }
        let requestGeneration = generation
        let requestID = UUID()
        paginationID = requestID
        isLoadingMore = true
        paginationError = nil
        let task = Task { try await loadPage(offset) }
        paginationTask = task
        defer {
            if paginationID == requestID {
                isLoadingMore = false
                paginationTask = nil
                paginationID = nil
            }
        }
        do {
            let page = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard generation == requestGeneration, paginationID == requestID else { return }
            var knownIDs = Set(sessions.map(\.id))
            sessions.append(contentsOf: page.sessions.filter { knownIDs.insert($0.id).inserted })
            nextOffset = page.nextOffset.flatMap { $0 > offset ? $0 : nil }
        } catch {
            guard generation == requestGeneration, paginationID == requestID,
                  !Task.isCancelled, !task.isCancelled else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            paginationError = error.localizedDescription
        }
    }
}
