package com.austinkimchi.mypiu.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.austinkimchi.mypiu.AppContainer
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceSession
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

class PerformanceViewModel(
    private val repository: PerformanceDataSource,
    refreshSignal: PerformanceRefreshSignal = PerformanceRefreshSignal(),
) : ViewModel() {
    private val mutableState = MutableStateFlow(PerformanceUiState())
    val state: StateFlow<PerformanceUiState> = mutableState.asStateFlow()

    private var sessionGeneration = 0L
    private var loadJob: Job? = null
    private var sessionJob: Job? = null
    private var started = false
    private var observedRefreshRevision = refreshSignal.revision.value

    init {
        viewModelScope.launch {
            refreshSignal.revision.collect { revision ->
                if (revision == observedRefreshRevision) return@collect
                observedRefreshRevision = revision
                if (started) refresh()
            }
        }
    }

    fun updateSession(accountId: String?, connected: Boolean) {
        val scope = accountId?.takeIf { connected }?.let { "account:$it" }
        val isConnected = scope != null
        val current = mutableState.value
        if (current.accountScope == scope && current.isConnected == isConnected) return

        sessionGeneration += 1
        loadJob?.cancel()
        sessionJob?.cancel()
        mutableState.value = PerformanceUiState(
            accountScope = scope,
            isConnected = isConnected,
        )
        if (started && isConnected) reload()
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
        if (!force && (snapshot.isSessionLoading || snapshot.isSessionLoaded)) return
        reloadSession()
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
                if (generation != sessionGeneration || mutableState.value.accountScope != scope) return@launch
                mutableState.update { it.copy(dashboard = dashboard, isLoading = false, error = null) }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (generation != sessionGeneration || mutableState.value.accountScope != scope) return@launch
                val sessionInvalidated = error is MyPiuApiException &&
                    (error.isUnauthorized || error.isAccountNotFound)
                if (sessionInvalidated) {
                    sessionGeneration += 1
                    sessionJob?.cancel()
                }
                mutableState.update {
                    it.copy(
                        dashboard = if (sessionInvalidated) null else it.dashboard,
                        session = if (sessionInvalidated) null else it.session,
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
        sessionJob?.cancel()
        sessionJob = viewModelScope.launch {
            mutableState.update {
                it.copy(
                    session = null,
                    isSessionLoading = true,
                    isSessionLoaded = false,
                    sessionError = null,
                )
            }
            try {
                val sessions = repository.sessions()
                if (generation != sessionGeneration || mutableState.value.accountScope != scope) return@launch
                mutableState.update {
                    it.copy(
                        session = sessions.firstOrNull(),
                        sessions = sessions,
                        isSessionLoading = false,
                        isSessionLoaded = true,
                        sessionError = null,
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (generation != sessionGeneration || mutableState.value.accountScope != scope) return@launch
                val sessionInvalidated = error is MyPiuApiException &&
                    (error.isUnauthorized || error.isAccountNotFound)
                if (sessionInvalidated) {
                    sessionGeneration += 1
                    loadJob?.cancel()
                }
                mutableState.update {
                    it.copy(
                        dashboard = if (sessionInvalidated) null else it.dashboard,
                        session = null,
                        sessions = emptyList(),
                        isConnected = if (sessionInvalidated) false else it.isConnected,
                        isSessionLoading = false,
                        isSessionLoaded = false,
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
    val accountScope: String? = null,
    val isConnected: Boolean = false,
    val dashboard: MyPiuPerformanceDashboard? = null,
    val session: MyPiuPerformanceSession? = null,
    val sessions: List<MyPiuPerformanceSession> = emptyList(),
    val isLoading: Boolean = false,
    val isSessionLoading: Boolean = false,
    val isSessionLoaded: Boolean = false,
    val sessionError: String? = null,
    val error: String? = null,
    val sessionInvalidated: Boolean = false,
)
