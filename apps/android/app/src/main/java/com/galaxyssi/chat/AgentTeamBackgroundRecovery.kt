package com.galaxyssi.chat

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException

/** A managed reply may arrive without any Activity having initialized the team controller. */
internal object AgentTeamBackgroundRecovery {
    fun enqueue(context: Context) = WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
        "galaxyssi-team-recovery-v1", ExistingWorkPolicy.KEEP,
        OneTimeWorkRequestBuilder<AgentTeamBackgroundRecoveryWorker>()
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)
            .build()
    )
}

class AgentTeamBackgroundRecoveryWorker(context: Context, parameters: WorkerParameters) :
    CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result = try {
        if (EncryptedAgentTeamExecutionStore(applicationContext).snapshots().isNotEmpty()) {
            GlobalSuperAgentRuntime.get(applicationContext).reconcileAgentTeams()
        }
        Result.success()
    } catch (error: Exception) {
        if (error is CancellationException) throw error
        android.util.Log.w("GalaxySSICollaboration", "Background team recovery will retry", error)
        Result.retry()
    }
}
