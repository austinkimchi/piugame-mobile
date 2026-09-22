package com.austinkimchi.mypiu.core.security

import com.austinkimchi.mypiu.core.model.MyPiuAccessToken
import com.austinkimchi.mypiu.core.model.PiuCredentials
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class SessionStore(
    private val secrets: SecretStore,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    fun credentials(): PiuCredentials? = secrets.get(CREDENTIALS)?.let(json::decodeFromString)
    fun saveCredentials(value: PiuCredentials) = secrets.put(CREDENTIALS, json.encodeToString(value))
    fun clearCredentials() = secrets.remove(CREDENTIALS)

    fun accessToken(): MyPiuAccessToken? = secrets.get(ACCESS_TOKEN)?.let(json::decodeFromString)
    fun saveAccessToken(value: MyPiuAccessToken) = secrets.put(ACCESS_TOKEN, json.encodeToString(value))
    fun clearAccessToken() = secrets.remove(ACCESS_TOKEN)

    fun pendingRevocations(): List<MyPiuAccessToken> =
        secrets.get(PENDING_REVOCATIONS)?.let(json::decodeFromString) ?: emptyList()

    fun enqueuePendingRevocation(value: MyPiuAccessToken) {
        val pending = pendingRevocations()
        if (pending.none { it.value == value.value }) {
            secrets.put(PENDING_REVOCATIONS, json.encodeToString(pending + value))
        }
    }

    fun removePendingRevocation(value: MyPiuAccessToken) {
        val remaining = pendingRevocations().filterNot { it.value == value.value }
        if (remaining.isEmpty()) {
            secrets.remove(PENDING_REVOCATIONS)
        } else {
            secrets.put(PENDING_REVOCATIONS, json.encodeToString(remaining))
        }
    }

    fun pendingOAuth(): PendingOAuth? = secrets.get(PENDING_OAUTH)?.let(json::decodeFromString)
    fun savePendingOAuth(value: PendingOAuth) = secrets.put(PENDING_OAUTH, json.encodeToString(value))
    fun clearPendingOAuth() = secrets.remove(PENDING_OAUTH)

    @Serializable
    data class PendingOAuth(
        val verifier: String,
        val state: String,
        val createdAtEpochMillis: Long,
    )

    private companion object {
        const val CREDENTIALS = "piu_credentials"
        const val ACCESS_TOKEN = "mypiu_access_token"
        const val PENDING_REVOCATIONS = "mypiu_pending_revocations"
        const val PENDING_OAUTH = "mypiu_pending_oauth"
    }
}
