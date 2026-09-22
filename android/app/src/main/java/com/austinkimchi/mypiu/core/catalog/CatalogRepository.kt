package com.austinkimchi.mypiu.core.catalog

import com.austinkimchi.mypiu.core.model.CatalogListing
import com.austinkimchi.mypiu.core.model.CatalogSearchPage
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.SongChartPerformance
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.security.SessionStore

interface CatalogDataSource {
    suspend fun search(query: String, cursor: String?, version: PiuGameVersion): CatalogSearchPage
    suspend fun setFavorite(slug: String, saved: Boolean, version: PiuGameVersion): Boolean
    suspend fun chartPerformance(slug: String, chart: String, version: PiuGameVersion): SongChartPerformance?
    suspend fun cached(query: String, version: PiuGameVersion, scope: String): CatalogCache.CachedListing?
    suspend fun cache(listing: CatalogListing, query: String, version: PiuGameVersion, scope: String)
    suspend fun cacheFavorite(saved: Boolean, slug: String, version: PiuGameVersion, scope: String)
    fun resolveUrl(value: String?): String?
}

class CatalogRepository(
    private val sessionStore: SessionStore,
    private val apiClient: MyPiuApiClient,
    private val cache: CatalogCache,
) : CatalogDataSource {
    override suspend fun search(
        query: String,
        cursor: String?,
        version: PiuGameVersion,
    ): CatalogSearchPage = withSession { token ->
        apiClient.searchCatalog(query, cursor, version, token)
    }

    override suspend fun setFavorite(slug: String, saved: Boolean, version: PiuGameVersion): Boolean {
        return withSession { token ->
            apiClient.setFavorite(slug, saved, version, token ?: throw MyPiuApiException(401, "invalid_token"))
        }
    }

    override suspend fun chartPerformance(
        slug: String,
        chart: String,
        version: PiuGameVersion,
    ): SongChartPerformance? {
        return withSession { token ->
            apiClient.chartPerformance(slug, chart, version, token ?: throw MyPiuApiException(401, "invalid_token"))
        }
    }

    override suspend fun cached(
        query: String,
        version: PiuGameVersion,
        scope: String,
    ): CatalogCache.CachedListing? = cache.load(query, version, scope)

    override suspend fun cache(
        listing: CatalogListing,
        query: String,
        version: PiuGameVersion,
        scope: String,
    ) = cache.save(listing, query, version, scope)

    override suspend fun cacheFavorite(
        saved: Boolean,
        slug: String,
        version: PiuGameVersion,
        scope: String,
    ) = cache.setFavorite(saved, slug, version, scope)

    override fun resolveUrl(value: String?): String? = apiClient.resolveUrl(value)

    private suspend fun <Value> withSession(operation: suspend (String?) -> Value): Value {
        val token = validToken()?.value
        return try {
            operation(token)
        } catch (error: MyPiuApiException) {
            if (
                (error.isUnauthorized || error.isAccountNotFound) &&
                token != null &&
                sessionStore.accessToken()?.value == token
            ) {
                sessionStore.clearAccessToken()
            }
            throw error
        }
    }

    private fun validToken() = sessionStore.accessToken()?.takeUnless { token ->
        if (token.isExpired()) {
            sessionStore.clearAccessToken()
            true
        } else {
            false
        }
    }
}
