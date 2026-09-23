package com.austinkimchi.mypiu.ui

import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceSession
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.performance.PerformanceDataSource
import com.austinkimchi.mypiu.core.performance.PerformanceRefreshSignal
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.coroutines.Continuation
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

@OptIn(ExperimentalCoroutinesApi::class)
class PerformanceViewModelTest {
    @Test
    fun connectedSessionLoadsAndRefreshesDashboard() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakePerformanceDataSource(
                ArrayDeque(listOf(dashboard("First"), dashboard("Updated"))),
            )
            val viewModel = PerformanceViewModel(source)
            viewModel.updateSession("one", connected = true)
            viewModel.start()
            advanceUntilIdle()

            assertEquals("First", viewModel.state.value.dashboard?.profile?.displayName)
            assertFalse(viewModel.state.value.isLoading)

            viewModel.refresh()
            advanceUntilIdle()

            assertEquals("Updated", viewModel.state.value.dashboard?.profile?.displayName)
            assertEquals(2, source.requests)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun successfulUploadSignalReloadsOnlyAfterProgressHasStarted() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakePerformanceDataSource(
                ArrayDeque(listOf(dashboard("First"), dashboard("Uploaded"))),
            )
            val refreshSignal = PerformanceRefreshSignal()
            val viewModel = PerformanceViewModel(source, refreshSignal)
            viewModel.updateSession("one", connected = true)

            refreshSignal.notifyUploadCompleted()
            advanceUntilIdle()
            assertEquals(0, source.requests)

            viewModel.start()
            advanceUntilIdle()
            assertEquals("First", viewModel.state.value.dashboard?.profile?.displayName)

            refreshSignal.notifyUploadCompleted()
            advanceUntilIdle()

            assertEquals("Uploaded", viewModel.state.value.dashboard?.profile?.displayName)
            assertEquals(2, source.requests)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun accountSwitchClearsOldDashboardAndLoadsReplacement() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakePerformanceDataSource(
                ArrayDeque(listOf(dashboard("First"), dashboard("Second"))),
            )
            val viewModel = PerformanceViewModel(source)
            viewModel.updateSession("one", connected = true)
            viewModel.start()
            advanceUntilIdle()
            assertEquals("First", viewModel.state.value.dashboard?.profile?.displayName)

            viewModel.updateSession("two", connected = true)
            assertNull(viewModel.state.value.dashboard)
            advanceUntilIdle()

            assertEquals("Second", viewModel.state.value.dashboard?.profile?.displayName)
            assertEquals("account:two", viewModel.state.value.accountScope)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun currentAuthorizationFailureInvalidatesSession() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakePerformanceDataSource(
                failure = MyPiuApiException(401, "invalid_token"),
            )
            val viewModel = PerformanceViewModel(source)
            viewModel.updateSession("one", connected = true)
            viewModel.start()
            advanceUntilIdle()

            assertFalse(viewModel.state.value.isConnected)
            assertTrue(viewModel.state.value.sessionInvalidated)
            assertNull(viewModel.state.value.dashboard)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun oldAuthorizationFailureCannotInvalidateReplacementSession() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            lateinit var oldRequest: Continuation<MyPiuPerformanceDashboard>
            var requests = 0
            val source = object : PerformanceDataSource {
                override suspend fun dashboard(): MyPiuPerformanceDashboard {
                    requests += 1
                    return if (requests == 1) {
                        suspendCoroutine { oldRequest = it }
                    } else {
                        dashboard("Replacement")
                    }
                }

                override suspend fun session(): MyPiuPerformanceSession? = null
            }
            val viewModel = PerformanceViewModel(source)
            viewModel.updateSession("one", connected = true)
            viewModel.start()
            runCurrent()

            viewModel.updateSession(null, connected = false)
            viewModel.updateSession("one", connected = true)
            advanceUntilIdle()
            assertEquals("Replacement", viewModel.state.value.dashboard?.profile?.displayName)

            oldRequest.resumeWithException(MyPiuApiException(401, "invalid_token"))
            advanceUntilIdle()

            assertTrue(viewModel.state.value.isConnected)
            assertFalse(viewModel.state.value.sessionInvalidated)
            assertEquals("Replacement", viewModel.state.value.dashboard?.profile?.displayName)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun unresolvedAccountDoesNotLoadPrivatePerformance() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakePerformanceDataSource()
            val viewModel = PerformanceViewModel(source)
            viewModel.updateSession(null, connected = true)
            viewModel.start()
            advanceUntilIdle()

            assertFalse(viewModel.state.value.isConnected)
            assertEquals(0, source.requests)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun recentSessionLoadsSeparatelyAndCanBeRefreshed() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakePerformanceDataSource(
                dashboards = ArrayDeque(listOf(dashboard("Player"))),
                sessions = ArrayDeque(listOf(session(4), session(6))),
            )
            val viewModel = PerformanceViewModel(source)
            viewModel.updateSession("one", connected = true)
            viewModel.start()
            advanceUntilIdle()

