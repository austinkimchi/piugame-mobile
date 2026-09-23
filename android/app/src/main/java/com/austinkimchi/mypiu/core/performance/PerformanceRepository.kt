package com.austinkimchi.mypiu.core.performance

import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceSession
import com.austinkimchi.mypiu.core.network.MyPiuApiClient
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import com.austinkimchi.mypiu.core.security.SessionStore

interface PerformanceDataSource {
    suspend fun dashboard(): MyPiuPerformanceDashboard
    suspend fun session(): MyPiuPerformanceSession?
    suspend fun sessions(): List<MyPiuPerformanceSession> = session()?.let(::listOf) ?: emptyList()
}

class PerformanceRepository(
    private val sessionStore: SessionStore,
    private val apiClient: MyPiuApiClient,
) : PerformanceDataSource {
    override suspend fun dashboard(): MyPiuPerformanceDashboard = withSession(apiClient::performance)

    override suspend fun session(): MyPiuPerformanceSession? = withSession(apiClient::performanceSession)

    override suspend fun sessions(): List<MyPiuPerformanceSession> = withSession(apiClient::performanceSessions)

    private suspend fun <Value> withSession(operation: suspend (String) -> Value): Value {
        val storedToken = sessionStore.accessToken()
        val token = when {
            storedToken == null -> throw MyPiuApiException(401, "invalid_token")
            storedToken.isExpired() -> {
                sessionStore.clearAccessToken()
                throw MyPiuApiException(401, "invalid_token")
            }
            else -> storedToken.value
        }
        return try {
            operation(token)
        } catch (error: MyPiuApiException) {
            if (
                (error.isUnauthorized || error.isAccountNotFound) &&
                sessionStore.accessToken()?.value == token
            ) {
                sessionStore.clearAccessToken()
            }
            throw error
        }
    }
}
