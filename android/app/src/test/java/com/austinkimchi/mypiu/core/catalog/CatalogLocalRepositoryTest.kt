package com.austinkimchi.mypiu.core.catalog

import com.austinkimchi.mypiu.core.model.*
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.security.SecretStore
import com.austinkimchi.mypiu.core.security.SessionStore
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class CatalogLocalRepositoryTest {
    private val json = Json { ignoreUnknownKeys = true }
    private fun fixture(): PublicCatalogSnapshot {
        val text = checkNotNull(javaClass.classLoader?.getResourceAsStream("catalog-local-query.json")).bufferedReader().use { it.readText() }
        return json.decodeFromJsonElement(PublicCatalogSnapshot.serializer(), json.parseToJsonElement(text).jsonObject.getValue("snapshot"))
    }
    private fun overlay(favorite: Boolean = false, hint: String = "S17") =
        """{"schemaVersion":1,"version":"phoenix2","favoriteSlugs":${if (favorite) "[\"all\"]" else "[]"},"recommendations":{"all":{"all":"$hint"}}}"""
    private fun token(value: String) = MyPiuAccessToken(value, Long.MAX_VALUE, "installation")

    @Test fun warmQuerySortAndFavoriteUseNoNewReadAndImportForcesRefresh() = runTest {
        val directory = Files.createTempDirectory("catalog-local").toFile()
        val sessions = SessionStore(LocalQuerySecrets()).also { it.saveAccessToken(token("a")) }
        val reads = AtomicInteger(); val publicReads = AtomicInteger()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            val body = if (request.method == "GET") overlay(hint = "hint-${reads.incrementAndGet()}") else """{"slug":"all","isFavorite":true}"""
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body(body.toResponseBody("application/json".toMediaType())).build()
        }.build()
        val storeScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val store = PublicCatalogStore(directory.resolve("public"), { _, _ -> publicReads.incrementAndGet(); PublicCatalogResponse(fixture(), "v1") }, storeScope)
            val repo = CatalogRepository(sessions, MyPiuApiClient("https://mypiu.example/", client = http), CatalogCache(directory), store)
            suspend fun search(query: String, reuse: Boolean = true) = checkNotNull(repo.localQuery(query, PiuGameVersion.PHOENIX_2, true, CatalogSortOption.TITLE, CatalogSortDirection.ASCENDING, reuse))
            assertEquals(12, search("").total)
            repo.setFavorite("all", true, PiuGameVersion.PHOENIX_2)
            assertTrue(search("alpha").songs.first { it.slug == "all" }.isFavorite)
            assertEquals(listOf("single"), search("key-single").songs.map { it.slug })
            assertEquals(1, reads.get()); assertEquals(1, publicReads.get())
            assertNull(repo.localQuery("favorites", PiuGameVersion.PHOENIX_2, true, CatalogSortOption.TITLE, CatalogSortDirection.ASCENDING, true))
            repo.invalidateLocal()
            assertEquals("hint-2", search("alpha").songs.first { it.slug == "all" }.recommendedChartToken)
            assertEquals(2, reads.get())
            sessions.saveAccessToken(token("replacement"))
            assertFalse(search("alpha").songs.first { it.slug == "all" }.isFavorite)
            assertEquals(3, reads.get())
            val public = checkNotNull(repo.localQuery("alpha", PiuGameVersion.PHOENIX_2, false, CatalogSortOption.TITLE, CatalogSortDirection.ASCENDING, true))
            assertTrue(public.songs.all { !it.isFavorite && it.recommendedChartToken == null })
            assertEquals(3, reads.get())
            assertFalse(directory.resolve("public/phoenix2.json").readText().contains("favoriteSlugs"))
        } finally { storeScope.cancel(); directory.deleteRecursively() }
    }

    @Test fun favoriteCompletedDuringOverlayReadWinsAndLateOldTokenCannotPopulateCache() = runTest {
        for (replaceToken in listOf(false, true)) {
            val directory = Files.createTempDirectory("catalog-local-race").toFile()
            val sessions = SessionStore(LocalQuerySecrets()).also { it.saveAccessToken(token("a")) }
            val started = CountDownLatch(1); val release = CountDownLatch(1)
            val reads = AtomicInteger()
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request()
                val body = if (request.method == "GET") {
                    if (reads.incrementAndGet() == 2) { started.countDown(); check(release.await(10, TimeUnit.SECONDS)) }
                    overlay(hint = if (request.header("Authorization") == "Bearer a") "old" else "new")
                } else """{"slug":"all","isFavorite":true}"""
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK").body(body.toResponseBody("application/json".toMediaType())).build()
            }.build()
            val storeScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            try {
                val store = PublicCatalogStore(directory.resolve("public"), { _, _ -> PublicCatalogResponse(fixture(), "v1") }, storeScope)
                val repo = CatalogRepository(sessions, MyPiuApiClient("https://mypiu.example/", client = http), CatalogCache(directory), store)
                suspend fun search(reuse: Boolean) = checkNotNull(repo.localQuery("alpha", PiuGameVersion.PHOENIX_2, true, CatalogSortOption.TITLE, CatalogSortDirection.ASCENDING, reuse))
                search(false)
                val pending = async(Dispatchers.Default) { runCatching { search(false) } }
                assertTrue(started.await(10, TimeUnit.SECONDS))
                if (replaceToken) { sessions.saveAccessToken(token("b")); repo.invalidateLocal() }
                else repo.setFavorite("all", true, PiuGameVersion.PHOENIX_2)
                release.countDown()
                val result = pending.await()
                if (replaceToken) {
                    assertTrue(result.exceptionOrNull() is CancellationException)
                    assertEquals("new", search(true).songs.first { it.slug == "all" }.recommendedChartToken)
                    assertEquals(3, reads.get())
                } else {
                    assertTrue(result.getOrThrow().songs.first { it.slug == "all" }.isFavorite)
                    assertTrue(search(true).songs.first { it.slug == "all" }.isFavorite)
                    assertEquals(2, reads.get())
                }
            } finally { release.countDown(); storeScope.cancel(); directory.deleteRecursively() }
        }
    }

    @Test fun only404PermitsLegacyFallbackAndFailedRefreshKeepsLocalFiltering() = runTest {
        val directory = Files.createTempDirectory("catalog-local-errors").toFile()
        val sessions = SessionStore(LocalQuerySecrets()).also { it.saveAccessToken(token("a")) }
        val status = AtomicInteger(200); val reads = AtomicInteger()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            reads.incrementAndGet()
            Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1).code(status.get()).message("test")
                .body((if (status.get() == 200) overlay(true) else """{"error":"unavailable"}""").toResponseBody("application/json".toMediaType())).build()
        }.build()
        val storeScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val store = PublicCatalogStore(directory.resolve("public"), { _, _ -> PublicCatalogResponse(fixture(), "v1") }, storeScope)
            val repo = CatalogRepository(sessions, MyPiuApiClient("https://mypiu.example/", client = http), CatalogCache(directory), store)
            suspend fun search(reuse: Boolean) = repo.localQuery("alpha", PiuGameVersion.PHOENIX_2, true, CatalogSortOption.ARTIST, CatalogSortDirection.DESCENDING, reuse)
            search(false)
            status.set(503)
            try { search(false); fail("503 must not silently fall back") } catch (error: MyPiuApiException) { assertEquals(503, error.status) }
            assertTrue(checkNotNull(search(true)).songs.first { it.slug == "all" }.isFavorite)
            assertEquals(2, reads.get())
            status.set(404)
            assertNull(search(false))
        } finally { storeScope.cancel(); directory.deleteRecursively() }
    }
}

private class LocalQuerySecrets : SecretStore {
    private val values = java.util.concurrent.ConcurrentHashMap<String, String>()
    override fun put(key: String, value: String) { values[key] = value }
    override fun get(key: String) = values[key]
    override fun remove(key: String) { values.remove(key) }
}
