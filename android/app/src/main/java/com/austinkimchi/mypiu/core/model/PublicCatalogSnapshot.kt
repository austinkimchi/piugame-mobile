package com.austinkimchi.mypiu.core.model

import kotlinx.serialization.Serializable

// Deliberately separate from CatalogSong: no account favorites or recommendation data on disk here.
@Serializable
data class PublicCatalogSong(
    val songKey: String,
    val slug: String,
    val title: String,
    val artist: String,
    val version: String,
    val supportedVersions: List<String>,
    val imageUrl: String? = null,
    val bpm: String? = null,
    val chartSummary: List<String>,
    val folder: String? = null,
    val folderPosition: Int? = null,
    val series: String? = null,
    val tags: List<String>,
    val isPremium: Boolean,
) {
    fun catalogSong() = CatalogSong(slug, title, artist, supportedVersions, imageUrl, bpm,
        chartSummary, folder, folderPosition, series, tags, isPremium)
}

@Serializable
data class PublicCatalogSnapshot(
    val schemaVersion: Int,
    val selectedVersion: String,
    val view: String,
    val total: Int,
    val filterOptions: PublicCatalogFilterOptions,
    val songs: List<PublicCatalogSong>,
) {
    fun validate(version: PiuGameVersion) {
        require(schemaVersion == 1 && selectedVersion == version.serialName && view == "supported" &&
            total == songs.size && songs.map { it.slug }.toSet().size == total &&
            songs.all { it.slug.isNotBlank() && it.songKey.isNotBlank() && version.serialName in it.supportedVersions }) {
            "The catalog response was incomplete. Please try again."
        }
    }
    fun defaultPage() = CatalogSearchPage(songs.map { it.catalogSong() }.sortedWith(defaultCatalogOrder), total = total)
}

@Serializable
data class PublicCatalogFilterOptions(val folders: List<String>, val series: List<String>, val levels: List<String>, val charts: List<String>)

@Serializable
data class MobileCatalogOverlay(
    val schemaVersion: Int,
    val version: String,
    val favoriteSlugs: List<String>,
    val recommendations: Map<String, Map<String, String?>>,
) {
    fun settingFavorite(saved: Boolean, slug: String) = copy(favoriteSlugs =
        favoriteSlugs.toMutableSet().also { if (saved) it.add(slug) else it.remove(slug) }.sorted())

    fun apply(snapshot: PublicCatalogSnapshot): CatalogSearchPage {
        require(schemaVersion == 1 && version == snapshot.selectedVersion) { "Invalid account catalog response." }
        val favorites = favoriteSlugs.toSet()
        return snapshot.defaultPage().let { page ->
            page.copy(songs = page.songs.map { it.copy(isFavorite = it.slug in favorites, recommendedChartToken = recommendations[it.slug]?.get("all")) })
        }
    }
}

private val seriesOrder = listOf("1st", "nx", "fiesta", "prime", "prime2", "xx", "phoenix", "phoenix2")
private fun seriesRank(value: String?) = seriesOrder.indexOf((value ?: "").lowercase(java.util.Locale.ROOT).replace(" ", ""))

// Mongo uses Unicode scalar/binary ordering, not locale-aware or UTF-16 String ordering.
private fun binaryCompare(left: String?, right: String?): Int {
    if (left == null) return if (right == null) 0 else -1
    if (right == null) return 1
    var a = 0
    var b = 0
    while (a < left.length && b < right.length) {
        val x = Character.codePointAt(left, a)
        val y = Character.codePointAt(right, b)
        if (x != y) return x.compareTo(y)
        a += Character.charCount(x)
        b += Character.charCount(y)
    }
    return (left.length - a).compareTo(right.length - b)
}

val defaultCatalogOrder: Comparator<CatalogSong> = Comparator { left, right ->
    compareValues(seriesRank(right.series), seriesRank(left.series)).takeIf { it != 0 }
        ?: binaryCompare(right.series, left.series).takeIf { it != 0 }
        ?: compareValues(right.folderPosition, left.folderPosition).takeIf { it != 0 }
        ?: binaryCompare(right.title, left.title).takeIf { it != 0 }
        ?: binaryCompare(right.artist, left.artist)
}
