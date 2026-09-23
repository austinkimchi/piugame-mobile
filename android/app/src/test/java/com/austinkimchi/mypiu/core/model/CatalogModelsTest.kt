package com.austinkimchi.mypiu.core.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CatalogModelsTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun searchPageDecodesAndGroupsCharts() {
        val page = json.decodeFromString<CatalogSearchPage>(FIXTURE)
        val song = page.songs.single()

        assertEquals(654, page.total)
        assertEquals("BATTLE NO.1", song.title)
        assertEquals(listOf("S10", "S19"), song.charts(CatalogChartMode.SINGLE))
        assertEquals(listOf("D20"), song.charts(CatalogChartMode.DOUBLE))
        assertEquals(listOf("C2"), song.charts(CatalogChartMode.COOP))
        assertEquals("ORIGINAL #49", song.folderLabel)
        assertTrue(song.isPremium)
        assertTrue(song.isFavorite)
    }

    @Test
    fun paginationDeduplicatesSongsAndStopsRepeatedCursor() {
        val page = json.decodeFromString<CatalogSearchPage>(FIXTURE)
        val listing = CatalogListing(page.songs, page.nextCursor, page.total).append(page, "Mg")

        assertEquals(listOf("battle-no-1"), listing.songs.map(CatalogSong::slug))
        assertFalse(listing.nextCursor != null)
    }

    private companion object {
        val FIXTURE = """
            {
              "songs": [{
                "slug": "battle-no-1",
                "title": "BATTLE NO.1",
                "artist": "TANO*C Sound Team",
                "supportedVersions": ["phoenix2", "phoenix"],
                "imageUrl": "/assets/piu/song.png",
                "bpm": "200",
                "chartSummary": ["S10", "S19", "D20", "C2"],
                "folder": "ORIGINAL",
                "folderPosition": 49,
                "series": "XX",
                "tags": ["intense"],
                "isPremium": true,
                "isFavorite": true,
                "recommendedChartToken": "S19"
              }],
              "nextCursor": "Mg",
              "total": 654,
              "filterOptions": {"folders": [], "series": [], "levels": [], "charts": []}
            }
        """.trimIndent()
    }
}
