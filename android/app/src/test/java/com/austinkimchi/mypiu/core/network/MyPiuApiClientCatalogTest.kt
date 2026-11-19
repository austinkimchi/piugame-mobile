package com.austinkimchi.mypiu.core.network

import com.austinkimchi.mypiu.core.model.PiuGameVersion
import kotlinx.coroutines.test.runTest
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MyPiuApiClientCatalogTest {
    @Test
    fun catalogEndpointsUseVersionedAuthenticatedContract() = runTest {
        val requests = mutableListOf<Request>()
        val responses = ArrayDeque(
            listOf(
                """{"songs":[],"nextCursor":null,"total":0}""",
                """{"slug":"battle-no-1","isFavorite":true}""",
                """{"performance":null}""",
            ),
        )
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val request = chain.request()
                requests += request
                Response.Builder()
                    .request(request)
                    .protocol(Protocol.HTTP_1_1)
                    .code(200)
                    .message("OK")
                    .body(responses.removeFirst().toResponseBody("application/json".toMediaType()))
                    .build()
            }
            .build()
        val client = MyPiuApiClient("https://mypiu.example/", client = httpClient)

        val page = client.searchCatalog("battle", "Mg", PiuGameVersion.PHOENIX_2, "token")
        val saved = client.setFavorite("battle-no-1", true, PiuGameVersion.PHOENIX_2, "token")
        val performance = client.chartPerformance("battle-no-1", "S19", PiuGameVersion.PHOENIX_2, "token")

        assertTrue(page.songs.isEmpty())
        assertTrue(saved)
        assertNull(performance)

        val search = requests[0]
        assertEquals("/api/songs/search", search.url.encodedPath)
        assertEquals("battle", search.url.queryParameter("q"))
        assertEquals("Mg", search.url.queryParameter("cursor"))
        assertEquals("phoenix2", search.url.queryParameter("supportedVersion"))
        assertEquals("series", search.url.queryParameter("sortBy"))
        assertEquals("desc", search.url.queryParameter("sortDirection"))
        assertEquals("Bearer token", search.header("Authorization"))

        val favorite = requests[1]
        assertEquals("PUT", favorite.method)
        assertEquals("/api/mobile/v1/songs/battle-no-1/favorite", favorite.url.encodedPath)
        val favoriteBody = Buffer().also { requireNotNull(favorite.body).writeTo(it) }.readUtf8()
        assertTrue(favoriteBody.contains("\"saved\":true"))
        assertTrue(favoriteBody.contains("\"version\":\"phoenix2\""))

        val history = requests[2]
        assertEquals("/api/mobile/v1/songs/battle-no-1/performance", history.url.encodedPath)
        assertEquals("S19", history.url.queryParameter("chart"))
        assertEquals("phoenix2", history.url.queryParameter("version"))
        assertEquals("https://mypiu.example/assets/piu/song.png", client.resolveUrl("/assets/piu/song.png"))
    }
    @Test
    fun publicSnapshotAndPrivateOverlayUseSeparateCredentialContracts() = runTest {
        val requests = mutableListOf<Request>()
        val http = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            requests += request
            val isPublic = request.url.encodedPath.startsWith("/api/catalog/")
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                .code(if (isPublic) 304 else 200).message("OK")
                .body((if (isPublic) "" else """{"schemaVersion":1,"version":"phoenix2","favoriteSlugs":[],"recommendations":{}}""")
                    .toResponseBody("application/json".toMediaType())).build()
        }.build()
        val client = MyPiuApiClient("https://mypiu.example/", client = http)
        assertTrue(client.publicCatalog(PiuGameVersion.PHOENIX_2, "v1").notModified)
        val overlay = client.catalogOverlay(PiuGameVersion.PHOENIX_2, "private-token")
        assertEquals("phoenix2", overlay.version)
        assertEquals("/api/catalog/v1/phoenix2", requests[0].url.encodedPath)
        assertNull(requests[0].header("Authorization"))
        assertEquals("v1", requests[0].header("If-None-Match"))
        assertEquals("/api/mobile/v1/catalog/overlay", requests[1].url.encodedPath)
        assertEquals("phoenix2", requests[1].url.queryParameter("version"))
        assertEquals("Bearer private-token", requests[1].header("Authorization"))
        assertNull(requests[1].header("If-None-Match"))
    }

}
