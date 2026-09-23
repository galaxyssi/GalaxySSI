package com.galaxyssi.watch

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.media.*
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import com.galaxyssi.chat.voice.audio.PeerVoiceOpusRecorder
import com.galaxyssi.chat.voice.audio.PeerVoiceMessageAudio
import java.util.concurrent.Executors

/** Uses Android's actual Opus recorder and speech playback attributes. No recognition service. */
internal class WatchPeerVoice(private val activity: Activity, private val send: (ByteArray, Long) -> Unit,
    private val failed: () -> Unit, private val onRecordingStopped: () -> Unit = {}) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var recorder: PeerVoiceOpusRecorder? = null // owned by worker
    @Volatile private var amplitude = 0
    private var recording = false
    private var generation = 0
    private var started = 0L
    private var cancelled = false
    private var popup: PopupWindow? = null
    private var meter: TextView? = null
    private var player: MediaPlayer? = null
    private var mediaSource: MediaDataSource? = null
    private var focus: AudioFocusRequest? = null
    private val manager = activity.getSystemService(AudioManager::class.java)
    private var playbackGeneration = 0
    private val timer = object : Runnable {
        override fun run() {
            if (!recording) return
            val seconds = (SystemClock.elapsedRealtime() - started) / 1000
            meter?.text = activity.getString(if (cancelled) R.string.peer_voice_cancel else R.string.peer_voice_recording, seconds)
            meter?.setBackgroundColor(if (cancelled) 0xff973b3b.toInt() else 0xff147d4b.toInt())
            if (seconds >= 60) finish(false) else main.postDelayed(this, 100)
        }
    }
    fun start() {
        if (recording) return
        stopPlayback()
        if (activity.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), 74); return
        }
        recording = true; cancelled = false; started = SystemClock.elapsedRealtime(); val owner = ++generation
        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val box = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; setPadding(16, 20, 16, 20)
            background = GradientDrawable().apply { setColor(0xff147d4b.toInt()); cornerRadius = 28f }
        }
        val waveform = object : View(activity) {
            private val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; strokeWidth = 5f; strokeCap = android.graphics.Paint.Cap.ROUND }
            override fun onDraw(canvas: android.graphics.Canvas) {
                val strength = amplitude / 32768f
                repeat(13) { index ->
                    val wave = kotlin.math.abs(kotlin.math.sin(SystemClock.elapsedRealtime() / 150.0 + index)).toFloat()
                    val half = 3f + (height * .4f) * strength * wave
                    val x = width * (index + 1) / 14f
                    canvas.drawLine(x, height / 2f - half, x, height / 2f + half, paint)
                }
                if (recording) postInvalidateDelayed(80)
            }
        }
        box.addView(waveform, LinearLayout.LayoutParams(-1, 70))
        meter = TextView(activity).apply { textSize = 13f; setTextColor(Color.WHITE); gravity = Gravity.CENTER }
        box.addView(meter)
        popup = PopupWindow(box, (activity.resources.displayMetrics.widthPixels * .75f).toInt(), -2, false).apply {
            isTouchable = false; showAtLocation(activity.window.decorView, Gravity.CENTER, 0, 0)
        }
        main.post(timer)
        worker.execute {
            runCatching { recorder = PeerVoiceOpusRecorder(activity).apply { start() } }.onFailure {
                main.post { if (generation == owner) { abort(); failed() } }
            }
        }
        sampleAmplitude(owner)
    }
    private fun sampleAmplitude(owner: Int) {
        if (!recording || generation != owner) return
        worker.execute { amplitude = recorder?.currentAmplitude() ?: 0 }
        main.postDelayed({ sampleAmplitude(owner) }, 100)
    }
    fun move(cancel: Boolean) { cancelled = cancel }
    fun finish(cancel: Boolean) {
        if (!recording) return
        recording = false; main.removeCallbacks(timer); popup?.dismiss(); popup = null
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val discard = cancel || cancelled || SystemClock.elapsedRealtime() - started < 500
        val owner = generation
        worker.execute {
            val current = recorder; recorder = null
            if (current == null) { main.post(onRecordingStopped); return@execute }
            if (discard) { current.cancel(); main.post(onRecordingStopped); return@execute }
            val result = runCatching { current.stopAndEncode() }
            main.post {
                onRecordingStopped()
                result.onSuccess {
                    if (generation == owner && !activity.isDestroyed) send(it.encodedOggOpus, it.durationMillis)
                    else it.encodedOggOpus.fill(0)
                }.onFailure { if (generation == owner && !activity.isDestroyed) failed() }
            }
        }
    }
    fun abort() { generation++; finish(true); stopPlayback() }
    fun close() { abort(); worker.shutdown() }
    fun play(bytes: ByteArray) {
        stopPlayback(); val owner = ++playbackGeneration
        val attrs = PeerVoiceMessageAudio.playbackAttributes()
        focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attrs)
            .setOnAudioFocusChangeListener { if (it < 0) stopPlayback() }.build()
        if (manager.requestAudioFocus(focus!!) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { bytes.fill(0); stopPlayback(); return }
        val source = object : MediaDataSource() {
            override fun getSize() = bytes.size.toLong()
            override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
                if (position < 0 || position >= bytes.size) return -1
                val count = minOf(size, bytes.size - position.toInt()); bytes.copyInto(buffer, offset, position.toInt(), position.toInt() + count); return count
            }
            override fun close() { bytes.fill(0) }
        }
        mediaSource = source
        runCatching {
            player = MediaPlayer().apply {
                setAudioAttributes(attrs); setDataSource(source)
                setOnPreparedListener { if (owner == playbackGeneration) { start(); activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) } }
                setOnCompletionListener { stopPlayback() }
                setOnErrorListener { _, _, _ -> stopPlayback(); failed(); true }
                prepareAsync()
            }
        }.onFailure { source.close(); stopPlayback(); failed() }
    }
    fun stopPlayback() {
        playbackGeneration++; player?.release(); player = null
        mediaSource?.close(); mediaSource = null
        focus?.let { manager.abandonAudioFocusRequest(it) }; focus = null
        if (!recording) activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
