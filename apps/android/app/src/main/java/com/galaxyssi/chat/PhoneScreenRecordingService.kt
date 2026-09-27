package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.io.File
import java.util.UUID

class PhoneScreenRecordingService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var recordingId = ""
    private var recorder: MediaRecorder? = null
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var output: File? = null
    private var started = false
    private var completed = false
    private val callback = object : MediaProjection.Callback() {
        override fun onStop() { finishRecording() }
    }
    override fun onCreate() { super.onCreate(); active = this }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getStringExtra("recording_id").orEmpty()
        if (intent?.action == STOP) {
            if (recordingId.isBlank() || recordingId == id) finishRecording()
            return START_NOT_STICKY
        }
        if (intent?.action != START || !PhoneScreenRecording.isPending(id)) { stopSelf(); return START_NOT_STICKY }
        if (recordingId.isNotBlank()) { PhoneScreenRecording.complete(id, error = "Another recording is active"); return START_NOT_STICKY }
        recordingId = id
        val seconds = intent.getIntExtra("duration_seconds", 15).coerceIn(1, 120)
        runCatching {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(
                CHANNEL, getString(R.string.screen_assistant_recording), NotificationManager.IMPORTANCE_LOW))
            val stop = PendingIntent.getService(this, 71, Intent(this, javaClass).setAction(STOP)
                .putExtra("recording_id", id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = (if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this))
                .setSmallIcon(R.drawable.ic_tab_chat_filled).setContentTitle(getString(R.string.screen_assistant_recording))
                .setContentText(getString(R.string.screen_assistant_recording_active)).setOngoing(true)
                .addAction(Notification.Action.Builder(null, getString(R.string.screen_assistant_stop), stop).build()).build()
            if (Build.VERSION.SDK_INT >= 29) startForeground(4071, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            else startForeground(4071, notification)
            val data = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra("projection_data", Intent::class.java)
                else @Suppress("DEPRECATION") (intent.getParcelableExtra("projection_data") as? Intent)
            requireNotNull(data)
            projection = getSystemService(MediaProjectionManager::class.java)
                .getMediaProjection(intent.getIntExtra("result_code", 0), data)
            projection?.registerCallback(callback, handler)
            val begin = { runCatching { beginRecording(seconds) }.onFailure { finishRecording(it.message.orEmpty()) }; Unit }
            GalaxySSIAccessibilityService.targetService()?.captureWithoutAssistant(begin) ?: begin()
        }.onFailure { finishRecording(it.message.orEmpty()) }
        return START_NOT_STICKY
    }
    private fun beginRecording(seconds: Int) {
        if (completed || !PhoneScreenRecording.isPending(recordingId)) { finishRecording("Recording cancelled"); return }
        val metrics = resources.displayMetrics
        val scale = minOf(1.0, 1280.0 / maxOf(metrics.widthPixels, metrics.heightPixels))
        val width = ((metrics.widthPixels * scale).toInt() / 2 * 2).coerceAtLeast(2)
        val height = ((metrics.heightPixels * scale).toInt() / 2 * 2).coerceAtLeast(2)
        output = File(filesDir, "agent-rich-output-v2/screen-assistant/${UUID.randomUUID()}.mp4").apply { parentFile?.mkdirs() }
        recorder = (if (Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else @Suppress("DEPRECATION") MediaRecorder()).apply {
            setVideoSource(MediaRecorder.VideoSource.SURFACE)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            setVideoSize(width, height)
            setVideoFrameRate(24)
            setVideoEncodingBitRate(2_000_000)
            setOutputFile(requireNotNull(output).absolutePath)
            prepare()
        }
        display = requireNotNull(projection).createVirtualDisplay("GalaxySSI-VisibleRecording", width, height,
            metrics.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, requireNotNull(recorder).surface, null, handler)
        recorder?.start()
        started = true
        handler.postDelayed({ finishRecording() }, seconds * 1_000L)
    }
    private fun finishRecording(error: String = "") {
        if (completed) return
        completed = true
        handler.removeCallbacksAndMessages(null)
        val stopped = started && runCatching { recorder?.stop(); true }.getOrDefault(false)
        display?.release(); display = null
        recorder?.release(); recorder = null
        projection?.unregisterCallback(callback)
        projection?.stop(); projection = null
        GalaxySSIAccessibilityService.targetService()?.restoreAssistantAfterCapture()
        val file = output?.takeIf { stopped && error.isBlank() && it.length() > 0 }
        if (file == null) output?.delete()
        PhoneScreenRecording.complete(recordingId, file, error.ifBlank { if (file == null) "Recording produced no playable video" else "" })
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }
    override fun onDestroy() {
        finishRecording("Recording service stopped")
        if (active === this) active = null
        super.onDestroy()
    }
    companion object {
        const val START = "com.galaxyssi.chat.PHONE_RECORD_START"
        const val STOP = "com.galaxyssi.chat.PHONE_RECORD_STOP"
        private const val CHANNEL = "galaxyssi_visible_phone_recording"
        @Volatile private var active: PhoneScreenRecordingService? = null
        internal fun stopIfActive(id: String) {
            active?.let { service -> service.handler.post { if (service.recordingId == id) service.finishRecording("Recording cancelled") } }
        }
    }
}
