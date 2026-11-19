package com.austinkimchi.mypiu.ui

import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceSession
import com.austinkimchi.mypiu.core.model.PerformanceSessionsResponse
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.performance.CachedSessionsPage
import com.austinkimchi.mypiu.core.performance.PerformanceDataSource
import java.io.IOException
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PerformanceSessionsCacheViewModelTest {
    private fun page(prefix: String): PerformanceSessionsResponse {
        val text = checkNotNull(javaClass.classLoader?.getResourceAsStream("session-cache-page.json"))
            .bufferedReader().use { it.readText() }.replace("fixture-", "$prefix-")
        return Json { ignoreUnknownKeys = true }.decodeFromString(text)
    }

    @Test fun cachedRowsDisablePaginationUntilFreshPageAndLateCacheCannotOverwriteIt() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val source = CacheFirstSessionSource()
        try {
            val model = PerformanceViewModel(source)
            model.updateSession("a", true); model.loadSession(); runCurrent()
            val request = source.requests.single()
            request.cached(CachedSessionsPage(page("saved"), 1000))
            assertTrue(model.state.value.isSessionLoaded)
            assertTrue(model.state.value.isSessionLoading)
            assertEquals("saved-session-0", model.state.value.sessions.first().id)
            assertNull(model.state.value.nextSessionOffset)
            model.loadMoreSessions(); runCurrent()
            assertEquals(0, source.paginationCalls)
            request.fresh(page("fresh")); runCurrent()
            assertEquals(20, model.state.value.nextSessionOffset)
            assertNull(model.state.value.sessionSavedAtEpochMillis)
            assertFalse(model.state.value.isSessionLoading)
            request.cached(CachedSessionsPage(page("late-saved"), 1000))
            assertEquals("fresh-session-0", model.state.value.sessions.first().id)
            // Identity validation/storage may still be finishing after fresh rows arrive.
            model.loadMoreSessions(); runCurrent()
            assertEquals(1, source.paginationCalls)
            request.finish(); runCurrent()
        } finally { source.close(); Dispatchers.resetMain() }
    }

    @Test fun cacheRemainsOnNetworkFailureAndCancellationWithoutRowsEndsLoading() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val source = CacheFirstSessionSource()
        try {
            val model = PerformanceViewModel(source)
            model.updateSession("a", true); model.loadSession(); runCurrent()
            source.requests.last().cached(CachedSessionsPage(page("saved"), 1000))
            source.requests.last().fail(IOException("Offline")); runCurrent()
            assertEquals("saved-session-0", model.state.value.sessions.first().id)
            assertEquals("Offline", model.state.value.sessionError)
            assertFalse(model.state.value.isSessionLoading)
            model.updateSession("b", true); model.loadSession(); runCurrent()
            source.requests.last().fail(CancellationException("Session changed")); runCurrent()
            assertTrue(model.state.value.sessions.isEmpty())
            assertFalse(model.state.value.isSessionLoading)
            assertNotNull(model.state.value.sessionError)
        } finally { source.close(); Dispatchers.resetMain() }
    }

    @Test fun accountReplacementRejectsOldCachedAndFreshCallbacks() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val source = CacheFirstSessionSource()
        try {
            val model = PerformanceViewModel(source)
            model.updateSession("a", true); model.loadSession(); runCurrent()
            val old = source.requests.last()
            old.cached(CachedSessionsPage(page("private-a"), 1000))
            model.updateSession("b", true); model.loadSession(); runCurrent()
            val replacement = source.requests.last()
            assertTrue(model.state.value.sessions.isEmpty())
            replacement.fresh(page("private-b")); replacement.finish(); runCurrent()
            old.cached(CachedSessionsPage(page("old-a"), 1000))
            old.fresh(page("old-a")); old.finish(); runCurrent()
            assertEquals("private-b-session-0", model.state.value.sessions.first().id)
            assertTrue(source.invalidations > 0)
        } finally { source.close(); Dispatchers.resetMain() }
    }

    @Test fun preferredVersionChangeClearsRowsAndRejectsOldCallbacks() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val source = CacheFirstSessionSource()
        try {
            val model = PerformanceViewModel(source)
            model.updateSession("a", true, PiuGameVersion.PHOENIX_2); model.loadSession(); runCurrent()
            val old = source.requests.last()
            old.cached(CachedSessionsPage(page("phoenix2"), 1000))
            model.updateSession("a", true, PiuGameVersion.PHOENIX)
            assertTrue(model.state.value.sessions.isEmpty())
            assertTrue(source.invalidations > 0)
            model.loadSession(); runCurrent()
            val replacement = source.requests.last()
            replacement.fresh(page("phoenix")); replacement.finish(); runCurrent()
            old.fresh(page("old-phoenix2")); old.finish(); runCurrent()
            assertEquals("phoenix-session-0", model.state.value.sessions.first().id)
        } finally { source.close(); Dispatchers.resetMain() }
    }
}

private class CacheFirstSessionSource : PerformanceDataSource {
    val requests = mutableListOf<Request>()
    var paginationCalls = 0
    var invalidations = 0
    override fun invalidateSessionCache() { invalidations += 1 }
    override suspend fun dashboard(): MyPiuPerformanceDashboard = error("Dashboard not requested")
    override suspend fun session(): MyPiuPerformanceSession? = null
    override suspend fun sessionPage(offset: Int, limit: Int): PerformanceSessionsResponse {
        paginationCalls += 1
        return PerformanceSessionsResponse()
    }
    override suspend fun firstSessionPage(accountId: String, onCached: (CachedSessionsPage) -> Unit,
        onFresh: (PerformanceSessionsResponse) -> Unit) = suspendCoroutine<Unit> {
        requests += Request(onCached, onFresh, it)
    }
    fun close() { requests.forEach { it.fail(CancellationException()) } }
    class Request(val cached: (CachedSessionsPage) -> Unit, val fresh: (PerformanceSessionsResponse) -> Unit,
        private val continuation: Continuation<Unit>) {
        private var completed = false
        fun finish() { if (!completed) { completed = true; continuation.resume(Unit) } }
        fun fail(error: Throwable) { if (!completed) { completed = true; continuation.resumeWithException(error) } }
    }
}
