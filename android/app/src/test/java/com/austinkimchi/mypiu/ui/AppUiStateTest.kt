package com.austinkimchi.mypiu.ui

import com.austinkimchi.mypiu.core.model.MyPiuSyncResult
import com.austinkimchi.mypiu.core.sync.RepositorySnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class AppUiStateTest {
    @Test
    fun eachSuccessfulUploadAdvancesPerformanceRevision() {
        val withoutUpload = RepositorySnapshot(
            account = null,
            piuSnapshot = null,
            syncResult = null,
            isPiuConnected = true,
            isMyPiuConnected = true,
        )
        val withUpload = withoutUpload.copy(
            syncResult = MyPiuSyncResult(
                accepted = true,
                importedRecentPlays = 1,
                duplicateRecentPlays = 2,
                syncCursor = "cursor",
                duplicateRequest = false,
            ),
        )

        val unchanged = AppUiState().applying(withoutUpload)
        val firstUpload = unchanged.applying(withUpload)
        val secondUpload = firstUpload.applying(withUpload)

        assertEquals(0L, unchanged.performanceRevision)
        assertEquals(1L, firstUpload.performanceRevision)
        assertEquals(2L, secondUpload.performanceRevision)
    }
}
