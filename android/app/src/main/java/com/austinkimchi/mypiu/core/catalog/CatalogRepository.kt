package com.austinkimchi.mypiu.core.catalog

import kotlinx.coroutines.async
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.CancellationException
import com.austinkimchi.mypiu.core.model.CatalogListing
import com.austinkimchi.mypiu.core.model.CatalogSearchPage
import com.austinkimchi.mypiu.core.model.CatalogSortDirection
import com.austinkimchi.mypiu.core.model.CatalogSortOption
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.SongChartPerformance
import com.austinkimchi.mypiu.core.model.CatalogLocalQuery
import com.austinkimchi.mypiu.core.model.PublicCatalogSnapshot
import com.austinkimchi.mypiu.core.model.MobileCatalogOverlay
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.security.SessionStore

interface CatalogDataSource {
    val supportsSnapshot: Boolean get() = false
    suspend fun snapshot(version: PiuGameVersion, authenticated: Boolean): CatalogSearchPage? = null
    fun invalidateLocal() {}
    suspend fun localQuery(query: String, version: PiuGameVersion, authenticated: Boolean,
        sortBy: CatalogSortOption, sortDirection: CatalogSortDirection, reuse: Boolean): CatalogSearchPage? =
        if (query.isBlank() && sortBy == CatalogSortOption.SERIES && sortDirection == CatalogSortDirection.DESCENDING)
            snapshot(version, authenticated) else null
    suspend fun cachedPublic(version: PiuGameVersion): CatalogSearchPage? = null
    suspend fun search(
        query: String,
        cursor: String?,
        version: PiuGameVersion,
        authenticated: Boolean,
        sortBy: CatalogSortOption = CatalogSortOption.SERIES,
        sortDirection: CatalogSortDirection = CatalogSortDirection.DESCENDING,
    ): CatalogSearchPage
    suspend fun setFavorite(slug: String, saved: Boolean, version: PiuGameVersion): Boolean
    suspend fun chartPerformance(slug: String, chart: String, version: PiuGameVersion): SongChartPerformance?
    suspend fun cached(query: String, version: PiuGameVersion, scope: String, sortBy: CatalogSortOption, sortDirection: CatalogSortDirection): CatalogCache.CachedListing?
    suspend fun cache(listing: CatalogListing, query: String, version: PiuGameVersion, scope: String, sortBy: CatalogSortOption, sortDirection: CatalogSortDirection)
    suspend fun cacheFavorite(saved: Boolean, slug: String, version: PiuGameVersion, scope: String)
    fun resolveUrl(value: String?): String?
}

