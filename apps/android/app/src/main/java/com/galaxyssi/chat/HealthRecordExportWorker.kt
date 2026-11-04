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

internal object HealthRecordExportScheduler {
    fun workName(s: HealthRecordExportSession) = "health-record-export:${s.phase}:${s.id}:${s.dispatch}"
    fun enqueue(context: Context, session: HealthRecordExportSession) = WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(workName(session), ExistingWorkPolicy.KEEP,
        OneTimeWorkRequestBuilder<HealthRecordExportWorker>().setInputData(workDataOf("export_id" to session.id, "dispatch" to session.dispatch, "phase" to session.phase)).build())
    fun recover(context: Context) {
        if (!context.getDatabasePath("health_record_exports_v1.db").exists()) return
        HealthRecordExportStore(context).use { exports ->
            var after = ""
            do { val page = exports.active(after); page.forEach { enqueue(context, it) }; after = if (page.size == 100) page.last().id else "" } while (after.isNotEmpty())
        }
    }
}
internal object HealthExportForeground {
    fun info(context: Context, id: String, title: Int): ForegroundInfo {
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel("health-export", context.getString(R.string.health_export_channel), NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
        val notification = NotificationCompat.Builder(context, "health-export").setSmallIcon(R.drawable.ic_rich_file).setContentTitle(context.getString(title))
            .setOngoing(true).setSilent(true).setLocalOnly(true).setVisibility(NotificationCompat.VISIBILITY_PRIVATE).build()
        return ForegroundInfo((id.hashCode() and Int.MAX_VALUE).coerceAtLeast(1), notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    }
}
class HealthRecordExportWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val id = inputData.getString("export_id") ?: return Result.failure(); val dispatch = inputData.getString("dispatch") ?: return Result.failure()
        val phase = inputData.getString("phase") ?: return Result.failure()
        return HealthRecordExportStore(applicationContext).use { exports ->
            val session = runCatching { exports.session(id) }.getOrNull() ?: return@use Result.failure()
            if (session.dispatch != dispatch || session.phase != phase || session.state !in listOf(HealthRecordExportState.PREPARING, HealthRecordExportState.QUEUED, HealthRecordExportState.GENERATING)) return@use Result.success()
            try { setForegroundAsync(HealthExportForeground.info(applicationContext, id, if (phase == "prepare") R.string.health_export_preparing else R.string.health_export_generating)).get() }
            catch (_: Exception) { exports.externalFailure(id, dispatch, "background_unavailable"); return@use Result.failure() }
            val outcome = if (phase == "prepare") HealthRecordStore(applicationContext).use { records -> HealthOriginalStore(applicationContext).use { originals ->
                HealthRecordExportPipeline.prepare(records, originals, exports, id, dispatch) { isStopped }
            } } else if (session.scope.bundlesOriginals) HealthOriginalStore(applicationContext).use { originals ->
                HealthRecordExportPipeline.generate(exports, id, dispatch, { isStopped }, originals = originals)
            } else HealthRecordExportPipeline.generate(exports, id, dispatch, { isStopped })
            when (outcome) { HealthOriginalArchiveOutcome.COMPLETE -> Result.success(); HealthOriginalArchiveOutcome.FAILED -> Result.failure(); HealthOriginalArchiveOutcome.RETRY -> Result.retry() }
        }
    }
}
