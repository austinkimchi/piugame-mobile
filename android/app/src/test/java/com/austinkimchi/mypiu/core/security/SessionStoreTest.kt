package com.austinkimchi.mypiu.core.security

import com.austinkimchi.mypiu.core.model.MyPiuAccessToken
import com.austinkimchi.mypiu.core.model.PiuCredentials
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionStoreTest {
    @Test
    fun credentialsAndTokensRoundTripThroughSecretBoundary() {
        val secrets = MemorySecretStore()
        val store = SessionStore(secrets)
        val credentials = PiuCredentials("player", "secret", PiuGameVersion.PHOENIX_2)
        val token = MyPiuAccessToken("mypiu_token", 1_900_000_000_000, "installation")

        store.saveCredentials(credentials)
        store.saveAccessToken(token)
        store.saveAccountId(token.value, "account-one")
        assertEquals(credentials, store.credentials())
        assertEquals(token, store.accessToken())
        assertEquals("account-one", store.accountId(token.value))

        store.clearCredentials()
        store.clearAccessToken()
        assertNull(store.credentials())
        assertNull(store.accessToken())
        assertNull(store.accountId(token.value))
    }

    @Test
    fun accountIdentityIsBoundToCurrentAccessToken() {
        val store = SessionStore(MemorySecretStore())
        val first = MyPiuAccessToken("first", 1_900_000_000_000, "installation")
        val replacement = MyPiuAccessToken("replacement", 1_900_000_000_000, "installation")
        store.saveAccessToken(first)
        store.saveAccountId(first.value, "account-one")

        store.saveAccessToken(replacement)

        assertNull(store.accountId(first.value))
        assertNull(store.accountId(replacement.value))
        store.saveAccountId(replacement.value, "account-two")
        assertEquals("account-two", store.accountId(replacement.value))
    }

    @Test
    fun pendingRevocationsAreDeduplicatedAndRemovedIndividually() {
        val store = SessionStore(MemorySecretStore())
        val first = MyPiuAccessToken("first", 1_900_000_000_000, "installation")
        val second = MyPiuAccessToken("second", 1_900_000_000_000, "installation")

        store.enqueuePendingRevocation(first)
        store.enqueuePendingRevocation(first)
        store.enqueuePendingRevocation(second)
        assertEquals(listOf(first, second), store.pendingRevocations())

        store.removePendingRevocation(first)
        assertEquals(listOf(second), store.pendingRevocations())
        store.removePendingRevocation(second)
        assertTrue(store.pendingRevocations().isEmpty())
    }
}

private class MemorySecretStore : SecretStore {
    private val values = mutableMapOf<String, String>()
    override fun put(key: String, value: String) { values[key] = value }
    override fun get(key: String): String? = values[key]
    override fun remove(key: String) { values.remove(key) }
}
