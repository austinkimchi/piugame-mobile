package com.austinkimchi.mypiu.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.austinkimchi.mypiu.AppContainer
import com.austinkimchi.mypiu.core.model.MyPiuAccount
import com.austinkimchi.mypiu.core.model.MyPiuAuthProvider
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.PiuProfile
import com.austinkimchi.mypiu.core.model.RecentPlay
import com.austinkimchi.mypiu.core.sync.RepositorySnapshot
import com.austinkimchi.mypiu.core.sync.SyncRepository
import com.austinkimchi.mypiu.core.sync.SyncScheduler
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class AppViewModel(
    private val repository: SyncRepository,
    private val scheduler: SyncScheduler,
    restoreOnInit: Boolean,
) : ViewModel() {
    private val mutableState = MutableStateFlow(AppUiState(isBusy = restoreOnInit))
    val state: StateFlow<AppUiState> = mutableState.asStateFlow()

    init {
        if (restoreOnInit) {
            viewModelScope.launch { runOperation { repository.restoreAndSync() } }
        }
    }

    fun authorizationUrl(provider: MyPiuAuthProvider): String? = runCatching {
        repository.beginAuthorization(provider)
    }.onFailure(::showError).getOrNull()

    fun handleOAuthCallback(callbackUrl: String) {
        viewModelScope.launch {
            val callbackError = runOperation { repository.completeAuthorization(callbackUrl) }
            if (callbackError != null) {
                runOperation { repository.restoreAndSync() }
                showError(callbackError)
            }
        }
    }

    fun connectPiu(username: String, password: String, version: PiuGameVersion) {
        viewModelScope.launch { runOperation { repository.connectPiu(username, password, version) } }
    }

    fun refresh(onSuccess: (() -> Unit)? = null) {
        viewModelScope.launch {
            if (runOperation { repository.sync() } == null) onSuccess?.invoke()
        }
    }

    fun reconcileConnectionState() {
        val connection = repository.connectionState()
        mutableState.update { current ->
            current.copy(
                isPiuConnected = connection.isPiuConnected,
                isMyPiuConnected = connection.isMyPiuConnected,
                account = current.account.takeIf { connection.isMyPiuConnected },
                accountId = if (connection.isMyPiuConnected) {
                    connection.accountId ?: current.accountId ?: current.account?.id
                } else {
                    null
                },
                accountPiuGameVersion = if (connection.isMyPiuConnected) {
                    connection.accountVersion ?: current.accountPiuGameVersion ?: current.account?.piuGameVersion
                } else {
                    null
                },
                profile = current.profile.takeIf { connection.isPiuConnected },
                recentPlays = current.recentPlays.takeIf { connection.isPiuConnected }.orEmpty(),
                piuVersion = current.piuVersion.takeIf { connection.isPiuConnected },
            )
        }
        if (connection.isPiuConnected && connection.isMyPiuConnected) scheduler.schedule() else scheduler.cancel()
    }

    fun disconnectPiu() {
        viewModelScope.launch {
            try {
                repository.disconnectPiu()
                mutableState.update {
                    it.copy(
                        isPiuConnected = false,
                        profile = null,
                        recentPlays = emptyList(),
                        piuVersion = null,
                        message = "PIUGAME disconnected.",
                    )
                }
                scheduler.cancel()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                showError(error)
            }
        }
    }

    fun disconnectMyPiu() {
        viewModelScope.launch {
            try {
                repository.disconnectMyPiu()
                mutableState.update {
                    it.copy(
                        isMyPiuConnected = false,
                        account = null,
                        accountId = null,
                        accountPiuGameVersion = null,
                        message = "MyPIU signed out.",
                    )
                }
                scheduler.cancel()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                showError(error)
            }
        }
    }

    private suspend fun runOperation(operation: suspend () -> RepositorySnapshot): Throwable? {
        mutableState.update { it.copy(isBusy = true, message = null) }
        return try {
            apply(operation())
            null
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            repository.clearUnauthorizedSession(error)
            val connection = repository.connectionState()
            mutableState.update { current ->
                current.copy(
                    isPiuConnected = connection.isPiuConnected,
                    isMyPiuConnected = connection.isMyPiuConnected,
                    account = current.account.takeIf { connection.isMyPiuConnected },
                    accountId = if (connection.isMyPiuConnected) {
                        connection.accountId ?: current.accountId ?: current.account?.id
                    } else {
                        null
                    },
                    accountPiuGameVersion = if (connection.isMyPiuConnected) {
                        connection.accountVersion ?: current.accountPiuGameVersion ?: current.account?.piuGameVersion
                    } else {
                        null
                    },
                    profile = current.profile.takeIf { connection.isPiuConnected },
                    recentPlays = current.recentPlays.takeIf { connection.isPiuConnected }.orEmpty(),
                    piuVersion = current.piuVersion.takeIf { connection.isPiuConnected },
                )
            }
            if (connection.isPiuConnected && connection.isMyPiuConnected) scheduler.schedule() else scheduler.cancel()
            showError(error)
            error
        } finally {
            mutableState.update { it.copy(isBusy = false) }
        }
    }

    private fun apply(snapshot: RepositorySnapshot) {
        mutableState.update { current ->
            current.copy(
                isPiuConnected = snapshot.isPiuConnected,
                isMyPiuConnected = snapshot.isMyPiuConnected,
                account = if (snapshot.isMyPiuConnected) snapshot.account ?: current.account else null,
                accountId = if (snapshot.isMyPiuConnected) {
                    snapshot.account?.id ?: current.accountId ?: current.account?.id
                } else {
                    null
                },
                accountPiuGameVersion = if (snapshot.isMyPiuConnected) {
                    snapshot.account?.piuGameVersion ?: current.accountPiuGameVersion ?: current.account?.piuGameVersion
                } else {
                    null
                },
                profile = if (snapshot.isPiuConnected) snapshot.piuSnapshot?.profile ?: current.profile else null,
                recentPlays = if (snapshot.isPiuConnected) {
                    snapshot.piuSnapshot?.recentPlays ?: current.recentPlays
                } else {
                    emptyList()
                },
                piuVersion = if (snapshot.isPiuConnected) snapshot.piuSnapshot?.version ?: current.piuVersion else null,
                message = snapshot.syncResult?.let { result ->
                    "Synced ${result.importedRecentPlays} new plays; ${result.duplicateRecentPlays} already current."
                },
            )
        }
        if (snapshot.isPiuConnected && snapshot.isMyPiuConnected) scheduler.schedule() else scheduler.cancel()
    }

    private fun showError(error: Throwable) {
        mutableState.update { it.copy(isBusy = false, message = error.message ?: "MyPIU could not complete the request.") }
    }

    class Factory(
        private val container: AppContainer,
        private val restoreOnInit: Boolean,
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            AppViewModel(container.repository, container.scheduler, restoreOnInit) as T
    }
}

data class AppUiState(
    val isBusy: Boolean = false,
    val isPiuConnected: Boolean = false,
    val isMyPiuConnected: Boolean = false,
    val account: MyPiuAccount? = null,
    val accountId: String? = null,
    val accountPiuGameVersion: PiuGameVersion? = null,
    val profile: PiuProfile? = null,
    val recentPlays: List<RecentPlay> = emptyList(),
    val piuVersion: PiuGameVersion? = null,
    val message: String? = null,
)
