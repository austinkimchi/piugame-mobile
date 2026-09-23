package com.austinkimchi.mypiu.core.network

import com.austinkimchi.mypiu.core.model.AccountResponse
import com.austinkimchi.mypiu.core.model.ApiErrorResponse
import com.austinkimchi.mypiu.core.model.CatalogSearchPage
import com.austinkimchi.mypiu.core.model.ChartPerformanceResponse
import com.austinkimchi.mypiu.core.model.FavoriteUpdatePayload
import com.austinkimchi.mypiu.core.model.FavoriteUpdateResponse
import com.austinkimchi.mypiu.core.model.MobilePerformanceImportPayload
import com.austinkimchi.mypiu.core.model.MyPiuAccessToken
import com.austinkimchi.mypiu.core.model.MyPiuAccount
import com.austinkimchi.mypiu.core.model.MyPiuAuthProvider
import com.austinkimchi.mypiu.core.model.MyPiuSyncResult
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.PiuSnapshot
import com.austinkimchi.mypiu.core.model.SongChartPerformance
import com.austinkimchi.mypiu.core.model.TokenResponse
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class MyPiuApiException(val status: Int, val code: String) : Exception(messageFor(code)) {
    val isUnauthorized: Boolean get() = status == 401
    val isAccountNotFound: Boolean get() = code == "account_not_found"
    val isPermanentPiuLinkError: Boolean
        get() = code == "piu_account_not_linked" || code == "piu_username_mismatch"

    companion object {
        private fun messageFor(code: String): String = when (code) {
            "invalid_token" -> "Your MyPIU session expired. Sign in again."
            "piu_account_not_linked" -> "Link this PIUGAME account on MyPIU before uploading."
            "piu_username_mismatch" -> "The PIUGAME username does not match the account linked to MyPIU."
            "account_not_found" -> "This MyPIU account no longer exists."
            "song_not_found" -> "This song is not available in the selected PIU version."
            "chart_not_found" -> "This chart is not available in the selected PIU version."
            "invalid_chart", "invalid_version" -> "MyPIU could not identify that chart."
            "favorite_update_failed" -> "MyPIU could not update this favorite. Try again."
            "rate_limited" -> "MyPIU is receiving syncs too quickly. Try again shortly."
            "account_busy" -> "MyPIU is finishing another account update. Try again shortly."
            else -> "MyPIU could not complete the request."
        }
    }
}

