package com.austinkimchi.mypiu.core.catalog

import com.austinkimchi.mypiu.core.model.MyPiuAccessToken
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.security.SecretStore
import com.austinkimchi.mypiu.core.security.SessionStore
import java.nio.file.Files
import kotlinx.coroutines.test.runTest
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CatalogRepositoryTest {
    @Test
    fun lateUnauthorizedResponseDoesNotClearReplacementToken() = runTest {
        val secrets = MemorySecretStore()
        val sessionStore = SessionStore(secrets)
        val oldToken = MyPiuAccessToken("old", Long.MAX_VALUE, "installation")
        val newToken = MyPiuAccessToken("new", Long.MAX_VALUE, "installation")
        sessionStore.saveAccessToken(oldToken)
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                assertEquals("Bearer old", chain.request().header("Authorization"))
                sessionStore.saveAccessToken(newToken)
                Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(401)
                    .message("Unauthorized")
                    .body("""{"error":"invalid_token"}""".toResponseBody("application/json".toMediaType()))
                    .build()
            }
            .build()
        val directory = Files.createTempDirectory("mypiu-catalog-repository-test").toFile()
        try {
            val repository = CatalogRepository(
                sessionStore,
                MyPiuApiClient("https://mypiu.example/", client = httpClient),
                CatalogCache(directory),
            )
            var rejected = false
            try {
                repository.search("", null, PiuGameVersion.PHOENIX_2, authenticated = true)
            } catch (_: MyPiuApiException) {
                rejected = true
            }

            assertTrue(rejected)
            assertEquals(newToken, sessionStore.accessToken())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun expiredSessionDoesNotSilentlyFallBackToPublicCatalog() = runTest {
        val secrets = MemorySecretStore()
        val sessionStore = SessionStore(secrets)
        sessionStore.saveAccessToken(MyPiuAccessToken("expired", 0, "installation"))
        var requestCount = 0
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { error("Unexpected request ${++requestCount}") }
            .build()
        val directory = Files.createTempDirectory("mypiu-catalog-repository-test").toFile()
        try {
            val repository = CatalogRepository(
                sessionStore,
                MyPiuApiClient("https://mypiu.example/", client = httpClient),
                CatalogCache(directory),
            )
            var rejected = false
            try {
                repository.search("", null, PiuGameVersion.PHOENIX_2, authenticated = true)
            } catch (_: MyPiuApiException) {
                rejected = true
            }

            assertTrue(rejected)
            assertEquals(0, requestCount)
            assertEquals(null, sessionStore.accessToken())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun publicCatalogSearchIgnoresStoredSession() = runTest {
        val secrets = MemorySecretStore()
        val sessionStore = SessionStore(secrets)
        sessionStore.saveAccessToken(MyPiuAccessToken("private", Long.MAX_VALUE, "installation"))
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                assertEquals(null, chain.request().header("Authorization"))
                Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(200)
                    .message("OK")
                    .body("""{"songs":[],"nextCursor":null,"total":0}""".toResponseBody("application/json".toMediaType()))
                    .build()
            }
            .build()
        val directory = Files.createTempDirectory("mypiu-catalog-repository-test").toFile()
        try {
            val repository = CatalogRepository(
                sessionStore,
                MyPiuApiClient("https://mypiu.example/", client = httpClient),
                CatalogCache(directory),
            )

            val page = repository.search("", null, PiuGameVersion.PHOENIX_2, authenticated = false)

            assertEquals(0, page.total)
            assertEquals("private", sessionStore.accessToken()?.value)
        } finally {
            directory.deleteRecursively()
        }
    }
}

private class MemorySecretStore : SecretStore {
    private val values = mutableMapOf<String, String>()
    override fun put(key: String, value: String) { values[key] = value }
    override fun get(key: String): String? = values[key]
    override fun remove(key: String) { values.remove(key) }
}
