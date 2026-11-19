package com.austinkimchi.mypiu.core.performance

import com.austinkimchi.mypiu.core.model.MyPiuAccessToken
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.security.SecretStore
import com.austinkimchi.mypiu.core.security.SessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class PerformanceRepositoryTest {
    @Test
    fun currentAuthorizationFailureClearsStoredSession() = runTest {
        val store = SessionStore(PerformanceMemorySecretStore())
        store.saveAccessToken(MyPiuAccessToken("old", Long.MAX_VALUE, "installation"))
        val repository = PerformanceRepository(store, failingClient())

        try {
            repository.dashboard()
            fail("Expected authorization failure")
        } catch (error: MyPiuApiException) {
            assertEquals(401, error.status)
        }

        assertNull(store.accessToken())
    }

    @Test
    fun oldAuthorizationFailureIsCanceledWithoutClearingReplacementToken() = runTest {
        val store = SessionStore(PerformanceMemorySecretStore())
        store.saveAccessToken(MyPiuAccessToken("old", Long.MAX_VALUE, "installation"))
        val replacement = MyPiuAccessToken("replacement", Long.MAX_VALUE, "installation")
        val repository = PerformanceRepository(
            store,
            failingClient { store.saveAccessToken(replacement) },
        )

        try {
            repository.dashboard()
            fail("Expected stale request cancellation")
        } catch (_: CancellationException) {
            // Do not forward an old 401 that could invalidate the replacement account's UI.
        }

        assertEquals(replacement, store.accessToken())
    }

    private fun failingClient(beforeResponse: () -> Unit = {}): MyPiuApiClient {
        val client = OkHttpClient.Builder()
            .addInterceptor { chain ->
                beforeResponse()
                Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(401)
                    .message("Unauthorized")
                    .body("""{"error":"invalid_token"}""".toResponseBody("application/json".toMediaType()))
                    .build()
            }
            .build()
        return MyPiuApiClient("https://mypiu.example/", client = client)
    }
}

private class PerformanceMemorySecretStore : SecretStore {
    private val values = mutableMapOf<String, String>()
    override fun put(key: String, value: String) { values[key] = value }
    override fun get(key: String): String? = values[key]
    override fun remove(key: String) { values.remove(key) }
}
