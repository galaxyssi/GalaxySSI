package com.signalasi.chat

import android.content.Context
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import android.icu.text.Transliterator
import android.os.SystemClock
import com.signalasi.chat.voice.metrics.VoiceLatencyTelemetry
import com.signalasi.chat.voice.metrics.VoiceLatencyTraceContext
import com.signalasi.chat.voice.metrics.VoiceTraceEvents
import com.whispercpp.whisper.WhisperContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteOrder
import java.util.Locale
import kotlin.math.floor

object LocalWhisperAsr {
    private const val TAG = "SignalASILocalASR"
    private const val TARGET_SAMPLE_RATE = 16_000
    private val mutex = Mutex()
    @Volatile private var whisperContext: WhisperContext? = null
    @Volatile private var loadedModelId: String? = null

    suspend fun transcribe(
        context: Context,
        audioFile: File,
        language: String = "auto",
        traceId: String = VoiceLatencyTraceContext.currentTraceId()
    ): String = mutex.withLock {
        val startedAtNs = SystemClock.elapsedRealtimeNanos()
        val selected = WhisperModelManager.model(VoiceAssistantSettings.get(context).asrModel)
        val baseAttributes = mapOf(
            "asr_provider" to "whisper.cpp",
            "model_profile_id" to selected.id,
            "execution_mode" to "full_file",
            "thread_count" to minOf(4, Runtime.getRuntime().availableProcessors()).toString()
        )
        trace(context, traceId, VoiceTraceEvents.ASR_FINAL_STARTED, baseAttributes, once = true)
        try {
            trace(context, traceId, VoiceTraceEvents.ASR_DECODE_STARTED, baseAttributes)
            val decodeStartedAtNs = SystemClock.elapsedRealtimeNanos()
            val samples = decodeTo16kMono(audioFile)
            require(samples.isNotEmpty()) { "Decoded audio is empty" }
            val decodeDurationMs = (SystemClock.elapsedRealtimeNanos() - decodeStartedAtNs) / 1_000_000L
            val audioDurationMs = samples.size.toLong() * 1_000L / TARGET_SAMPLE_RATE
            val audioAttributes = baseAttributes + mapOf(
                "audio_duration_ms" to audioDurationMs.toString(),
                "duration_ms" to decodeDurationMs.toString()
            )
            trace(context, traceId, VoiceTraceEvents.ASR_DECODE_COMPLETED, audioAttributes)
            require(WhisperModelManager.isAvailable(context, selected)) {
                "ASR model ${selected.displayName} is not downloaded"
            }
            if (loadedModelId != selected.id) {
                whisperContext?.release()
                whisperContext = null
                loadedModelId = null
            }
            val coldStart = whisperContext == null
            if (coldStart) {
                trace(
                    context,
                    traceId,
                    VoiceTraceEvents.ASR_MODEL_LOAD_STARTED,
                    audioAttributes + ("cold_start" to "true")
                )
            }
            val model = whisperContext ?: if (selected.bundled) {
                WhisperContext.createContextFromAsset(context.applicationContext.assets, selected.fileName)
            } else {
                WhisperContext.createContextFromFile(WhisperModelManager.downloadedFile(context, selected).absolutePath)
            }.also {
                whisperContext = it
                loadedModelId = selected.id
            }
            if (coldStart) {
                trace(
                    context,
                    traceId,
                    VoiceTraceEvents.ASR_MODEL_LOAD_COMPLETED,
                    audioAttributes + ("cold_start" to "true")
                )
            }
            val normalizedLanguage = language.substringBefore('-').lowercase()
                .takeIf { it in setOf("zh", "en") } ?: "auto"
            val inferenceStartedAtNs = SystemClock.elapsedRealtimeNanos()
            trace(context, traceId, VoiceTraceEvents.WHISPER_FULL_STARTED, audioAttributes)
            val rawText = model.transcribeData(samples, normalizedLanguage, printTimestamp = false).trim()
            val inferenceDurationMs = (SystemClock.elapsedRealtimeNanos() - inferenceStartedAtNs) / 1_000_000L
            val rtf = if (audioDurationMs > 0L) {
                String.format(Locale.US, "%.4f", inferenceDurationMs.toDouble() / audioDurationMs)
            } else {
                "0"
            }
            trace(
                context,
                traceId,
                VoiceTraceEvents.WHISPER_FULL_COMPLETED,
                audioAttributes + mapOf(
                    "duration_ms" to inferenceDurationMs.toString(),
                    "rtf" to rtf
                )
            )
            val text = normalizeChineseScript(rawText, language)
            val totalDurationMs = (SystemClock.elapsedRealtimeNanos() - startedAtNs) / 1_000_000L
            trace(
                context,
                traceId,
                VoiceTraceEvents.ASR_FINAL_RECEIVED,
                audioAttributes + mapOf("duration_ms" to totalDurationMs.toString(), "success" to "true"),
                once = true
            )
            Log.i(
                TAG,
                "Local transcription completed model=${selected.id} samples=${samples.size} " +
                    "language=$normalizedLanguage elapsed=${totalDurationMs}ms"
            )
            text
        } catch (error: Throwable) {
            trace(
                context,
                traceId,
                VoiceTraceEvents.ASR_FINAL_FAILED,
                baseAttributes + mapOf(
                    "duration_ms" to ((SystemClock.elapsedRealtimeNanos() - startedAtNs) / 1_000_000L).toString(),
                    "success" to "false",
                    "error_code" to error.javaClass.simpleName
                ),
                once = true
            )
            throw error
        }
    }

