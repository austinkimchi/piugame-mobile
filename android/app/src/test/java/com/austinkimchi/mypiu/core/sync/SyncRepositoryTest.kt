package com.austinkimchi.mypiu.core.sync

import com.austinkimchi.mypiu.core.model.MyPiuAccessToken
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.network.OAuthCoordinator
import com.austinkimchi.mypiu.core.security.SecretStore
import com.austinkimchi.mypiu.core.security.SessionStore
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SyncRepositoryTest {
    @Test
    fun connectionStateRestoresOnlyCurrentTokensAccountIdentity() {
        val sessionStore = SessionStore(MemorySecretStore())
        val token = MyPiuAccessToken("token", Long.MAX_VALUE, "installation")
        sessionStore.saveAccessToken(token)
        sessionStore.saveAccountIdentity(token.value, "account-one", PiuGameVersion.PHOENIX)
        val repository = repository(sessionStore)

        val connected = repository.connectionState()

        assertTrue(connected.isMyPiuConnected)
        assertEquals("account-one", connected.accountId)
        assertEquals(PiuGameVersion.PHOENIX, connected.accountVersion)

        sessionStore.saveAccessToken(MyPiuAccessToken("replacement", Long.MAX_VALUE, "installation"))
        val replacement = repository.connectionState()
        assertTrue(replacement.isMyPiuConnected)
        assertNull(replacement.accountId)
        assertNull(replacement.accountVersion)
    }

    @Test
    fun expiredTokenClearsPersistedAccountIdentity() {
        val sessionStore = SessionStore(MemorySecretStore())
        val token = MyPiuAccessToken("expired", 0, "installation")
        sessionStore.saveAccessToken(token)
        sessionStore.saveAccountIdentity(token.value, "account-one", PiuGameVersion.PHOENIX)

        val connection = repository(sessionStore).connectionState()

        assertFalse(connection.isMyPiuConnected)
        assertNull(connection.accountId)
        assertNull(connection.accountVersion)
        assertNull(sessionStore.accountIdentity(token.value))
    }

    @Test
    fun deletedAccountClearsTokenAndPersistedIdentity() = runTest {
        val sessionStore = SessionStore(MemorySecretStore())
        val token = MyPiuAccessToken("token", Long.MAX_VALUE, "installation")
        sessionStore.saveAccessToken(token)
        sessionStore.saveAccountIdentity(token.value, "deleted-account", PiuGameVersion.PHOENIX)

        val cleared = repository(sessionStore).clearUnauthorizedSession(
            MyPiuApiException(404, "account_not_found"),
        )

        assertTrue(cleared)
        assertNull(sessionStore.accessToken())
        assertNull(sessionStore.accountIdentity(token.value))
    }

    private fun repository(sessionStore: SessionStore): SyncRepository {
        val apiClient = MyPiuApiClient("https://mypiu.example/")
        return SyncRepository(
            sessionStore = sessionStore,
            apiClient = apiClient,
            oauthCoordinator = OAuthCoordinator(apiClient, sessionStore, "installation", "test"),
            installationId = "installation",
            appVersion = "test",
        )
    }
}

private class MemorySecretStore : SecretStore {
    private val values = mutableMapOf<String, String>()
    override fun put(key: String, value: String) { values[key] = value }
    override fun get(key: String): String? = values[key]
    override fun remove(key: String) { values.remove(key) }
}
