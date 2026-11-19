package com.austinkimchi.mypiu.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.austinkimchi.mypiu.AppContainer
import com.austinkimchi.mypiu.core.catalog.CatalogDataSource
import com.austinkimchi.mypiu.core.model.CatalogListing
import com.austinkimchi.mypiu.core.model.CatalogSearchPage
import com.austinkimchi.mypiu.core.model.CatalogSong
import com.austinkimchi.mypiu.core.model.CatalogSortDirection
import com.austinkimchi.mypiu.core.model.CatalogSortOption
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.SongChartPerformance
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import java.text.Normalizer
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class CatalogViewModel(
    private val repository: CatalogDataSource,
    refreshSignal: com.austinkimchi.mypiu.core.performance.PerformanceRefreshSignal = com.austinkimchi.mypiu.core.performance.PerformanceRefreshSignal(),
) : ViewModel() {
    private data class PendingFavorite(val id: UUID, val previous: Boolean, val requested: Boolean)
    private data class ConfirmedFavorite(val saved: Boolean, val protectThroughRequestId: Long)
    private data class FavoriteWriteKey(val scope: String, val slug: String)
    private data class FavoriteMutationKey(
        val scope: String,
        val version: PiuGameVersion,
        val sessionGeneration: Long,
        val slug: String,
    )

    private val mutableState = MutableStateFlow(CatalogUiState())
    val state: StateFlow<CatalogUiState> = mutableState.asStateFlow()

    private val pendingFavorites = mutableMapOf<FavoriteMutationKey, PendingFavorite>()
    private val confirmedFavorites = mutableMapOf<String, ConfirmedFavorite>()
    private val activeFavoriteWrites = mutableSetOf<FavoriteWriteKey>()
    private var latestSearchRequestId = 0L
    private var requestGeneration = 0
    private var sessionGeneration = 0L
    private var loadJob: Job? = null
    private var paginationJob: Job? = null
    private var historyJob: Job? = null
    private var started = false

    private var observedRefreshRevision = refreshSignal.revision.value

    init {
        viewModelScope.launch {
            refreshSignal.revision.collect { revision ->
                if (revision == observedRefreshRevision) return@collect
                observedRefreshRevision = revision
                repository.invalidateLocal()
                if (started && mutableState.value.isMyPiuConnected) refresh()
            }
        }
    }

    fun start() {
        if (started) return
        started = true
        reload(debounce = false)
    }

    fun updateSession(accountId: String?, connected: Boolean, preferredVersion: PiuGameVersion?) {
        val scope = when {
            accountId != null -> "account:$accountId"
            connected -> null
            else -> PUBLIC_SCOPE
        }
        val accountConnected = connected && accountId != null
        val current = mutableState.value
        val sessionIdentityChanged = current.cacheScope != scope || current.isMyPiuConnected != accountConnected
        val preferredVersionChanged = preferredVersion != null && current.version != preferredVersion
        if (current.cacheScope == scope && current.isMyPiuConnected == accountConnected && !preferredVersionChanged) return

        if (sessionIdentityChanged) {
            sessionGeneration += 1
            repository.invalidateLocal()
        }
        confirmedFavorites.clear()
        historyJob?.cancel()
        mutableState.update { state ->
            val disconnectedHistory = if (!accountConnected) {
                state.chartHistory?.copy(
                    isLoading = false,
                    performance = null,
                    error = state.chartHistory.error ?: SIGN_IN_FOR_HISTORY_MESSAGE,
                )
            } else {
                null
            }
            state.copy(
                cacheScope = scope,
                isMyPiuConnected = accountConnected,
                feed = if (!accountConnected && state.feed.requiresAccount) CatalogFeed.CATALOG else state.feed,
                version = preferredVersion ?: state.version,
                listing = CatalogListing(),
                updatingFavorites = activeFavoriteSlugs(scope),
                detailFavoriteStates = emptyMap(),
                favoriteError = null,
                chartHistory = disconnectedHistory,
            )
        }
        if (started) reload(debounce = false)
    }

    fun setFeed(feed: CatalogFeed) {
        val current = mutableState.value
        if (current.feed == feed || (feed.requiresAccount && !current.isMyPiuConnected)) return
        mutableState.update { it.copy(feed = feed, listing = CatalogListing(), error = null) }
        reload(debounce = false)
    }

    fun setVersion(version: PiuGameVersion) {
        if (mutableState.value.version == version) return
        confirmedFavorites.clear()
        historyJob?.cancel()
        mutableState.update {
            it.copy(
                version = version,
                listing = CatalogListing(),
                updatingFavorites = activeFavoriteSlugs(it.cacheScope),
                detailFavoriteStates = emptyMap(),
                favoriteError = null,
                chartHistory = null,
            )
        }
        reload(debounce = false)
    }

    fun setQuery(query: String) {
        if (mutableState.value.feed != CatalogFeed.CATALOG || mutableState.value.query == query) return
        mutableState.update { it.copy(query = query) }
        reload(debounce = query.isNotBlank())
    }

    fun setSort(sortBy: CatalogSortOption, sortDirection: CatalogSortDirection) {
        val current = mutableState.value
        if (current.feed != CatalogFeed.CATALOG ||
            current.sortBy == sortBy && current.sortDirection == sortDirection
        ) return
        mutableState.update { it.copy(sortBy = sortBy, sortDirection = sortDirection) }
        reload(debounce = false)
    }

    fun refresh() = reload(debounce = false, useFreshCompleteCache = false)

    fun loadMore() {
        val snapshot = mutableState.value
        val cursor = snapshot.listing.nextCursor ?: return
        if (snapshot.isLoading || snapshot.isLoadingMore || paginationJob?.isActive == true) return
        val generation = requestGeneration
        val query = snapshot.requestQuery
        val version = snapshot.version
        val scope = snapshot.cacheScope
        val authenticated = snapshot.isMyPiuConnected
        val sortBy = snapshot.sortBy
        val sortDirection = snapshot.sortDirection
        val requestId = ++latestSearchRequestId
        paginationJob = viewModelScope.launch {
            mutableState.update { it.copy(isLoadingMore = true, paginationError = null) }
            try {
                val page = repository.search(query, cursor, version, authenticated, sortBy, sortDirection)
                if (generation != requestGeneration) return@launch
                check(page.nextCursor != cursor) { "The catalog response repeated a page. Please retry." }
                val listing = applyFavoriteOverrides(
                    mutableState.value.listing.append(page, cursor),
                    requestId,
                    scope,
                    version,
                )
                retireFavoriteOverrides(requestId)
                mutableState.update { it.copy(listing = listing, isLoadingMore = false) }
                scope?.let {
                    runCatching {
                        repository.cache(listingForCache(listing, it, version), query, version, it, sortBy, sortDirection)
                    }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (generation != requestGeneration) return@launch
                noteAuthorizationFailure(error)
                mutableState.update {
                    it.copy(
                        isLoadingMore = false,
                        paginationError = error.message ?: "More songs could not be loaded.",
                    )
                }
            }
        }
    }

    fun toggleFavorite(song: CatalogSong) {
        val snapshot = mutableState.value
        if (!snapshot.isMyPiuConnected) return
        val version = snapshot.version
        val scope = snapshot.cacheScope ?: return
        val writeKey = FavoriteWriteKey(scope, song.slug)
        if (!activeFavoriteWrites.add(writeKey)) return
        val mutationSessionGeneration = sessionGeneration
        val mutationKey = FavoriteMutationKey(scope, version, mutationSessionGeneration, song.slug)
        val requested = !song.isFavorite
        val mutation = PendingFavorite(UUID.randomUUID(), song.isFavorite, requested)
        pendingFavorites[mutationKey] = mutation
        mutableState.update {
            it.copy(
                listing = it.listing.setFavorite(song.slug, requested),
                updatingFavorites = activeFavoriteSlugs(scope),
                detailFavoriteStates = it.detailFavoriteStates + (song.slug to requested),
                favoriteError = null,
            )
        }

        viewModelScope.launch {
            try {
                val authoritative = repository.setFavorite(song.slug, requested, version)
                val isCurrentMutation = finishFavoriteMutation(mutationKey, mutation)
                val current = mutableState.value
                val shouldReconcileReplacementSession =
                    isCurrentMutation &&
                        mutationSessionGeneration != sessionGeneration &&
                        current.isMyPiuConnected &&
                        current.version == version &&
                        current.cacheScope == scope
                if (
                    isCurrentMutation &&
                    mutationSessionGeneration == sessionGeneration &&
                    current.version == version &&
                    current.cacheScope == scope
                ) {
                    confirmedFavorites[song.slug] = ConfirmedFavorite(authoritative, latestSearchRequestId)
                    val listing = when {
                        current.feed == CatalogFeed.FAVORITES && !authoritative -> {
                            current.listing.removeSong(song.slug)
                        }
                        current.feed == CatalogFeed.FAVORITES -> {
                            current.listing.upsertSong(song.copy(isFavorite = true))
                        }
                        else -> current.listing.setFavorite(song.slug, authoritative)
                    }
                    mutableState.update {
                        it.copy(
                            listing = listing,
                            updatingFavorites = activeFavoriteSlugs(scope),
                            detailFavoriteStates = it.detailFavoriteStates + (song.slug to authoritative),
                        )
                    }
                }
                if (isCurrentMutation) {
                    try {
                        repository.cacheFavorite(authoritative, song.slug, version, scope)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        // A future catalog load can repair a failed best-effort cache update.
                    }
                }
                if (
                    shouldReconcileReplacementSession &&
                    mutationSessionGeneration != sessionGeneration &&
                    mutableState.value.isMyPiuConnected &&
                    mutableState.value.version == version &&
                    mutableState.value.cacheScope == scope
                ) {
                    reload(debounce = false)
                }
            } catch (error: CancellationException) {
                if (finishFavoriteMutation(mutationKey, mutation)) {
                    rollbackFavorite(song.slug, mutation, version, scope, mutationSessionGeneration)
                }
                throw error
            } catch (error: Exception) {
                val isCurrentMutation = finishFavoriteMutation(mutationKey, mutation)
                if (isCurrentMutation) {
                    rollbackFavorite(song.slug, mutation, version, scope, mutationSessionGeneration)
                }
                if (
                    isCurrentMutation &&
                    mutationSessionGeneration == sessionGeneration &&
                    mutableState.value.version == version &&
                    mutableState.value.cacheScope == scope
                ) {
                    noteAuthorizationFailure(error)
                    mutableState.update {
                        it.copy(favoriteError = error.message ?: "The favorite could not be updated.")
                    }
                }
            } finally {
                activeFavoriteWrites.remove(writeKey)
                if (mutableState.value.cacheScope == scope) {
                    mutableState.update { it.copy(updatingFavorites = activeFavoriteSlugs(scope)) }
                }
            }
        }
    }

    fun dismissFavoriteError() {
        mutableState.update { it.copy(favoriteError = null) }
    }

    fun song(slug: String): CatalogSong? = mutableState.value.listing.songs.firstOrNull { it.slug == slug }

    fun imageUrl(song: CatalogSong): String? = repository.resolveUrl(song.imageUrl)

    fun artworkUrl(songTitle: String): String? =
        mutableState.value.artworkByTitle[artworkKey(songTitle)]

    fun loadChartHistory(song: CatalogSong, chartToken: String, force: Boolean = false) {
        val current = mutableState.value
        val existing = current.chartHistory
        if (!force && existing?.songSlug == song.slug && existing.chartToken == chartToken && !existing.isLoading) return
        historyJob?.cancel()
        if (!current.isMyPiuConnected) {
            mutableState.update {
                it.copy(
                    chartHistory = ChartHistoryUiState(
                        songSlug = song.slug,
                        chartToken = chartToken,
                        error = SIGN_IN_FOR_HISTORY_MESSAGE,
                    ),
                )
            }
            return
        }
        val version = current.version
        val scope = current.cacheScope ?: return
        historyJob = viewModelScope.launch {
            mutableState.update {
                it.copy(chartHistory = ChartHistoryUiState(song.slug, chartToken, isLoading = true))
            }
            try {
                val performance = repository.chartPerformance(song.slug, chartToken, version)
                val latest = mutableState.value
                if (
                    latest.version != version || latest.cacheScope != scope ||
                    latest.chartHistory?.songSlug != song.slug || latest.chartHistory?.chartToken != chartToken
                ) return@launch
                mutableState.update {
                    it.copy(
                        chartHistory = ChartHistoryUiState(
                            songSlug = song.slug,
                            chartToken = chartToken,
                            performance = performance,
                        ),
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val latest = mutableState.value
                if (
                    latest.version != version || latest.cacheScope != scope ||
                    latest.chartHistory?.songSlug != song.slug || latest.chartHistory?.chartToken != chartToken
                ) return@launch
                noteAuthorizationFailure(error)
                mutableState.update {
                    it.copy(
                        chartHistory = ChartHistoryUiState(
                            songSlug = song.slug,
                            chartToken = chartToken,
                            error = error.message ?: "Chart history could not be loaded.",
                        ),
                    )
                }
            }
        }
    }

    fun acknowledgeSessionInvalidation() {
        mutableState.update { it.copy(sessionInvalidated = false) }
    }

    private fun reload(debounce: Boolean, useFreshCompleteCache: Boolean = true) {
        loadJob?.cancel()
        paginationJob?.cancel()
        val generation = ++requestGeneration
        loadJob = viewModelScope.launch {
            if (debounce) delay(SEARCH_DEBOUNCE_MILLIS)
            val snapshot = mutableState.value
            val query = snapshot.requestQuery
            val version = snapshot.version
            val scope = snapshot.cacheScope
            val authenticated = snapshot.isMyPiuConnected
            val sortBy = snapshot.sortBy
            val sortDirection = snapshot.sortDirection
            mutableState.update {
                it.copy(
                    listing = if (useFreshCompleteCache) CatalogListing() else it.listing,
                    isLoading = true,
                    isLoadingMore = false,
                    isShowingCachedData = false,
                    error = null,
                    paginationError = null,
                )
            }
            val cached = scope?.let { repository.cached(query, version, it, sortBy, sortDirection) }
            if (generation != requestGeneration) return@launch
            if (snapshot.feed == CatalogFeed.CATALOG && query.isBlank()) {
                repository.cachedPublic(version)?.let { publicPage ->
                    if (generation == requestGeneration) mutableState.update {
                        it.copy(artworkByTitle = it.artworkByTitle + artworkIndex(publicPage.songs))
                    }
                }
            }
            if (generation != requestGeneration) return@launch
            if (cached != null) {
                mutableState.update {
                    it.copy(
                        listing = applyFavoriteOverrides(cached.listing, scope = scope, version = version),
                        artworkByTitle = if (
                            snapshot.feed == CatalogFeed.CATALOG && query.isBlank() && cached.listing.nextCursor == null
                        ) {
                            it.artworkByTitle + artworkIndex(cached.listing.songs)
                        } else {
                            it.artworkByTitle
                        },
                        isShowingCachedData = true,
                    )
                }
                val cacheIsFresh = System.currentTimeMillis() - cached.cachedAtEpochMillis < COMPLETE_CATALOG_FRESHNESS_MILLIS
                if (
                    useFreshCompleteCache && !authenticated && !repository.supportsSnapshot &&
                    snapshot.feed == CatalogFeed.CATALOG && query.isBlank() &&
                    cached.listing.nextCursor == null && cached.listing.total == cached.listing.songs.size && cacheIsFresh
                ) {
                    mutableState.update { it.copy(isLoading = false) }
                    return@launch
                }
            }
            val requestId = ++latestSearchRequestId
            try {
                val bulkPage = if (snapshot.feed == CatalogFeed.CATALOG)
                    repository.localQuery(query, version, authenticated, sortBy, sortDirection, useFreshCompleteCache) else null
                val page = bulkPage ?: run {
                    val firstPage = repository.search(query, null, version, authenticated, sortBy, sortDirection)
                    if (snapshot.feed == CatalogFeed.CATALOG && query.isBlank()) {
                        completeCatalogPage(firstPage, query, version, authenticated, sortBy, sortDirection) { partial ->
                            if (generation == requestGeneration && cached == null &&
                                (useFreshCompleteCache || snapshot.listing.songs.isEmpty())) {
                                mutableState.update { it.copy(
                                    listing = applyFavoriteOverrides(partial, requestId, scope, version),
                                    artworkByTitle = it.artworkByTitle + artworkIndex(partial.songs),
                                ) }
                            }
                        }
                    } else firstPage
                }
                if (generation != requestGeneration) return@launch
                val listing = applyFavoriteOverrides(
                    CatalogListing(page.songs, page.nextCursor, page.total),
                    requestId,
                    scope,
                    version,
                )
                retireFavoriteOverrides(requestId)
                mutableState.update {
                    it.copy(
                        listing = listing,
                        artworkByTitle = if (snapshot.feed == CatalogFeed.CATALOG && query.isBlank()) {
                            it.artworkByTitle + artworkIndex(listing.songs)
                        } else {
                            it.artworkByTitle
                        },
                        isLoading = false,
                        isShowingCachedData = false,
                        error = null,
                    )
                }
                scope?.let {
                    runCatching {
                        repository.cache(listingForCache(listing, it, version), query, version, it, sortBy, sortDirection)
                    }
                }
            } catch (error: CancellationException) {
                if (generation == requestGeneration) mutableState.update { it.copy(isLoading = false) }
                throw error
            } catch (error: Exception) {
                if (generation != requestGeneration) return@launch
                noteAuthorizationFailure(error)
                mutableState.update {
                    it.copy(
                        isLoading = false,
                        error = error.message ?: "The catalog could not be loaded.",
                    )
                }
            }
        }
    }

    private suspend fun completeCatalogPage(
        firstPage: CatalogSearchPage,
        query: String,
        version: PiuGameVersion,
        authenticated: Boolean,
        sortBy: CatalogSortOption,
        sortDirection: CatalogSortDirection,
        onProgress: (CatalogListing) -> Unit,
    ): CatalogSearchPage {
        var listing = CatalogListing(firstPage.songs, firstPage.nextCursor, firstPage.total)
        var pageCount = 1
        val seenCursors = mutableSetOf<String>()
        onProgress(listing)
        while (listing.nextCursor != null) {
            val cursor = listing.nextCursor ?: break
            check(pageCount < 200 && seenCursors.add(cursor)) { "The catalog response was incomplete. Please retry." }
            val page = repository.search(query, cursor, version, authenticated, sortBy, sortDirection)
            check(page.nextCursor != cursor) { "The catalog response repeated a page. Please retry." }
            listing = listing.append(page, cursor)
            pageCount += 1
            onProgress(listing)
        }
        check(listing.total == listing.songs.size) { "The catalog response was incomplete. Please retry." }
        return CatalogSearchPage(
            songs = listing.songs,
            nextCursor = null,
            total = listing.total,
        )
    }

    private fun applyFavoriteOverrides(
        listing: CatalogListing,
        requestId: Long? = null,
        scope: String? = mutableState.value.cacheScope,
        version: PiuGameVersion = mutableState.value.version,
    ): CatalogListing = listing.copy(
        songs = listing.songs.map { song ->
            val confirmed = confirmedFavorites[song.slug]
                ?.takeIf { requestId == null || requestId <= it.protectThroughRequestId }
                ?.saved
            val pending = scope?.let {
                pendingFavorites[FavoriteMutationKey(it, version, sessionGeneration, song.slug)]
            }
            val saved = pending?.requested ?: confirmed
            if (saved == null) song else song.copy(isFavorite = saved)
        },
    )

    private fun retireFavoriteOverrides(requestId: Long) {
        confirmedFavorites.entries.removeAll { it.value.protectThroughRequestId <= requestId }
    }

    private fun listingForCache(
        listing: CatalogListing,
        scope: String,
        version: PiuGameVersion,
    ): CatalogListing = listing.copy(
        songs = listing.songs.map { song ->
            val pending = pendingFavorites[FavoriteMutationKey(scope, version, sessionGeneration, song.slug)]
            if (pending == null) song else song.copy(isFavorite = pending.previous)
        },
    )

    private fun rollbackFavorite(
        slug: String,
        mutation: PendingFavorite,
        version: PiuGameVersion,
        scope: String,
        mutationSessionGeneration: Long,
    ) {
        if (
            sessionGeneration != mutationSessionGeneration ||
            mutableState.value.version != version ||
            mutableState.value.cacheScope != scope
        ) return
        mutableState.update {
            it.copy(
                listing = it.listing.setFavorite(slug, mutation.previous),
                updatingFavorites = activeFavoriteSlugs(scope),
                detailFavoriteStates = it.detailFavoriteStates + (slug to mutation.previous),
            )
        }
    }

    private fun finishFavoriteMutation(key: FavoriteMutationKey, mutation: PendingFavorite): Boolean {
        if (pendingFavorites[key]?.id != mutation.id) return false
        pendingFavorites.remove(key)
        return true
    }

    private fun activeFavoriteSlugs(scope: String?): Set<String> {
        if (scope == null) return emptySet()
        return activeFavoriteWrites
            .asSequence()
            .filter { it.scope == scope }
            .mapTo(mutableSetOf(), FavoriteWriteKey::slug)
    }

    private fun noteAuthorizationFailure(error: Exception) {
        if (error is MyPiuApiException && (error.isUnauthorized || error.isAccountNotFound)) {
            mutableState.update {
                it.copy(isMyPiuConnected = false, sessionInvalidated = true)
            }
        }
    }

    private fun artworkIndex(songs: List<CatalogSong>): Map<String, String> =
        songs.mapNotNull { song ->
            repository.resolveUrl(song.imageUrl)?.let { artworkKey(song.title) to it }
        }.toMap()

    class Factory(private val container: AppContainer) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            CatalogViewModel(container.catalogRepository, container.performanceRefreshSignal) as T
    }

    private companion object {
        const val PUBLIC_SCOPE = "public"
        const val SEARCH_DEBOUNCE_MILLIS = 300L
        const val SIGN_IN_FOR_HISTORY_MESSAGE = "Sign in to MyPIU to view chart history."
        const val COMPLETE_CATALOG_FRESHNESS_MILLIS = 7L * 24 * 60 * 60 * 1_000
    }
}

private fun artworkKey(value: String): String =
    Normalizer.normalize(value, Normalizer.Form.NFKC)
        .trim()
        .replace(Regex("\\s+"), " ")
        .lowercase(Locale.ROOT)

enum class CatalogFeed(val label: String, val query: String, val requiresAccount: Boolean) {
    CATALOG("Catalog", "", false),
    RECOMMENDATIONS("For you", "recommendation", true),
    FAVORITES("Favorites", "favorites", true),
}

data class CatalogUiState(
    val feed: CatalogFeed = CatalogFeed.CATALOG,
    val query: String = "",
    val version: PiuGameVersion = PiuGameVersion.PHOENIX_2,
    val sortBy: CatalogSortOption = CatalogSortOption.SERIES,
    val sortDirection: CatalogSortDirection = CatalogSortDirection.DESCENDING,
    val cacheScope: String? = "public",
    val isMyPiuConnected: Boolean = false,
    val listing: CatalogListing = CatalogListing(),
    val artworkByTitle: Map<String, String> = emptyMap(),
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val isShowingCachedData: Boolean = false,
    val error: String? = null,
    val paginationError: String? = null,
    val updatingFavorites: Set<String> = emptySet(),
    val detailFavoriteStates: Map<String, Boolean> = emptyMap(),
    val favoriteError: String? = null,
    val chartHistory: ChartHistoryUiState? = null,
    val sessionInvalidated: Boolean = false,
) {
    val requestQuery: String get() = if (feed == CatalogFeed.CATALOG) query.trim() else feed.query
}

data class ChartHistoryUiState(
    val songSlug: String,
    val chartToken: String,
    val isLoading: Boolean = false,
    val performance: SongChartPerformance? = null,
    val error: String? = null,
)
