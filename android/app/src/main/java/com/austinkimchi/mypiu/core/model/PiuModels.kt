package com.austinkimchi.mypiu.core.model

import java.time.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class PiuGameVersion(val displayName: String, val baseUrl: String, val serialName: String) {
    @SerialName("phoenix")
    PHOENIX("PHOENIX", "https://phoenix.piugame.com", "phoenix"),

    @SerialName("phoenix2")
    PHOENIX_2("PHOENIX 2", "https://www.piugame.com", "phoenix2"),
}

data class PiuProfile(
    val username: String,
    val titleName: String?,
    val gameIdTag: String?,
    val avatarUrl: String?,
    val pp: Double?,
    val pumbilityScore: Double?,
    val playCount: Int?,
    val rating: Int?,
    val clearCount: Int?,
    val totalCharts: Int?,
    val progressPercent: Int?,
    val recentArcade: String?,
    val lastAccess: String?,
    val plateCounts: Map<String, Int>,
) {
    val displayName: String get() = gameIdTag ?: username
}

@Serializable
data class JudgmentCounts(
    val perfect: Int?,
    val great: Int?,
    val good: Int?,
    val bad: Int?,
    val miss: Int?,
)

data class RecentPlay(
    val songName: String,
    val songImageUrl: String?,
    val mode: String?,
    val level: String?,
    val score: Int?,
    val grade: String?,
    val plate: String?,
    val stageBreak: Boolean,
    val judgments: JudgmentCounts,
    val playedAt: String?,
) {
    val id: String
        get() = listOf(songName, mode.orEmpty(), level.orEmpty(), playedAt.orEmpty(), score ?: -1)
            .joinToString(":")

    val chartToken: String get() = if (mode != null && level != null) "${mode.uppercase()}$level" else "-"
}

data class PiuSnapshot(
    val version: PiuGameVersion,
    val profile: PiuProfile,
    val recentPlays: List<RecentPlay>,
    val fetchedAt: Instant,
)

@Serializable
data class PiuCredentials(
    val username: String,
    val password: String,
    val version: PiuGameVersion,
)
