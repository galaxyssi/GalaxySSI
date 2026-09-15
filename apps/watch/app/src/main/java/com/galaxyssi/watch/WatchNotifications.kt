package com.galaxyssi.watch

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.*

fun TaskState.label(): Int = when (this) {
    TaskState.QUEUED -> R.string.state_queued
    TaskState.SENT -> R.string.state_sent
    TaskState.ACCEPTED -> R.string.state_accepted
    TaskState.RUNNING -> R.string.state_running
    TaskState.WAITING_APPROVAL -> R.string.state_waiting_approval
    TaskState.STOP_REQUESTED -> R.string.state_stop_requested
    TaskState.COMPLETED -> R.string.state_completed
    TaskState.FAILED -> R.string.state_failed
    TaskState.CANCELLED -> R.string.state_cancelled
}

object WatchNotifications {
    const val MONITOR_ID = 41
    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)
    fun channels(context: Context) {
        manager(context).createNotificationChannel(NotificationChannel("watch_connection", context.getString(R.string.monitor_channel), NotificationManager.IMPORTANCE_LOW))
        manager(context).createNotificationChannel(NotificationChannel("watch_results", context.getString(R.string.result_channel), NotificationManager.IMPORTANCE_DEFAULT).apply {
            enableVibration(false)
        })
    }
    private fun open(context: Context, task: String = ""): PendingIntent = PendingIntent.getActivity(context, task.hashCode(),
        Intent(context, MainActivity::class.java).putExtra("task_id", task).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun monitoring(context: Context): Notification {
        channels(context)
        val stop = PendingIntent.getService(context, 2, Intent(context, WatchConnectionService::class.java).setAction("stop"), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(context, "watch_connection").setSmallIcon(R.drawable.ic_galaxyssi_logo)
            .setContentTitle(context.getString(R.string.monitor_title)).setContentText(context.getString(R.string.monitor_body))
            .setContentIntent(open(context)).setOngoing(true)
            .addAction(Notification.Action.Builder(null, context.getString(R.string.monitor_stop), stop).build()).build()
    }
    fun completed(context: Context, task: WatchTask) {
        val repo = (context.applicationContext as WatchApplication).repository
        if (repo.conversationVisibility.isViewing(task)) return
        channels(context)
        if (repo.store.vibration) context.getSystemService(VibratorManager::class.java).defaultVibrator
            .vibrate(VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE))
        if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            manager(context).notify(task.id.hashCode(), Notification.Builder(context, "watch_results")
                .setSmallIcon(R.drawable.ic_galaxyssi_logo).setContentTitle(context.getString(task.state.label()))
                .setContentText(task.reply.ifBlank { task.prompt }.take(100)).setAutoCancel(true)
                .setVisibility(Notification.VISIBILITY_PRIVATE).setContentIntent(open(context, task.id)).build())
        }
    }
    fun dismissConversation(context: Context, tasks: List<WatchTask>, current: WatchTask) {
        tasks.filter { it.conversationKey() == current.conversationKey() }.forEach { manager(context).cancel(it.id.hashCode()) }
    }
}

/** User-controlled persistent assistant connection; microphone remains user-initiated. */
class WatchConnectionService : Service() {
    private val repo get() = (application as WatchApplication).repository
    private val finishWhenIdle: () -> Unit = { if (!repo.activeTasks()) stopSelf() }
    override fun onCreate() {
        super.onCreate()
        val type = if (Build.VERSION.SDK_INT >= 34) android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        startForeground(WatchNotifications.MONITOR_ID, WatchNotifications.monitoring(this), type)
        repo.monitor(true)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") {
            repo.store.backgroundEnabled = false
            stopSelf()
            return START_NOT_STICKY
        }
        if (!repo.store.backgroundEnabled) {
            if (repo.activeTasks()) repo.listen(finishWhenIdle) else stopSelf()
            return START_NOT_STICKY
        }
        repo.unlisten(finishWhenIdle)
        return START_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) { stopSelf() }
    override fun onDestroy() {
        repo.unlisten(finishWhenIdle)
        repo.monitor(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
    override fun onBind(intent: Intent?) = null
}

/** Restore the user-enabled assistant after boot or an application update. */
class WatchBootReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) return
        if (WatchStore(context).backgroundEnabled) {
            runCatching { context.startForegroundService(Intent(context, WatchConnectionService::class.java)) }
                .onFailure { android.util.Log.w("WatchBackground", "System deferred background service startup") }
        }
    }
}
