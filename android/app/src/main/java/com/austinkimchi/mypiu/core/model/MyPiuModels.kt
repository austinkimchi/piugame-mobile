package com.austinkimchi.mypiu.core.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

enum class MyPiuAuthProvider(val wireValue: String, val displayName: String) {
    GOOGLE("google", "Google"),
    DISCORD("discord", "Discord"),
}

@Serializable
data class MyPiuAccessToken(
    val value: String,
    val expiresAtEpochMillis: Long,
    val installationId: String,
) {
    fun isExpired(nowEpochMillis: Long = System.currentTimeMillis()): Boolean =
        expiresAtEpochMillis <= nowEpochMillis
}

@Serializable
data class MyPiuAccount(
    val id: String,
    val name: String,
    val email: String,
    val username: String?,
    val imageUrl: String?,
    val piuGameVersion: PiuGameVersion,
    val piuProfile: LinkedPiuProfile?,
) {
    @Serializable
    data class LinkedPiuProfile(
        val piuUsername: String,
        val displayName: String,
        val avatarUrl: String?,
    )
}

@Serializable
data class MyPiuSyncResult(
    val accepted: Boolean,
    val importedRecentPlays: Int,
    val duplicateRecentPlays: Int,
    val syncCursor: String,
    val duplicateRequest: Boolean,
)

@Serializable
data class TokenResponse(
    @SerialName("access_token") val accessToken: String,
    @SerialName("token_type") val tokenType: String,
    @SerialName("expires_in") val expiresIn: Long,
)

@Serializable
data class AccountResponse(val account: MyPiuAccount)

@Serializable
data class ApiErrorResponse(val error: String = "request_failed")
