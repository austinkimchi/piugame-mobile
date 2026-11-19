package com.austinkimchi.mypiu.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.austinkimchi.mypiu.AppContainer
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceSession
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.performance.PerformanceDataSource
import com.austinkimchi.mypiu.core.performance.PerformanceRefreshSignal
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

class PerformanceViewModel(
    private val repository: PerformanceDataSource,
    refreshSignal: PerformanceRefreshSignal = PerformanceRefreshSignal(),
) : ViewModel() {
    private val mutableState = MutableStateFlow(PerformanceUiState())
    val state: StateFlow<PerformanceUiState> = mutableState.asStateFlow()

    private var sessionGeneration = 0L
    private var sessionLoadGeneration = 0L
    private var loadJob: Job? = null
    private var sessionJob: Job? = null
    private var sessionPaginationJob: Job? = null
    private var started = false
    private var observedRefreshRevision = refreshSignal.revision.value

    init {
        viewModelScope.launch {
            refreshSignal.revision.collect { revision ->
                if (revision == observedRefreshRevision) return@collect
                observedRefreshRevision = revision
                repository.invalidateSessionCache()
                if (started) refresh()
            }
        }
    }

    fun updateSession(accountId: String?, connected: Boolean, preferredVersion: PiuGameVersion? = null) {
        val scope = accountId?.takeIf { connected }?.let { "account:$it" }
        val isConnected = scope != null
        val current = mutableState.value
        if (current.accountScope == scope && current.isConnected == isConnected &&
            current.preferredVersion == preferredVersion) return
        val restartHistory = current.accountScope == scope &&
            current.preferredVersion != preferredVersion && sessionJob != null

        sessionGeneration += 1
        if (current.accountScope != null) repository.invalidateSessionCache()
        loadJob?.cancel()
        sessionJob?.cancel()
        sessionPaginationJob?.cancel()
        mutableState.value = PerformanceUiState(
            accountScope = scope,
            isConnected = isConnected,
            preferredVersion = preferredVersion,
        )
        if (started && isConnected) reload()
        // The mounted screen's account effect does not restart for a preference-only change.
        if (restartHistory && isConnected) reloadSession()
    }

    fun start() {
        if (started) return
        started = true
        if (mutableState.value.isConnected) reload()
    }

    fun refresh() {
        val snapshot = mutableState.value
        if (!snapshot.isConnected) return
        reload()
        if (snapshot.isSessionLoaded || snapshot.isSessionLoading) reloadSession()
    }

    fun loadSession(force: Boolean = false) {
        val snapshot = mutableState.value
        if (!snapshot.isConnected || snapshot.accountScope == null) return
        if (!force && snapshot.isSessionLoading) return
        reloadSession()
    }

    fun loadMoreSessions() {
        val snapshot = mutableState.value
        val offset = snapshot.nextSessionOffset ?: return
        val scope = snapshot.accountScope ?: return
        if (!snapshot.isConnected || snapshot.isSessionLoading || snapshot.isSessionLoadingMore || sessionPaginationJob?.isActive == true) return
        val generation = sessionGeneration
        val loadGeneration = sessionLoadGeneration
        sessionPaginationJob = viewModelScope.launch {
            mutableState.update { it.copy(isSessionLoadingMore = true, sessionPaginationError = null) }
            try {
                val page = repository.sessionPage(offset)
                currentCoroutineContext().ensureActive()
                if (generation != sessionGeneration || loadGeneration != sessionLoadGeneration ||
                    mutableState.value.accountScope != scope) return@launch
                mutableState.update { state ->
                    val knownIds = state.sessions.mapTo(mutableSetOf()) { it.id }
                    state.copy(
                        sessions = state.sessions + page.sessions.filter { knownIds.add(it.id) },
                        nextSessionOffset = page.nextOffset?.takeIf { it > offset },
                        isSessionLoadingMore = false,
                        sessionPaginationError = null,
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                if (generation != sessionGeneration || loadGeneration != sessionLoadGeneration ||
                    mutableState.value.accountScope != scope) return@launch
                if (error is MyPiuApiException && (error.isUnauthorized || error.isAccountNotFound)) {
                    sessionGeneration += 1
                    sessionJob?.cancel()
                    loadJob?.cancel()
                    mutableState.value = PerformanceUiState(
                        accountScope = scope,
                        sessionError = error.message,
                        sessionInvalidated = true,
                    )
                    return@launch
                }
                mutableState.update {
                    it.copy(
                        isSessionLoadingMore = false,
                        sessionPaginationError = error.message ?: "More sessions could not be loaded.",
                    )
                }
            }
        }
    }

    fun acknowledgeSessionInvalidation() {
        mutableState.update { it.copy(sessionInvalidated = false) }
    }

    private fun reload() {
        val snapshot = mutableState.value
        if (!snapshot.isConnected || snapshot.accountScope == null) return
        val generation = sessionGeneration
        val scope = snapshot.accountScope
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            mutableState.update { it.copy(isLoading = true, error = null) }
            try {
                val dashboard = repository.dashboard()
                currentCoroutineContext().ensureActive()
                if (generation != sessionGeneration || mutableState.value.accountScope != scope) return@launch
                mutableState.update { it.copy(dashboard = dashboard, isLoading = false, error = null) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                if (generation != sessionGeneration || mutableState.value.accountScope != scope) return@launch
                val sessionInvalidated = error is MyPiuApiException &&
                    (error.isUnauthorized || error.isAccountNotFound)
                if (sessionInvalidated) {
                    sessionGeneration += 1
                    sessionJob?.cancel()
                    sessionPaginationJob?.cancel()
                }
                mutableState.update {
                    it.copy(
                        dashboard = if (sessionInvalidated) null else it.dashboard,
                        session = if (sessionInvalidated) null else it.session,
                        sessions = if (sessionInvalidated) emptyList() else it.sessions,
                        nextSessionOffset = if (sessionInvalidated) null else it.nextSessionOffset,
                        isSessionLoadingMore = if (sessionInvalidated) false else it.isSessionLoadingMore,
                        sessionPaginationError = if (sessionInvalidated) null else it.sessionPaginationError,
                        isSessionLoaded = if (sessionInvalidated) false else it.isSessionLoaded,
                        isSessionLoading = if (sessionInvalidated) false else it.isSessionLoading,
                        sessionError = if (sessionInvalidated) null else it.sessionError,
                        isConnected = if (sessionInvalidated) false else it.isConnected,
                        isLoading = false,
                        error = error.message ?: "Performance could not be loaded.",
                        sessionInvalidated = sessionInvalidated,
                    )
                }
            }
        }
    }

    private fun reloadSession() {
        val snapshot = mutableState.value
        if (!snapshot.isConnected || snapshot.accountScope == null) return
        val generation = sessionGeneration
        val scope = snapshot.accountScope
        sessionLoadGeneration += 1
        val loadGeneration = sessionLoadGeneration
        sessionPaginationJob?.cancel()
        sessionJob?.cancel()
        sessionJob = viewModelScope.launch {
            mutableState.update {
                it.copy(
                    isSessionLoading = true,
                    isSessionLoadingMore = false,
                    sessionError = null,
                    sessionPaginationError = null,
                )
            }
            try {
                repository.firstSessionPage(scope.removePrefix("account:"), onCached = { cached ->
                    if (generation == sessionGeneration && loadGeneration == sessionLoadGeneration &&
                        mutableState.value.accountScope == scope) mutableState.update {
                        if (it.isSessionLoaded) it else it.copy(
                            session = cached.page.sessions.firstOrNull(),
                            sessions = cached.page.sessions.distinctBy { session -> session.id },
                            nextSessionOffset = null,
                            isSessionLoaded = true,
                            sessionSavedAtEpochMillis = cached.savedAtEpochMillis,
                        )
                    }
                }, onFresh = { page ->
                    if (generation == sessionGeneration && loadGeneration == sessionLoadGeneration &&
                        mutableState.value.accountScope == scope) mutableState.update {
                        it.copy(
                            session = page.sessions.firstOrNull(),
                            sessions = page.sessions.distinctBy { session -> session.id },
                            nextSessionOffset = page.nextOffset?.takeIf { offset -> offset > 0 },
                            isSessionLoading = false,
                            isSessionLoaded = true,
                            sessionError = null,
                            sessionPaginationError = null,
                            sessionSavedAtEpochMillis = null,
                        )
                    }
                })
            } catch (error: CancellationException) {
                if (generation == sessionGeneration && loadGeneration == sessionLoadGeneration &&
                    mutableState.value.accountScope == scope) mutableState.update {
                    it.copy(isSessionLoading = false,
                        sessionError = if (it.isSessionLoaded) it.sessionError else "Loading was interrupted. Try again.")
                }
                throw error
            } catch (error: Exception) {
                currentCoroutineContext().ensureActive()
                if (generation != sessionGeneration || mutableState.value.accountScope != scope) return@launch
                val sessionInvalidated = error is MyPiuApiException &&
                    (error.isUnauthorized || error.isAccountNotFound)
                if (sessionInvalidated) {
                    sessionGeneration += 1
                    loadJob?.cancel()
                    sessionPaginationJob?.cancel()
                }
                mutableState.update {
                    it.copy(
                        dashboard = if (sessionInvalidated) null else it.dashboard,
                        session = if (sessionInvalidated) null else it.session,
                        sessions = if (sessionInvalidated) emptyList() else it.sessions,
                        nextSessionOffset = if (sessionInvalidated) null else it.nextSessionOffset,
                        isConnected = if (sessionInvalidated) false else it.isConnected,
                        isSessionLoading = false,
                        isSessionLoaded = if (sessionInvalidated) false else it.isSessionLoaded,
                        sessionError = error.message ?: "Recent session could not be loaded.",
                        sessionInvalidated = sessionInvalidated,
                    )
                }
            }
        }
    }

    class Factory(private val container: AppContainer) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            PerformanceViewModel(container.performanceRepository, container.performanceRefreshSignal) as T
    }
}

data class PerformanceUiState(
    val preferredVersion: PiuGameVersion? = null,
    val accountScope: String? = null,
    val isConnected: Boolean = false,
    val dashboard: MyPiuPerformanceDashboard? = null,
    val session: MyPiuPerformanceSession? = null,
    val sessions: List<MyPiuPerformanceSession> = emptyList(),
    val isLoading: Boolean = false,
    val isSessionLoading: Boolean = false,
    val isSessionLoaded: Boolean = false,
    val nextSessionOffset: Int? = null,
    val isSessionLoadingMore: Boolean = false,
    val sessionPaginationError: String? = null,
    val sessionError: String? = null,
    val sessionSavedAtEpochMillis: Long? = null,
    val error: String? = null,
    val sessionInvalidated: Boolean = false,
)
