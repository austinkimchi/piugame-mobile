package com.austinkimchi.mypiu.core.performance

import com.austinkimchi.mypiu.core.model.MyPiuAccessToken
import com.austinkimchi.mypiu.core.model.PerformanceSessionsResponse
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.security.SecretStore
import com.austinkimchi.mypiu.core.security.SessionStore
import java.io.IOException
import java.nio.file.Files
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.*
import org.junit.Test

class PerformanceSessionsRepositoryTest {
    private val json = Json { ignoreUnknownKeys = true }
    private val origin = "https://example.test"
    private fun pageText() = checkNotNull(javaClass.classLoader?.getResourceAsStream("session-cache-page.json"))
        .bufferedReader().use { it.readText() }
    private fun account() = """{"account":{"id":"a","name":"Fixture","email":"fixture@example.test","username":null,"imageUrl":null,"piuGameVersion":"phoenix2","piuProfile":null}}"""
    private fun sessionStore(): SessionStore = SessionStore(SessionCacheSecrets()).also { replaceToken(it, "old") }
    private fun replaceToken(store: SessionStore, value: String) {
        store.saveAccessToken(MyPiuAccessToken(value, Long.MAX_VALUE, "fixture-installation"))
        store.saveAccountIdentity(value, "a", PiuGameVersion.PHOENIX_2)
    }

    @Test fun verifiedCachedPageArrivesBeforeTransientNetworkFailure() = runTest {
        val directory = Files.createTempDirectory("session-repository").toFile()
        val release = CountDownLatch(1)
        try {
            val cache = PerformanceSessionsCache(directory)
            val context = SessionsCacheContext.fromToken(origin, "a", PiuGameVersion.PHOENIX_2, "old")
            cache.save(json.decodeFromString<PerformanceSessionsResponse>(pageText()), context, { true })
            val loaded = CountDownLatch(1)
            val http = OkHttpClient.Builder().addInterceptor { chain ->
                val request = chain.request()
                if (!request.url.encodedPath.endsWith("/me")) {
                    check(release.await(10, TimeUnit.SECONDS)); throw IOException("fixture offline")
                }
                Response.Builder().request(request).protocol(Protocol.HTTP_1_1).code(200).message("OK")
                    .body(account().toResponseBody("application/json".toMediaType())).build()
            }.build()
            val repo = PerformanceRepository(sessionStore(), MyPiuApiClient(origin, client = http), cache, origin)
            val operation = async(Dispatchers.Default) { runCatching {
                repo.firstSessionPage("a", onCached = { assertEquals(20, it.page.sessions.size); loaded.countDown() },
                    onFresh = { fail("Network must fail") })
            } }
            assertTrue(loaded.await(10, TimeUnit.SECONDS))
            release.countDown()
            assertTrue(operation.await().exceptionOrNull() is IOException)
            assertNotNull(cache.load(context, { true }))
        } finally { release.countDown(); directory.deleteRecursively() }
    }

    @Test fun replacedTokenRejectsLateSuccessAndUnauthorizedResponse() = runTest {
        for (status in listOf(200, 401)) {
            val directory = Files.createTempDirectory("session-repository-race").toFile()
            val started = CountDownLatch(1); val release = CountDownLatch(1)
            try {
                val sessions = sessionStore()
                val cache = PerformanceSessionsCache(directory)
                val http = OkHttpClient.Builder().addInterceptor { chain ->
                    val request = chain.request()
                    val isIdentity = request.url.encodedPath.endsWith("/me")
                    if (!isIdentity) { started.countDown(); check(release.await(10, TimeUnit.SECONDS)) }
                    Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                        .code(if (isIdentity) 200 else status).message("Fixture")
                        .body((if (isIdentity) account() else if (status == 401) """{"error":"invalid_token"}""" else pageText())
                            .toResponseBody("application/json".toMediaType())).build()
                }.build()
                val repo = PerformanceRepository(sessions, MyPiuApiClient(origin, client = http), cache, origin)
                val operation = async(Dispatchers.Default) { runCatching {
                    repo.firstSessionPage("a", onCached = { fail("No cache exists") }, onFresh = { fail("Late token response") })
                } }
                assertTrue(started.await(10, TimeUnit.SECONDS))
                replaceToken(sessions, "new")
                repo.invalidateSessionCache()
                release.countDown()
                assertTrue(operation.await().exceptionOrNull() is CancellationException)
                assertEquals("new", sessions.accessToken()?.value)
                val old = SessionsCacheContext.fromToken(origin, "a", PiuGameVersion.PHOENIX_2, "old")
                assertNull(cache.load(old, { true }))
            } finally { release.countDown(); directory.deleteRecursively() }
        }
    }
}

private class SessionCacheSecrets : SecretStore {
    private val values = ConcurrentHashMap<String, String>()
    override fun get(key: String): String? = values[key]
    override fun put(key: String, value: String) { values[key] = value }
    override fun remove(key: String) { values.remove(key) }
}
