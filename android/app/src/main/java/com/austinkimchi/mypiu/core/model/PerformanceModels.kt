package com.austinkimchi.mypiu.core.model

import kotlinx.serialization.Serializable

@Serializable
data class MyPiuPerformanceDashboard(
    val profile: Profile? = null,
    val totals: Totals,
    val recentPlays: List<Play> = emptyList(),
    val topCharts: List<Chart> = emptyList(),
    val canSync: Boolean,
    val mongoReady: Boolean,
) {
    @Serializable
    data class Profile(
        val displayName: String,
        val pumbilityScore: Double? = null,
        val rating: Double? = null,
        val playCount: Int? = null,
        val clearCount: Int? = null,
        val totalCharts: Int? = null,
        val progressPercent: Double? = null,
        val nextTitle: NextTitle? = null,
        val recentArcade: String? = null,
        val lastSyncedAt: String? = null,
    )

    @Serializable
    data class NextTitle(
        val name: String,
        val metric: String,
        val current: Double,
        val target: Double,
    ) {
        val progressFraction: Float
            get() = if (target > 0) (current / target).coerceIn(0.0, 1.0).toFloat() else 0f

        val remaining: Double
            get() = (target - current).coerceAtLeast(0.0)
    }

    @Serializable
    data class Totals(
        val trackedPlays: Int,
        val trackedCharts: Int,
        val trackedPumbilityCharts: Int,
        val upscores: Int,
        val upscoresThisWeek: Int,
        val upscoresThisMonth: Int,
        val upscoresToday: Int,
        val averageBestScore: Int? = null,
        val pumbilityChange24Hours: Double? = null,
        val averageBestScoreChange24Hours: Double? = null,
        val recentlyPlayed: Int,
    )

    @Serializable
    data class Play(
        val id: String,
        val songName: String,
        val chartToken: String,
        val score: Int? = null,
        val grade: String? = null,
        val plate: String? = null,
        val mode: String? = null,
        val level: String? = null,
        val playedAt: String? = null,
        val stageBreak: Boolean = false,
        val arcadeName: String? = null,
        val judgments: JudgmentCounts? = null,
        val songImageUrl: String? = null,
    ) {
        val displayChartToken: String
            get() = if (mode != null && level != null) "${mode.uppercase()}$level" else chartToken
    }

    @Serializable
    data class Chart(
        val songName: String,
        val chartToken: String,
        val bestScore: Int? = null,
        val previousBestScore: Int? = null,
        val delta: Int? = null,
        val bestGrade: String? = null,
        val bestPlate: String? = null,
        val mode: String? = null,
        val level: String? = null,
        val topPlayRank: Int? = null,
        val topPumbilityScore: Double? = null,
    ) {
        val id: String get() = "$songName:$chartToken"
        val displayChartToken: String
            get() = if (mode != null && level != null) "${mode.uppercase()}$level" else chartToken
    }
}

@Serializable
data class PerformanceResponse(val performance: MyPiuPerformanceDashboard)

@Serializable
data class MyPiuPerformanceSession(
    val id: String = "",
    val arcadeName: String? = null,
    val summary: Summary,
    val plays: List<MyPiuPerformanceDashboard.Play> = emptyList(),
) {
    @Serializable
    data class Summary(
        val playCount: Int,
        val clearCount: Int,
        val failedCount: Int,
        val stageBreakCount: Int,
        val averageScore: Int? = null,
        val bestScore: Int? = null,
        val distinctCharts: Int,
        val startedAt: String,
        val endedAt: String,
        val durationMinutes: Int,
    ) {
        val clearRate: Double?
            get() = if (playCount > 0) {
                (clearCount.toDouble() / playCount * 100.0).coerceIn(0.0, 100.0)
            } else {
                null
            }
    }
}

@Serializable
data class PerformanceSessionResponse(val session: MyPiuPerformanceSession? = null)

@Serializable
data class PerformanceSessionsResponse(
    val sessions: List<MyPiuPerformanceSession> = emptyList(),
    val nextOffset: Int? = null,
)

data class PerformanceProgressSummary(
    val clearedCharts: Int?,
    val totalCharts: Int?,
    val playCount: Int?,
    val completionPercent: Double?,
) {
    val remainingCharts: Int?
        get() = if (clearedCharts != null && totalCharts != null) {
            (totalCharts - clearedCharts).coerceAtLeast(0)
        } else {
            null
        }

    val completionFraction: Float?
        get() = completionPercent?.div(100.0)?.toFloat()

    companion object {
        fun from(
            clearCount: Int?,
            totalCharts: Int?,
            progressPercent: Double?,
            playCount: Int?,
        ): PerformanceProgressSummary {
            val normalizedClears = clearCount?.coerceAtLeast(0)
            val normalizedTotal = totalCharts?.coerceAtLeast(0)
            val normalizedPercent = when {
                progressPercent?.isFinite() == true -> progressPercent.coerceIn(0.0, 100.0)
                normalizedClears != null && normalizedTotal != null && normalizedTotal > 0 -> {
                    (normalizedClears.toDouble() / normalizedTotal * 100.0).coerceIn(0.0, 100.0)
                }
                else -> null
            }
            return PerformanceProgressSummary(
                clearedCharts = normalizedClears,
                totalCharts = normalizedTotal,
                playCount = playCount?.coerceAtLeast(0),
                completionPercent = normalizedPercent,
            )
        }

        fun from(profile: MyPiuPerformanceDashboard.Profile): PerformanceProgressSummary = from(
            clearCount = profile.clearCount,
            totalCharts = profile.totalCharts,
            progressPercent = profile.progressPercent,
            playCount = profile.playCount,
        )

        fun from(profile: PiuProfile): PerformanceProgressSummary = from(
            clearCount = profile.clearCount,
            totalCharts = profile.totalCharts,
            progressPercent = profile.progressPercent?.toDouble(),
            playCount = profile.playCount,
        )
    }
}
