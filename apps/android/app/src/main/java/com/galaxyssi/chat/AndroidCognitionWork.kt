package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

enum class AndroidCognitionWorkMode {
    EVENT,
    SCHEDULED,
    EXPLICIT,
    PROJECTION
}

data class AndroidCognitionWorkPlan(
    val eventLimit: Int,
    val runBatchCognition: Boolean,
    val cycleCount: Int,
    val projectKnowledge: Boolean
)

object AndroidCognitionSchedulePolicy {
    fun workPlan(mode: AndroidCognitionWorkMode): AndroidCognitionWorkPlan = when (mode) {
        AndroidCognitionWorkMode.EVENT -> AndroidCognitionWorkPlan(12, false, 0, false)
        AndroidCognitionWorkMode.SCHEDULED -> AndroidCognitionWorkPlan(48, true, 1, true)
        AndroidCognitionWorkMode.EXPLICIT -> AndroidCognitionWorkPlan(200, true, 2, true)
        AndroidCognitionWorkMode.PROJECTION -> AndroidCognitionWorkPlan(0, false, 0, true)
    }

    fun nextExplorationDelayMillis(
        pendingEvents: Int,
        activeCognition: Int,
        activeResearch: Int,
        pendingInsights: Int
    ): Long = when {
        pendingEvents > 0 || activeCognition > 0 || activeResearch > 0 -> MIN_DELAY_MILLIS
        pendingInsights > 0 -> 30L * 60L * 1_000L
        else -> MAX_DELAY_MILLIS
    }

    const val MIN_DELAY_MILLIS = 10L * 60L * 1_000L
    const val MAX_DELAY_MILLIS = 4L * 60L * 60L * 1_000L
}

object AndroidCognitionScheduler {
    fun requestImmediate(context: Context, explicit: Boolean = false) {
        enqueue(
            context = context,
            uniqueName = if (explicit) EXPLICIT_WORK else EVENT_WORK,
            mode = if (explicit) AndroidCognitionWorkMode.EXPLICIT else AndroidCognitionWorkMode.EVENT,
            delayMillis = 0L,
            policy = if (explicit) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP
        )
    }

    fun scheduleAt(context: Context, triggerAtMillis: Long) {
        if (triggerAtMillis <= 0L) {
            WorkManager.getInstance(context.applicationContext).cancelUniqueWork(SCHEDULED_WORK)
            return
        }
        enqueue(
            context = context,
            uniqueName = SCHEDULED_WORK,
            mode = AndroidCognitionWorkMode.SCHEDULED,
            delayMillis = (triggerAtMillis - System.currentTimeMillis()).coerceAtLeast(0L),
            policy = ExistingWorkPolicy.REPLACE
        )
    }

    fun requestObsidianProjection(context: Context) {
        enqueue(
            context = context,
            uniqueName = PROJECTION_WORK,
            mode = AndroidCognitionWorkMode.PROJECTION,
            delayMillis = 0L,
            policy = ExistingWorkPolicy.APPEND_OR_REPLACE
        )
    }

    fun scheduleDynamic(context: Context, runtime: GlobalSuperAgentRuntime) {
        val continuity = runtime.continuitySnapshot()
        val dashboard = runtime.dashboard()
        val activeResearch = runtime.researchTasks().count { task ->
            task.status in setOf(
                GlobalResearchTaskStatus.QUEUED,
                GlobalResearchTaskStatus.RUNNING,
                GlobalResearchTaskStatus.SCHEDULED,
                GlobalResearchTaskStatus.WAITING_FOR_RESOURCE
            )
        }
        val delay = AndroidCognitionSchedulePolicy.nextExplorationDelayMillis(
            pendingEvents = continuity.pendingEventCount,
            activeCognition = dashboard.queuedCognitionCount,
            activeResearch = activeResearch,
            pendingInsights = dashboard.pendingInsightCount
        )
        scheduleAt(context, System.currentTimeMillis() + delay)
    }

    private fun enqueue(
        context: Context,
        uniqueName: String,
        mode: AndroidCognitionWorkMode,
        delayMillis: Long,
        policy: ExistingWorkPolicy
    ) {
        val request = OneTimeWorkRequestBuilder<AndroidCognitionWorker>()
            .setInputData(workDataOf(KEY_MODE to mode.name))
            .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
            .addTag(WORK_TAG)
            .build()
        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(uniqueName, policy, request)
    }

    internal const val KEY_MODE = "mode"
    private const val EVENT_WORK = "galaxyssi-cognition-event-v1"
    private const val SCHEDULED_WORK = "galaxyssi-cognition-scheduled-v1"
    private const val EXPLICIT_WORK = "galaxyssi-cognition-explicit-v1"
    private const val PROJECTION_WORK = "galaxyssi-obsidian-projection-v1"
    private const val WORK_TAG = "galaxyssi-cognition"
}

class AndroidCognitionWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val startedAt = SystemClock.elapsedRealtime()
        val mode = runCatching {
            AndroidCognitionWorkMode.valueOf(inputData.getString(AndroidCognitionScheduler.KEY_MODE).orEmpty())
        }.getOrDefault(AndroidCognitionWorkMode.SCHEDULED)
        if (mode == AndroidCognitionWorkMode.EXPLICIT || mode == AndroidCognitionWorkMode.PROJECTION) {
            setForeground(foregroundInfo())
        }
        val runtime = GlobalSuperAgentRuntime.get(applicationContext)
        val backgroundEnabled = runtime.settings().enabled
        if (!backgroundEnabled && mode != AndroidCognitionWorkMode.PROJECTION) {
            Log.i(LOG_TAG, "run_skipped mode=$mode reason=background_disabled elapsed_ms=${elapsed(startedAt)}")
            return Result.success()
        }
        return runCatching {
            val explicit = mode == AndroidCognitionWorkMode.EXPLICIT
            val plan = AndroidCognitionSchedulePolicy.workPlan(mode)
            var projection = ObsidianProjectionResult(configured = false)
            if (plan.eventLimit > 0) runtime.processPending(plan.eventLimit)
            if (plan.runBatchCognition) {
                runtime.processLongHorizonCycle()
                runtime.processProactiveDiscoveryCycle(force = explicit)
                repeat(plan.cycleCount) {
                    runtime.executeCognitionCycle(explicitUserOverride = explicit)
                    runtime.executeAutonomousCycle(explicitUserOverride = explicit)
                    runtime.executeResearchCycle(explicitUserOverride = explicit)
                }
                runtime.processPending(plan.eventLimit)
                deliverInsights(runtime)
            }
            if (plan.projectKnowledge) {
                projection = ObsidianAndroidBridge.projectIncrementally(
                    applicationContext,
                    maximumWrites = if (mode == AndroidCognitionWorkMode.PROJECTION) 32 else 12
                )
                if (projection.remainingCount > 0) {
                    AndroidCognitionScheduler.requestObsidianProjection(applicationContext)
                }
            }
            if (backgroundEnabled) AndroidCognitionScheduler.scheduleDynamic(applicationContext, runtime)
            Log.i(
                LOG_TAG,
                "run_complete mode=$mode elapsed_ms=${elapsed(startedAt)} " +
                    "projection_configured=${projection.configured} projection_written=${projection.writtenCount} " +
                    "projection_unchanged=${projection.unchangedCount} " +
                    "projection_candidates=${projection.candidateCount} projection_remaining=${projection.remainingCount}"
            )
            Result.success()
        }.getOrElse { error ->
            Log.w(
                LOG_TAG,
                "run_retry mode=$mode elapsed_ms=${elapsed(startedAt)} " +
                    "error=${error.javaClass.simpleName} message=${error.message.orEmpty().take(240)}",
                error
            )
            if (mode != AndroidCognitionWorkMode.PROJECTION) {
                AndroidCognitionScheduler.scheduleAt(
                    applicationContext,
                    System.currentTimeMillis() + AndroidCognitionSchedulePolicy.MIN_DELAY_MILLIS
                )
            }
            Result.retry()
        }
    }

    private fun elapsed(startedAt: Long): Long =
        (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(0L)

    private fun deliverInsights(runtime: GlobalSuperAgentRuntime) {
        val delivered = runtime.deliverPending(AgentTranscriptStore(applicationContext))
        if (delivered.isEmpty()) return
        val candidate = runtime.notificationCandidateForDelivered(delivered) ?: return
        if (!AndroidCognitionNotificationCenter.notify(applicationContext, candidate)) return
        runtime.markNotified(candidate.messageIds)
    }

    private fun foregroundInfo(): ForegroundInfo {
        val notification = AndroidCognitionNotificationCenter.workingNotification(applicationContext)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                AndroidCognitionNotificationCenter.WORK_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            ForegroundInfo(AndroidCognitionNotificationCenter.WORK_NOTIFICATION_ID, notification)
        }
    }

    private companion object {
        const val LOG_TAG = "GalaxySSICognition"
    }
}

object AndroidCognitionNotificationCenter {
    const val WORK_NOTIFICATION_ID = 0x534101
    private const val INSIGHT_NOTIFICATION_ID = 0x534102
    private const val CHANNEL_ID = "galaxyssi_cognition"

    fun workingNotification(context: Context): Notification {
        ensureChannel(context)
        return Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_tab_chat_filled)
            .setContentTitle(context.getString(R.string.cc_global_agent_title))
            .setContentText(context.getString(R.string.cc_global_process_now_subtitle))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    fun notify(context: Context, candidate: GlobalAgentNotificationCandidate): Boolean = runCatching {
        ensureChannel(context)
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("galaxyssi_open_agent", true)
            putExtra("galaxyssi_agent_conversation_id", candidate.conversationId)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            INSIGHT_NOTIFICATION_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_tab_chat_filled)
            .setContentTitle(candidate.title)
            .setContentText(candidate.content)
            .setStyle(Notification.BigTextStyle().bigText(candidate.content))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(INSIGHT_NOTIFICATION_ID, notification)
        true
    }.getOrDefault(false)

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.cc_global_agent_title),
                NotificationManager.IMPORTANCE_DEFAULT
            )
        )
    }
}
