package com.austinkimchi.mypiu.core.performance

import com.austinkimchi.mypiu.core.model.PerformanceSessionsResponse
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import java.nio.file.Files
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class PerformanceSessionsCacheTest {
    private val json = Json { ignoreUnknownKeys = true }
    private fun page() = json.decodeFromString<PerformanceSessionsResponse>(checkNotNull(
        javaClass.classLoader?.getResourceAsStream("session-cache-page.json")).bufferedReader().use { it.readText() })
    private fun context(account: String = "a", version: PiuGameVersion = PiuGameVersion.PHOENIX_2,
        token: String = "synthetic-token", origin: String = "https://example.test") =
        SessionsCacheContext.fromToken(origin, account, version, token)

    @Test fun exactIdentityAndVersionAreRequiredWithoutPersistingToken() = runTest {
        val directory = Files.createTempDirectory("sessions-cache").toFile()
        try {
            val cache = PerformanceSessionsCache(directory)
            cache.save(page(), context(), { true }, 1000)
            assertEquals(page(), cache.load(context(), { true }, 1000)?.page)
            for (other in listOf(context(account = "b"), context(token = "new"),
                context(version = PiuGameVersion.PHOENIX), context(origin = "https://another.test"))) {
                assertNull(cache.load(other, { true }, 1000))
            }
            assertFalse(directory.listFiles()!!.single().readText().contains("synthetic-token"))
        } finally { directory.deleteRecursively() }
    }

    @Test fun staleFutureCorruptAndOversizedFilesAreMisses() = runTest {
        val directory = Files.createTempDirectory("sessions-cache-invalid").toFile()
        try {
            val cache = PerformanceSessionsCache(directory)
            cache.save(page(), context(), { true }, 1000)
            assertNull(cache.load(context(), { true }, 999))
            assertNull(cache.load(context(), { true }, 1001 + PerformanceSessionsCache.MAX_AGE_MILLIS))
            val file = directory.listFiles()!!.single()
            file.writeText(file.readText().replace("\"schemaVersion\":1", "\"schemaVersion\":99"))
            assertNull(cache.load(context(), { true }, 1000))
            file.writeText("{broken")
            assertNull(cache.load(context(), { true }, 1000))
            file.writeBytes(ByteArray(PerformanceSessionsCache.MAX_PAGE_BYTES + 1))
            assertNull(cache.load(context(), { true }, 1000))
        } finally { directory.deleteRecursively() }
    }

    @Test fun oldServerUnknownVersionAndOversizedCompletePagesDoNotPersist() = runTest {
        val directory = Files.createTempDirectory("sessions-cache-version").toFile()
        try {
            val cache = PerformanceSessionsCache(directory)
            for (version in listOf(null, "unknown", "phoenix")) {
                cache.save(page().copy(selectedVersion = version), context(), { true }, 1000)
                assertNull(cache.load(context(), { true }, 1000))
            }
            val original = page()
            val largePlay = original.sessions.first().plays.first().copy(songName = "x".repeat(PerformanceSessionsCache.MAX_PAGE_BYTES))
            val large = original.copy(sessions = listOf(original.sessions.first().copy(plays = listOf(largePlay))))
            cache.save(large, context(), { true }, 1000)
            assertNull(cache.load(context(), { true }, 1000))
            cache.save(original.copy(sessions = original.sessions + original.sessions.first()), context(), { true }, 1000)
            assertNull(cache.load(context(), { true }, 1000))
        } finally { directory.deleteRecursively() }
    }

    @Test fun twoVersionRetentionAndInvalidGenerationAreBounded() = runTest {
        val directory = Files.createTempDirectory("sessions-cache-retention").toFile()
        try {
            val cache = PerformanceSessionsCache(directory)
            cache.save(page(), context(), { true }, 1000)
            cache.save(page().copy(selectedVersion = "phoenix"), context(version = PiuGameVersion.PHOENIX), { true }, 1000)
            assertEquals(2, directory.listFiles()!!.size)
            assertTrue(directory.listFiles()!!.sumOf { it.length() } <= PerformanceSessionsCache.MAX_TOTAL_BYTES)
            cache.save(page(), context(account = "b"), { true }, 1000)
            assertEquals(1, directory.listFiles()!!.size)
            cache.clear()
            cache.save(page(), context(), { false }, 1000)
            assertFalse(directory.exists())
        } finally { directory.deleteRecursively() }
    }

    @Test fun failedStorageIsBestEffort() = runTest {
        val file = Files.createTempFile("sessions-cache-blocked", ".tmp").toFile()
        try {
            val cache = PerformanceSessionsCache(file)
            cache.save(page(), context(), { true }, 1000)
            assertTrue(file.isFile)
            assertNull(cache.load(context(), { true }, 1000))
        } finally { file.delete() }
    }
}
