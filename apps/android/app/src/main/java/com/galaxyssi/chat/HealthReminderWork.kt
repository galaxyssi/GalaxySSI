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

internal object HealthReminderWork {
    private const val WORK = "health-reminder-reconcile"
    private const val CHANNEL = "health_record_reminders"
    private const val TAG = "health-record-reminder:"
    private const val ID = 1

    fun enqueue(context: Context) = WorkManager.getInstance(context).enqueueUniqueWork(
        WORK, ExistingWorkPolicy.APPEND_OR_REPLACE, OneTimeWorkRequestBuilder<HealthReminderWorker>().build())

    private fun alarm(context: Context) = PendingIntent.getBroadcast(context, 0, Intent(context, HealthReminderReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun systemAllowed(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager.areNotificationsEnabled() && manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
    }

    @Synchronized fun save(context: Context, store: HealthReminderStore, candidate: HealthReminderSettings, live: Boolean) {
        if (live) enqueue(context)
        store.save(candidate, System.currentTimeMillis())
        refresh(context, store, live)
    }

    @Synchronized fun act(context: Context, store: HealthReminderStore, event: HealthReminderOccurrence, action: HealthReminderAction, live: Boolean) {
        if (live) enqueue(context)
        store.act(event.day, event.revision, action, System.currentTimeMillis())
        refresh(context, store, live)
    }

    @Synchronized fun refresh(context: Context, store: HealthReminderStore, live: Boolean) {
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        store.reconcile(now, zone)
        if (!live) return
        val settings = store.settings()
        val alerts = context.getSystemService(NotificationManager::class.java)
        val scheduler = context.getSystemService(AlarmManager::class.java)
        val nextDaily = HealthReminderPolicy.nextDaily(settings, now, zone)
        val nextSnooze = store.nextSnooze()
        val quietUntil = HealthReminderPolicy.quietUntil(settings, now, zone)
        val allowed = settings.enabled && settings.notifications && systemAllowed(context)
        val canPost = allowed && now >= settings.pauseUntil && quietUntil == null
        val pending = store.pendingDelivery(now)
        val defer = if (allowed && pending.isNotEmpty()) maxOf(quietUntil ?: 0, settings.pauseUntil).takeIf { it > now } else null
        val next = listOfNotNull(nextDaily, nextSnooze, defer).minOrNull()
        if (next == null) scheduler.cancel(alarm(context))
        else scheduler.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, alarm(context))
        // Remove obsolete visible alerts without altering the persisted handling state.
        alerts.activeNotifications.filter { it.tag?.startsWith(TAG) == true }.forEach { existing ->
            val day = runCatching { LocalDate.parse(existing.tag.removePrefix(TAG)) }.getOrNull()
            val event = day?.let(store::occurrence)
            if (!canPost || event?.state != HealthReminderState.PENDING ||
                existing.notification.visibility != visibility(settings)) alerts.cancel(existing.tag, existing.id)
        }
        pending.forEach { event ->
            when {
                !allowed -> store.delivered(event, HealthReminderDelivery.IN_APP_ONLY)
                canPost -> {
                    val posted = try { notify(context, alerts, event, settings); true } catch (_: SecurityException) { false }
                    store.delivered(event, if (posted) HealthReminderDelivery.POSTED else HealthReminderDelivery.IN_APP_ONLY)
                }
            }
        }
    }

    private fun visibility(settings: HealthReminderSettings) =
        if (settings.hideOnLock) Notification.VISIBILITY_PRIVATE else Notification.VISIBILITY_PUBLIC

    private fun notify(context: Context, manager: NotificationManager, event: HealthReminderOccurrence, settings: HealthReminderSettings) {
        manager.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.health_reminder_channel), NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(context, HealthReminderActivity::class.java).putExtra("health_reminder_day", event.day.toString())
        val open = PendingIntent.getActivity(context, event.day.toEpochDay().toInt(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun base() = Notification.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_settings_notification)
            .setContentTitle(context.getString(R.string.health_reminder_generic)).setContentIntent(open)
            .setAutoCancel(true).setOnlyAlertOnce(true).setCategory(Notification.CATEGORY_REMINDER)
        val public = base().setVisibility(Notification.VISIBILITY_PUBLIC).build()
        manager.notify(TAG + event.day, ID, base().setContentText(context.getString(event.target.titleResource()))
            .setVisibility(visibility(settings)).setPublicVersion(public).build())
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
