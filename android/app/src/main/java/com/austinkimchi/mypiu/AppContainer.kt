package com.austinkimchi.mypiu

import android.content.Context
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.OAuthCoordinator
import com.austinkimchi.mypiu.core.security.AndroidKeystoreSecretStore
import com.austinkimchi.mypiu.core.security.InstallationIdentity
import com.austinkimchi.mypiu.core.security.SessionStore
import com.austinkimchi.mypiu.core.sync.SyncRepository
import com.austinkimchi.mypiu.core.sync.SyncScheduler

class AppContainer(context: Context) {
    private val sessionStore = SessionStore(AndroidKeystoreSecretStore(context))
    private val installationId = InstallationIdentity(context).current()
    private val apiClient = MyPiuApiClient(BuildConfig.MYPIU_BASE_URL)
    private val oauthCoordinator = OAuthCoordinator(
        apiClient = apiClient,
        sessionStore = sessionStore,
        installationId = installationId,
        appVersion = BuildConfig.VERSION_NAME,
    )

    val repository = SyncRepository(
        sessionStore = sessionStore,
        apiClient = apiClient,
        oauthCoordinator = oauthCoordinator,
        installationId = installationId,
        appVersion = BuildConfig.VERSION_NAME,
    )
    val scheduler = SyncScheduler(context)
}
