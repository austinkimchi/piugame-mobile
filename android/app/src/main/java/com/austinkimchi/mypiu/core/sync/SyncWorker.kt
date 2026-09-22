package com.austinkimchi.mypiu.core.sync

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.austinkimchi.mypiu.MyPIUApplication
import com.austinkimchi.mypiu.core.network.PiuGameException

class SyncWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    override suspend fun doWork(): Result {
        val repository = (applicationContext as MyPIUApplication).container.repository
        return try {
            val snapshot = repository.sync()
            if (snapshot.isPiuConnected) Result.success() else Result.failure()
        } catch (_: PiuGameException.AuthenticationFailed) {
            Result.failure()
        } catch (error: Throwable) {
            val sessionCleared = repository.clearUnauthorizedSession(error)
            if (sessionCleared) return Result.failure()
            if (runAttemptCount < MAX_RETRIES) Result.retry() else Result.failure()
        }
    }

    private companion object {
        const val MAX_RETRIES = 3
    }
}
