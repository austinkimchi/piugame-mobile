package com.austinkimchi.mypiu.core.model

import kotlinx.serialization.Serializable

enum class CatalogChartMode(val title: String, private val prefix: Char) {
    SINGLE("Singles", 'S'),
    DOUBLE("Doubles", 'D'),
    COOP("Co-op", 'C');

    fun contains(chartToken: String): Boolean = chartToken.firstOrNull()?.uppercaseChar() == prefix
}

@Serializable
enum class CatalogSortOption(val wireValue: String, val title: String) {
    SERIES("series", "Series"),
    TITLE("title", "Title"),
    ARTIST("artist", "Artist"),
    FOLDER("folder", "Folder"),
}

@Serializable
enum class CatalogSortDirection(val wireValue: String, val title: String) {
    ASCENDING("asc", "Ascending"),
    DESCENDING("desc", "Descending"),
}

@Serializable
data class CatalogSong(
    val slug: String,
    val title: String,
    val artist: String,
    val supportedVersions: List<String> = emptyList(),
    val imageUrl: String? = null,
    val bpm: String? = null,
    val chartSummary: List<String> = emptyList(),
    val folder: String? = null,
    val series: String? = null,
    val tags: List<String> = emptyList(),
    val isPremium: Boolean = false,
    val isFavorite: Boolean = false,
    val recommendedChartToken: String? = null,
) {
    fun charts(mode: CatalogChartMode): List<String> = chartSummary.filter(mode::contains)
}

@Serializable
data class CatalogSearchPage(
    val songs: List<CatalogSong>,
    val nextCursor: String? = null,
    val total: Int,
)

data class CatalogListing(
    val songs: List<CatalogSong> = emptyList(),
    val nextCursor: String? = null,
    val total: Int = 0,
) {
    fun append(page: CatalogSearchPage, requestedCursor: String): CatalogListing {
        val knownSlugs = songs.mapTo(mutableSetOf(), CatalogSong::slug)
        return copy(
            songs = songs + page.songs.filter { knownSlugs.add(it.slug) },
            nextCursor = page.nextCursor.takeUnless { it == requestedCursor },
            total = page.total,
        )
    }

    fun setFavorite(slug: String, saved: Boolean): CatalogListing = copy(
        songs = songs.map { song -> if (song.slug == slug) song.copy(isFavorite = saved) else song },
    )

    fun upsertSong(song: CatalogSong): CatalogListing {
        val index = songs.indexOfFirst { it.slug == song.slug }
        if (index < 0) return copy(songs = listOf(song) + songs, total = total + 1)
        return copy(songs = songs.toMutableList().also { it[index] = song })
    }

    fun removeSong(slug: String): CatalogListing {
        if (songs.none { it.slug == slug }) return this
        return copy(songs = songs.filterNot { it.slug == slug }, total = (total - 1).coerceAtLeast(0))
    }
}

@Serializable
data class FavoriteUpdatePayload(val saved: Boolean, val version: PiuGameVersion)

@Serializable
data class FavoriteUpdateResponse(val slug: String, val isFavorite: Boolean)

@Serializable
data class SongChartPerformance(
    val latestPlay: Attempt? = null,
    val history: List<Attempt> = emptyList(),
    val stats: Stats? = null,
) {
    @Serializable
    data class Attempt(
        val id: String,
        val score: Int? = null,
        val grade: String? = null,
        val plate: String? = null,
        val playedAt: String? = null,
        val stageBreak: Boolean = false,
        val judgments: JudgmentCounts = JudgmentCounts(null, null, null, null, null),
    )

    @Serializable
    data class Stats(
        val bestScore: Int? = null,
        val previousBestScore: Int? = null,
        val latestScore: Int? = null,
        val latestStageBreak: Boolean = false,
        val latestPlayedAt: String? = null,
        val recentPlayCount: Int = 0,
        val stageBreakCount: Int = 0,
        val bestGrade: String? = null,
        val bestPlate: String? = null,
        val bestBucketPage: Int? = null,
        val bestSyncedAt: String? = null,
    )
}

@Serializable
data class ChartPerformanceResponse(val performance: SongChartPerformance? = null)
