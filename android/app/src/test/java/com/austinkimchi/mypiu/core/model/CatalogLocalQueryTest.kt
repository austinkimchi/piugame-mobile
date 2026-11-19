package com.austinkimchi.mypiu.core.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class CatalogLocalQueryTest {
    private val json = Json { ignoreUnknownKeys = true }
    @Serializable private data class Fixture(val snapshot: PublicCatalogSnapshot, val cases: List<Case>)
    @Serializable private data class Case(val name: String, val query: String,
        val folders: List<String> = emptyList(), val series: List<String> = emptyList(),
        val levels: List<String> = emptyList(), val charts: List<String> = emptyList(),
        val levelMode: String, val sortBy: String, val sortDirection: String,
        val expectedSlugs: List<String>, val expectedOptions: PublicCatalogFilterOptions)
    private fun text(name: String) = checkNotNull(javaClass.classLoader?.getResourceAsStream("$name.json")).bufferedReader().use { it.readText() }
    private fun fixture() = json.decodeFromString<Fixture>(text("catalog-local-query"))

    @Test fun sharedWebParityForLiteralTextLevelsIntersectionsAndEverySort() {
        val fixture = fixture()
        assertEquals(36, fixture.cases.size)
        fixture.cases.forEach { case ->
            val result = CatalogLocalQuery.query(fixture.snapshot, null, case.query, CatalogLocalQuery.Filters(
                case.folders, case.series, case.levels, case.charts, case.levelMode,
                CatalogSortOption.entries.first { it.wireValue == case.sortBy },
                CatalogSortDirection.entries.first { it.wireValue == case.sortDirection }))
            assertEquals(case.name, case.expectedSlugs, result.page.songs.map { it.slug })
            assertEquals(case.name, case.expectedOptions, result.filterOptions)
            assertEquals(result.page.songs.size, result.page.total)
            assertNull(result.page.nextCursor)
        }
    }

    @Test fun allSixteenOrderedModesPreserveFavoritesAndPublicIdentity() {
        val snapshot = fixture().snapshot
        val selections = listOf(emptyList(), listOf("singles"), listOf("doubles"), listOf("co-op"),
            listOf("singles", "doubles"), listOf("doubles", "singles"), listOf("singles", "co-op"), listOf("co-op", "singles"),
            listOf("doubles", "co-op"), listOf("co-op", "doubles"), listOf("singles", "doubles", "co-op"),
            listOf("singles", "co-op", "doubles"), listOf("doubles", "singles", "co-op"), listOf("doubles", "co-op", "singles"),
            listOf("co-op", "singles", "doubles"), listOf("co-op", "doubles", "singles"))
        val keys = listOf("all", "S", "D", "C", "SD", "DS", "SC", "CS", "DC", "CD", "SDC", "SCD", "DSC", "DCS", "CSD", "CDS")
        val overlay = MobileCatalogOverlay(1, "phoenix2", listOf("all"), mapOf("all" to keys.associateWith { "hint-$it" }))
        selections.zip(keys).forEach { (charts, key) ->
            assertEquals(key, CatalogLocalQuery.modeKey(charts))
            val song = CatalogLocalQuery.query(snapshot, overlay, "", CatalogLocalQuery.Filters(charts = charts)).page.songs.first { it.slug == "all" }
            assertTrue(song.isFavorite)
            assertEquals("hint-$key", song.recommendedChartToken)
        }
        assertEquals("DS", CatalogLocalQuery.modeKey(listOf("doubles", "doubles", "singles")))
        assertTrue(snapshot.defaultPage().songs.all { !it.isFavorite && it.recommendedChartToken == null })
        assertThrows(IllegalArgumentException::class.java) { CatalogLocalQuery.query(snapshot, overlay.copy(version = "phoenix"), "") }
    }

    @Serializable private data class AliasFixture(val songs: List<AliasSong>, val cases: List<AliasCase>)
    @Serializable private data class AliasSong(val title: String, val artist: String, val slug: String)
    @Serializable private data class AliasCase(val query: String, val expectedSlugs: List<String>)
    @Test fun sharedAliasFixturePreservesOfficialTitleAndOtherArtists() {
        val alias = json.decodeFromString<AliasFixture>(text("catalog-search-aliases"))
        val songs = alias.songs.map { PublicCatalogSong(it.slug, it.slug, it.title, it.artist, "phoenix2", listOf("phoenix2"), chartSummary = emptyList(), tags = emptyList(), isPremium = false) }
        val snapshot = PublicCatalogSnapshot(1, "phoenix2", "supported", songs.size, PublicCatalogFilterOptions(emptyList(), emptyList(), emptyList(), emptyList()), songs)
        alias.cases.forEach { case ->
            val result = CatalogLocalQuery.query(snapshot, null, case.query).page.songs
            assertEquals(case.query, case.expectedSlugs.toSet(), result.map { it.slug }.toSet())
            result.forEach { song -> assertEquals(songs.first { it.slug == song.slug }.title, song.title) }
        }
        listOf("favorites", " RECOMMENDATION ", "Recent").forEach { assertFalse(CatalogLocalQuery.isOrdinary(it)) }
        assertTrue(CatalogLocalQuery.isOrdinary("recent remix"))
    }
}