            viewModel.loadSession()
            advanceUntilIdle()
            assertEquals(4, viewModel.state.value.session?.summary?.playCount)
            assertTrue(viewModel.state.value.isSessionLoaded)

            viewModel.loadSession(force = true)
            advanceUntilIdle()
            assertEquals(6, viewModel.state.value.session?.summary?.playCount)
            assertEquals(2, source.sessionRequests)
            assertEquals("Player", viewModel.state.value.dashboard?.profile?.displayName)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun accountSwitchClearsLoadedSession() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakePerformanceDataSource(
                dashboards = ArrayDeque(listOf(dashboard("First"), dashboard("Second"))),
                sessions = ArrayDeque(listOf(session(4))),
            )
            val viewModel = PerformanceViewModel(source)
            viewModel.updateSession("one", connected = true)
            viewModel.start()
            advanceUntilIdle()
            viewModel.loadSession()
            advanceUntilIdle()
            assertEquals(4, viewModel.state.value.session?.summary?.playCount)

            viewModel.updateSession("two", connected = true)

            assertNull(viewModel.state.value.session)
            assertFalse(viewModel.state.value.isSessionLoaded)
            advanceUntilIdle()
            assertEquals("Second", viewModel.state.value.dashboard?.profile?.displayName)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun oldSessionAuthorizationFailureCannotInvalidateReplacementSession() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            lateinit var oldRequest: Continuation<MyPiuPerformanceSession?>
            var dashboardRequests = 0
            var sessionRequests = 0
            val source = object : PerformanceDataSource {
                override suspend fun dashboard(): MyPiuPerformanceDashboard =
                    dashboard(if (dashboardRequests++ == 0) "First" else "Replacement")

                override suspend fun session(): MyPiuPerformanceSession? {
                    sessionRequests += 1
                    return if (sessionRequests == 1) {
                        suspendCoroutine { oldRequest = it }
                    } else {
                        session(6)
                    }
                }
            }
            val viewModel = PerformanceViewModel(source)
            viewModel.updateSession("one", connected = true)
            viewModel.start()
            advanceUntilIdle()
            viewModel.loadSession()
            runCurrent()

            viewModel.updateSession(null, connected = false)
            viewModel.updateSession("one", connected = true)
            advanceUntilIdle()
            viewModel.loadSession()
            advanceUntilIdle()
            assertEquals(6, viewModel.state.value.session?.summary?.playCount)

            oldRequest.resumeWithException(MyPiuApiException(401, "invalid_token"))
            advanceUntilIdle()

            assertTrue(viewModel.state.value.isConnected)
            assertFalse(viewModel.state.value.sessionInvalidated)
            assertEquals(6, viewModel.state.value.session?.summary?.playCount)
            assertEquals("Replacement", viewModel.state.value.dashboard?.profile?.displayName)
        } finally {
            Dispatchers.resetMain()
        }
    }
}

private class FakePerformanceDataSource(
    private val dashboards: ArrayDeque<MyPiuPerformanceDashboard> = ArrayDeque(),
    private val sessions: ArrayDeque<MyPiuPerformanceSession?> = ArrayDeque(),
    private val failure: Exception? = null,
) : PerformanceDataSource {
    var requests = 0
    var sessionRequests = 0

    override suspend fun dashboard(): MyPiuPerformanceDashboard {
        requests += 1
        failure?.let { throw it }
        return dashboards.removeFirst()
    }

    override suspend fun session(): MyPiuPerformanceSession? {
        sessionRequests += 1
        failure?.let { throw it }
        return sessions.removeFirst()
    }
}

private fun dashboard(name: String) = MyPiuPerformanceDashboard(
    profile = MyPiuPerformanceDashboard.Profile(displayName = name),
    totals = MyPiuPerformanceDashboard.Totals(
        trackedPlays = 0,
        trackedCharts = 0,
        trackedPumbilityCharts = 0,
        upscores = 0,
        upscoresThisWeek = 0,
        upscoresThisMonth = 0,
        upscoresToday = 0,
        recentlyPlayed = 0,
    ),
    canSync = true,
    mongoReady = true,
)

private fun session(playCount: Int) = MyPiuPerformanceSession(
    summary = MyPiuPerformanceSession.Summary(
        playCount = playCount,
        clearCount = playCount,
        failedCount = 0,
        stageBreakCount = 0,
        distinctCharts = playCount,
        startedAt = "2026-09-22T06:00:00Z",
        endedAt = "2026-09-22T07:00:00Z",
        durationMinutes = 60,
    ),
)
