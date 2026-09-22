import Combine
import Foundation

@MainActor
final class SongCatalogModel: ObservableObject {
    typealias CatalogSearch = @MainActor (
        _ query: String,
        _ cursor: String?,
        _ version: PIUGameVersion
    ) async throws -> CatalogSearchPage

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var listing = CatalogListing()
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var paginationError: String?
    @Published private(set) var isShowingCachedData = false
    @Published private(set) var paginationGeneration = 0

    private let cache: CatalogCache
    private var searchCatalog: CatalogSearch
    private var requestID = UUID()
    private var listingRequestID: UUID?
    private var currentQuery = ""
    private var currentVersion: PIUGameVersion = .phoenix2
    private var currentCacheScope: String?

    init(apiClient: MyPIUAPIClient = MyPIUAPIClient(), cache: CatalogCache = CatalogCache()) {
        self.cache = cache
        self.searchCatalog = { query, cursor, version in
            try await apiClient.searchCatalog(query: query, cursor: cursor, version: version)
        }
    }

    func loadIfNeeded(
        query: String,
        version: PIUGameVersion,
        cacheScope: String? = "public",
        debounce: Bool = true,
        using searchCatalog: CatalogSearch? = nil
    ) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let searchCatalog {
            self.searchCatalog = searchCatalog
        }
        guard state != .loaded
            || normalizedQuery != currentQuery
            || version != currentVersion
            || cacheScope != currentCacheScope
        else {
            return
        }

        await reload(
            query: normalizedQuery,
            version: version,
            cacheScope: cacheScope,
            debounce: debounce
        )
    }

    func reload(
        query: String,
        version: PIUGameVersion,
        cacheScope: String? = "public",
        debounce: Bool = true,
        using searchCatalog: CatalogSearch? = nil
    ) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        self.requestID = requestID
        if let searchCatalog {
            self.searchCatalog = searchCatalog
        }
        listingRequestID = nil
        currentQuery = normalizedQuery
        currentVersion = version
        currentCacheScope = cacheScope
        isLoadingMore = false
        paginationError = nil
        state = .loading

        if debounce, !normalizedQuery.isEmpty {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }
        }
        guard !Task.isCancelled, self.requestID == requestID else { return }

        let cached: CatalogCache.CachedListing?
        if let cacheScope {
            cached = await cache.load(query: normalizedQuery, version: version, scope: cacheScope)
        } else {
            cached = nil
        }
        guard !Task.isCancelled, self.requestID == requestID else { return }
        listing = cached?.listing ?? CatalogListing()
        isShowingCachedData = cached != nil
        do {
            let page = try await self.searchCatalog(normalizedQuery, nil, version)
            guard !Task.isCancelled, self.requestID == requestID else { return }
            listing.replace(with: page)
            listingRequestID = requestID
            paginationGeneration += 1
            isShowingCachedData = false
            state = .loaded
            if let cacheScope {
                try? await cache.save(listing, query: normalizedQuery, version: version, scope: cacheScope)
            }
        } catch is CancellationError {
            return
        } catch {
            guard self.requestID == requestID else { return }
            if cached != nil {
                listingRequestID = requestID
                paginationGeneration += 1
                state = .loaded
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func retry() async {
        await reload(
            query: currentQuery,
            version: currentVersion,
            cacheScope: currentCacheScope,
            debounce: false
        )
    }

    func loadMoreIfNeeded(after song: CatalogSong) async {
        guard let index = listing.songs.firstIndex(where: { $0.id == song.id }) else { return }
        guard index >= max(0, listing.songs.count - 5) else { return }
        await loadMore()
    }

    func retryPagination() async {
        await loadMore()
    }

    private func loadMore() async {
        guard listingRequestID == requestID, !isLoadingMore, let cursor = listing.nextCursor else { return }
        let requestID = self.requestID
        isLoadingMore = true
        paginationError = nil
        defer {
            if self.requestID == requestID {
                isLoadingMore = false
            }
        }

        do {
            let page = try await searchCatalog(currentQuery, cursor, currentVersion)
            guard !Task.isCancelled, self.requestID == requestID else { return }
            listing.append(page, requestedCursor: cursor)
            if let currentCacheScope {
                try? await cache.save(
                    listing,
                    query: currentQuery,
                    version: currentVersion,
                    scope: currentCacheScope
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard self.requestID == requestID else { return }
            paginationError = error.localizedDescription
        }
    }
}
