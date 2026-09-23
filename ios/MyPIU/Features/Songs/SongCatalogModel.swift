import Combine
import Foundation

@MainActor
final class SongCatalogModel: ObservableObject {
    private static let completeCatalogFreshness: TimeInterval = 7 * 24 * 60 * 60
    private struct PendingFavoriteMutation {
        let id: UUID
        let previousValue: Bool
        let requestedValue: Bool
        let startingRevision: Int
    }

    private struct ConfirmedFavorite {
        let value: Bool
        let revision: Int
    }

    typealias CatalogSearch = @MainActor (
        _ query: String,
        _ cursor: String?,
        _ version: PIUGameVersion
    ) async throws -> CatalogSearchPage
    typealias FilteredCatalogSearch = @MainActor (
        _ query: String,
        _ cursor: String?,
        _ version: PIUGameVersion,
        _ filters: CatalogFilters
    ) async throws -> CatalogSearchPage
    typealias FavoriteUpdate = @MainActor (
        _ songSlug: String,
        _ saved: Bool,
        _ version: PIUGameVersion
    ) async throws -> Bool

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
    @Published private(set) var favoriteError: String?

    private let cache: CatalogCache
    private var searchCatalog: CatalogSearch
    private var filteredSearchCatalog: FilteredCatalogSearch
    private var requestID = UUID()
    private var listingRequestID: UUID?
    private var currentQuery = ""
    private var currentVersion: PIUGameVersion = .phoenix2
    private var currentFilters: CatalogFilters = .empty
    private var currentCacheScope: String?
    private var favoriteMutations: [String: PendingFavoriteMutation] = [:]
    private var confirmedFavorites: [String: ConfirmedFavorite] = [:]
    private var favoriteRevision = 0

    init(apiClient: MyPIUAPIClient = MyPIUAPIClient(), cache: CatalogCache = CatalogCache()) {
        self.cache = cache
        self.searchCatalog = { query, cursor, version in
            try await apiClient.searchCatalog(query: query, cursor: cursor, version: version)
        }
        self.filteredSearchCatalog = { query, cursor, version, filters in
            try await apiClient.searchCatalog(
                query: query,
                cursor: cursor,
                version: version,
                filters: filters
            )
        }
    }

    func loadIfNeeded(
        query: String,
        version: PIUGameVersion,
        filters: CatalogFilters = .empty,
        cacheScope: String? = "public",
        debounce: Bool = true,
        using searchCatalog: CatalogSearch? = nil,
        usingFiltered filteredSearchCatalog: FilteredCatalogSearch? = nil
    ) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let searchCatalog {
            self.searchCatalog = searchCatalog
        }
        if let filteredSearchCatalog {
            self.filteredSearchCatalog = filteredSearchCatalog
        }
        guard state != .loaded
            || normalizedQuery != currentQuery
            || version != currentVersion
            || filters != currentFilters
            || cacheScope != currentCacheScope
        else {
            return
        }

