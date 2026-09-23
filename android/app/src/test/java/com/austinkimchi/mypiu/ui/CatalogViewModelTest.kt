package com.austinkimchi.mypiu.ui

import com.austinkimchi.mypiu.core.catalog.CatalogCache
import com.austinkimchi.mypiu.core.catalog.CatalogDataSource
import com.austinkimchi.mypiu.core.model.CatalogListing
import com.austinkimchi.mypiu.core.model.CatalogSearchPage
import com.austinkimchi.mypiu.core.model.CatalogSong
import com.austinkimchi.mypiu.core.model.CatalogSortDirection
import com.austinkimchi.mypiu.core.model.CatalogSortOption
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.SongChartPerformance
import com.austinkimchi.mypiu.core.network.MyPiuApiException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CatalogViewModelTest {
    @Test
    fun sortChangesReloadTheCatalogWithWebsiteSortValues() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakeCatalogDataSource()
            val viewModel = CatalogViewModel(source)
            viewModel.start()
            advanceUntilIdle()

            viewModel.setSort(CatalogSortOption.ARTIST, CatalogSortDirection.ASCENDING)
            advanceUntilIdle()

            assertEquals(CatalogSortOption.ARTIST, source.searches.last().sortBy)
            assertEquals(CatalogSortDirection.ASCENDING, source.searches.last().sortDirection)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun accountFeedsUseSpecialQueriesAndPreferredVersion() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakeCatalogDataSource()
            val viewModel = CatalogViewModel(source)
            viewModel.start()
            advanceUntilIdle()

            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX)
            advanceUntilIdle()
            viewModel.setFeed(CatalogFeed.RECOMMENDATIONS)
            advanceUntilIdle()

            assertEquals("recommendation", source.searches.last().query)
            assertEquals(PiuGameVersion.PHOENIX, source.searches.last().version)
            assertTrue(source.searches.last().authenticated)
            assertTrue(viewModel.state.value.isMyPiuConnected)

            viewModel.updateSession(null, connected = false, preferredVersion = null)
            advanceUntilIdle()
            assertEquals(CatalogFeed.CATALOG, viewModel.state.value.feed)
            assertEquals("", source.searches.last().query)
            assertFalse(source.searches.last().authenticated)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun rapidSearchOnlyRequestsNewestDebouncedQuery() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakeCatalogDataSource()
            val viewModel = CatalogViewModel(source)
            viewModel.start()
            advanceUntilIdle()
            source.searches.clear()

            viewModel.setQuery("old")
            viewModel.setQuery("new")
            advanceTimeBy(299)
            assertTrue(source.searches.isEmpty())
            advanceUntilIdle()

            assertEquals(listOf("new"), source.searches.map(Search::query))
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun artworkIndexSurvivesSearchAndNormalizesSessionTitle() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakeCatalogDataSource(song = favoriteSong().copy(imageUrl = "/jackets/song.png"))
            val viewModel = CatalogViewModel(source)
            viewModel.start()
            advanceUntilIdle()

            source.searchHandler = { _, _, _, _ -> CatalogSearchPage(emptyList(), null, 0) }
            viewModel.setQuery("unrelated")
            advanceUntilIdle()

            assertTrue(viewModel.state.value.listing.songs.isEmpty())
            assertEquals("/jackets/song.png", viewModel.artworkUrl("  SONG  "))
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun failedFavoriteRollsBackOptimisticState() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakeCatalogDataSource(favoriteFailure = IllegalStateException("Favorite failed"))
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()
            val song = viewModel.state.value.listing.songs.single()

            viewModel.toggleFavorite(song)
            assertTrue(viewModel.state.value.listing.songs.single().isFavorite)
            advanceUntilIdle()

            assertFalse(viewModel.state.value.listing.songs.single().isFavorite)
            assertNotNull(viewModel.state.value.favoriteError)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun unresolvedAccountSessionIsNeverCachedAsPublicData() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakeCatalogDataSource()
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession(null, connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()

            assertEquals(null, viewModel.state.value.cacheScope)
            assertTrue(source.cacheReads.isEmpty())
            assertTrue(source.cacheWrites.isEmpty())
            assertFalse(viewModel.state.value.isMyPiuConnected)
            assertFalse(source.searches.single().authenticated)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun oldAccountFavoriteResponseCannotSettleNewAccountsMutation() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val firstStarted = CompletableDeferred<Unit>()
            val firstResult = CompletableDeferred<Boolean>()
            val secondStarted = CompletableDeferred<Unit>()
            val secondResult = CompletableDeferred<Boolean>()
            var requestCount = 0
            val source = FakeCatalogDataSource(favoriteHandler = { _, _, _ ->
                if (requestCount++ == 0) {
                    firstStarted.complete(Unit)
                    firstResult.await()
                } else {
                    secondStarted.complete(Unit)
                    secondResult.await()
                }
            })
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()

            viewModel.toggleFavorite(viewModel.state.value.listing.songs.single())
            runCurrent()
            assertTrue(firstStarted.isCompleted)
            assertEquals(setOf("song"), viewModel.state.value.updatingFavorites)

            viewModel.updateSession("two", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            runCurrent()
            assertTrue(viewModel.state.value.updatingFavorites.isEmpty())
            viewModel.toggleFavorite(viewModel.state.value.listing.songs.single())
            runCurrent()
            assertTrue(secondStarted.isCompleted)

            firstResult.complete(true)
            runCurrent()
            assertEquals(setOf("song"), viewModel.state.value.updatingFavorites)

            secondResult.complete(true)
            advanceUntilIdle()
            assertTrue(viewModel.state.value.updatingFavorites.isEmpty())
            assertTrue(viewModel.state.value.listing.songs.single().isFavorite)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun oldFavoriteAuthorizationFailureCannotInvalidateReplacementSession() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val requestStarted = CompletableDeferred<Unit>()
            val requestResult = CompletableDeferred<Boolean>()
            val source = FakeCatalogDataSource(favoriteHandler = { _, _, _ ->
                requestStarted.complete(Unit)
                requestResult.await()
            })
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()

            viewModel.toggleFavorite(viewModel.state.value.listing.songs.single())
            runCurrent()
            assertTrue(requestStarted.isCompleted)

            viewModel.updateSession(null, connected = false, preferredVersion = null)
            advanceUntilIdle()
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            advanceUntilIdle()
            assertFalse(viewModel.state.value.listing.songs.single().isFavorite)

            requestResult.completeExceptionally(MyPiuApiException(401, "invalid_token"))
            advanceUntilIdle()

            assertTrue(viewModel.state.value.isMyPiuConnected)
            assertFalse(viewModel.state.value.sessionInvalidated)
            assertTrue(viewModel.state.value.updatingFavorites.isEmpty())
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun oldFavoriteSuccessReloadsMatchingReplacementSession() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val requestStarted = CompletableDeferred<Unit>()
            val requestResult = CompletableDeferred<Boolean>()
            var serverFavorite = false
            val source = FakeCatalogDataSource(favoriteHandler = { _, _, _ ->
                requestStarted.complete(Unit)
                requestResult.await().also { serverFavorite = it }
            })
            source.searchHandler = { _, _, _, _ ->
                CatalogSearchPage(listOf(favoriteSong().copy(isFavorite = serverFavorite)), null, 1)
            }
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()

            viewModel.toggleFavorite(viewModel.state.value.listing.songs.single())
            runCurrent()
            assertTrue(requestStarted.isCompleted)

            viewModel.updateSession(null, connected = false, preferredVersion = null)
            advanceUntilIdle()
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            advanceUntilIdle()
            assertFalse(viewModel.state.value.listing.songs.single().isFavorite)
            val searchesBeforeSuccess = source.searches.size

            requestResult.complete(true)
            advanceUntilIdle()

            assertTrue(source.searches.size > searchesBeforeSuccess)
            assertTrue(viewModel.state.value.listing.songs.single().isFavorite)
            assertTrue(viewModel.state.value.isMyPiuConnected)
            assertTrue(viewModel.state.value.updatingFavorites.isEmpty())
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun refavoritingFromRemovedFavoritesDetailReinsertsSong() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakeCatalogDataSource(song = favoriteSong())
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()
            viewModel.setFeed(CatalogFeed.FAVORITES)
            advanceUntilIdle()
            val selectedSong = viewModel.state.value.listing.songs.single()

            viewModel.toggleFavorite(selectedSong)
            advanceUntilIdle()
            assertTrue(viewModel.state.value.listing.songs.isEmpty())

            viewModel.toggleFavorite(selectedSong.copy(isFavorite = false))
            advanceUntilIdle()

            assertEquals(1, viewModel.state.value.listing.total)
            assertTrue(viewModel.state.value.listing.songs.single().isFavorite)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun staleSearchStartedBeforeFavoriteCannotUndoMutation() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val searchStarted = CompletableDeferred<Unit>()
            val searchResult = CompletableDeferred<CatalogSearchPage>()
            val source = FakeCatalogDataSource()
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()
            val selectedSong = viewModel.state.value.listing.songs.single()
            source.searchHandler = { _, _, _, _ ->
                searchStarted.complete(Unit)
                searchResult.await()
            }

            viewModel.refresh()
            runCurrent()
            assertTrue(searchStarted.isCompleted)
            viewModel.toggleFavorite(selectedSong)
            runCurrent()

            searchResult.complete(CatalogSearchPage(listOf(favoriteSong().copy(isFavorite = false)), null, 1))
            advanceUntilIdle()

            assertTrue(viewModel.state.value.listing.songs.single().isFavorite)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun staleSearchCannotOverwriteFavoriteCacheWhileFavoriteCacheWriteIsSuspended() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val searchStarted = CompletableDeferred<Unit>()
            val searchResult = CompletableDeferred<CatalogSearchPage>()
            val favoriteCacheStarted = CompletableDeferred<Unit>()
            val favoriteCacheResult = CompletableDeferred<Unit>()
            val source = FakeCatalogDataSource(
                cacheFavoriteHandler = { _, _, _, _ ->
                    favoriteCacheStarted.complete(Unit)
                    favoriteCacheResult.await()
                },
            )
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()
            val selectedSong = viewModel.state.value.listing.songs.single()
            source.searchHandler = { _, _, _, _ ->
                searchStarted.complete(Unit)
                searchResult.await()
            }

            viewModel.refresh()
            runCurrent()
            assertTrue(searchStarted.isCompleted)
            viewModel.toggleFavorite(selectedSong)
            runCurrent()
            assertTrue(favoriteCacheStarted.isCompleted)

            searchResult.complete(CatalogSearchPage(listOf(selectedSong.copy(isFavorite = false)), null, 1))
            runCurrent()

            assertTrue(viewModel.state.value.listing.songs.single().isFavorite)
            assertEquals(listOf(true), source.cachedSongFavorites.last())

            favoriteCacheResult.complete(Unit)
            advanceUntilIdle()
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun versionChangesKeepFavoriteWritesSerialized() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val firstStarted = CompletableDeferred<Unit>()
            val firstResult = CompletableDeferred<Boolean>()
            val secondStarted = CompletableDeferred<Unit>()
            val secondResult = CompletableDeferred<Boolean>()
            val requestedWrites = mutableListOf<Boolean>()
            var requestCount = 0
            val source = FakeCatalogDataSource(favoriteHandler = { _, saved, _ ->
                requestedWrites += saved
                if (requestCount++ == 0) {
                    firstStarted.complete(Unit)
                    firstResult.await()
                } else {
                    secondStarted.complete(Unit)
                    secondResult.await()
                }
            })
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()

            viewModel.toggleFavorite(viewModel.state.value.listing.songs.single())
            runCurrent()
            assertTrue(firstStarted.isCompleted)

            viewModel.setVersion(PiuGameVersion.PHOENIX)
            advanceUntilIdle()
            assertFalse(viewModel.state.value.listing.songs.single().isFavorite)
            assertEquals(setOf("song"), viewModel.state.value.updatingFavorites)
            viewModel.setVersion(PiuGameVersion.PHOENIX_2)
            advanceUntilIdle()
            assertTrue(viewModel.state.value.listing.songs.single().isFavorite)
            viewModel.toggleFavorite(viewModel.state.value.listing.songs.single().copy(isFavorite = true))
            runCurrent()
            assertFalse(secondStarted.isCompleted)
            assertEquals(listOf(true), requestedWrites)
            assertEquals(setOf("song"), viewModel.state.value.updatingFavorites)

            firstResult.complete(true)
            advanceUntilIdle()
            assertTrue(viewModel.state.value.updatingFavorites.isEmpty())
            assertTrue(viewModel.state.value.listing.songs.single().isFavorite)
            assertEquals(listOf(true), source.cachedFavoriteWrites.map(CachedFavoriteWrite::saved))

            viewModel.toggleFavorite(viewModel.state.value.listing.songs.single())
            runCurrent()
            assertTrue(secondStarted.isCompleted)
            assertEquals(listOf(true, false), requestedWrites)

            secondResult.complete(false)
            advanceUntilIdle()

            assertEquals(listOf(true, false), source.cachedFavoriteWrites.map(CachedFavoriteWrite::saved))
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun refreshAcceptsFavoriteChangedOnAnotherDevice() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakeCatalogDataSource()
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()

            viewModel.toggleFavorite(viewModel.state.value.listing.songs.single())
            advanceUntilIdle()
            assertTrue(viewModel.state.value.listing.songs.single().isFavorite)

            viewModel.refresh()
            advanceUntilIdle()

            assertFalse(viewModel.state.value.listing.songs.single().isFavorite)
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun favoriteMutationUpdatesDetailStateWhenSongIsNotListed() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakeCatalogDataSource()
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()
            val selectedSong = viewModel.state.value.listing.songs.single()
            source.searchHandler = { _, _, _, _ -> CatalogSearchPage(emptyList(), null, 0) }
            viewModel.refresh()
            advanceUntilIdle()
            assertTrue(viewModel.state.value.listing.songs.isEmpty())

            viewModel.toggleFavorite(selectedSong)
            advanceUntilIdle()

            assertEquals(true, viewModel.state.value.detailFavoriteStates[selectedSong.slug])
            assertTrue(viewModel.state.value.listing.songs.isEmpty())
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun sessionInvalidationKeepsChartHistoryInTerminalState() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        Dispatchers.setMain(dispatcher)
        try {
            val source = FakeCatalogDataSource(chartFailure = MyPiuApiException(401, "invalid_token"))
            val viewModel = CatalogViewModel(source)
            viewModel.updateSession("one", connected = true, preferredVersion = PiuGameVersion.PHOENIX_2)
            viewModel.start()
            advanceUntilIdle()
            val song = viewModel.state.value.listing.songs.single()

            viewModel.loadChartHistory(song, "S16")
            advanceUntilIdle()
            viewModel.updateSession(null, connected = false, preferredVersion = null)
            advanceUntilIdle()

            val history = requireNotNull(viewModel.state.value.chartHistory)
            assertFalse(history.isLoading)
            assertNotNull(history.error)
            assertEquals(null, history.performance)
        } finally {
            Dispatchers.resetMain()
        }
    }
}

