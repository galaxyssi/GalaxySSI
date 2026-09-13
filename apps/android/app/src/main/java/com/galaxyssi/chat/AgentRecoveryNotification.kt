package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.work.ForegroundInfo

internal object AgentRecoveryNotification {
    fun foregroundInfo(context: Context, taskKey: String): ForegroundInfo {
        val channel = "galaxyssi_agent_long_tasks"
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(channel, context.getString(R.string.app_name), NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(context, taskKey.hashCode(),
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_tab_chat_filled)
            .setContentTitle(context.getString(R.string.app_name))
            .setContentText(context.getString(R.string.agent_task_liveness_assessment))
            .setContentIntent(open).setOnlyAlertOnce(true).setOngoing(true).build()
        val id = 0x53410A xor taskKey.hashCode()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            ForegroundInfo(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else ForegroundInfo(id, notification)
    }
}