        await reload(
            query: normalizedQuery,
            version: version,
            filters: filters,
            cacheScope: cacheScope,
            debounce: debounce,
            useFreshCompleteCache: true
        )
    }

    func reload(
        query: String,
        version: PIUGameVersion,
        filters: CatalogFilters = .empty,
        cacheScope: String? = "public",
        debounce: Bool = true,
        useFreshCompleteCache: Bool = false,
        using searchCatalog: CatalogSearch? = nil,
        usingFiltered filteredSearchCatalog: FilteredCatalogSearch? = nil
    ) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestID = UUID()
        self.requestID = requestID
        if let searchCatalog {
            self.searchCatalog = searchCatalog
        }
        if let filteredSearchCatalog {
            self.filteredSearchCatalog = filteredSearchCatalog
        }
        if cacheScope != currentCacheScope || version != currentVersion {
            favoriteMutations.removeAll()
            confirmedFavorites.removeAll()
            favoriteRevision = 0
            favoriteError = nil
        }
        listingRequestID = nil
        currentQuery = normalizedQuery
        currentVersion = version
        currentFilters = filters
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
        if let cacheScope, filters.isEmpty {
            cached = await cache.load(
                query: normalizedQuery,
                version: version,
                scope: cacheScope,
                sortBy: filters.sortBy,
                sortDirection: filters.sortDirection
            )
        } else {
            cached = nil
        }
        guard !Task.isCancelled, self.requestID == requestID else { return }
        listing = listingApplyingCurrentFavorites(cached?.listing ?? CatalogListing())
        isShowingCachedData = cached != nil
        if useFreshCompleteCache,
           normalizedQuery.isEmpty,
           filters.isEmpty,
           let cached,
           cached.listing.hasMore == false,
           Date().timeIntervalSince(cached.cachedAt) < Self.completeCatalogFreshness {
            listingRequestID = requestID
            state = .loaded
            return
        }
        let startingFavoriteRevision = favoriteRevision
        do {
            let page = if normalizedQuery.isEmpty {
                try await performCompleteSearch(
                    query: normalizedQuery,
                    version: version,
                    filters: filters
                )
            } else {
                try await performSearch(
                    query: normalizedQuery,
                    cursor: nil,
                    version: version,
                    filters: filters
                )
            }
            guard !Task.isCancelled, self.requestID == requestID else { return }
            listing.replace(with: pageApplyingFavorites(page, confirmedAfter: startingFavoriteRevision))
            listingRequestID = requestID
            paginationGeneration += 1
            isShowingCachedData = false
            state = .loaded
            if let cacheScope, filters.isEmpty {
                try? await cache.save(
                    listingForCache(),
                    query: normalizedQuery,
                    version: version,
                    scope: cacheScope,
                    sortBy: filters.sortBy,
                    sortDirection: filters.sortDirection
                )
            }
            guard self.requestID == requestID,
                  currentVersion == version,
                  currentFilters == filters,
                  currentCacheScope == cacheScope else { return }
            discardConfirmedFavorites(through: startingFavoriteRevision)
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
            filters: currentFilters,
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

    func song(slug: String) -> CatalogSong? {
        listing.songs.first(where: { $0.slug == slug })
    }

    func isUpdatingFavorite(slug: String) -> Bool {
        favoriteMutations[slug] != nil
    }

    func clearFavoriteError() {
        favoriteError = nil
    }

    func setFavorite(
        _ saved: Bool,
        for song: CatalogSong,
        using update: FavoriteUpdate
    ) async {
        guard favoriteMutations[song.slug] == nil else { return }
        guard let cacheScope = currentCacheScope, cacheScope.hasPrefix("account:") else { return }

        let mutation = PendingFavoriteMutation(
            id: UUID(),
            previousValue: song.isFavorite,
            requestedValue: saved,
            startingRevision: favoriteRevision
        )
        let version = currentVersion
        guard listing.setFavorite(saved, forSlug: song.slug) else { return }

        favoriteError = nil
        favoriteMutations[song.slug] = mutation
        defer {
            if favoriteMutations[song.slug]?.id == mutation.id {
                favoriteMutations[song.slug] = nil
            }
        }

        do {
            let authoritativeValue = try await update(song.slug, saved, version)
            guard favoriteMutations[song.slug]?.id == mutation.id else {
                try? await cache.setFavorite(
                    authoritativeValue,
                    forSlug: song.slug,
                    version: version,
                    scope: cacheScope
                )
                return
            }
            await applyConfirmedFavorite(
                authoritativeValue,
                slug: song.slug,
                version: version,
                cacheScope: cacheScope
            )
        } catch is CancellationError {
            rollbackFavoriteIfCurrent(
                mutation,
                slug: song.slug,
                version: version,
                cacheScope: cacheScope
            )
        } catch {
            let shouldRestoreCache = !hasConfirmedFavorite(
                slug: song.slug,
                newerThan: mutation.startingRevision
            )
            rollbackFavoriteIfCurrent(
                mutation,
                slug: song.slug,
                version: version,
                cacheScope: cacheScope
            )
            if shouldRestoreCache {
                try? await cache.setFavorite(
                    mutation.previousValue,
                    forSlug: song.slug,
                    version: version,
                    scope: cacheScope
                )
            }
            if currentVersion == version, currentCacheScope == cacheScope {
                favoriteError = error.localizedDescription
            }
        }
    }

    func applyConfirmedFavorite(
        _ isFavorite: Bool,
        slug: String,
        version: PIUGameVersion,
        cacheScope: String
    ) async {
        var removedFromFavoriteFeed = false
        if currentVersion == version, currentCacheScope == cacheScope {
            if confirmedFavorites[slug]?.value != isFavorite {
                favoriteRevision += 1
                confirmedFavorites[slug] = ConfirmedFavorite(
                    value: isFavorite,
                    revision: favoriteRevision
                )
            }
            if isFavoriteFeed, !isFavorite {
                removedFromFavoriteFeed = listing.removeSong(slug: slug)
            } else {
                listing.setFavorite(isFavorite, forSlug: slug)
            }
        }
        try? await cache.setFavorite(
            isFavorite,
            forSlug: slug,
            version: version,
            scope: cacheScope
        )
        if removedFromFavoriteFeed {
            try? await cache.save(
                listingForCache(),
                query: currentQuery,
                version: version,
                scope: cacheScope,
                sortBy: currentFilters.sortBy,
                sortDirection: currentFilters.sortDirection
            )
        }
    }

    private var isFavoriteFeed: Bool {
        currentQuery.lowercased() == "favorites"
    }

    private func loadMore() async {
        guard listingRequestID == requestID, !isLoadingMore, let cursor = listing.nextCursor else { return }
        let requestID = self.requestID
        let startingFavoriteRevision = favoriteRevision
        isLoadingMore = true
        paginationError = nil
        defer {
            if self.requestID == requestID {
                isLoadingMore = false
            }
        }

        do {
            let page = try await performSearch(
                query: currentQuery,
                cursor: cursor,
                version: currentVersion,
                filters: currentFilters
            )
            guard !Task.isCancelled, self.requestID == requestID else { return }
            listing.append(
                pageApplyingFavorites(page, confirmedAfter: startingFavoriteRevision),
                requestedCursor: cursor
            )
            if let currentCacheScope, currentFilters.isEmpty {
                try? await cache.save(
                    listingForCache(),
                    query: currentQuery,
                    version: currentVersion,
                    scope: currentCacheScope,
                    sortBy: currentFilters.sortBy,
                    sortDirection: currentFilters.sortDirection
                )
            }
            guard self.requestID == requestID else { return }
            discardConfirmedFavorites(through: startingFavoriteRevision)
        } catch is CancellationError {
            return
        } catch {
            guard self.requestID == requestID else { return }
            paginationError = error.localizedDescription
        }
    }

    private func rollbackFavoriteIfCurrent(
        _ mutation: PendingFavoriteMutation,
        slug: String,
        version: PIUGameVersion,
        cacheScope: String
    ) {
        guard favoriteMutations[slug]?.id == mutation.id,
              !hasConfirmedFavorite(slug: slug, newerThan: mutation.startingRevision),
              currentVersion == version,
              currentCacheScope == cacheScope else { return }
        listing.setFavorite(mutation.previousValue, forSlug: slug)
    }

    private func listingApplyingCurrentFavorites(_ source: CatalogListing) -> CatalogListing {
        var listing = source
        for (slug, favorite) in confirmedFavorites {
            listing.setFavorite(favorite.value, forSlug: slug)
        }
        for (slug, mutation) in favoriteMutations {
            listing.setFavorite(mutation.requestedValue, forSlug: slug)
        }
        return listing
    }

    private func pageApplyingFavorites(
        _ source: CatalogSearchPage,
        confirmedAfter startingRevision: Int
    ) -> CatalogSearchPage {
        var songs = source.songs
        for index in songs.indices {
            let slug = songs[index].slug
            if let favorite = confirmedFavorites[slug], favorite.revision > startingRevision {
                songs[index].isFavorite = favorite.value
            }
            if let mutation = favoriteMutations[slug] {
                songs[index].isFavorite = mutation.requestedValue
            }
        }
        return CatalogSearchPage(
            songs: songs,
            nextCursor: source.nextCursor,
            total: source.total,
            filterOptions: source.filterOptions
        )
    }

    private func performSearch(
        query: String,
        cursor: String?,
        version: PIUGameVersion,
        filters: CatalogFilters
    ) async throws -> CatalogSearchPage {
        if filters.isEmpty && filters.usesDefaultSort {
            return try await searchCatalog(query, cursor, version)
        }
        return try await filteredSearchCatalog(query, cursor, version, filters)
    }

    private func performCompleteSearch(
        query: String,
        version: PIUGameVersion,
        filters: CatalogFilters
    ) async throws -> CatalogSearchPage {
        let firstPage = try await performSearch(
            query: query,
            cursor: nil,
            version: version,
            filters: filters
        )
        var listing = CatalogListing()
        listing.replace(with: firstPage)
        var pageCount = 1

        while let cursor = listing.nextCursor, pageCount < 200 {
            try Task.checkCancellation()
            let page = try await performSearch(
                query: query,
                cursor: cursor,
                version: version,
                filters: filters
            )
            listing.append(page, requestedCursor: cursor)
            pageCount += 1
        }

        return CatalogSearchPage(
            songs: listing.songs,
            nextCursor: nil,
            total: listing.total,
            filterOptions: listing.filterOptions
        )
    }

    private func listingForCache() -> CatalogListing {
        var cacheListing = listing
        for (slug, mutation) in favoriteMutations {
            let value = if let favorite = confirmedFavorites[slug],
                           favorite.revision > mutation.startingRevision {
                favorite.value
            } else {
                mutation.previousValue
            }
            cacheListing.setFavorite(value, forSlug: slug)
        }
        return cacheListing
    }

    private func hasConfirmedFavorite(slug: String, newerThan revision: Int) -> Bool {
        guard let favorite = confirmedFavorites[slug] else { return false }
        return favorite.revision > revision
    }

    private func discardConfirmedFavorites(through revision: Int) {
        confirmedFavorites = confirmedFavorites.filter { $0.value.revision > revision }
    }
}
