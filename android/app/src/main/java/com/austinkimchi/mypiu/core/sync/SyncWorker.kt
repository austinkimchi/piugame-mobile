package com.austinkimchi.mypiu.core.sync

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.austinkimchi.mypiu.MyPIUApplication
import com.austinkimchi.mypiu.core.network.PiuGameException
import kotlinx.coroutines.CancellationException

class SyncWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    override suspend fun doWork(): Result {
        val container = (applicationContext as MyPIUApplication).container
        val repository = container.repository
        return try {
            val snapshot = repository.sync()
            if (snapshot.isPiuConnected && snapshot.isMyPiuConnected) {
                Result.success()
            } else {
                container.scheduler.cancel()
                Result.failure()
            }
        } catch (_: PiuGameException.AuthenticationFailed) {
            container.scheduler.cancel()
            Result.failure()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            val sessionCleared = repository.clearUnauthorizedSession(error)
            if (sessionCleared) {
                container.scheduler.cancel()
                return Result.failure()
            }
            if (runAttemptCount < MAX_RETRIES) Result.retry() else Result.failure()
        }
    }

    private companion object {
        const val MAX_RETRIES = 3
    }
}
