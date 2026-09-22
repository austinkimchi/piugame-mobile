package com.austinkimchi.mypiu.core.model

import java.time.format.DateTimeFormatter
import kotlinx.serialization.Serializable

@Serializable
data class MobilePerformanceImportPayload(
    val schemaVersion: Int,
    val idempotencyKey: String,
    val installationId: String,
    val source: String,
    val appVersion: String?,
    val piuVersion: PiuGameVersion,
    val generatedAt: String,
    val profile: Profile,
    val recentPlays: List<Play>,
) {
    @Serializable
    data class Profile(
        val username: String,
        val displayName: String,
        val titleName: String?,
        val gameId: String?,
        val pumpTag: String?,
        val avatarUrl: String?,
        val pumbilityScore: Double?,
        val pp: Double?,
        val rating: Int?,
        val playCount: Int?,
        val clearCount: Int?,
        val totalCharts: Int?,
        val progressPercent: Int?,
        val plateCounts: Map<String, Int>,
        val recentArcade: String?,
        val lastAccess: String?,
    )

    @Serializable
    data class Play(
        val songName: String,
        val mode: String,
        val level: String,
        val score: Int?,
        val grade: String?,
        val plate: String?,
        val stageBreak: Boolean,
        val judgments: JudgmentCounts,
        val playedAt: String,
    )

    companion object {
        fun from(snapshot: PiuSnapshot, installationId: String, appVersion: String?): MobilePerformanceImportPayload {
            val generatedAt = DateTimeFormatter.ISO_INSTANT.format(snapshot.fetchedAt)
            return MobilePerformanceImportPayload(
                schemaVersion = 1,
                idempotencyKey = "android:$installationId:$generatedAt",
                installationId = installationId,
                source = "android",
                appVersion = appVersion,
                piuVersion = snapshot.version,
                generatedAt = generatedAt,
                profile = Profile(
                    username = snapshot.profile.username,
                    displayName = snapshot.profile.displayName,
                    titleName = snapshot.profile.titleName,
                    gameId = null,
                    pumpTag = snapshot.profile.gameIdTag,
                    avatarUrl = snapshot.profile.avatarUrl,
                    pumbilityScore = snapshot.profile.pumbilityScore,
                    pp = snapshot.profile.pp,
                    rating = snapshot.profile.rating,
                    playCount = snapshot.profile.playCount,
                    clearCount = snapshot.profile.clearCount,
                    totalCharts = snapshot.profile.totalCharts,
                    progressPercent = snapshot.profile.progressPercent,
                    plateCounts = snapshot.profile.plateCounts,
                    recentArcade = snapshot.profile.recentArcade,
                    lastAccess = snapshot.profile.lastAccess,
                ),
                recentPlays = snapshot.recentPlays.mapNotNull { play ->
                    val mode = play.mode?.uppercase() ?: return@mapNotNull null
                    val level = play.level ?: return@mapNotNull null
                    val playedAt = play.playedAt ?: return@mapNotNull null
                    Play(
                        songName = play.songName,
                        mode = mode,
                        level = level,
                        score = play.score,
                        grade = play.grade,
                        plate = play.plate,
                        stageBreak = play.stageBreak,
                        judgments = play.judgments,
                        playedAt = playedAt,
                    )
                },
            )
        }
    }
}
