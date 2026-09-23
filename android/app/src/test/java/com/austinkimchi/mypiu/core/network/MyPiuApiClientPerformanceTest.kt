package com.austinkimchi.mypiu.core.network

import com.austinkimchi.mypiu.core.model.PerformanceModelsTest
import kotlinx.coroutines.test.runTest
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Test

class MyPiuApiClientPerformanceTest {
    @Test
    fun performanceUsesMobileBearerContract() = runTest {
        lateinit var captured: Request
        val httpClient = OkHttpClient.Builder()
            .addInterceptor { chain ->
                captured = chain.request()
                Response.Builder()
                    .request(captured)
                    .protocol(Protocol.HTTP_1_1)
                    .code(200)
                    .message("OK")
                    .body(PerformanceModelsTest.FIXTURE.toResponseBody("application/json".toMediaType()))
                    .build()
            }
            .build()
        val dashboard = MyPiuApiClient("https://mypiu.example/", client = httpClient).performance("token")

        assertEquals("PLAYER#1234", dashboard.profile?.displayName)
        assertEquals("GET", captured.method)
        assertEquals("/api/mobile/v1/performance", captured.url.encodedPath)
        assertEquals("Bearer token", captured.header("Authorization"))
        assertEquals("application/json", captured.header("Accept"))
    }
}
