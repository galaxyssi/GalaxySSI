package com.galaxyssi.glasses

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.util.concurrent.atomic.AtomicBoolean

/** One microphone stream feeds Mandarin and English decoders; no system ASR service is needed. */
internal class BilingualSpeech(
    private val context: Context,
    private val chineseModel: Model,
    private val englishModel: Model,
    private val onLevel: (Int) -> Unit,
    private val onPartial: (String) -> Unit,
    private val onFinal: (String) -> Unit,
    private val onError: (String) -> Unit
) {
    private val main = Handler(Looper.getMainLooper())
    private val running = AtomicBoolean(false)
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
        var chinese: Recognizer? = null
        var english: Recognizer? = null
        try {
            chinese = Recognizer(chineseModel, 16000f)
            english = Recognizer(englishModel, 16000f)
            chinese.setWords(true); english.setWords(true)
            val buffer = ByteArray(4096)
            var previousPartial = ""
            var lastPartialAt = 0L
            var badReads = 0
            var lastLevelAt = 0L
            while (running.get()) {
                val size = capture.read(buffer, 0, buffer.size)
                if (size <= 0) {
                    if (size < 0 || ++badReads >= 10) error("麦克风读取中断（$size）")
                    continue
                }
                badReads = 0
                if (System.currentTimeMillis() - lastLevelAt > 500) {
                    lastLevelAt = System.currentTimeMillis()
                    var total = 0L
                    var count = 0
                    for (i in 0 until size - 1 step 16) {
                        val sample = ((buffer[i + 1].toInt() shl 8) or (buffer[i].toInt() and 0xff)).toShort().toInt()
                        total += kotlin.math.abs(sample).toLong()
                        count++
                    }
                    val level = if (count == 0) 0 else ((total / count) / 120).toInt().coerceIn(0, 100)
                    main.post { if (running.get()) onLevel(level) }
                }
                val cnDone = chinese.acceptWaveForm(buffer, size)
                val enDone = english.acceptWaveForm(buffer, size)
                if (cnDone || enDone) {
                    val cn = if (cnDone) chinese.result else chinese.partialResult
                    val en = if (enDone) english.result else english.partialResult
                    val chosen = choose(cn, en)
                    if (chosen.isNotBlank()) main.post { if (running.get()) onFinal(chosen) }
                    chinese.reset(); english.reset()
                    previousPartial = ""
                } else if (System.currentTimeMillis() - lastPartialAt > 250) {
                    lastPartialAt = System.currentTimeMillis()
                    val cn = JSONObject(chinese.partialResult).optString("partial")
                    val en = JSONObject(english.partialResult).optString("partial")
                    val partial = chooseText(cn, en)
                    if (partial.isNotBlank() && partial != previousPartial) {
                        previousPartial = partial
                        main.post { if (running.get()) onPartial(partial) }
                    }
                }
            }
        } catch (error: Exception) {
            main.post { if (running.get()) onError(error.message ?: "语音识别失败") }
        } finally {
            chinese?.close(); english?.close()
            capture.release()
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

    private fun choose(cnJson: String, enJson: String): String {
        val cn = JSONObject(cnJson)
        val en = JSONObject(enJson)
        val cnText = cn.optString("text", cn.optString("partial")).trim()
        val enText = en.optString("text", en.optString("partial")).trim()
        if (enText.isBlank()) return cnText
        if (cnText.isBlank()) return enText
        // The English decoder may hear the wake phrase while Mandarin hears the command.
        if (wakePhrase.containsMatchIn(enText) && cnText.count(::isHan) >= 2)
            return "$enText $cnText"
        val enConfidence = confidence(en)
        val cnConfidence = confidence(cn)
        return if (enText.contains(Regex("(?i)\\b(hello|hi|hey)\\b")) ||
            enConfidence > cnConfidence + 0.12) enText else cnText
    }

    private fun confidence(json: JSONObject): Double {
        val words = json.optJSONArray("result") ?: return 0.0
        if (words.length() == 0) return 0.0
        return (0 until words.length()).sumOf { words.optJSONObject(it)?.optDouble("conf") ?: 0.0 } / words.length()
    }

    private fun chooseText(cn: String, en: String): String {
        if (wakePhrase.containsMatchIn(en) && cn.count(::isHan) >= 2) return "$en $cn"
        if (en.contains(Regex("(?i)\\b(hello|hi|hey)\\b"))) return en
        return if (cn.isNotBlank()) cn else en
    }
    private fun isHan(char: Char) = char.code in 0x4e00..0x9fff
    private val wakePhrase = Regex("(?i)\\bhello[\\s,，。.!?]*hello\\b")
}