class CatalogRepository(
    private val sessionStore: SessionStore,
    private val apiClient: MyPiuApiClient,
    private val cache: CatalogCache,
    private val publicCatalog: PublicCatalogStore? = null,
) : CatalogDataSource {
    override val supportsSnapshot: Boolean get() = publicCatalog != null
    private data class Dataset(val snapshot: PublicCatalogSnapshot, val overlay: MobileCatalogOverlay?)
    private data class Favorite(val saved: Boolean, val revision: Long)
    private val localLock = Any()
    private val datasets = mutableMapOf<PiuGameVersion, Dataset>()
    private val favorites = mutableMapOf<Pair<PiuGameVersion, String>, Favorite>()
    private val requests = mutableMapOf<PiuGameVersion, Long>()
    private var revision = 0L
    private var generation = 0L
    private var localIdentity: String? = null

    override fun invalidateLocal() {
        synchronized(localLock) {
            datasets.clear(); favorites.clear(); requests.clear(); generation += 1
        }
    }

    override suspend fun cachedPublic(version: PiuGameVersion): CatalogSearchPage? = publicCatalog?.cached(version)?.defaultPage()

    override suspend fun snapshot(version: PiuGameVersion, authenticated: Boolean): CatalogSearchPage? {
        return localQuery("", version, authenticated, CatalogSortOption.SERIES, CatalogSortDirection.DESCENDING, false)
    }

    override suspend fun localQuery(query: String, version: PiuGameVersion, authenticated: Boolean,
        sortBy: CatalogSortOption, sortDirection: CatalogSortDirection, reuse: Boolean): CatalogSearchPage? {
        if (!CatalogLocalQuery.isOrdinary(query)) return null
        val store = publicCatalog ?: return null
        val token = if (authenticated) sessionStore.accessToken()?.takeUnless { it.isExpired() }?.value
            ?: throw MyPiuApiException(401, "invalid_token") else null
        val identity = token?.let { "account:$it" } ?: "public"
        val filters = CatalogLocalQuery.Filters(sortBy = sortBy, sortDirection = sortDirection)
        val context = synchronized(localLock) {
            if (localIdentity != identity) { invalidateLocal(); localIdentity = identity }
            if (reuse) datasets[version]?.let { return CatalogLocalQuery.query(it.snapshot, it.overlay, query, filters).page }
            val request = (requests[version] ?: 0) + 1
            requests[version] = request
            Triple(generation, request, revision)
        }
        return try {
            kotlinx.coroutines.coroutineScope {
                val snapshot = async { store.refresh(version) }
                var overlay = if (authenticated) withSession { apiClient.catalogOverlay(version, it) } else null
                val public = snapshot.await()
                kotlinx.coroutines.currentCoroutineContext().ensureActive()
                synchronized(localLock) {
                    if (generation != context.first || requests[version] != context.second ||
                        authenticated && sessionStore.accessToken()?.value != token) throw CancellationException("Account or request changed")
                    favorites.filter { it.key.first == version && it.value.revision > context.third }.forEach { (key, favorite) ->
                        overlay = overlay?.settingFavorite(favorite.saved, key.second)
                    }
                    val result = CatalogLocalQuery.query(public, overlay, query, filters).page
                    datasets[version] = Dataset(public, overlay)
                    result
                }
            }
        } catch (error: MyPiuApiException) {
            if (error.status == 404) null else throw error
        }
    }

    override suspend fun search(
        query: String,
        cursor: String?,
        version: PiuGameVersion,
        authenticated: Boolean,
        sortBy: CatalogSortOption,
        sortDirection: CatalogSortDirection,
    ): CatalogSearchPage {
        if (!authenticated) return apiClient.searchCatalog(query, cursor, version, null, sortBy, sortDirection)
        return withSession { token ->
            apiClient.searchCatalog(query, cursor, version, token, sortBy, sortDirection)
        }
    }

    override suspend fun setFavorite(slug: String, saved: Boolean, version: PiuGameVersion): Boolean {
        // The ViewModel reconciles successful writes into their original account scope and
        // refreshes a matching replacement session; only stale reads should be discarded.
        return withSession(requireCurrentSession = false) { token ->
            apiClient.setFavorite(slug, saved, version, token).also { value ->
                synchronized(localLock) {
                    if (localIdentity == "account:$token" && sessionStore.accessToken()?.value == token) {
                        favorites[version to slug] = Favorite(value, ++revision)
                        datasets[version]?.let { datasets[version] = it.copy(overlay = it.overlay?.settingFavorite(value, slug)) }
                    }
                }
            }
        }
    }

    override suspend fun chartPerformance(
        slug: String,
        chart: String,
        version: PiuGameVersion,
    ): SongChartPerformance? {
        return withSession { token ->
            apiClient.chartPerformance(slug, chart, version, token)
        }
    }

    override suspend fun cached(
        query: String,
        version: PiuGameVersion,
        scope: String,
        sortBy: CatalogSortOption,
        sortDirection: CatalogSortDirection,
    ): CatalogCache.CachedListing? = cache.load(query, version, scope, sortBy, sortDirection)

    override suspend fun cache(
        listing: CatalogListing,
        query: String,
        version: PiuGameVersion,
        scope: String,
        sortBy: CatalogSortOption,
        sortDirection: CatalogSortDirection,
    ) = cache.save(
        listing = listing,
        query = query,
        version = version,
        scope = scope,
        sortBy = sortBy,
        sortDirection = sortDirection,
    )

    override suspend fun cacheFavorite(
        saved: Boolean,
        slug: String,
        version: PiuGameVersion,
        scope: String,
    ) = cache.setFavorite(saved, slug, version, scope)

    override fun resolveUrl(value: String?): String? = apiClient.resolveUrl(value)

    private suspend fun <Value> withSession(requireCurrentSession: Boolean = true, operation: suspend (String) -> Value): Value {
        val storedToken = sessionStore.accessToken()
        val token = when {
            storedToken == null -> throw MyPiuApiException(401, "invalid_token")
            storedToken.isExpired() -> {
                sessionStore.clearAccessToken()
                throw MyPiuApiException(401, "invalid_token")
            }
            else -> storedToken.value
        }
        return try {
            operation(token).also {
                if (requireCurrentSession && sessionStore.accessToken()?.value != token) throw CancellationException("Account changed")
            }
        } catch (error: MyPiuApiException) {
            if (
                (error.isUnauthorized || error.isAccountNotFound) &&
                sessionStore.accessToken()?.value == token
            ) {
                sessionStore.clearAccessToken()
            }
            throw error
        }
    }
}
