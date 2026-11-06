package com.galaxyssi.chat

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.TimeUnit

internal object HealthReminderWork {
    private const val WORK = "health-reminder-reconcile"
    private const val CHANNEL = "health_record_reminders"
    private const val TAG = "health-record-reminder:"
    private const val SLEEP_TAG = "health-sleep-change:"
    private const val REPORT_TAG = "health-report-review:"
    private const val SYNC_TAG = "health-sync-incident:"
    private const val ID = 1
    @Volatile private var sleepEnabled: Boolean? = null

    fun enqueue(context: Context) = WorkManager.getInstance(context).enqueueUniqueWork(
        WORK, ExistingWorkPolicy.APPEND_OR_REPLACE, OneTimeWorkRequestBuilder<HealthReminderWorker>().build())

    fun sleepRecordsChanged(context: Context) {
        if (!context.getDatabasePath(HealthReminderStore.DEFAULT_DB).exists() || sleepEnabled == false) return
        runCatching {
            val enabled = sleepEnabled ?: HealthReminderStore(context.applicationContext).use { it.settings().sleepChanges }.also { sleepEnabled = it }
            if (enabled) WorkManager.getInstance(context).enqueueUniqueWork("$WORK-sleep", ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<HealthReminderWorker>().setInitialDelay(1, TimeUnit.SECONDS).build())
        }.onFailure { android.util.Log.w("HealthReminder", "Sleep reconciliation enqueue failed: ${it.javaClass.simpleName}") }
    }

    fun reportReady(context: Context, id: String) {
        if (!context.getDatabasePath(HealthReminderStore.DEFAULT_DB).exists()) return
        val waiting = HealthReminderStore(context).use { it.admitReportNotice(id, System.currentTimeMillis()) }
        if (waiting) enqueue(context).result.get(10, TimeUnit.SECONDS)
    }

    fun sourceRemindersChanged(context: Context) {
        if (context.getDatabasePath(HealthReminderStore.DEFAULT_DB).exists()) {
            runCatching { enqueue(context) }.onFailure {
                android.util.Log.w("HealthReminder", "Source reminder enqueue failed: ${it.javaClass.simpleName}")
            }
        }
    }

