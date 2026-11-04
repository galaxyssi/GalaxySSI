package com.galaxyssi.chat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf

internal object HealthOriginalExportScheduler {
    fun workName(id: String, dispatch: String) = "health-original-export:$id:$dispatch"
    fun terminal(states: List<androidx.work.WorkInfo.State>) = states.isNotEmpty() && states.all { it.isFinished }
    fun enqueue(context: Context, id: String) {
        val dispatch = HealthOriginalStore(context).use { HealthOriginalLibraryStore(context, it).session(id)?.dispatch }.orEmpty()
        require(java.util.UUID.fromString(dispatch).toString() == dispatch)
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(workName(id, dispatch), ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<HealthOriginalExportWorker>().setInputData(workDataOf("export_id" to id, "dispatch" to dispatch)).build())
    }
    fun recover(context: Context) = HealthOriginalStore(context).use { originals ->
        val library = HealthOriginalLibraryStore(context, originals); var after = ""
        do { val page = library.active(after); page.forEach { enqueue(context, it) }; after = if (page.size == 100) page.last() else "" } while (after.isNotEmpty())
    }
}
class HealthOriginalExportWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val id = inputData.getString("export_id") ?: return Result.failure()
        val dispatch = inputData.getString("dispatch") ?: return Result.failure()
        if (runCatching { java.util.UUID.fromString(id) }.isFailure) return Result.failure()
        val pending = HealthOriginalStore(applicationContext).use { HealthOriginalLibraryStore(applicationContext, it).session(id) }
        if (pending == null || pending.dispatch != dispatch || pending.state !in listOf(HealthOriginalExportState.QUEUED, HealthOriginalExportState.GENERATING)) return Result.success()
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("health-export", applicationContext.getString(R.string.health_library_export), NotificationManager.IMPORTANCE_LOW))
        val notification = NotificationCompat.Builder(applicationContext, "health-export").setSmallIcon(R.drawable.ic_rich_file)
            .setContentTitle(applicationContext.getString(R.string.health_library_generating)).setOngoing(true).setSilent(true).build()
        try { setForegroundAsync(ForegroundInfo((id.hashCode() and Int.MAX_VALUE).coerceAtLeast(1), notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)).get() }
        catch (_: Exception) { HealthOriginalStore(applicationContext).use { HealthOriginalLibraryStore(applicationContext, it).cannotStart(id, dispatch) }; return Result.failure() }
        return HealthOriginalStore(applicationContext).use { originals ->
            when (HealthOriginalArchive.generate(originals, HealthOriginalLibraryStore(applicationContext, originals), id, dispatch) { isStopped }) {
                HealthOriginalArchiveOutcome.COMPLETE -> Result.success()
                HealthOriginalArchiveOutcome.FAILED -> Result.failure()
                HealthOriginalArchiveOutcome.RETRY -> Result.retry()
            }
        }
    }
}
