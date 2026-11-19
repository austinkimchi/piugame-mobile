package com.austinkimchi.mypiu.core.catalog

import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.PublicCatalogSnapshot
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

data class PublicCatalogResponse(val snapshot: PublicCatalogSnapshot?, val etag: String?, val notModified: Boolean = false)

class PublicCatalogStore(
    private val directory: File,
    private val fetch: suspend (PiuGameVersion, String?) -> PublicCatalogResponse,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
) {
    @Serializable
    private data class Entry(val snapshot: PublicCatalogSnapshot, val etag: String?)
    private val json = Json { ignoreUnknownKeys = true }
    private val mutex = Mutex()
    private val entries = mutableMapOf<PiuGameVersion, Entry>()
    private val inFlight = mutableMapOf<PiuGameVersion, Deferred<PublicCatalogSnapshot>>()

    suspend fun cached(version: PiuGameVersion): PublicCatalogSnapshot? = withContext(Dispatchers.IO) {
        mutex.withLock { readEntry(version)?.snapshot }
    }

    suspend fun refresh(version: PiuGameVersion): PublicCatalogSnapshot {
        val task = mutex.withLock {
            inFlight[version]?.takeUnless { it.isCompleted } ?: scope.async { download(version) }.also { inFlight[version] = it }
        }
        // A canceled view must not cancel the shared public request or release its coalescing entry early.
        task.invokeOnCompletion {
            scope.async { mutex.withLock { if (inFlight[version] === task) inFlight.remove(version) } }
        }
        return task.await()
    }

    private suspend fun download(version: PiuGameVersion): PublicCatalogSnapshot {
        val cached = mutex.withLock { readEntry(version) }
        val response = fetch(version, cached?.etag)
        if (response.notModified) return requireNotNull(cached) { "304 without a complete cached catalog." }.snapshot
        val snapshot = requireNotNull(response.snapshot)
        snapshot.validate(version)
        val entry = Entry(snapshot, response.etag)
        mutex.withLock {
            entries[version] = entry
            // Cache failures must not discard a valid fresh catalog (for example, on a full disk).
            runCatching {
                check(directory.isDirectory || directory.mkdirs())
                val temporary = File(directory, "${version.serialName}.tmp")
                temporary.writeText(json.encodeToString(entry))
                check(temporary.renameTo(file(version)))
            }
        }
        return snapshot
    }

    private fun readEntry(version: PiuGameVersion): Entry? {
        entries[version]?.let { return it }
        return runCatching {
            val file = file(version)
            require(file.length() <= MAX_BYTES)
            json.decodeFromString<Entry>(file.readText()).also { it.snapshot.validate(version) }
        }.getOrNull()?.also { entries[version] = it }
    }
    private fun file(version: PiuGameVersion) = File(directory, "${version.serialName}.json")
    companion object { const val MAX_BYTES = 8L * 1024 * 1024 }
}
