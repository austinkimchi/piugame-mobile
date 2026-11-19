package com.austinkimchi.mypiu.core.catalog

import com.austinkimchi.mypiu.core.model.MobileCatalogOverlay
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.PublicCatalogSnapshot
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PublicCatalogStoreTest {
    private val version = PiuGameVersion.PHOENIX_2
    private val json = Json { ignoreUnknownKeys = true }
    private fun snapshot() = json.decodeFromString<PublicCatalogSnapshot>(FIXTURE)

    @Test fun diskCacheRevalidatesWithETagAndContainsNoPrivateFields() = runTest {
        val directory = Files.createTempDirectory("public-catalog").toFile()
        try {
            val store = PublicCatalogStore(directory, { _, _ -> PublicCatalogResponse(snapshot(), "v1") }, backgroundScope)
            val first = store.refresh(version)
            assertFalse(first.defaultPage().songs.single().isFavorite)
            assertNull(first.defaultPage().songs.single().recommendedChartToken)
            val saved = directory.resolve("phoenix2.json").readText()
            assertFalse(saved.contains("isFavorite"))
            assertFalse(saved.contains("recommendedChartToken"))
            val restored = PublicCatalogStore(directory, { selected, etag ->
                assertEquals(version, selected)
                assertEquals("v1", etag)
                PublicCatalogResponse(null, etag, true)
            }, backgroundScope)
            assertEquals(first, restored.cached(version))
            assertEquals(first, restored.refresh(version))
            assertNull(restored.cached(PiuGameVersion.PHOENIX))
        } finally { directory.deleteRecursively() }
    }

    @Test fun concurrentReadersShareDownloadEvenWhenOneViewIsCanceled() = runTest {
        val directory = Files.createTempDirectory("public-catalog").toFile()
        try {
            val gate = CompletableDeferred<Unit>()
            var count = 0
            val store = PublicCatalogStore(directory, { _, _ ->
                count += 1
                gate.await()
                PublicCatalogResponse(snapshot(), null)
            }, backgroundScope)
            val first = async { store.refresh(version) }
            val second = async { store.refresh(version) }
            runCurrent()
            first.cancel()
            gate.complete(Unit)
            assertEquals(1, second.await().total)
            assertEquals(1, count)
        } finally { directory.deleteRecursively() }
    }

    @Test fun invalidOrPartialSnapshotsNeverBecomeCompleteCaches() = runTest {
        // Match the production store's supervised downloads: a deliberately rejected response
        // must reach the awaiting caller without also failing runTest's background parent.
        val downloads = CoroutineScope(backgroundScope.coroutineContext + SupervisorJob(backgroundScope.coroutineContext[Job]))
        val directory = Files.createTempDirectory("public-catalog").toFile()
        try {
            for (bad in listOf(snapshot().copy(total = 2), snapshot().copy(view = "removed"),
                snapshot().copy(songs = snapshot().songs + snapshot().songs, total = 2))) {
                val store = PublicCatalogStore(directory, { _, _ -> PublicCatalogResponse(bad, null) }, downloads)
                var failed = false
                try { store.refresh(version) } catch (_: IllegalArgumentException) { failed = true }
                assertTrue(failed)
                assertNull(store.cached(version))
            }
        } finally { directory.deleteRecursively() }
    }

    @Test fun overlayAddsFavoritesAndHintsWithoutChangingPublicIdentityOrCharts() {
        val snapshot = snapshot()
        val overlay = MobileCatalogOverlay(1, "phoenix2", listOf("one-phoenix2"), mapOf("one-phoenix2" to mapOf("all" to "S19")))
        val song = overlay.apply(snapshot).songs.single()
        assertEquals("one-phoenix2", song.slug)
        assertEquals(listOf("S19"), song.chartSummary)
        assertTrue(song.isFavorite)
        assertEquals("S19", song.recommendedChartToken)
        assertFalse(snapshot.defaultPage().songs.single().isFavorite)
    }

    @Test fun defaultOrderUsesRankBinaryUnicodeAndNullPosition() {
        val base = snapshot().songs.single()
        val songs = listOf(base.copy(slug = "unknown", series = "Other", folderPosition = 99),
            base.copy(slug = "older", series = "XX"), base.copy(slug = "missing", folderPosition = null),
            base.copy(slug = "z", title = "Z"), base.copy(slug = "a", title = "a"),
            base.copy(slug = "newer-position", folderPosition = 2))
        assertEquals(listOf("newer-position", "a", "z", "missing", "older", "unknown"), snapshot().copy(songs = songs, total = songs.size).defaultPage().songs.map { it.slug })
    }

    companion object {
        private const val FIXTURE = """{"schemaVersion":1,"selectedVersion":"phoenix2","view":"supported","total":1,"filterOptions":{"folders":[],"series":[],"levels":[],"charts":[]},"songs":[{"songKey":"one","slug":"one-phoenix2","title":"One","artist":"Artist","version":"phoenix2","supportedVersions":["phoenix","phoenix2"],"imageUrl":"/one.png","bpm":"180","chartSummary":["S19"],"folder":"Original","folderPosition":1,"series":"PHOENIX 2","tags":[],"isPremium":false,"isFavorite":true,"recommendedChartToken":"S19"}]}"""
    }
}
