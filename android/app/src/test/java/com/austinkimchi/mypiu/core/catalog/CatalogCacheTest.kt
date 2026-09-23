package com.austinkimchi.mypiu.core.catalog

import com.austinkimchi.mypiu.core.model.CatalogListing
import com.austinkimchi.mypiu.core.model.CatalogSong
import com.austinkimchi.mypiu.core.model.CatalogSortDirection
import com.austinkimchi.mypiu.core.model.CatalogSortOption
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import java.nio.file.Files
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CatalogCacheTest {
    @Test
    fun cacheSeparatesScopeVersionAndNormalizedQuery() = runTest {
        val directory = Files.createTempDirectory("mypiu-catalog-test").toFile()
        try {
            val cache = CatalogCache(directory)
            cache.save(LISTING, "  BATTLE  ", PiuGameVersion.PHOENIX_2, "account:one", 100)

            assertEquals(
                LISTING,
                cache.load("battle", PiuGameVersion.PHOENIX_2, "account:one")?.listing,
            )
            assertNull(cache.load("battle", PiuGameVersion.PHOENIX, "account:one"))
            assertNull(cache.load("battle", PiuGameVersion.PHOENIX_2, "account:two"))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun cacheKeepsTwelveNewestListings() = runTest {
        val directory = Files.createTempDirectory("mypiu-catalog-test").toFile()
        try {
            val cache = CatalogCache(directory)
            repeat(13) { index ->
                cache.save(LISTING, "query-$index", PiuGameVersion.PHOENIX_2, "public", index.toLong())
            }

            assertNull(cache.load("query-0", PiuGameVersion.PHOENIX_2, "public"))
            assertEquals(
                SONG.slug,
                cache.load("query-12", PiuGameVersion.PHOENIX_2, "public")?.listing?.songs?.single()?.slug,
            )
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun cacheSeparatesSortOrders() = runTest {
        val directory = Files.createTempDirectory("mypiu-catalog-test").toFile()
        try {
            val cache = CatalogCache(directory)
            cache.save(
                listing = LISTING,
                query = "",
                version = PiuGameVersion.PHOENIX_2,
                scope = "public",
                sortBy = CatalogSortOption.ARTIST,
                sortDirection = CatalogSortDirection.ASCENDING,
            )

            assertEquals(
                LISTING,
                cache.load(
                    "",
                    PiuGameVersion.PHOENIX_2,
                    "public",
                    CatalogSortOption.ARTIST,
                    CatalogSortDirection.ASCENDING,
                )?.listing,
            )
            assertNull(cache.load("", PiuGameVersion.PHOENIX_2, "public"))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun favoriteChangesPropagateOnlyWithinAccountAndVersion() = runTest {
        val directory = Files.createTempDirectory("mypiu-catalog-test").toFile()
        try {
            val cache = CatalogCache(directory)
            cache.save(LISTING, "one", PiuGameVersion.PHOENIX_2, "account:one")
            cache.save(LISTING, "favorites", PiuGameVersion.PHOENIX_2, "account:one")
            cache.save(LISTING, "one", PiuGameVersion.PHOENIX, "account:one")

            cache.setFavorite(false, SONG.slug, PiuGameVersion.PHOENIX_2, "account:one")

            assertEquals(
                false,
                cache.load("one", PiuGameVersion.PHOENIX_2, "account:one")?.listing?.songs?.single()?.isFavorite,
            )
            assertTrue(
                cache.load("favorites", PiuGameVersion.PHOENIX_2, "account:one")?.listing?.songs?.isEmpty() == true,
            )
            assertEquals(
                true,
                cache.load("one", PiuGameVersion.PHOENIX, "account:one")?.listing?.songs?.single()?.isFavorite,
            )
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun addingFavoriteInvalidatesFavoriteFeedForRefetch() = runTest {
        val directory = Files.createTempDirectory("mypiu-catalog-test").toFile()
        try {
            val cache = CatalogCache(directory)
            cache.save(LISTING, "favorites", PiuGameVersion.PHOENIX_2, "account:one")
            cache.save(
                LISTING.setFavorite(SONG.slug, false),
                "songs",
                PiuGameVersion.PHOENIX_2,
                "account:one",
            )

            cache.setFavorite(true, SONG.slug, PiuGameVersion.PHOENIX_2, "account:one")

            assertNull(cache.load("favorites", PiuGameVersion.PHOENIX_2, "account:one"))
            assertEquals(
                true,
                cache.load("songs", PiuGameVersion.PHOENIX_2, "account:one")?.listing?.songs?.single()?.isFavorite,
            )
        } finally {
            directory.deleteRecursively()
        }
    }

    private companion object {
        val SONG = CatalogSong(
            slug = "battle-no-1",
            title = "BATTLE NO.1",
            artist = "TANO*C Sound Team",
            chartSummary = listOf("S10", "S19"),
            isFavorite = true,
        )
        val LISTING = CatalogListing(listOf(SONG), "Mg", 654)
    }
}
