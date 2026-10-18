package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.telecom.TelecomManager
import android.content.pm.PackageManager

internal object ContactReminderNotifications {
    fun callActive(context: Context): Boolean {
        val audio = context.getSystemService(AudioManager::class.java)
        if (audio.mode != AudioManager.MODE_NORMAL) return true
        if (runCatching { audio.activeRecordingConfigurations.isNotEmpty() }.getOrDefault(false)) return true
        if (context.checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) return false
        return runCatching { context.getSystemService(TelecomManager::class.java).isInCall }.getOrDefault(false)
    }

    fun show(base: Context, value: ContactReminder) {
        if (value.terminal || System.currentTimeMillis() >= value.expiresAt) return
        val context = AppLanguage.wrap(base)
        val foreground = AppForegroundTracker.isForeground()
        val quiet = callActive(context) || value.status == "quiet"
        val manager = context.getSystemService(NotificationManager::class.java)
        val channelId = if (quiet) "contact_reminders_quiet_v2" else "contact_reminders_panel_v2"
        val channel = NotificationChannel(channelId, context.getString(R.string.contact_reminder_title),
            if (quiet) NotificationManager.IMPORTANCE_DEFAULT else NotificationManager.IMPORTANCE_HIGH).apply {
            setShowBadge(false)
            enableVibration(!quiet && !foreground)
            // Sound has its own bounded lifecycle; do not play it twice through the OS notification.
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
        val intent = ContactReminderActivity.intent(context, value.id)
        val open = PendingIntent.getActivity(context, value.id.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        // Keep all notification text private, including the public lockscreen version.
        val notice = Notification.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_voice_call_wave)
            .setContentTitle(context.getString(R.string.contact_reminder_title))
            .setContentText(context.getString(R.string.contact_reminder_message))
            .setContentIntent(open).setOnlyAlertOnce(true).setAutoCancel(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC).setCategory(Notification.CATEGORY_REMINDER)
            .setTimeoutAfter(value.expiresAt - System.currentTimeMillis())
            .addAction(Notification.Action.Builder(null, context.getString(R.string.contact_reminder_mute), action(context, value.id, "muted")).build())
            .addAction(Notification.Action.Builder(null, context.getString(R.string.contact_reminder_ignore), action(context, value.id, "dismissed")).build())
            .addAction(Notification.Action.Builder(null, context.getString(R.string.contact_reminder_confirm), action(context, value.id, "acknowledged")).build())
            .setDeleteIntent(action(context, value.id, "muted"))
        val allowFullScreen = Build.VERSION.SDK_INT < 34 || manager.canUseFullScreenIntent()
        if (!quiet && !foreground && allowFullScreen && ContactReminders.preferences(context).getBoolean("lockscreen", false)) {
            notice.setFullScreenIntent(open, true)
        }
        if (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            manager.notify(value.id, 4601, notice.build())
            if (!quiet) ContactReminderSound.start(context, value)
        }
        if (foreground && !quiet) {
            ContactReminderSound.start(context, value)
            context.startActivity(intent)
        }
    }

    private fun action(context: Context, id: String, action: String): PendingIntent = PendingIntent.getBroadcast(
        context, "$id:$action".hashCode(), Intent(context, ContactReminderActionReceiver::class.java)
            .setAction(action).setData(android.net.Uri.parse("galaxyssi-reminder:$id/$action"))
            .putExtra("reminder_id", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun cancel(context: Context, id: String) {
        ContactReminderSound.stop(id)
        context.getSystemService(NotificationManager::class.java).cancel(id, 4601)
    }
}

class ContactReminderActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        ContactReminders.act(context, intent.getStringExtra("reminder_id").orEmpty(), intent.action.orEmpty())
        // The same single-thread executor drains the action before releasing the broadcast.
        ContactReminders.submit { pending.finish() }
    }
}
