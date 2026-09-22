package com.austinkimchi.mypiu.core.sync

import com.austinkimchi.mypiu.core.model.MyPiuAccount
import com.austinkimchi.mypiu.core.model.MyPiuAuthProvider
import com.austinkimchi.mypiu.core.model.MyPiuSyncResult
import com.austinkimchi.mypiu.core.model.PiuCredentials
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.PiuSnapshot
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.network.OAuthCoordinator
import com.austinkimchi.mypiu.core.network.PiuGameClient
import com.austinkimchi.mypiu.core.network.PiuGameException
import com.austinkimchi.mypiu.core.security.SessionStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class SyncRepository(
    private val sessionStore: SessionStore,
    private val apiClient: MyPiuApiClient,
    private val oauthCoordinator: OAuthCoordinator,
    private val installationId: String,
    private val appVersion: String,
    private val piuClient: (PiuGameVersion) -> PiuGameClient = ::PiuGameClient,
) {
    private val syncMutex = Mutex()

    fun beginAuthorization(provider: MyPiuAuthProvider): String = oauthCoordinator.begin(provider)

    fun connectionState(): RepositoryConnectionState {
        val token = validToken()
        return RepositoryConnectionState(
            isPiuConnected = sessionStore.credentials() != null,
            isMyPiuConnected = token != null,
            accountId = token?.let { sessionStore.accountId(it.value) },
        )
    }

    suspend fun completeAuthorization(callbackUrl: String): RepositorySnapshot = syncMutex.withLock {
        val token = oauthCoordinator.complete(callbackUrl)
        retryPendingRevocations()
        val account = apiClient.account(token.value)
        sessionStore.saveAccountId(token.value, account.id)
        val credentials = sessionStore.credentials()
        val piuSnapshot = credentials?.let { fetch(it) }
        val result = piuSnapshot?.let { upload(it, token.value) }
        RepositorySnapshot(account, piuSnapshot, result, credentials != null, true)
    }

    suspend fun restoreAndSync(): RepositorySnapshot = syncMutex.withLock {
        retryPendingRevocations()
        val credentials = sessionStore.credentials()
        var token = validToken()
        val account = token?.let {
            try {
                apiClient.account(it.value).also { account ->
                    sessionStore.saveAccountId(it.value, account.id)
                }
            } catch (error: MyPiuApiException) {
                if (!error.isUnauthorized && !error.isAccountNotFound) throw error
                sessionStore.clearAccessToken()
                token = null
                null
            }
        }
        val piuSnapshot = credentials?.let { fetch(it) }
        val result = if (piuSnapshot != null && token != null) upload(piuSnapshot, token.value) else null
        RepositorySnapshot(account, piuSnapshot, result, credentials != null, token != null)
    }

    suspend fun connectPiu(
        username: String,
        password: String,
        version: PiuGameVersion,
    ): RepositorySnapshot = syncMutex.withLock {
        retryPendingRevocations()
        val credentials = PiuCredentials(username.trim(), password, version)
        require(credentials.username.isNotEmpty() && credentials.password.isNotEmpty()) {
            "Enter your PIUGAME username and password."
        }
        val piuSnapshot = fetch(credentials)
        val token = validToken()
        val account = token?.let {
            apiClient.account(it.value).also { account ->
                sessionStore.saveAccountId(it.value, account.id)
            }
        }
        val result = token?.let { upload(piuSnapshot, it.value) }
        sessionStore.saveCredentials(credentials)
        RepositorySnapshot(account, piuSnapshot, result, true, token != null)
    }

    suspend fun sync(): RepositorySnapshot = syncMutex.withLock {
        retryPendingRevocations()
        val credentials = sessionStore.credentials()
            ?: return@withLock RepositorySnapshot(null, null, null, false, validToken() != null)
        val token = validToken()
        val piuSnapshot = fetch(credentials)
        val result = token?.let { upload(piuSnapshot, it.value) }
        RepositorySnapshot(null, piuSnapshot, result, true, token != null)
    }

    suspend fun disconnectPiu() = syncMutex.withLock { sessionStore.clearCredentials() }

    suspend fun disconnectMyPiu() = syncMutex.withLock {
        val token = sessionStore.accessToken() ?: return@withLock
        sessionStore.enqueuePendingRevocation(token)
        sessionStore.clearAccessToken()
        retryPendingRevocations()
    }

    private suspend fun fetch(credentials: PiuCredentials): PiuSnapshot = try {
        piuClient(credentials.version).loginAndFetch(credentials.username, credentials.password)
    } catch (error: PiuGameException.AuthenticationFailed) {
        if (sessionStore.credentials() == credentials) sessionStore.clearCredentials()
        throw error
    }

    private suspend fun upload(snapshot: PiuSnapshot, accessToken: String): MyPiuSyncResult = try {
        apiClient.upload(snapshot, accessToken, installationId, appVersion)
    } catch (error: MyPiuApiException) {
        if (error.isPermanentPiuLinkError) {
            val credentials = sessionStore.credentials()
            if (credentials?.username == snapshot.profile.username && credentials.version == snapshot.version) {
                sessionStore.clearCredentials()
            }
        }
        throw error
    }

    private fun validToken() = sessionStore.accessToken()?.takeUnless { token ->
        if (token.isExpired()) {
            sessionStore.clearAccessToken()
            true
        } else {
            false
        }
    }

    suspend fun clearUnauthorizedSession(error: Throwable): Boolean {
        if (error is MyPiuApiException && (error.isUnauthorized || error.isAccountNotFound)) {
            syncMutex.withLock { sessionStore.clearAccessToken() }
            return true
        }
        return false
    }

    private suspend fun retryPendingRevocations() {
        oauthCoordinator.retryUnstoredTokenRevocations()
        sessionStore.pendingRevocations().forEach { token ->
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
            if (revoked) sessionStore.removePendingRevocation(token)
        }
    }
}

data class RepositorySnapshot(
    val account: MyPiuAccount?,
    val piuSnapshot: PiuSnapshot?,
    val syncResult: MyPiuSyncResult?,
    val isPiuConnected: Boolean,
    val isMyPiuConnected: Boolean,
)

data class RepositoryConnectionState(
    val isPiuConnected: Boolean,
    val isMyPiuConnected: Boolean,
    val accountId: String?,
)
