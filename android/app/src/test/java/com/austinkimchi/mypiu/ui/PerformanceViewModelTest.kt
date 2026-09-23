package com.austinkimchi.mypiu.ui

import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.performance.PerformanceDataSource
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
}

private class FakePerformanceDataSource(
    private val dashboards: ArrayDeque<MyPiuPerformanceDashboard> = ArrayDeque(),
    private val failure: Exception? = null,
) : PerformanceDataSource {
    var requests = 0

    override suspend fun dashboard(): MyPiuPerformanceDashboard {
        requests += 1
        failure?.let { throw it }
        return dashboards.removeFirst()
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
