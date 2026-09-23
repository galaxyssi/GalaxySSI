package com.galaxyssi.watch

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.StorageService

/** Opt-in local recognition, owned by the activity or microphone foreground service. No captured audio or transcript is saved or sent. */
internal class WatchForegroundWake(context: Context,
    private val onState: (State) -> Unit,
    private val onWake: () -> Unit) {
    enum class State { OFF, LOADING, LISTENING, PAUSED, FAILED }
    private val context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val generation = AtomicLong()
    @Volatile private var recorder: AudioRecord? = null
    private var model: Model? = null // Owned exclusively by worker; reused between foreground sessions.
    private var enabled = false
    private var closed = false
    private var failed = false
    var state = State.OFF
        private set

    fun setEnabled(value: Boolean) {
        if (closed || enabled == value || (value && failed)) return
        enabled = value
        val token = generation.incrementAndGet()
        if (!value) {
            // Unblock capture immediately; release and any handoff are completed on the worker.
            runCatching { recorder?.stop() }
            publish(State.PAUSED)
            return
        }
        publish(State.LOADING)
        worker.execute { capture(token) }
    }
    fun stopThen(action: () -> Unit) {
        setEnabled(false)
        worker.execute { main.post { if (!closed) action() } }
    }
    fun retry() { failed = false }
    private fun publish(value: State) { state = value; onState(value) }
    @android.annotation.SuppressLint("MissingPermission")
    private fun capture(token: Long) {
        var input: AudioRecord? = null
        var recognizer: Recognizer? = null
        var detected = false
        var error = false
        try {
            if (model == null) {
                model = Model(StorageService.sync(context, "model-en-us", "wake-model"))
            }
            if (generation.get() != token) return
            recognizer = Recognizer(requireNotNull(model), 16000f, "[\"hello hello\", \"[unk]\"]")
            recognizer.setWords(true)
            val size = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            require(size > 0)
            input = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(size * 2, 6400))
            recorder = input
            check(input.state == AudioRecord.STATE_INITIALIZED)
            if (generation.get() != token) return
            input.startRecording()
            check(input.recordingState == AudioRecord.RECORDSTATE_RECORDING)
            main.post { if (generation.get() == token) publish(State.LISTENING) }
            val samples = ShortArray(1600)
            val candidate = WatchWakeCandidate()
            var reads = 0L
            var rejected = 0L
            var lastDiagnostic = android.os.SystemClock.elapsedRealtime()
            while (generation.get() == token) {
                val count = input.read(samples, 0, samples.size)
                if (generation.get() != token) break
                check(count > 0)
                reads++
                if (recognizer.acceptWaveForm(samples, count)) {
                    if (WatchWakePolicy.confidentResult(recognizer.result)) { detected = true; break }
                    rejected++
                    candidate.observe("{}", android.os.SystemClock.elapsedRealtime())
                } else if (candidate.observe(recognizer.partialResult, android.os.SystemClock.elapsedRealtime())) {
                    detected = true
                    break
                }
                val now = android.os.SystemClock.elapsedRealtime()
                if (now - lastDiagnostic >= 30000) {
                    // Counters only: never log captured sound or recognized words.
                    android.util.Log.i("WatchWake", "capture reads=$reads rejected=$rejected")
                    lastDiagnostic = now
                }
            }
            samples.fill(0)
        } catch (_: Exception) { error = true }
          catch (_: LinkageError) { error = true }
        finally {
            runCatching { input?.stop() }
            input?.release()
            recorder = null
            recognizer?.close()
            main.post {
                if (generation.get() == token && !closed) {
                    enabled = false
                    failed = error
                    publish(if (error) State.FAILED else State.PAUSED)
                    android.util.Log.i("WatchWake", "capture ended detected=$detected error=$error")
                    if (detected && !error) onWake()
                }
            }
        }
    }
    fun shutdown() {
        setEnabled(false)
        closed = true
        worker.execute { model?.close(); model = null }
        worker.shutdown()
    }
}
