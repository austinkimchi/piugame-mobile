package com.austinkimchi.mypiu.core.catalog

import com.austinkimchi.mypiu.core.model.CatalogListing
import com.austinkimchi.mypiu.core.model.CatalogSong
import com.austinkimchi.mypiu.core.model.CatalogSortDirection
import com.austinkimchi.mypiu.core.model.CatalogSortOption
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import java.io.File
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class CatalogCache(
    private val directory: File,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    data class CachedListing(val listing: CatalogListing, val cachedAtEpochMillis: Long)

    @Serializable
    private data class Store(val schemaVersion: Int = SCHEMA_VERSION, val entries: List<Entry> = emptyList())

    @Serializable
    private data class Entry(
        val scope: String,
        val query: String,
        val version: PiuGameVersion,
        val sortBy: CatalogSortOption,
        val sortDirection: CatalogSortDirection,
        val songs: List<CatalogSong>,
        val nextCursor: String? = null,
        val total: Int,
        val cachedAtEpochMillis: Long,
    )

    private val mutex = Mutex()
    private val cacheFile = File(directory, "catalog-v$SCHEMA_VERSION.json")

    suspend fun load(
        query: String,
        version: PiuGameVersion,
        scope: String,
        sortBy: CatalogSortOption = CatalogSortOption.SERIES,
        sortDirection: CatalogSortDirection = CatalogSortDirection.DESCENDING,
    ): CachedListing? = mutex.withLock {
        withContext(Dispatchers.IO) {
            readStore().entries.firstOrNull {
                it.scope == scope && it.query == normalize(query) && it.version == version &&
                    it.sortBy == sortBy && it.sortDirection == sortDirection
            }?.let { entry ->
                CachedListing(
                    CatalogListing(entry.songs, entry.nextCursor, entry.total),
                    entry.cachedAtEpochMillis,
                )
            }
        }
    }

    suspend fun save(
        listing: CatalogListing,
        query: String,
        version: PiuGameVersion,
        scope: String,
        nowEpochMillis: Long = System.currentTimeMillis(),
        sortBy: CatalogSortOption = CatalogSortOption.SERIES,
        sortDirection: CatalogSortDirection = CatalogSortDirection.DESCENDING,
    ) = mutex.withLock {
        withContext(Dispatchers.IO) {
            val normalizedQuery = normalize(query)
            val replacement = Entry(
                scope = scope,
                query = normalizedQuery,
                version = version,
                sortBy = sortBy,
                sortDirection = sortDirection,
                songs = listing.songs,
                nextCursor = listing.nextCursor,
                total = listing.total,
                cachedAtEpochMillis = nowEpochMillis,
            )
            val entries = (readStore().entries.filterNot {
                it.scope == scope && it.query == normalizedQuery && it.version == version &&
                    it.sortBy == sortBy && it.sortDirection == sortDirection
            } + replacement).sortedByDescending(Entry::cachedAtEpochMillis).take(MAXIMUM_ENTRIES)
            writeStore(Store(entries = entries))
        }
    }

    suspend fun setFavorite(saved: Boolean, slug: String, version: PiuGameVersion, scope: String) = mutex.withLock {
        withContext(Dispatchers.IO) {
            val store = readStore()
            var changed = false
            val entries = store.entries.mapNotNull { entry ->
                if (entry.scope != scope || entry.version != version) return@mapNotNull entry
                if (saved && entry.query == FAVORITES_QUERY) {
                    changed = true
                    return@mapNotNull null
                }
                val song = entry.songs.firstOrNull { it.slug == slug } ?: return@mapNotNull entry
                changed = true
                if (!saved && entry.query == FAVORITES_QUERY) {
                    entry.copy(
                        songs = entry.songs.filterNot { it.slug == slug },
                        total = (entry.total - 1).coerceAtLeast(0),
                    )
                } else {
                    entry.copy(
                        songs = entry.songs.map { if (it.slug == slug) song.copy(isFavorite = saved) else it },
                    )
                }
            }
            if (changed) writeStore(store.copy(entries = entries))
        }
    }

    private fun readStore(): Store = runCatching {
        json.decodeFromString<Store>(cacheFile.readText()).takeIf { it.schemaVersion == SCHEMA_VERSION }
    }.getOrNull() ?: Store()

    private fun writeStore(store: Store) {
        directory.mkdirs()
        val temporaryFile = File(directory, "${cacheFile.name}.tmp")
        temporaryFile.writeText(json.encodeToString(store))
        try {
            Files.move(
                temporaryFile.toPath(),
                cacheFile.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(temporaryFile.toPath(), cacheFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun normalize(value: String): String = value.trim().lowercase(Locale.ROOT)

    private companion object {
        const val SCHEMA_VERSION = 2
        const val MAXIMUM_ENTRIES = 12
        const val FAVORITES_QUERY = "favorites"
    }
}
