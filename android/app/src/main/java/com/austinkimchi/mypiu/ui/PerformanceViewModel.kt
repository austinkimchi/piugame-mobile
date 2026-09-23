package com.austinkimchi.mypiu.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.austinkimchi.mypiu.AppContainer
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.performance.PerformanceDataSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class PerformanceViewModel(private val repository: PerformanceDataSource) : ViewModel() {
    private val mutableState = MutableStateFlow(PerformanceUiState())
    val state: StateFlow<PerformanceUiState> = mutableState.asStateFlow()

    private var sessionGeneration = 0L
    private var loadJob: Job? = null
    private var started = false

    fun updateSession(accountId: String?, connected: Boolean) {
        val scope = accountId?.takeIf { connected }?.let { "account:$it" }
        val isConnected = scope != null
        val current = mutableState.value
        if (current.accountScope == scope && current.isConnected == isConnected) return

        sessionGeneration += 1
        loadJob?.cancel()
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
        if (!mutableState.value.isConnected) return
        reload()
    }

    fun onAppResumed() {
        if (started) refresh()
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
                mutableState.update {
                    it.copy(
                        dashboard = if (sessionInvalidated) null else it.dashboard,
                        isConnected = if (sessionInvalidated) false else it.isConnected,
                        isLoading = false,
                        error = error.message ?: "Performance could not be loaded.",
                        sessionInvalidated = sessionInvalidated,
                    )
                }
            }
        }
    }

    class Factory(private val container: AppContainer) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            PerformanceViewModel(container.performanceRepository) as T
    }
}

data class PerformanceUiState(
    val accountScope: String? = null,
    val isConnected: Boolean = false,
    val dashboard: MyPiuPerformanceDashboard? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
    val sessionInvalidated: Boolean = false,
)
