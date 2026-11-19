import Combine
import Foundation

/// Private cached rows are usable only after the current token's account is verified.
@MainActor
final class PerformanceSessionsModel: ObservableObject {
    typealias Loader = @MainActor @Sendable (Int) async throws -> MyPIUPerformanceSessionsPage
    typealias ContextLoader = @MainActor @Sendable () async throws -> PerformanceSessionsCacheContext?

    @Published private(set) var scope: String?
    @Published private(set) var sessions: [MyPIUPerformanceSession] = []
    @Published private(set) var nextOffset: Int?
    @Published private(set) var hasLoaded = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var paginationError: String?
    @Published private(set) var revision = 0
    @Published private(set) var savedAt: Date?

    private var generation = UUID()
    private var refreshTask: Task<MyPIUPerformanceSessionsPage, Error>?
    private var paginationTask: Task<MyPIUPerformanceSessionsPage, Error>?
    private var paginationID: UUID?
    private let cache: PerformanceSessionsCache?
    private var cacheLease = PerformanceSessionsCacheLease()
    private var cacheClearTask: Task<Void, Never>?

    init(cache: PerformanceSessionsCache? = nil) { self.cache = cache }

    func updateScope(_ newScope: String?) {
        let accountScope = newScope.flatMap { $0.hasPrefix("account:") ? $0 : nil }
        guard scope != accountScope else { return }
        if scope != nil { clearPrivateCache() }
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
        savedAt = nil
    }

    func invalidate() {
        clearPrivateCache()
        generation = UUID()
        refreshTask?.cancel()
        paginationTask?.cancel()
        refreshTask = nil
        paginationTask = nil
        paginationID = nil
        isRefreshing = false
        isLoadingMore = false
        nextOffset = nil
        revision += 1
    }

    func resetVersion() {
        let previousScope = scope
        updateScope(nil)
        updateScope(previousScope)
        revision += 1
    }

    func clearPrivateCache() {
        cacheLease.invalidate()
        if let cache {
            let previous = cacheClearTask
            cacheClearTask = Task { await previous?.value; await cache.clear() }
        }
    }

    func refresh(scope: String?, cacheContext: @escaping ContextLoader = { nil },
                 loadPage: @escaping Loader) async {
        updateScope(scope)
        guard self.scope != nil else { return }
        refreshTask?.cancel()
        paginationTask?.cancel()
        paginationTask = nil
        paginationID = nil
        isLoadingMore = false
        let requestID = UUID()
        generation = requestID
        cacheLease.invalidate()
        let lease = PerformanceSessionsCacheLease()
        cacheLease = lease
        isRefreshing = true
        error = nil
        paginationError = nil
        let task = Task { try await loadPage(0) }
        let contextTask = Task { try await cacheContext() }
        let pendingClear = cacheClearTask
        let cachedRows = Task {
            await pendingClear?.value
            guard let cache, let context = try? await contextTask.value,
                  "account:\(context.accountID)" == scope,
                  !hasLoaded,
                  let cached = await cache.load(context: context, lease: lease),
                  generation == requestID, lease.isValid, !Task.isCancelled, !hasLoaded else { return }
            sessions = cached.page.sessions
            nextOffset = nil // A saved offset must never be mixed with a current server page.
            savedAt = cached.savedAt
            hasLoaded = true
        }
        refreshTask = task
        defer {
            cachedRows.cancel()
            contextTask.cancel()
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
            savedAt = nil
            hasLoaded = true
            isRefreshing = false // Identity validation and persistence must not delay fresh pagination.
            if let context = try? await contextTask.value,
               "account:\(context.accountID)" == scope, generation == requestID,
               lease.isValid, !Task.isCancelled {
                await pendingClear?.value
                guard generation == requestID, lease.isValid, !Task.isCancelled else { return }
                await cache?.save(page, context: context, lease: lease)
            }
        } catch {
            guard generation == requestID, !Task.isCancelled, !task.isCancelled else { return }
            await cachedRows.value
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
