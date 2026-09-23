package com.galaxyssi.watch

import android.Manifest
import android.app.*
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.*

/** User-started microphone service; never started by boot receivers or background jobs. */
class WatchBackgroundWakeService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var engine: WatchForegroundWake
    private lateinit var cpu: PowerManager.WakeLock
    private var detectedUntil = 0L
    private val reconcile = Runnable { refresh() }
    override fun onBind(intent: Intent?) = null
    override fun onCreate() {
        super.onCreate()
        instance = this
        cpu = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GalaxySSI:WakeWord")
        cpu.setReferenceCounted(false)
        engine = WatchForegroundWake(this, { state ->
            if (state == WatchForegroundWake.State.LOADING || state == WatchForegroundWake.State.LISTENING) {
                if (!cpu.isHeld) cpu.acquire()
            } else if (cpu.isHeld) cpu.release()
            if (state == WatchForegroundWake.State.FAILED) {
                getSystemService(NotificationManager::class.java).notify(ID, notification(R.string.wake_failed))
            }
        }, {
            getSystemService(VibratorManager::class.java).defaultVibrator.vibrate(
                VibrationEffect.createOneShot(45, VibrationEffect.DEFAULT_AMPLITUDE))
            val action = foregroundWake
            if (visible && foregroundAllowed && action != null) action()
            else {
                detectedUntil = SystemClock.elapsedRealtime() + 8000
                getSystemService(NotificationManager::class.java).notify(WAKE_ID, notification(R.string.background_wake_detected, true))
                // A user-enabled system-bound accessibility service can request voice entry.
                // Keep the notification if the OEM declines the background launch.
                WatchSamsungConfirmService.openAfterWake()
                handler.postDelayed(reconcile, 8100)
            }
            refresh()
        })
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("wake_monitor", getString(R.string.background_wake), NotificationManager.IMPORTANCE_LOW))
        manager.createNotificationChannel(NotificationChannel("wake_detected", getString(R.string.background_wake_detected), NotificationManager.IMPORTANCE_HIGH))
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val store = (application as WatchApplication).repository.store
        if (intent?.action == STOP) {
            store.backgroundWake = false
            store.foregroundWake = false
            stopSelf()
            return START_NOT_STICKY
        }
        if (!store.backgroundWake || !store.foregroundWake || checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            startForeground(ID, notification(R.string.background_wake_running), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            refresh()
        } catch (_: SecurityException) { stopSelf() }
        return START_NOT_STICKY
    }
    private fun notification(text: Int, detected: Boolean = false): Notification {
        val open = PendingIntent.getActivity(this, 71, Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_VOICE_COMMAND)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 72, Intent(this, javaClass).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, if (detected) "wake_detected" else "wake_monitor")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now).setContentTitle(getString(R.string.background_wake))
            .setContentText(getString(text)).setContentIntent(open).setOngoing(!detected).setAutoCancel(detected)
            .setOnlyAlertOnce(true).addAction(Notification.Action.Builder(null, getString(R.string.background_wake_stop), stop).build()).build()
    }
    private fun refresh() {
        val allowed = WatchBackgroundWakePolicy.allowed(visible, foregroundAllowed, blocked || peerRecording,
            SystemClock.elapsedRealtime() < detectedUntil)
        engine.setEnabled(allowed)
    }
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        engine.shutdown()
        if (cpu.isHeld) cpu.release()
        getSystemService(NotificationManager::class.java).cancel(WAKE_ID)
        if (instance === this) instance = null
        super.onDestroy()
    }
    companion object {
        private const val ID = 7401
        private const val WAKE_ID = 7402
        private const val STOP = "com.galaxyssi.watch.STOP_WAKE"
        private var instance: WatchBackgroundWakeService? = null
        private var visible = false
        private var foregroundAllowed = false
        private var blocked = false
        private var peerRecording = false
        private var foregroundWake: (() -> Unit)? = null
        fun visibility(value: Boolean) {
            visible = value
            if (value) instance?.getSystemService(NotificationManager::class.java)?.cancel(WAKE_ID)
            if (!value) { foregroundWake = null; foregroundAllowed = false }
            instance?.handler?.removeCallbacks(instance!!.reconcile)
            // Allow activity transitions and microphone handoffs to finish first.
            instance?.handler?.postDelayed(instance!!.reconcile, if (value) 0 else 600)
        }
        fun update(allowed: Boolean, suspended: Boolean, onWake: (() -> Unit)?) {
            foregroundAllowed = allowed; blocked = suspended; foregroundWake = onWake
            instance?.refresh()
        }
        fun otherPage(allowed: Boolean) {
            foregroundAllowed = allowed
            blocked = false
            foregroundWake = null
            instance?.refresh()
        }
        fun stopForPeerRecordingThen(action: () -> Unit) {
            peerRecording = true
            val service = instance
            if (service == null) action() else service.engine.stopThen(action)
        }
        fun peerRecordingFinished() {
            peerRecording = false
            instance?.refresh()
        }
        fun stopThen(action: () -> Unit) {
            blocked = true
            val service = instance
            if (service == null) action() else service.engine.stopThen(action)
        }
        fun start(activity: Activity): Boolean = try {
            activity.startForegroundService(Intent(activity, WatchBackgroundWakeService::class.java)); true
        } catch (_: RuntimeException) { false }
        fun stop(context: android.content.Context) { context.stopService(Intent(context, WatchBackgroundWakeService::class.java)) }
    }
}

internal object WatchBackgroundWakePolicy {
    fun allowed(visible: Boolean, foregroundAllowed: Boolean, blocked: Boolean, coolingDown: Boolean) =
        !blocked && !coolingDown && (!visible || foregroundAllowed)
}
