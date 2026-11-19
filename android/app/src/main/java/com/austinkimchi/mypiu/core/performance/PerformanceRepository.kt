package com.austinkimchi.mypiu.core.performance

import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceSession
import com.austinkimchi.mypiu.core.model.PerformanceSessionsResponse
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.security.SessionStore
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.isActive

interface PerformanceDataSource {
    fun invalidateSessionCache() {}
    suspend fun firstSessionPage(accountId: String, onCached: (CachedSessionsPage) -> Unit,
        onFresh: (PerformanceSessionsResponse) -> Unit) { onFresh(sessionPage()) }
    suspend fun dashboard(): MyPiuPerformanceDashboard
    suspend fun session(): MyPiuPerformanceSession?
    suspend fun sessions(): List<MyPiuPerformanceSession> = session()?.let(::listOf) ?: emptyList()
    suspend fun sessionPage(offset: Int = 0, limit: Int = 20): PerformanceSessionsResponse =
        PerformanceSessionsResponse(sessions())
}

class PerformanceRepository(
    private val sessionStore: SessionStore,
    private val apiClient: MyPiuApiClient,
    private val cache: PerformanceSessionsCache? = null,
    private val origin: String = "https://mypiu.austin.kim/",
) : PerformanceDataSource {
    private val cacheGeneration = AtomicLong()
    private val cleanupScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val cacheLock = Any()
    private var pendingClear: Job? = null

    override fun invalidateSessionCache() {
        synchronized(cacheLock) {
            cacheGeneration.incrementAndGet()
            cache?.let {
                val previous = pendingClear
                pendingClear = cleanupScope.launch(start = CoroutineStart.LAZY) { previous?.join(); it.clear() }
                pendingClear?.start()
            }
        }
    }

    override suspend fun firstSessionPage(accountId: String, onCached: (CachedSessionsPage) -> Unit,
        onFresh: (PerformanceSessionsResponse) -> Unit) = coroutineScope {
        val storedToken = sessionStore.accessToken()
        if (storedToken?.isExpired() == true) {
            sessionStore.clearAccessToken()
            invalidateSessionCache()
        }
        val token = storedToken?.takeUnless { it.isExpired() }?.value
            ?: throw MyPiuApiException(401, "invalid_token")
        if (sessionStore.accountIdentity(token)?.accountId != accountId) {
            throw CancellationException("Account identity changed")
        }
        val (generation, clearing) = synchronized(cacheLock) { cacheGeneration.incrementAndGet() to pendingClear }
        val isCurrent = {
            cacheGeneration.get() == generation && sessionStore.accessToken()?.let { !it.isExpired() && it.value == token } == true &&
                sessionStore.accountIdentity(token)?.accountId == accountId
        }
        val identity = async {
            try {
                val account = withSession { currentToken ->
                    if (currentToken != token) throw CancellationException("Session changed")
                    apiClient.account(currentToken)
                }
                if (!isCurrent() || account.id != accountId) throw CancellationException("Account changed")
                SessionsCacheContext.fromToken(origin, account.id, account.piuGameVersion, token)
            } catch (error: CancellationException) { throw error }
            catch (error: MyPiuApiException) {
                if (error.isUnauthorized || error.isAccountNotFound) throw error
                null
            } catch (_: Exception) { null }
        }
        val fresh = async {
            try {
                Result.success(withSession { currentToken ->
                    if (currentToken != token) throw CancellationException("Session changed")
                    apiClient.performanceSessionsPage(0, 20, currentToken)
                })
            } catch (error: CancellationException) { throw error }
            catch (error: Exception) { Result.failure(error) }
        }
        val publishedFresh = AtomicBoolean()
        val saved = launch {
            clearing?.join()
            val context = identity.await() ?: return@launch
            val cached = cache?.load(context, isCurrent) ?: return@launch
            if (isCurrent() && !publishedFresh.get()) onCached(cached)
        }
        try {
            val page = fresh.await().getOrThrow()
            if (!isCurrent()) throw CancellationException("Session changed")
            publishedFresh.set(true)
            onFresh(page)
            val context = identity.await()
            clearing?.join()
            if (context != null && isCurrent()) cache?.save(page, context, isCurrent)
        } finally {
            // Await a possible saved page on transient network failure, but never on cancellation.
            if (kotlinx.coroutines.currentCoroutineContext().isActive) saved.join() else saved.cancel()
        }
    }
    override suspend fun dashboard(): MyPiuPerformanceDashboard = withSession(apiClient::performance)

    override suspend fun session(): MyPiuPerformanceSession? = withSession(apiClient::performanceSession)

    override suspend fun sessions(): List<MyPiuPerformanceSession> = withSession(apiClient::performanceSessions)

    override suspend fun sessionPage(offset: Int, limit: Int): PerformanceSessionsResponse = withSession { token ->
        apiClient.performanceSessionsPage(offset, limit, token)
    }

    private suspend fun <Value> withSession(operation: suspend (String) -> Value): Value {
        val storedToken = sessionStore.accessToken()
        val token = when {
            storedToken == null -> throw MyPiuApiException(401, "invalid_token")
            storedToken.isExpired() -> {
                sessionStore.clearAccessToken()
                invalidateSessionCache()
                throw MyPiuApiException(401, "invalid_token")
            }
            else -> storedToken.value
        }
        return try {
            operation(token).also {
                if (sessionStore.accessToken()?.value != token) throw CancellationException("Session changed")
            }
        } catch (error: MyPiuApiException) {
            if (sessionStore.accessToken()?.value != token) throw CancellationException("Session changed")
            if (
                (error.isUnauthorized || error.isAccountNotFound) &&
                sessionStore.accessToken()?.value == token
            ) {
                sessionStore.clearAccessToken()
                invalidateSessionCache()
            }
            throw error
        }
    }
}
