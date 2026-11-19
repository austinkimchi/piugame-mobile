package com.austinkimchi.mypiu.core.performance

import com.austinkimchi.mypiu.core.model.PerformanceSessionsResponse
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class SessionsCacheContext(
    val origin: String,
    val accountId: String,
    val version: PiuGameVersion,
    val tokenFingerprint: String,
) {
    companion object {
        fun fromToken(origin: String, accountId: String, version: PiuGameVersion, token: String) =
            SessionsCacheContext(origin, accountId, version, digest(token.toByteArray(Charsets.UTF_8)))
        internal fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
            .digest(bytes).joinToString("") { "%02x".format(it) }
    }
}

data class CachedSessionsPage(val page: PerformanceSessionsResponse, val savedAtEpochMillis: Long)

class PerformanceSessionsCache(private val directory: File) {
    @Serializable
    private data class Entry(val schemaVersion: Int, val context: SessionsCacheContext,
        val savedAtEpochMillis: Long, val page: PerformanceSessionsResponse)
    private val json = Json { ignoreUnknownKeys = true }
    private val mutex = Mutex()

    suspend fun load(context: SessionsCacheContext, isCurrent: () -> Boolean,
        now: Long = System.currentTimeMillis()): CachedSessionsPage? = withContext(Dispatchers.IO) {
        mutex.withLock {
            if (!isCurrent()) return@withLock null
            val entry = read(file(context), now)?.takeIf { it.context == context } ?: return@withLock null
            if (!isCurrent()) null else CachedSessionsPage(entry.page, entry.savedAtEpochMillis)
        }
    }

    suspend fun save(page: PerformanceSessionsResponse, context: SessionsCacheContext,
        isCurrent: () -> Boolean, now: Long = System.currentTimeMillis()) = withContext(Dispatchers.IO) {
        mutex.withLock {
            if (!isCurrent()) return@withLock
            val destination = file(context)
            if (page.selectedVersion != context.version.serialName || page.sessions.size > 20 ||
                context.accountId.isBlank() || context.origin.isBlank()) {
                destination.delete()
                return@withLock
            }
            val encoded = json.encodeToString(Entry(1, context, now, page)).toByteArray(Charsets.UTF_8)
            if (encoded.size > MAX_PAGE_BYTES) { destination.delete(); return@withLock }
            var temporary: File? = null
            try {
                check(directory.isDirectory || directory.mkdirs())
                // Drop the replaced slot before staging, so temporary bytes also fit the limit.
                check(!destination.exists() || destination.delete())
                val retained = checkNotNull(directory.listFiles()).mapNotNull { candidate ->
                    val entry = read(candidate, now)
                    if (entry != null && entry.context.origin == context.origin &&
                        entry.context.accountId == context.accountId &&
                        entry.context.tokenFingerprint == context.tokenFingerprint &&
                        entry.context.version != context.version) candidate to entry
                    else { check(candidate.delete()); null }
                }.sortedByDescending { it.second.savedAtEpochMillis }
                var retainedBytes = encoded.size.toLong()
                retained.forEachIndexed { index, (candidate, _) ->
                    if (index > 0 || retainedBytes + candidate.length() > MAX_TOTAL_BYTES) check(candidate.delete())
                    else retainedBytes += candidate.length()
                }
                if (!isCurrent()) return@withLock
                temporary = File.createTempFile("sessions-", ".tmp", directory)
                temporary.writeBytes(encoded)
                if (isCurrent()) {
                    Files.move(temporary.toPath(), destination.toPath(),
                        StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
                }
                if (!isCurrent()) destination.delete()
            } catch (_: Exception) {
                // A cache failure never changes the successful network page.
            } finally { temporary?.delete() }
        }
    }

    suspend fun clear() = withContext(Dispatchers.IO) { mutex.withLock { directory.deleteRecursively(); Unit } }

    private fun file(context: SessionsCacheContext) = File(directory,
        "sessions-${SessionsCacheContext.digest(json.encodeToString(context).toByteArray(Charsets.UTF_8))}.json")

    private fun read(file: File, now: Long): Entry? = runCatching {
        if (!file.isFile || file.length() > MAX_PAGE_BYTES) return null
        val bytes = file.readBytes()
        if (bytes.size > MAX_PAGE_BYTES) return null
        json.decodeFromString<Entry>(bytes.toString(Charsets.UTF_8)).takeIf {
            it.schemaVersion == 1 && it.page.sessions.size <= 20 &&
                it.page.selectedVersion == it.context.version.serialName &&
                now >= it.savedAtEpochMillis && now - it.savedAtEpochMillis <= MAX_AGE_MILLIS
        }
    }.getOrNull()

    companion object {
        const val MAX_PAGE_BYTES = 2 * 1024 * 1024
        const val MAX_TOTAL_BYTES = 4 * 1024 * 1024
        const val MAX_AGE_MILLIS = 24 * 60 * 60 * 1000L
    }
}
