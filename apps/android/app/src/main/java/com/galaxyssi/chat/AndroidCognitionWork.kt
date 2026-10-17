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
import androidx.work.BackoffPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.WorkInfo
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit
import java.util.UUID
import java.util.concurrent.Executors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.withLock

enum class AndroidCognitionWorkMode {
    EVENT,
    SCHEDULED,
    EXPLICIT,
    ATTENTION,
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
        AndroidCognitionWorkMode.ATTENTION -> AndroidCognitionWorkPlan(12, false, 0, false)
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
    private val attentionDispatch = Executors.newSingleThreadExecutor { Thread(it, "attention-wake-coalescer") }
    private val attentionWakeLock = Any()
    private var attentionWakePending = false
    private var attentionWakeActive = false

    fun requestAttention(context: Context, delayMillis: Long = 0L) {
        val app = context.applicationContext
        if (!GlobalAgentRepository(app).settings().enabled) return
        if (delayMillis > 0L) {
            enqueue(app, ATTENTION_TIMER, AndroidCognitionWorkMode.ATTENTION, delayMillis, ExistingWorkPolicy.REPLACE)
        } else requestAttentionWake(app)
    }

    private fun requestAttentionWake(app: Context) = synchronized(attentionWakeLock) {
        attentionWakePending = true
        if (attentionWakeActive) return@synchronized
        attentionWakeActive = true
        attentionDispatch.execute {
            while (true) {
                synchronized(attentionWakeLock) {
                    if (!attentionWakePending) { attentionWakeActive = false; return@execute }
                    attentionWakePending = false
                }
                // Keep at most one successor. A running worker may already have taken its snapshot.
                runCatching {
                    val pending = WorkManager.getInstance(app).getWorkInfosForUniqueWork(ATTENTION_WORK)
                        .get(10, TimeUnit.SECONDS).any {
                            it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.BLOCKED
                        }
                    if (!pending) enqueue(app, ATTENTION_WORK, AndroidCognitionWorkMode.ATTENTION, 0L,
                        ExistingWorkPolicy.APPEND_OR_REPLACE)?.result?.get(10, TimeUnit.SECONDS)
                }.onFailure {
                    Log.w("GalaxySSICognition", "attention_wake_deferred type=${it.javaClass.simpleName}")
                    requestAttention(app, 60_000L)
                }
            }
        }
    }

    internal fun requestScheduledNow(context: Context) = enqueue(context, SCHEDULED_NOW,
        AndroidCognitionWorkMode.SCHEDULED, 0L, ExistingWorkPolicy.KEEP)

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
        if (!runtime.settings().enabled) {
            cancelLearning(context)
            return
        }
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
    ): androidx.work.Operation? {
        if (!allowsWork(mode, GlobalAgentRepository(context).settings().enabled)) return null
        val request = buildRequest(mode, delayMillis, uniqueName == ATTENTION_TIMER || uniqueName == SCHEDULED_WORK)
        return WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(uniqueName, policy, request)
    }

    internal fun allowsWork(mode: AndroidCognitionWorkMode, learningEnabled: Boolean): Boolean =
        learningEnabled || mode == AndroidCognitionWorkMode.PROJECTION

    fun cancelLearning(context: Context) {
        synchronized(attentionWakeLock) { attentionWakePending = false }
        val manager = WorkManager.getInstance(context.applicationContext)
        learningWorkNames.forEach(manager::cancelUniqueWork)
    }

    internal val learningWorkNames get() = listOf(
        EVENT_WORK, ATTENTION_WORK, ATTENTION_TIMER, SCHEDULED_WORK, SCHEDULED_NOW, EXPLICIT_WORK
    )

    internal fun buildRequest(mode: AndroidCognitionWorkMode, delayMillis: Long, timer: Boolean) =
        OneTimeWorkRequestBuilder<AndroidCognitionWorker>()
            .setInputData(workDataOf(KEY_MODE to mode.name,
                KEY_TIMER to timer,
                KEY_RESUME_TOKEN to if (mode == AndroidCognitionWorkMode.EXPLICIT) UUID.randomUUID().toString() else ""))
            .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(WORK_TAG)
            .build()

    internal const val KEY_MODE = "mode"
    internal const val KEY_RESUME_TOKEN = "resume_token"
    internal const val KEY_TIMER = "timer_only"
    private const val EVENT_WORK = "galaxyssi-cognition-event-v1"
    private const val ATTENTION_WORK = "galaxyssi-attention-continuation-v1"
    private const val ATTENTION_TIMER = "galaxyssi-attention-retry-v1"
    private const val SCHEDULED_WORK = "galaxyssi-cognition-scheduled-v1"
    private const val SCHEDULED_NOW = "galaxyssi-cognition-scheduled-now-v1"
    private const val EXPLICIT_WORK = "galaxyssi-cognition-explicit-v1"
    private const val PROJECTION_WORK = "galaxyssi-obsidian-projection-v1"
    private const val WORK_TAG = "galaxyssi-cognition"
}

class AndroidCognitionWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val mode = runCatching {
            AndroidCognitionWorkMode.valueOf(inputData.getString(AndroidCognitionScheduler.KEY_MODE).orEmpty())
        }.getOrDefault(AndroidCognitionWorkMode.SCHEDULED)
        if (!AndroidCognitionScheduler.allowsWork(mode, GlobalAgentRepository(applicationContext).settings().enabled)) {
            Log.i(LOG_TAG, "run_skipped mode=$mode reason=background_disabled")
            return Result.success()
        }
        if (inputData.getBoolean(AndroidCognitionScheduler.KEY_TIMER, false)) {
            if (inputData.getString(AndroidCognitionScheduler.KEY_MODE) == AndroidCognitionWorkMode.ATTENTION.name)
                AndroidCognitionScheduler.requestAttention(applicationContext)
            else AndroidCognitionScheduler.requestScheduledNow(applicationContext)
            return Result.success()
        }
        return AndroidCognitionRecovery.execution.withLock { executeOnce() }
    }

    private suspend fun executeOnce(): Result {
        val startedAt = SystemClock.elapsedRealtime()
        val mode = runCatching {
            AndroidCognitionWorkMode.valueOf(inputData.getString(AndroidCognitionScheduler.KEY_MODE).orEmpty())
        }.getOrDefault(AndroidCognitionWorkMode.SCHEDULED)
        // Collection has its own network-constrained worker, even when learning is paused by a budget or recovery gate.
        if (mode in setOf(AndroidCognitionWorkMode.SCHEDULED, AndroidCognitionWorkMode.EXPLICIT))
            ProactiveAttentionFeedScheduler.request(applicationContext)
        if (mode != AndroidCognitionWorkMode.EXPLICIT && mode != AndroidCognitionWorkMode.PROJECTION) {
            val load = BackgroundLearningLoadSampler.read(applicationContext)
            if (load.deferMillis > 0) {
                // Pending events/results remain durable; this is neither a failure nor a model retry.
                if (mode == AndroidCognitionWorkMode.ATTENTION)
                    AndroidCognitionScheduler.requestAttention(applicationContext, load.deferMillis)
                else AndroidCognitionScheduler.scheduleAt(applicationContext, System.currentTimeMillis() + load.deferMillis)
                Log.i(LOG_TAG, "run_deferred mode=$mode reason=device_load delay_ms=${load.deferMillis}")
                return Result.success()
            }
        }
        val recovery = AndroidCognitionRecovery(applicationContext)
        if (mode == AndroidCognitionWorkMode.EXPLICIT) {
            recovery.resumeOnce(inputData.getString(AndroidCognitionScheduler.KEY_RESUME_TOKEN).orEmpty())
        }
        val saved = recovery.state(mode)
        if (saved.stopped) {
            AndroidCognitionRecovery.reportStopped(applicationContext, mode, saved)
            return Result.failure()
        }
        if (!recovery.mayAttempt(mode)) return Result.retry()
        if (mode == AndroidCognitionWorkMode.EXPLICIT || mode == AndroidCognitionWorkMode.PROJECTION) {
            setForeground(foregroundInfo())
        }
        return try {
            val runtime = GlobalSuperAgentRuntime.get(applicationContext)
            val backgroundEnabled = runtime.settings().enabled
            if (!backgroundEnabled && mode != AndroidCognitionWorkMode.PROJECTION) {
                Log.i(LOG_TAG, "run_skipped mode=$mode reason=background_disabled elapsed_ms=${elapsed(startedAt)}")
                return Result.success()
            }
            val explicit = mode == AndroidCognitionWorkMode.EXPLICIT
            val plan = AndroidCognitionSchedulePolicy.workPlan(mode)
            var projection = ObsidianProjectionResult(configured = false)
            if (plan.eventLimit > 0) runtime.processPending(plan.eventLimit)
            if (mode == AndroidCognitionWorkMode.ATTENTION) {
                ProactiveAttentionCoordinator(applicationContext).reconcile()
                val result = runtime.executeResearchCycle(attentionOnly = true)
                val tasks = runtime.researchTasks().filter(ProactiveAttentionPolicy::isAttention)
                val next = GlobalResearchClaimCoordinator.attentionNextWake(tasks)
                if (next != null) AndroidCognitionScheduler.requestAttention(applicationContext,
                    (next - System.currentTimeMillis()).coerceAtLeast(
                        if (result == null && tasks.none { it.status == GlobalResearchTaskStatus.RUNNING })
                            AndroidCognitionSchedulePolicy.MIN_DELAY_MILLIS else 15_000L))
            }
            if (plan.runBatchCognition) {
                runtime.processLongHorizonCycle()
                runtime.processProactiveDiscoveryCycle(force = explicit)
                repeat(plan.cycleCount) {
                    runtime.executeCognitionCycle(explicitUserOverride = explicit)
                    runtime.executeAutonomousCycle(explicitUserOverride = explicit)
                    runtime.executeResearchCycle(explicitUserOverride = explicit)
                }
                runtime.processPending(plan.eventLimit)
            }
            if (mode != AndroidCognitionWorkMode.PROJECTION) deliverInsights(runtime)
            if (plan.projectKnowledge) {
                projection = ObsidianAndroidBridge.projectIncrementally(
                    applicationContext,
                    maximumWrites = if (mode == AndroidCognitionWorkMode.PROJECTION) 32 else 12
                )
                check(projection.error.isBlank()) { "Obsidian projection failed: ${projection.error}" }
                if (projection.remainingCount > 0) {
                    AndroidCognitionScheduler.requestObsidianProjection(applicationContext)
                }
            }
            // Incoming progress must not postpone the scheduled research worker indefinitely.
            if (backgroundEnabled && mode !in setOf(AndroidCognitionWorkMode.EVENT, AndroidCognitionWorkMode.ATTENTION)) {
                AndroidCognitionScheduler.scheduleDynamic(applicationContext, runtime)
            }
            recovery.succeeded(mode)
            Log.i(
                LOG_TAG,
                "run_complete mode=$mode elapsed_ms=${elapsed(startedAt)} " +
                    "projection_configured=${projection.configured} projection_written=${projection.writtenCount} " +
                    "projection_unchanged=${projection.unchangedCount} " +
                    "projection_candidates=${projection.candidateCount} projection_remaining=${projection.remainingCount}"
            )
            Result.success()
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            val failure = recovery.failed(mode, error)
            Log.w(
                LOG_TAG,
                "${if (failure.stopped) "run_stopped" else "run_retry"} mode=$mode elapsed_ms=${elapsed(startedAt)} " +
                    "failures=${failure.failures} error=${error.javaClass.simpleName} reason=${failure.reason}"
            )
            if (failure.stopped) {
                AndroidCognitionRecovery.reportStopped(applicationContext, mode, failure)
                Result.failure()
            } else {
                // WorkManager is the only retry scheduler. Do not replace the currently running work.
                Result.retry()
            }
        }
    }

    private fun elapsed(startedAt: Long): Long =
        (SystemClock.elapsedRealtime() - startedAt).coerceAtLeast(0L)

    private fun deliverInsights(runtime: GlobalSuperAgentRuntime) {
        val delivered = (runtime.deliverPending(AgentTranscriptStore(applicationContext)) + runtime.unnotifiedDeliveredMessages()).distinctBy { it.id }
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
    private const val ATTENTION_NOTIFICATION_ID = 0x534103
    private const val CHANNEL_ID = "galaxyssi_cognition"
    private const val ATTENTION_CHANNEL_ID = "galaxyssi_attention_findings_v1"

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
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return false
        if (candidate.attention) manager.createNotificationChannel(NotificationChannel(
            ATTENTION_CHANNEL_ID, context.getString(R.string.attention_notification_channel), NotificationManager.IMPORTANCE_HIGH
        ))
        val channel = if (candidate.attention) ATTENTION_CHANNEL_ID else CHANNEL_ID
        val notificationId = if (candidate.attention) ATTENTION_NOTIFICATION_ID else INSIGHT_NOTIFICATION_ID
        if (manager.getNotificationChannel(channel)?.importance == NotificationManager.IMPORTANCE_NONE) return false
        val openIntent = Intent(context, if (candidate.attention && candidate.conversationId.isBlank())
            ProactiveAttentionActivity::class.java else MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("galaxyssi_open_agent", true)
            putExtra("galaxyssi_agent_conversation_id", candidate.conversationId)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_tab_chat_filled)
            .setContentTitle(candidate.title)
            .setContentText(candidate.content)
            .setStyle(Notification.BigTextStyle().bigText(candidate.content))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setGroup(if (candidate.attention) "galaxyssi_attention" else "galaxyssi_cognition")
            .build()
        context.getSystemService(NotificationManager::class.java)
            .notify(notificationId, notification)
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
