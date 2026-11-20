package com.austinkimchi.mypiu.core.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class PerformanceModelsTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun sessionResultVersionIsDerivedFromPageAndNeverChangesSerializedContract() {
        val session = json.decodeFromString<PerformanceSessionResponse>(SESSION_FIXTURE).session!!
        val page = PerformanceSessionsResponse(listOf(session), selectedVersion = "phoenix")
        val decorated = page.copy(sessions = page.sessionsWithResultVersion())
        assertEquals(PiuGameVersion.PHOENIX, decorated.sessions.single().resultVersion)
        assertNull(page.sessions.single().resultVersion)
        val encoder = Json { encodeDefaults = true }
        val encoded = encoder.encodeToString(decorated)
        assertFalse(encoded.contains("resultVersion"))
        assertEquals(encoder.encodeToString(page), encoded)
        val cached = encoder.decodeFromString<PerformanceSessionsResponse>(encoded)
        assertNull(cached.sessions.single().resultVersion)
        assertEquals(PiuGameVersion.PHOENIX, cached.sessionsWithResultVersion().single().resultVersion)
        assertNull(decorated.copy(selectedVersion = "future-version").sessionsWithResultVersion().single().resultVersion)
        assertNull(decorated.copy(selectedVersion = null).sessionsWithResultVersion().single().resultVersion)
    }

    @Test
    fun dashboardDecodesPerformanceContract() {
        val response = json.decodeFromString<PerformanceResponse>(FIXTURE)
        val dashboard = response.performance

        assertEquals("PLAYER#1234", dashboard.profile?.displayName)
        assertEquals(15_770.43, dashboard.profile?.pumbilityScore ?: 0.0, 0.001)
        assertEquals("[S] ADVANCED LV.5", dashboard.profile?.nextTitle?.name)
        assertEquals(171.06, dashboard.profile?.nextTitle?.remaining ?: 0.0, 0.001)
        assertEquals(0.31576f, dashboard.profile?.nextTitle?.progressFraction ?: 0f, 0.00001f)
        assertEquals(954_848, dashboard.totals.averageBestScore)
        assertEquals("S19", dashboard.recentPlays.single().displayChartToken)
        assertEquals("Big Daddy:big-daddy:s:19", dashboard.topCharts.single().id)
        assertEquals(550.0, dashboard.topCharts.single().topPumbilityScore ?: 0.0, 0.001)
    }

    @Test
    fun sessionDecodesSummaryAndSharedPlayContract() {
        val response = json.decodeFromString<PerformanceSessionResponse>(SESSION_FIXTURE)
        val session = response.session ?: error("Expected session")

        assertEquals(4, session.summary.playCount)
        assertEquals(75.0, session.summary.clearRate ?: 0.0, 0.001)
        assertEquals("S19", session.plays.single().displayChartToken)
        assertEquals(
            "https://mypiu.austin.kim/assets/piu/phoenix2/song_img2/big-daddy.png",
            session.plays.single().songImageUrl,
        )
        assertEquals(73, session.summary.durationMinutes)
    }

    @Test
    fun sessionClearRateHandlesEmptyAndClampsInvalidCounts() {
        val empty = sessionSummary(playCount = 0, clearCount = 0)
        val overReported = sessionSummary(playCount = 2, clearCount = 3)
        val negative = sessionSummary(playCount = 2, clearCount = -1)

        assertNull(empty.clearRate)
        assertEquals(100.0, overReported.clearRate ?: 0.0, 0.001)
        assertEquals(0.0, negative.clearRate ?: -1.0, 0.001)
    }

    @Test
    fun progressSummaryUsesReportedPercentageAndSafeCounts() {
        val summary = PerformanceProgressSummary.from(
            clearCount = 640,
            totalCharts = 3_900,
            progressPercent = 16.0,
            playCount = 1_200,
        )

        assertEquals(640, summary.clearedCharts)
        assertEquals(3_260, summary.remainingCharts)
        assertEquals(1_200, summary.playCount)
        assertEquals(16.0, summary.completionPercent ?: 0.0, 0.001)
        assertEquals(0.16f, summary.completionFraction ?: 0f, 0.001f)
    }

    @Test
    fun progressSummaryDerivesClampsAndRejectsNonFinitePercentages() {
        val derived = PerformanceProgressSummary.from(1, 4, null, null)
        val clamped = PerformanceProgressSummary.from(12, 10, 125.0, -4)
        val unknown = PerformanceProgressSummary.from(null, null, Double.NaN, null)

        assertEquals(25.0, derived.completionPercent ?: 0.0, 0.001)
        assertEquals(100.0, clamped.completionPercent ?: 0.0, 0.001)
        assertEquals(0, clamped.remainingCharts)
        assertEquals(0, clamped.playCount)
        assertNull(unknown.completionPercent)
    }

    companion object {
        val FIXTURE = """
            {
              "performance": {
                "profile": {
                  "displayName": "PLAYER#1234",
                  "pumbilityScore": 15770.43,
                  "rating": 18318,
                  "playCount": 1200,
                  "clearCount": 640,
                  "totalCharts": 3900,
                  "progressPercent": 16,
                  "nextTitle": {
                    "name": "[S] ADVANCED LV.5",
                    "metric": "single_pumbility",
                    "current": 15828.94,
                    "previousTarget": 15750,
                    "target": 16000
                  },
                  "recentArcade": "ROUND1",
                  "lastSyncedAt": "2026-09-22T07:30:00.000Z"
                },
                "totals": {
                  "trackedPlays": 42,
                  "trackedCharts": 120,
                  "trackedPumbilityCharts": 20,
                  "upscores": 30,
                  "upscoresThisWeek": 7,
                  "upscoresThisMonth": 18,
                  "upscoresToday": 2,
                  "averageBestScore": 954848,
                  "pumbilityChange24Hours": 14.5,
                  "averageBestScoreChange24Hours": 320,
                  "recentlyPlayed": 9
                },
                "recentPlays": [{
                  "id": "play-1",
                  "songName": "BATTLE NO.1",
                  "chartToken": "battle-no-1:s:19",
                  "score": 954848,
                  "grade": "s",
                  "plate": "rg",
                  "mode": "S",
                  "level": "19",
                  "playedAt": "2026-09-22T07:20:00.000Z",
                  "stageBreak": false
                }],
                "topCharts": [{
                  "songName": "Big Daddy",
                  "chartToken": "big-daddy:s:19",
                  "bestScore": 928767,
                  "previousBestScore": 920000,
                  "delta": 8767,
                  "bestGrade": "aa",
                  "bestPlate": "fg",
                  "mode": "S",
                  "level": "19",
                  "topPlayRank": 3,
                  "topPumbilityScore": 550
                }],
                "canSync": true,
                "mongoReady": true
              }
            }
        """.trimIndent()

        val SESSION_FIXTURE = """
            {
              "session": {
                "summary": {
                  "playCount": 4,
                  "clearCount": 3,
                  "failedCount": 1,
                  "stageBreakCount": 1,
                  "averageScore": 932100,
                  "bestScore": 978500,
                  "distinctCharts": 3,
                  "startedAt": "2026-09-22T06:07:00.000Z",
                  "endedAt": "2026-09-22T07:20:00.000Z",
                  "durationMinutes": 73
                },
                "plays": [{
                  "id": "session-play-1",
                  "songName": "Big Daddy",
                  "chartToken": "big-daddy:s:19",
                  "score": 928767,
                  "grade": "aa",
                  "mode": "S",
                  "level": "19",
                  "songImageUrl": "https://mypiu.austin.kim/assets/piu/phoenix2/song_img2/big-daddy.png",
                  "playedAt": "2026-09-22T07:20:00.000Z",
                  "stageBreak": false
                }]
              }
            }
        """.trimIndent()
    }
}

private fun sessionSummary(playCount: Int, clearCount: Int) = MyPiuPerformanceSession.Summary(
    playCount = playCount,
    clearCount = clearCount,
    failedCount = 0,
    stageBreakCount = 0,
    distinctCharts = 0,
    startedAt = "2026-09-22T06:00:00Z",
    endedAt = "2026-09-22T06:00:00Z",
    durationMinutes = 0,
)