    private fun trace(
        context: Context,
        traceId: String,
        event: String,
        attributes: Map<String, String>,
        once: Boolean = false
    ) {
        if (traceId.isNotBlank()) {
            VoiceLatencyTelemetry.record(context, traceId, event, attributes, once)
        }
    }

    private fun normalizeChineseScript(text: String, language: String): String {
        if (!language.equals("zh-CN", ignoreCase = true) || text.isBlank()) return text
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Transliterator.getInstance("Traditional-Simplified").transliterate(text)
        } else {
            text
        }
    }

    private fun decodeTo16kMono(file: File): FloatArray {
        val extractor = MediaExtractor()
        extractor.setDataSource(file.absolutePath)
        val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
            extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: error("No audio track found")
        extractor.selectTrack(trackIndex)
        val inputFormat = extractor.getTrackFormat(trackIndex)
        val mime = inputFormat.getString(MediaFormat.KEY_MIME) ?: error("Audio MIME is missing")
        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(inputFormat, null, null, 0)
        decoder.start()

        val pcm = ByteArrayOutputStream()
        val info = MediaCodec.BufferInfo()
        var inputEnded = false
        var outputEnded = false
        var sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        try {
            while (!outputEnded) {
                if (!inputEnded) {
                    val inputIndex = decoder.dequeueInputBuffer(10_000)
                    if (inputIndex >= 0) {
                        val input = decoder.getInputBuffer(inputIndex) ?: error("Decoder input buffer missing")
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnded = true
                        } else {
                            decoder.queueInputBuffer(inputIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                when (val outputIndex = decoder.dequeueOutputBuffer(info, 10_000)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val outputFormat = decoder.outputFormat
                        sampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                    else -> if (outputIndex >= 0) {
                        decoder.getOutputBuffer(outputIndex)?.let { output ->
                            if (info.size > 0) {
                                output.position(info.offset)
                                output.limit(info.offset + info.size)
                                val bytes = ByteArray(info.size)
                                output.get(bytes)
                                pcm.write(bytes)
                            }
                        }
                        decoder.releaseOutputBuffer(outputIndex, false)
                        outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    }
                }
            }
        } finally {
            runCatching { decoder.stop() }
            decoder.release()
            extractor.release()
        }
        return resamplePcm16(pcm.toByteArray(), sampleRate, channels)
    }

    private fun resamplePcm16(bytes: ByteArray, sourceRate: Int, channels: Int): FloatArray {
        val shorts = bytes.size / 2
        if (shorts == 0 || sourceRate <= 0 || channels <= 0) return FloatArray(0)
        val buffer = java.nio.ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val frames = shorts / channels
        val mono = FloatArray(frames)
        for (frame in 0 until frames) {
            var sum = 0f
            for (channel in 0 until channels) sum += buffer.get(frame * channels + channel) / 32768f
            mono[frame] = sum / channels
        }
        if (sourceRate == TARGET_SAMPLE_RATE) return mono
        val outputSize = (frames.toLong() * TARGET_SAMPLE_RATE / sourceRate).toInt().coerceAtLeast(1)
        return FloatArray(outputSize) { index ->
            val source = index.toDouble() * sourceRate / TARGET_SAMPLE_RATE
            val left = floor(source).toInt().coerceIn(0, mono.lastIndex)
            val right = (left + 1).coerceAtMost(mono.lastIndex)
            val fraction = (source - left).toFloat()
            mono[left] + (mono[right] - mono[left]) * fraction
        }
    }
}