class MyPiuApiClient(
    baseUrl: String,
    private val json: Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    },
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(45, TimeUnit.SECONDS)
        .callTimeout(60, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            chain.proceed(chain.request().newBuilder().header("User-Agent", "MyPIU-Android/0.1").build())
        }
        .build(),
) {
    private val baseUrl = baseUrl.toHttpUrl()

    fun authorizationUrl(provider: MyPiuAuthProvider, challenge: String, state: String): String =
        baseUrl.newBuilder()
            .addPathSegments("api/mobile/v1/authorize")
            .addQueryParameter("client_id", CLIENT_ID)
            .addQueryParameter("redirect_uri", REDIRECT_URI)
            .addQueryParameter("code_challenge", challenge)
            .addQueryParameter("code_challenge_method", "S256")
            .addQueryParameter("state", state)
            .addQueryParameter("provider", provider.wireValue)
            .build()
            .toString()

    suspend fun exchangeAuthorizationCode(
        code: String,
        verifier: String,
        installationId: String,
        appVersion: String,
    ): MyPiuAccessToken {
        val request = Request.Builder()
            .url(url("api/mobile/v1/token"))
            .post(
                FormBody.Builder()
                    .add("grant_type", "authorization_code")
                    .add("client_id", CLIENT_ID)
                    .add("code", code)
                    .add("code_verifier", verifier)
                    .add("redirect_uri", REDIRECT_URI)
                    .add("installation_id", installationId)
                    .add("app_version", appVersion)
                    .build(),
            )
            .build()
        val response: TokenResponse = send(request)
        if (!response.tokenType.equals("Bearer", ignoreCase = true)) {
            throw MyPiuApiException(500, "invalid_response")
        }
        return MyPiuAccessToken(
            value = response.accessToken,
            expiresAtEpochMillis = System.currentTimeMillis() + response.expiresIn * 1_000,
            installationId = installationId,
        )
    }

    suspend fun account(accessToken: String): MyPiuAccount {
        val request = authenticatedRequest("api/mobile/v1/me", accessToken).get().build()
        return send<AccountResponse>(request).account
    }

    suspend fun upload(
        snapshot: PiuSnapshot,
        accessToken: String,
        installationId: String,
        appVersion: String,
    ): MyPiuSyncResult {
        val payload = MobilePerformanceImportPayload.from(snapshot, installationId, appVersion)
        val request = authenticatedRequest("api/mobile/v1/performance/import", accessToken)
            .post(json.encodeToString(payload).toRequestBody(JSON_MEDIA_TYPE))
            .build()
        return send(request)
    }

    suspend fun searchCatalog(
        query: String,
        cursor: String?,
        version: PiuGameVersion,
        accessToken: String?,
    ): CatalogSearchPage {
        val requestUrl = url("api/songs/search").newBuilder()
            .addQueryParameter("q", query)
            .addQueryParameter("limit", "30")
            .addQueryParameter("sortBy", "title")
            .addQueryParameter("sortDirection", "asc")
            .addQueryParameter("supportedVersion", version.serialName)
            .apply { cursor?.let { addQueryParameter("cursor", it) } }
            .build()
        val request = Request.Builder()
            .url(requestUrl)
            .header("Accept", "application/json")
            .apply { accessToken?.let { header("Authorization", "Bearer $it") } }
            .get()
            .build()
        return send(request)
    }

    suspend fun setFavorite(
        slug: String,
        saved: Boolean,
        version: PiuGameVersion,
        accessToken: String?,
    ): Boolean {
        val token = accessToken ?: throw MyPiuApiException(401, "invalid_token")
        val requestUrl = baseUrl.newBuilder()
            .addPathSegments("api/mobile/v1/songs")
            .addPathSegment(slug)
            .addPathSegment("favorite")
            .build()
        val request = Request.Builder()
            .url(requestUrl)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json")
            .put(json.encodeToString(FavoriteUpdatePayload(saved, version)).toRequestBody(JSON_MEDIA_TYPE))
            .build()
        val response: FavoriteUpdateResponse = send(request)
        if (response.slug != slug) throw MyPiuApiException(500, "invalid_response")
        return response.isFavorite
    }

    suspend fun chartPerformance(
        slug: String,
        chart: String,
        version: PiuGameVersion,
        accessToken: String?,
    ): SongChartPerformance? {
        val token = accessToken ?: throw MyPiuApiException(401, "invalid_token")
        val requestUrl = baseUrl.newBuilder()
            .addPathSegments("api/mobile/v1/songs")
            .addPathSegment(slug)
            .addPathSegment("performance")
            .addQueryParameter("chart", chart)
            .addQueryParameter("version", version.serialName)
            .build()
        val request = Request.Builder()
            .url(requestUrl)
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json")
            .get()
            .build()
        return send<ChartPerformanceResponse>(request).performance
    }

    fun resolveUrl(value: String?): String? = value
        ?.takeIf(String::isNotBlank)
        ?.let(baseUrl::resolve)
        ?.toString()

    suspend fun revoke(accessToken: String) {
        val request = authenticatedRequest("api/mobile/v1/token", accessToken).delete().build()
        sendData(request)
    }

    private fun authenticatedRequest(path: String, accessToken: String): Request.Builder = Request.Builder()
        .url(url(path))
        .header("Authorization", "Bearer $accessToken")
        .header("Accept", "application/json")

    private suspend inline fun <reified Response> send(request: Request): Response =
        json.decodeFromString(sendData(request))

    private suspend fun sendData(request: Request): String = withContext(Dispatchers.IO) {
        client.newCall(request).execute().use { response ->
            val body = response.body.string()
            if (!response.isSuccessful) {
                val code = runCatching { json.decodeFromString<ApiErrorResponse>(body).error }
                    .getOrDefault("request_failed")
                throw MyPiuApiException(response.code, code)
            }
            body
        }
    }

    private fun url(path: String) = baseUrl.newBuilder().addPathSegments(path).build()

    companion object {
        const val CLIENT_ID = "mypiu-android"
        const val REDIRECT_URI = "mypiu://oauth/callback"
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
