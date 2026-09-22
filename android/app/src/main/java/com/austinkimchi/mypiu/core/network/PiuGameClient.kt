package com.austinkimchi.mypiu.core.network

import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.PiuSnapshot
import com.austinkimchi.mypiu.core.parsing.PiuHtmlParser
import java.net.CookieManager
import java.net.CookiePolicy
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.java.net.cookiejar.JavaNetCookieJar
import org.jsoup.Jsoup

sealed class PiuGameException(message: String) : Exception(message) {
    class AuthenticationFailed : PiuGameException("PIUGAME could not verify those credentials.")
    class UnexpectedStatus(val status: Int) : PiuGameException("PIUGAME returned HTTP $status.")
    class InvalidResponse : PiuGameException("PIUGAME returned an invalid response.")
}

class PiuGameClient(
    private val version: PiuGameVersion,
    private val parser: PiuHtmlParser = PiuHtmlParser(),
    private val client: OkHttpClient = defaultClient(),
) {
    suspend fun loginAndFetch(username: String, password: String): PiuSnapshot {
        login(username, password)
        return fetchSnapshot(username)
    }

    suspend fun login(username: String, password: String) {
        val body = FormBody.Builder()
            .add("url", "/")
            .add("mb_id", username)
            .add("mb_password", password)
            .build()
        val request = Request.Builder()
            .url(url("/bbs/login_check.php"))
            .header("Origin", version.baseUrl)
            .header("Referer", "${version.baseUrl}/")
            .post(body)
            .build()
        send(request)

        validateAuthenticatedProfile(fetchHtml("/my_page/play_data.php"))
    }

    suspend fun fetchSnapshot(username: String): PiuSnapshot = coroutineScope {
        val profileHtml = async { fetchHtml("/my_page/play_data.php") }
        val recentHtml = async { fetchHtml("/my_page/recently_played.php") }
        val pumbilityHtml = async { fetchHtml("/my_page/pumbility.php") }
        val pumbility = parser.parsePumbilityScore(pumbilityHtml.await())
        PiuSnapshot(
            version = version,
            profile = parser.parseProfile(profileHtml.await(), username, pumbility),
            recentPlays = parser.parseRecentPlays(recentHtml.await()),
            fetchedAt = Instant.now(),
        )
    }

    private suspend fun fetchHtml(path: String): String {
        val request = Request.Builder()
            .url(url(path))
            .header("Accept", "text/html,application/xhtml+xml")
            .get()
            .build()
        return send(request)
    }

    private suspend fun send(request: Request): String = withContext(Dispatchers.IO) {
        client.newCall(request).execute().use { response ->
            if (response.code !in 200..399) throw PiuGameException.UnexpectedStatus(response.code)
            response.body.string().takeIf(String::isNotEmpty) ?: throw PiuGameException.InvalidResponse()
        }
    }

    private fun url(path: String): String = "${version.baseUrl}$path"

    companion object {
        private fun defaultClient(): OkHttpClient {
            val cookieManager = CookieManager().apply { setCookiePolicy(CookiePolicy.ACCEPT_ALL) }
            return OkHttpClient.Builder()
                .cookieJar(JavaNetCookieJar(cookieManager))
                .connectTimeout(20, TimeUnit.SECONDS)
                .readTimeout(45, TimeUnit.SECONDS)
                .callTimeout(60, TimeUnit.SECONDS)
                .followRedirects(true)
                .addInterceptor { chain ->
                    chain.proceed(
                        chain.request().newBuilder()
                            .header("Accept-Language", "en-US,en;q=0.9")
                            .header("User-Agent", "MyPIU-Android/0.1")
                            .build(),
                    )
                }
                .build()
        }
    }
}

internal fun validateAuthenticatedProfile(html: String) {
    if (Regex("subProfile_wrap|play_data_wrap|profile_name").containsMatchIn(html)) return

    val document = Jsoup.parse(html)
    val hasUsernameField = document.selectFirst("input[name=mb_id]") != null
    val hasPasswordField = document.selectFirst("input[name=mb_password]") != null
    if (hasUsernameField && hasPasswordField) throw PiuGameException.AuthenticationFailed()

    throw PiuGameException.InvalidResponse()
}
