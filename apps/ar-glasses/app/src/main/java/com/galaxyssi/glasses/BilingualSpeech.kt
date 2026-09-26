package com.galaxyssi.glasses

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs

/** Vosk detects the wake phrase; after wake, PCM utterances go to multilingual Whisper Tiny. */
internal class BilingualSpeech(
    private val context: Context,
    private val englishModel: Model,
    private val isAwake: () -> Boolean,
    private val onLevel: (Int) -> Unit,
    private val onPartial: (String) -> Unit,
    private val onFinal: (String) -> Unit,
    private val onUtterance: (ShortArray, () -> Unit) -> Unit,
    private val onError: (String) -> Unit
) {
    private val main = Handler(Looper.getMainLooper())
    private val running = AtomicBoolean(false)
    private val transcribing = AtomicBoolean(false)
    private var audio: AudioRecord? = null
    private var thread: Thread? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        check(context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            "麦克风权限尚未授予"
        }
        val minimum = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        require(minimum > 0) { "设备不支持 16 kHz 麦克风录音" }
        val capture = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(8192, minimum * 2))
        if (capture.state != AudioRecord.STATE_INITIALIZED) {
            capture.release(); running.set(false)
            error("麦克风初始化失败")
        }
        audio = capture
        try { capture.startRecording() } catch (error: Exception) {
            capture.release(); audio = null; running.set(false); throw error
        }
        thread = Thread({ decode(capture) }, "galaxyssi-ar-asr").apply { isDaemon = true; start() }
    }

    private fun decode(capture: AudioRecord) {
        var wake: Recognizer? = null
        try {
            val buffer = ByteArray(4096)
            val segmenter = SpeechSegmenter()
            var previousPartial = ""
            var lastPartialAt = 0L
            var lastLevelAt = 0L
            var badReads = 0
            while (running.get()) {
                val size = capture.read(buffer, 0, buffer.size)
                if (size <= 0) {
                    if (size < 0 || ++badReads >= 10) error("麦克风读取中断（$size）")
                    continue
                }
                badReads = 0
                var total = 0L
                var count = 0
                for (i in 0 until size - 1 step 16) {
                    val sample = ((buffer[i + 1].toInt() shl 8) or (buffer[i].toInt() and 0xff)).toShort().toInt()
                    total += abs(sample).toLong(); count++
                }
                val amplitude = if (count == 0) 0 else (total / count).toInt()
                val now = System.currentTimeMillis()
                if (now - lastLevelAt > 500) {
                    lastLevelAt = now
                    if (isAwake()) Log.d("GalaxySpeech", "amplitude=$amplitude")
                    main.post { if (running.get()) onLevel((amplitude / 120).coerceIn(0, 100)) }
                }
                if (!isAwake()) {
                    segmenter.reset()
                    if (wake == null) wake = Recognizer(englishModel, 16000f,
                        "[\"hello hello\", \"hello\", \"[unk]\"]").also { it.setWords(true) }
                    val done = wake.acceptWaveForm(buffer, size)
                    if (done) {
                        val result = JSONObject(wake.result).optString("text")
                        if (result.isNotBlank()) main.post { if (running.get()) onFinal(result) }
                        wake.reset(); previousPartial = ""
                    } else if (now - lastPartialAt > 250) {
                        lastPartialAt = now
                        val partial = JSONObject(wake.partialResult).optString("partial")
                        if (partial.isNotBlank() && partial != previousPartial) {
                            previousPartial = partial
                            main.post { if (running.get()) onPartial(partial) }
                        }
                    }
                    continue
                }
                wake?.close(); wake = null
                if (transcribing.get()) continue
                val pcm = segmenter.accept(buffer, size, amplitude)
                if (pcm != null && transcribing.compareAndSet(false, true)) {
                    Log.d("GalaxySpeech", "utterance samples=${pcm.size}")
                    main.post {
                        if (running.get()) onUtterance(pcm) { transcribing.set(false) }
                        else transcribing.set(false)
                    }
                }
            }
        } catch (error: Exception) {
            main.post { if (running.get()) onError(error.message ?: "语音识别失败") }
        } finally {
            wake?.close(); capture.release()
            if (audio === capture) audio = null
        }
    }

    fun stop() {
        running.set(false)
        runCatching { audio?.stop() }
        thread?.interrupt()
        runCatching { thread?.join(1000) }
        thread = null
    }
}