private data class Search(
    val query: String,
    val cursor: String?,
    val version: PiuGameVersion,
    val authenticated: Boolean,
    val sortBy: CatalogSortOption,
    val sortDirection: CatalogSortDirection,
)

private data class CachedFavoriteWrite(
    val saved: Boolean,
    val slug: String,
    val version: PiuGameVersion,
    val scope: String,
)

private class FakeCatalogDataSource(
    private val favoriteFailure: Exception? = null,
    private val song: CatalogSong = favoriteSong().copy(isFavorite = false),
    private val chartFailure: Exception? = null,
    private val favoriteHandler: (suspend (String, Boolean, PiuGameVersion) -> Boolean)? = null,
    private val cacheFavoriteHandler: (suspend (Boolean, String, PiuGameVersion, String) -> Unit)? = null,
) : CatalogDataSource {
    val searches = mutableListOf<Search>()
    val cacheReads = mutableListOf<String>()
    val cacheWrites = mutableListOf<String>()
    val cachedSongFavorites = mutableListOf<List<Boolean>>()
    val cachedFavoriteWrites = mutableListOf<CachedFavoriteWrite>()
    var searchHandler: (suspend (String, String?, PiuGameVersion, Boolean) -> CatalogSearchPage)? = null

    override suspend fun search(
        query: String,
        cursor: String?,
        version: PiuGameVersion,
        authenticated: Boolean,
        sortBy: CatalogSortOption,
        sortDirection: CatalogSortDirection,
    ): CatalogSearchPage {
        searches += Search(query, cursor, version, authenticated, sortBy, sortDirection)
        searchHandler?.let { return it(query, cursor, version, authenticated) }
        return CatalogSearchPage(listOf(song), null, 1)
    }

    override suspend fun setFavorite(slug: String, saved: Boolean, version: PiuGameVersion): Boolean {
        favoriteHandler?.let { return it(slug, saved, version) }
        favoriteFailure?.let { throw it }
        return saved
    }

    override suspend fun chartPerformance(
        slug: String,
        chart: String,
        version: PiuGameVersion,
    ): SongChartPerformance? {
        chartFailure?.let { throw it }
        return null
    }

    override suspend fun cached(
        query: String,
        version: PiuGameVersion,
        scope: String,
        sortBy: CatalogSortOption,
        sortDirection: CatalogSortDirection,
    ): CatalogCache.CachedListing? {
        cacheReads += scope
        return null
    }

    override suspend fun cache(
        listing: CatalogListing,
        query: String,
        version: PiuGameVersion,
        scope: String,
        sortBy: CatalogSortOption,
        sortDirection: CatalogSortDirection,
    ) {
        cacheWrites += scope
        cachedSongFavorites += listing.songs.map(CatalogSong::isFavorite)
    }

    override suspend fun cacheFavorite(
        saved: Boolean,
        slug: String,
        version: PiuGameVersion,
        scope: String,
    ) {
        cachedFavoriteWrites += CachedFavoriteWrite(saved, slug, version, scope)
        cacheFavoriteHandler?.invoke(saved, slug, version, scope)
    }

    override fun resolveUrl(value: String?): String? = value
}

private fun favoriteSong() = CatalogSong(
    slug = "song",
    title = "Song",
    artist = "Artist",
    chartSummary = listOf("S16"),
    isFavorite = true,
)
