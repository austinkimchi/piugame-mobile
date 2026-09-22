package com.austinkimchi.mypiu.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.austinkimchi.mypiu.AppContainer
import com.austinkimchi.mypiu.core.catalog.CatalogDataSource
import com.austinkimchi.mypiu.core.model.CatalogListing
import com.austinkimchi.mypiu.core.model.CatalogSong
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.SongChartPerformance
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class CatalogViewModel(private val repository: CatalogDataSource) : ViewModel() {
    private data class PendingFavorite(val id: UUID, val previous: Boolean, val requested: Boolean)

    private val mutableState = MutableStateFlow(CatalogUiState())
    val state: StateFlow<CatalogUiState> = mutableState.asStateFlow()

    private val pendingFavorites = mutableMapOf<String, PendingFavorite>()
    private val confirmedFavorites = mutableMapOf<String, Boolean>()
    private var requestGeneration = 0
    private var loadJob: Job? = null
    private var paginationJob: Job? = null
    private var historyJob: Job? = null
    private var started = false

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
        val preferredVersionChanged = preferredVersion != null && current.version != preferredVersion
        if (current.cacheScope == scope && current.isMyPiuConnected == accountConnected && !preferredVersionChanged) return

        pendingFavorites.clear()
        confirmedFavorites.clear()
        historyJob?.cancel()
        mutableState.update {
            it.copy(
                cacheScope = scope,
                isMyPiuConnected = accountConnected,
                feed = if (!accountConnected && it.feed.requiresAccount) CatalogFeed.CATALOG else it.feed,
                version = preferredVersion ?: it.version,
                listing = CatalogListing(),
                updatingFavorites = emptySet(),
                favoriteError = null,
                chartHistory = null,
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
        pendingFavorites.clear()
        confirmedFavorites.clear()
        historyJob?.cancel()
        mutableState.update {
            it.copy(
                version = version,
                listing = CatalogListing(),
                updatingFavorites = emptySet(),
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

    fun refresh() = reload(debounce = false)

    fun loadMore() {
        val snapshot = mutableState.value
        val cursor = snapshot.listing.nextCursor ?: return
        if (snapshot.isLoading || snapshot.isLoadingMore || paginationJob?.isActive == true) return
        val generation = requestGeneration
        val query = snapshot.requestQuery
        val version = snapshot.version
        val scope = snapshot.cacheScope
        paginationJob = viewModelScope.launch {
            mutableState.update { it.copy(isLoadingMore = true, paginationError = null) }
            try {
                val page = repository.search(query, cursor, version)
                if (generation != requestGeneration) return@launch
                val listing = applyFavoriteOverrides(mutableState.value.listing.append(page, cursor))
                mutableState.update { it.copy(listing = listing, isLoadingMore = false) }
                scope?.let { runCatching { repository.cache(listingForCache(listing), query, version, it) } }
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
        if (!snapshot.isMyPiuConnected || pendingFavorites.containsKey(song.slug)) return
        val requested = !song.isFavorite
        val mutation = PendingFavorite(UUID.randomUUID(), song.isFavorite, requested)
        val version = snapshot.version
        val scope = snapshot.cacheScope ?: return
        pendingFavorites[song.slug] = mutation
        mutableState.update {
            it.copy(
                listing = it.listing.setFavorite(song.slug, requested),
                updatingFavorites = pendingFavorites.keys.toSet(),
                favoriteError = null,
            )
        }

        viewModelScope.launch {
            try {
                val authoritative = repository.setFavorite(song.slug, requested, version)
                val isCurrentMutation = finishFavoriteMutation(song.slug, mutation)
                runCatching { repository.cacheFavorite(authoritative, song.slug, version, scope) }
                val current = mutableState.value
                if (isCurrentMutation && current.version == version && current.cacheScope == scope) {
                    confirmedFavorites[song.slug] = authoritative
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
                        it.copy(listing = listing, updatingFavorites = pendingFavorites.keys.toSet())
                    }
                }
            } catch (error: CancellationException) {
                if (finishFavoriteMutation(song.slug, mutation)) {
                    rollbackFavorite(song.slug, mutation, version, scope)
                }
                throw error
            } catch (error: Exception) {
                val isCurrentMutation = finishFavoriteMutation(song.slug, mutation)
                if (isCurrentMutation) rollbackFavorite(song.slug, mutation, version, scope)
                if (
                    isCurrentMutation &&
                    mutableState.value.version == version &&
                    mutableState.value.cacheScope == scope
                ) {
                    noteAuthorizationFailure(error)
                    mutableState.update {
                        it.copy(favoriteError = error.message ?: "The favorite could not be updated.")
                    }
                }
            }
        }
    }

    fun dismissFavoriteError() {
        mutableState.update { it.copy(favoriteError = null) }
    }

    fun song(slug: String): CatalogSong? = mutableState.value.listing.songs.firstOrNull { it.slug == slug }

    fun imageUrl(song: CatalogSong): String? = repository.resolveUrl(song.imageUrl)

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
                        error = "Sign in to MyPIU to view chart history.",
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

    private fun reload(debounce: Boolean) {
        loadJob?.cancel()
        paginationJob?.cancel()
        val generation = ++requestGeneration
        loadJob = viewModelScope.launch {
            if (debounce) delay(SEARCH_DEBOUNCE_MILLIS)
            val snapshot = mutableState.value
            val query = snapshot.requestQuery
            val version = snapshot.version
            val scope = snapshot.cacheScope
            mutableState.update {
                it.copy(
                    listing = CatalogListing(),
                    isLoading = true,
                    isLoadingMore = false,
                    isShowingCachedData = false,
                    error = null,
                    paginationError = null,
                )
            }
            val cached = scope?.let { repository.cached(query, version, it) }
            if (generation != requestGeneration) return@launch
            if (cached != null) {
                mutableState.update {
                    it.copy(listing = applyFavoriteOverrides(cached.listing), isShowingCachedData = true)
                }
            }
            try {
                val page = repository.search(query, null, version)
                if (generation != requestGeneration) return@launch
                val listing = applyFavoriteOverrides(CatalogListing(page.songs, page.nextCursor, page.total))
                mutableState.update {
                    it.copy(
                        listing = listing,
                        isLoading = false,
                        isShowingCachedData = false,
                        error = null,
                    )
                }
                scope?.let { runCatching { repository.cache(listingForCache(listing), query, version, it) } }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (generation != requestGeneration) return@launch
                noteAuthorizationFailure(error)
                mutableState.update {
                    it.copy(
                        isLoading = false,
                        error = if (cached == null) error.message ?: "The catalog could not be loaded." else null,
                    )
                }
            }
        }
    }

    private fun applyFavoriteOverrides(listing: CatalogListing): CatalogListing = listing.copy(
        songs = listing.songs.map { song ->
            val saved = pendingFavorites[song.slug]?.requested ?: confirmedFavorites[song.slug]
            if (saved == null) song else song.copy(isFavorite = saved)
        },
    )

    private fun listingForCache(listing: CatalogListing): CatalogListing = listing.copy(
        songs = listing.songs.map { song ->
            val pending = pendingFavorites[song.slug]
            if (pending == null) song else song.copy(isFavorite = pending.previous)
        },
    )

    private fun rollbackFavorite(
        slug: String,
        mutation: PendingFavorite,
        version: PiuGameVersion,
        scope: String,
    ) {
        if (mutableState.value.version != version || mutableState.value.cacheScope != scope) return
        mutableState.update {
            it.copy(
                listing = it.listing.setFavorite(slug, mutation.previous),
                updatingFavorites = pendingFavorites.keys.toSet(),
            )
        }
    }

    private fun finishFavoriteMutation(slug: String, mutation: PendingFavorite): Boolean {
        if (pendingFavorites[slug]?.id != mutation.id) return false
        pendingFavorites.remove(slug)
        return true
    }

    private fun noteAuthorizationFailure(error: Exception) {
        if (error is MyPiuApiException && (error.isUnauthorized || error.isAccountNotFound)) {
            mutableState.update {
                it.copy(isMyPiuConnected = false, sessionInvalidated = true)
            }
        }
    }

    class Factory(private val container: AppContainer) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            CatalogViewModel(container.catalogRepository) as T
    }

    private companion object {
        const val PUBLIC_SCOPE = "public"
        const val SEARCH_DEBOUNCE_MILLIS = 300L
    }
}

enum class CatalogFeed(val label: String, val query: String, val requiresAccount: Boolean) {
    CATALOG("Catalog", "", false),
    RECOMMENDATIONS("For you", "recommendation", true),
    FAVORITES("Favorites", "favorites", true),
}

data class CatalogUiState(
    val feed: CatalogFeed = CatalogFeed.CATALOG,
    val query: String = "",
    val version: PiuGameVersion = PiuGameVersion.PHOENIX_2,
    val cacheScope: String? = "public",
    val isMyPiuConnected: Boolean = false,
    val listing: CatalogListing = CatalogListing(),
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val isShowingCachedData: Boolean = false,
    val error: String? = null,
    val paginationError: String? = null,
    val updatingFavorites: Set<String> = emptySet(),
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
