package com.austinkimchi.mypiu.core.model

import java.time.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class MobilePerformanceImportPayloadTest {
    @Test
    fun payloadContainsNormalizedAndroidDataOnly() {
        val snapshot = PiuSnapshot(
            version = PiuGameVersion.PHOENIX_2,
            profile = PiuProfile(
                username = "fixture_user",
                titleName = "CONRAD FOLLOWER",
                gameIdTag = "PLAYER#1234",
                avatarUrl = "https://www.piugame.com/avatar.png",
                pp = 1_034.0,
                pumbilityScore = 15_770.43,
                playCount = 1_200,
                rating = 18_318,
                clearCount = 640,
                totalCharts = 3_900,
                progressPercent = 16,
                recentArcade = "ROUND1",
                lastAccess = "2026-09-22 10:55:00",
                plateCounts = mapOf("rg" to 12),
            ),
            recentPlays = listOf(
                RecentPlay(
                    songName = "BATTLE NO.1",
                    songImageUrl = null,
                    mode = "S",
                    level = "19",
                    score = 954_848,
                    grade = "s",
                    plate = "rg",
                    stageBreak = false,
                    judgments = JudgmentCounts(1_234, 20, 4, 0, 1),
                    playedAt = "2026-09-22 10:55:00 (GMT+9)",
                ),
            ),
            fetchedAt = Instant.parse("2026-09-22T17:00:00Z"),
        )
        val json = Json { explicitNulls = false }
        val encoded = json.encodeToString(
            MobilePerformanceImportPayload.from(snapshot, "fixture-install", "0.1.0"),
        )
        val root = json.parseToJsonElement(encoded).jsonObject

        assertEquals("android", root.getValue("source").jsonPrimitive.content)
        assertEquals("phoenix2", root.getValue("piuVersion").jsonPrimitive.content)
        assertEquals("fixture_user", root.getValue("profile").jsonObject.getValue("username").jsonPrimitive.content)
        assertFalse(encoded.contains("password", ignoreCase = true))
        assertFalse(encoded.contains("rawHtml", ignoreCase = true))
    }
}
