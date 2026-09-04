package com.galaxyssi.chat.voice.asr.local

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.galaxyssi.chat.MainActivity
import com.galaxyssi.chat.R

class LargeTurboQnnModelDownloadService : Service() {
    override fun onCreate() {
        super.onCreate()
        running = true
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE -> {
                LargeTurboQnnModelManager.pauseInProcess(::refreshNotification)
                refreshNotification()
            }
            ACTION_START -> {
                val policy = runCatching {
                    QnnModelDownloadNetworkPolicy.valueOf(
                        intent.getStringExtra(EXTRA_NETWORK_POLICY).orEmpty()
                    )
                }.getOrDefault(QnnModelDownloadNetworkPolicy.WIFI_ONLY)
                startForeground(
                    NOTIFICATION_ID,
                    notification(LargeTurboQnnModelState(LargeTurboQnnModelStatus.DOWNLOADING))
                )
                LargeTurboQnnModelManager.enqueueInProcess(this, policy, ::refreshNotification)
            }
            else -> {
                stopSelf(startId)
                return START_NOT_STICKY
            }
        }
        return START_REDELIVER_INTENT
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun refreshNotification() {
        val state = LargeTurboQnnModelManager.state(this)
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(state))
        if (!state.status.isActiveDownloadState()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun notification(state: LargeTurboQnnModelState): Notification {
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_tab_chat_filled)
            .setContentTitle(getString(
                R.string.local_model_download_notification_title,
                LargeTurboQnnModelManager.manifest.displayName
            ))
            .setContentText(stateLabel(state))
            .setOnlyAlertOnce(true)
            .setOngoing(state.status.isActiveDownloadState())
            .setProgress(100, state.progress, state.status == LargeTurboQnnModelStatus.CHECKING)
            .setContentIntent(PendingIntent.getActivity(
                this,
                CONTENT_REQUEST_CODE,
                Intent(this, MainActivity::class.java)
                    .putExtra("galaxyssi_debug_open_local_model", true),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            ))
        if (state.status == LargeTurboQnnModelStatus.DOWNLOADING) {
            builder.addAction(
                0,
                getString(R.string.local_model_pause_action),
                PendingIntent.getService(
                    this,
                    PAUSE_REQUEST_CODE,
                    Intent(this, LargeTurboQnnModelDownloadService::class.java).setAction(ACTION_PAUSE),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        }
        return builder.build()
    }

    private fun stateLabel(state: LargeTurboQnnModelState): String = when (state.status) {
        LargeTurboQnnModelStatus.CHECKING -> getString(R.string.voice_provider_checking)
        LargeTurboQnnModelStatus.NOT_INSTALLED -> getString(R.string.voice_asr_model_download_size)
        LargeTurboQnnModelStatus.DOWNLOADING -> getString(R.string.local_model_download_progress, state.progress)
        LargeTurboQnnModelStatus.PAUSED -> getString(R.string.local_model_download_paused)
        LargeTurboQnnModelStatus.VERIFYING -> getString(R.string.local_model_download_verifying)
        LargeTurboQnnModelStatus.INSTALLING -> getString(R.string.local_model_download_installing)
        LargeTurboQnnModelStatus.READY -> getString(R.string.local_model_download_ready)
        LargeTurboQnnModelStatus.FAILED -> state.detail.ifBlank { getString(R.string.local_model_download_failed) }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.local_model_download_channel),
                NotificationManager.IMPORTANCE_LOW
            )
        )
    }

    companion object {
        private const val ACTION_START = "com.galaxyssi.chat.qnn.large_turbo.START"
        private const val ACTION_PAUSE = "com.galaxyssi.chat.qnn.large_turbo.PAUSE"
        private const val EXTRA_NETWORK_POLICY = "network_policy"
        private const val CHANNEL_ID = "galaxyssi_qnn_large_turbo"
        private const val NOTIFICATION_ID = 9_019
        private const val CONTENT_REQUEST_CODE = 19_010
        private const val PAUSE_REQUEST_CODE = 19_011

        @Volatile
        var running: Boolean = false
            private set

        fun start(context: Context, policy: QnnModelDownloadNetworkPolicy) {
            val intent = Intent(context, LargeTurboQnnModelDownloadService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_NETWORK_POLICY, policy.name)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun pause(context: Context) {
            context.startService(
                Intent(context, LargeTurboQnnModelDownloadService::class.java).setAction(ACTION_PAUSE)
            )
        }
    }
}

private fun LargeTurboQnnModelStatus.isActiveDownloadState(): Boolean = this in setOf(
    LargeTurboQnnModelStatus.CHECKING,
    LargeTurboQnnModelStatus.DOWNLOADING,
    LargeTurboQnnModelStatus.VERIFYING,
    LargeTurboQnnModelStatus.INSTALLING
)
