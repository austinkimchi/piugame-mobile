package com.austinkimchi.mypiu.core.network

import com.austinkimchi.mypiu.core.model.MyPiuAccessToken
import com.austinkimchi.mypiu.core.model.MyPiuAuthProvider
import com.austinkimchi.mypiu.core.security.SessionStore
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import kotlinx.coroutines.CancellationException

class OAuthException(message: String) : Exception(message)

class OAuthCoordinator(
    private val apiClient: MyPiuApiClient,
    private val sessionStore: SessionStore,
    private val installationId: String,
    private val appVersion: String,
    private val clock: () -> Long = System::currentTimeMillis,
    private val random: SecureRandom = SecureRandom(),
) {
    fun begin(provider: MyPiuAuthProvider): String {
        val verifier = randomValue(32)
        val state = randomValue(24)
        val challenge = pkceChallenge(verifier)
        sessionStore.savePendingOAuth(
            SessionStore.PendingOAuth(
                verifier = verifier,
                state = state,
                createdAtEpochMillis = clock(),
            ),
        )
        return apiClient.authorizationUrl(provider, challenge, state)
    }

    suspend fun complete(callbackUrl: String): MyPiuAccessToken {
        val callback = URI(callbackUrl)
        if (callback.scheme != "mypiu" || callback.host != "oauth" || callback.path != "/callback") {
            throw OAuthException("MyPIU returned an invalid sign-in callback.")
        }
        val parameters = callback.rawQuery.orEmpty()
            .split('&')
            .filter(String::isNotEmpty)
            .associate { pair ->
                val pieces = pair.split('=', limit = 2)
                decode(pieces[0]) to decode(pieces.getOrElse(1) { "" })
            }
        parameters["error"]?.let { throw OAuthException("MyPIU sign-in was not completed.") }
        val pending = sessionStore.pendingOAuth()
            ?: throw OAuthException("Start MyPIU sign-in again.")
        if (clock() - pending.createdAtEpochMillis > PENDING_TTL_MILLIS) {
            sessionStore.clearPendingOAuth()
            throw OAuthException("MyPIU sign-in expired. Start again.")
        }
        val callbackState = parameters["state"] ?: throw OAuthException("MyPIU returned an invalid sign-in state.")
        if (!MessageDigest.isEqual(callbackState.toByteArray(), pending.state.toByteArray())) {
            throw OAuthException("MyPIU returned an invalid sign-in state.")
        }
        val code = parameters["code"] ?: throw OAuthException("MyPIU did not return an authorization code.")
        val token = apiClient.exchangeAuthorizationCode(
            code = code,
            verifier = pending.verifier,
            installationId = installationId,
            appVersion = appVersion,
        )
        try {
            sessionStore.saveAccessToken(token)
        } catch (_: Exception) {
            discardUnstoredToken(token)
            throw OAuthException("MyPIU could not securely save this session. Sign in again.")
        }
        sessionStore.clearPendingOAuth()
        return token
    }

    private suspend fun discardUnstoredToken(token: MyPiuAccessToken) {
        val queued = runCatching { sessionStore.enqueuePendingRevocation(token) }.isSuccess
        val revoked = try {
            apiClient.revoke(token.value)
            true
        } catch (error: CancellationException) {
            throw error
        } catch (error: MyPiuApiException) {
            error.isUnauthorized
        } catch (_: Exception) {
            false
        }
        if (revoked && queued) runCatching { sessionStore.removePendingRevocation(token) }
        if (!revoked && !queued) {
            throw OAuthException(
                "MyPIU could not securely save or revoke this session. Keep the app open and try again.",
            )
        }
    }

    private fun randomValue(byteCount: Int): String = ByteArray(byteCount)
        .also(random::nextBytes)
        .let { Base64.getUrlEncoder().withoutPadding().encodeToString(it) }

    private fun decode(value: String): String = URLDecoder.decode(value, StandardCharsets.UTF_8.name())

    private companion object {
        const val PENDING_TTL_MILLIS = 10 * 60 * 1_000L
    }
}