    private fun alarm(context: Context) = PendingIntent.getBroadcast(context, 0, Intent(context, HealthReminderReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun systemAllowed(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager.areNotificationsEnabled() && manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun syncDeliveryEnabled(context: Context): Boolean {
        if (!context.getDatabasePath(HealthReminderStore.DEFAULT_DB).exists()) return false
        return runCatching {
            HealthReminderStore(context).use { it.settings().notifications } && systemAllowed(context)
        }.getOrDefault(false)
    }

    @Synchronized fun save(context: Context, store: HealthReminderStore, candidate: HealthReminderSettings, live: Boolean) {
        if (live) enqueue(context)
        store.save(candidate, System.currentTimeMillis())
        if (live) sleepEnabled = candidate.sleepChanges
        refresh(context, store, live)
    }

    @Synchronized fun actSleep(context: Context, store: HealthReminderStore, alert: HealthSleepAlert, action: HealthReminderAction, live: Boolean) {
        if (live) {
            if (!refresh(context, store, true)) throw HealthReminderConflict()
            enqueue(context)
        }
        store.actSleep(alert, action, System.currentTimeMillis())
        if (live && action == HealthReminderAction.DISABLE) sleepEnabled = false
        refresh(context, store, live)
    }

    @Synchronized fun act(context: Context, store: HealthReminderStore, event: HealthReminderOccurrence, action: HealthReminderAction, live: Boolean) {
        if (live) enqueue(context)
        store.act(event.day, event.revision, action, System.currentTimeMillis())
        refresh(context, store, live)
    }

    @Synchronized fun refresh(context: Context, store: HealthReminderStore, live: Boolean): Boolean {
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        store.reconcile(now, zone)
        if (!live) return false
        val settings = store.settings()
        sleepEnabled = settings.sleepChanges
        val sleepAllowed = runCatching { HealthSleepAlertEngine.evaluate(context, store, now, zone) }
            .onFailure { android.util.Log.w("HealthReminder", "Sleep evaluation failed: ${it.javaClass.simpleName}") }.getOrDefault(false)
        val sleep = if (sleepAllowed && settings.sleepChanges) store.activeSleep() else null
        val alerts = context.getSystemService(NotificationManager::class.java)
        val scheduler = context.getSystemService(AlarmManager::class.java)
        val nextDaily = HealthReminderPolicy.nextDaily(settings, now, zone)
        val nextSnooze = store.nextSnooze()
        val systemAllowed = systemAllowed(context)
        val dailyVisible = alerts.activeNotifications.mapNotNull { notice ->
            val tag = notice.tag?.takeIf { it.startsWith(TAG) } ?: return@mapNotNull null
            val day = runCatching { LocalDate.parse(tag.removePrefix(TAG)) }.getOrNull() ?: return@mapNotNull null
            day to (notice.notification.visibility == Notification.VISIBILITY_PRIVATE)
        }.toMap()
        val dailyDelivery = HealthRoutineNotificationDelivery.daily(store, settings, now, zone, systemAllowed, dailyVisible,
            post = { event ->
                try { notify(context, alerts, event, settings); true } catch (_: SecurityException) { false }
            }, cancel = { day -> alerts.cancel(TAG + day, ID) })
        val sleepDelivery = HealthRoutineNotificationDelivery.sleep(store, sleep, settings, now, zone, systemAllowed,
            activeSourceNotices(alerts, SLEEP_TAG), post = { event ->
                val intent = Intent(context, HealthReminderActivity::class.java).putExtra("health_sleep_alert_id", event.id)
                    .setData(android.net.Uri.parse("galaxyssi://health/sleep/${event.id}"))
                postSourceNotice(context, alerts, SLEEP_TAG + event.id, intent, R.string.health_sleep_alert_title, settings)
            }, cancel = { id -> alerts.cancel(SLEEP_TAG + id, ID) })
        val sleepWake = sleep?.resumeAt?.takeIf { sleep.state == HealthReminderState.SNOOZED && it > now }
        val nextSleepDay = if (settings.sleepChanges) HealthReminderPolicy.day(now, zone).plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli() else null
        val reportNext = runCatching { reconcileReports(context, store, settings, alerts, now, zone) }
            .onFailure { android.util.Log.w("HealthReminder", "Report reconciliation failed: ${it.javaClass.simpleName}") }
            .getOrNull()
        val syncNext = runCatching { reconcileSync(context, settings, alerts, now, zone) }
            .onFailure { android.util.Log.w("HealthReminder", "Sync reconciliation failed: ${it.javaClass.simpleName}") }
            .getOrNull()
        val next = listOfNotNull(nextDaily, nextSnooze, dailyDelivery, sleepWake, sleepDelivery, nextSleepDay, reportNext, syncNext).minOrNull()
        if (next == null) scheduler.cancel(alarm(context))
        else scheduler.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, alarm(context))
        return sleepAllowed
    }

    private fun reconcileReports(context: Context, store: HealthReminderStore, settings: HealthReminderSettings,
        manager: NotificationManager, now: Long, zone: ZoneId): Long? {
        val visible = activeSourceNotices(manager, REPORT_TAG)
        val repository = HealthReportReviewRepository(context, HealthOverviewDatabases())
        return HealthReportNotificationDelivery.reconcile(store, settings, now, zone, systemAllowed(context), visible,
            lookup = { repository.byId(store, it) }, post = { report ->
                postSourceNotice(context, manager, REPORT_TAG + report.id, report.intent(context)
                    .setData(android.net.Uri.parse("galaxyssi://health/report-review/${report.id}")),
                    R.string.health_report_review_notice, settings)
            }, cancel = { manager.cancel(REPORT_TAG + it, ID) })
    }

    private fun reconcileSync(context: Context, settings: HealthReminderSettings, manager: NotificationManager,
        now: Long, zone: ZoneId): Long? {
        val visible = activeSourceNotices(manager, SYNC_TAG)
        if (!context.getDatabasePath(HealthRecordStore.DEFAULT_DB).exists()) {
            visible.keys.forEach { manager.cancel(SYNC_TAG + it, ID) }
            return null
        }
        return HealthRecordStore(context).use { records ->
            HealthSyncNotificationDelivery.reconcile(records, settings, HealthConnectSettings.selection(context),
                now, zone, systemAllowed(context), visible,
                post = { postSourceNotice(context, manager, SYNC_TAG + it.id, it.intent(context), R.string.health_sync_reminder_notice, settings) },
                cancel = { manager.cancel(SYNC_TAG + it, ID) })
        }
    }

    private fun activeSourceNotices(manager: NotificationManager, prefix: String): Map<String, Boolean> =
        manager.activeNotifications.mapNotNull {
            val tag = it.tag ?: return@mapNotNull null
            if (!tag.startsWith(prefix)) return@mapNotNull null
            val id = tag.removePrefix(prefix)
            if (!HealthProfilePolicy.uuid(id)) return@mapNotNull null
            id to (it.notification.visibility == Notification.VISIBILITY_PRIVATE)
        }.toMap()

    private fun postSourceNotice(context: Context, manager: NotificationManager, tag: String, intent: Intent, title: Int,
        settings: HealthReminderSettings): Boolean = try {
        post(context, manager, tag, intent, 0, title, settings)
        true
    } catch (_: SecurityException) { false }

    private fun visibility(settings: HealthReminderSettings) =
        if (settings.hideOnLock) Notification.VISIBILITY_PRIVATE else Notification.VISIBILITY_PUBLIC

    private fun notify(context: Context, manager: NotificationManager, event: HealthReminderOccurrence, settings: HealthReminderSettings) {
        val intent = Intent(context, HealthReminderActivity::class.java).putExtra("health_reminder_day", event.day.toString())
        post(context, manager, TAG + event.day, intent, event.day.toEpochDay().toInt(), event.target.titleResource(), settings)
    }

    private fun post(context: Context, manager: NotificationManager, tag: String, intent: Intent, requestCode: Int, title: Int, settings: HealthReminderSettings) {
        manager.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.health_reminder_channel), NotificationManager.IMPORTANCE_DEFAULT))
        manager.notify(tag, ID, notification(context, intent, requestCode, title, settings))
    }

    internal fun notification(context: Context, intent: Intent, requestCode: Int, title: Int, settings: HealthReminderSettings): Notification {
        val open = PendingIntent.getActivity(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun base() = Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_settings_notification)
            .setContentTitle(context.getString(R.string.health_reminder_generic)).setContentIntent(open)
            .setAutoCancel(true).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_REMINDER)
        val public = base().setVisibility(Notification.VISIBILITY_PUBLIC).build()
        return base().setContentText(context.getString(title)).setVisibility(visibility(settings)).setPublicVersion(public).build()
    }

    fun openSystemSettings(context: Context) = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)

    fun requestPermission(activity: HealthReminderActivity) {
        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 60)
        } else activity.startActivity(openSystemSettings(activity))
    }
}

class HealthReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!context.getDatabasePath(HealthReminderStore.DEFAULT_DB).exists()) return
        val result = goAsync()
        try {
            HealthReminderWork.enqueue(context.applicationContext).result.addListener({ result.finish() }, java.util.concurrent.Executor { it.run() })
        } catch (e: RuntimeException) {
            result.finish()
            android.util.Log.w("HealthReminder", "Unable to enqueue reconciliation", e)
        }
    }
}

class HealthReminderWorker(context: Context, parameters: WorkerParameters) : Worker(context, parameters) {
    override fun doWork(): Result = try {
        if (applicationContext.getDatabasePath(HealthReminderStore.DEFAULT_DB).exists()) {
            HealthReminderStore(applicationContext).use { HealthReminderWork.refresh(applicationContext, it, true) }
        }
        Result.success()
    } catch (_: android.database.sqlite.SQLiteDatabaseLockedException) {
        Result.retry()
    } catch (_: Exception) {
        Result.failure()
    }
}
