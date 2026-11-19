package com.austinkimchi.mypiu

import android.content.Context
import com.austinkimchi.mypiu.core.catalog.CatalogCache
import com.austinkimchi.mypiu.core.catalog.CatalogRepository
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.OAuthCoordinator
import com.austinkimchi.mypiu.core.performance.PerformanceRepository
import com.austinkimchi.mypiu.core.performance.PerformanceRefreshSignal
import com.austinkimchi.mypiu.core.security.AndroidKeystoreSecretStore
import com.austinkimchi.mypiu.core.security.InstallationIdentity
import com.austinkimchi.mypiu.core.security.SessionStore
import com.austinkimchi.mypiu.core.sync.SyncRepository
import com.austinkimchi.mypiu.core.sync.SyncScheduler
import java.io.File

class AppContainer(context: Context) {
    private val sessionStore = SessionStore(AndroidKeystoreSecretStore(context))
    private val installationId = InstallationIdentity(context).current()
    private val apiClient = MyPiuApiClient(BuildConfig.MYPIU_BASE_URL)
    val performanceRefreshSignal = PerformanceRefreshSignal()
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
        performanceRefreshSignal = performanceRefreshSignal,
    )
    val catalogRepository = CatalogRepository(
        sessionStore = sessionStore,
        apiClient = apiClient,
        cache = CatalogCache(File(context.cacheDir, "catalog")),
        publicCatalog = com.austinkimchi.mypiu.core.catalog.PublicCatalogStore(
            File(context.cacheDir, "public-catalog-v1"), apiClient::publicCatalog),
    )
    val performanceRepository = PerformanceRepository(sessionStore, apiClient,
        com.austinkimchi.mypiu.core.performance.PerformanceSessionsCache(File(context.cacheDir, "private-sessions-v1")),
        BuildConfig.MYPIU_BASE_URL)
    val scheduler = SyncScheduler(context)
}
