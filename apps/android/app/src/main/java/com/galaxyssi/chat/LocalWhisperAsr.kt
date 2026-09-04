package com.galaxyssi.chat

import android.content.Context
import android.icu.text.Transliterator
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.galaxyssi.chat.voice.VoiceFeatureFlags
import com.galaxyssi.chat.voice.asr.local.AbortReason
import com.galaxyssi.chat.voice.asr.local.AcceleratedLocalWhisperRuntime
import com.galaxyssi.chat.voice.asr.local.LocalWhisperRuntime
import com.galaxyssi.chat.voice.asr.local.LocalWhisperSessionConfig
import com.galaxyssi.chat.voice.asr.local.NativeWhisperCode
import com.galaxyssi.chat.voice.asr.local.NativeWhisperResult
import com.galaxyssi.chat.voice.asr.local.QnnWhisperPackageManager
import com.galaxyssi.chat.voice.asr.local.WhisperDecodeRequest
import com.galaxyssi.chat.voice.asr.local.WhisperFinalAudioChunker
import com.galaxyssi.chat.voice.asr.local.WhisperFinalResultAssembler
import com.galaxyssi.chat.voice.asr.local.WhisperLoadOptions
import com.galaxyssi.chat.voice.asr.local.WhisperRuntimeState
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkManager
import com.galaxyssi.chat.voice.benchmark.WhisperProviderChoice
import com.galaxyssi.chat.voice.benchmark.WhisperUserVoiceMode
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTraceContext
import com.galaxyssi.chat.voice.metrics.VoiceTraceEvents
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import com.whispercpp.whisper.WhisperContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import kotlin.math.floor
import kotlin.math.roundToInt

class LocalWhisperException(
    val code: NativeWhisperCode,
    message: String
) : IllegalStateException(message)

data class LocalWhisperDecodeOutcome(
    val profileId: String,
    val result: NativeWhisperResult
)

data class LocalWhisperTranscriptionOutcome(
    val text: String,
    val profileId: String,
    val confidence: Float?
)

object LocalWhisperAsr {
    private const val TAG = "GalaxySSILocalASR"
    private const val TARGET_SAMPLE_RATE = 16_000
    private val mutex = Mutex()
    @Volatile private var whisperRuntime: LocalWhisperRuntime? = null
    @Volatile private var legacyContext: WhisperContext? = null
    @Volatile private var legacyModelId: String? = null

    suspend fun transcribe(
        context: Context,
        audioFile: File,
        language: String = "auto",
        traceId: String = VoiceLatencyTraceContext.currentTraceId()
    ): String {
        val decodeStartedAtNs = SystemClock.elapsedRealtimeNanos()
        trace(context, traceId, VoiceTraceEvents.ASR_DECODE_STARTED, mapOf("audio_source" to "compatibility_file"))
        val samples = decodeAudioFileToPcm16(audioFile)
        val decodeDurationMs = (SystemClock.elapsedRealtimeNanos() - decodeStartedAtNs) / 1_000_000L
        trace(
            context,
            traceId,
            VoiceTraceEvents.ASR_DECODE_COMPLETED,
            mapOf(
                "audio_source" to "compatibility_file",
                "duration_ms" to decodeDurationMs.toString(),
                "audio_duration_ms" to durationMs(samples).toString()
            )
        )
        return transcribePcm(context, samples, TARGET_SAMPLE_RATE, language, traceId, "compatibility_file")
    }

    suspend fun transcribePcm(
        context: Context,
        pcm16: ShortArray,
        sampleRateHz: Int = TARGET_SAMPLE_RATE,
        language: String = "auto",
        traceId: String = VoiceLatencyTraceContext.currentTraceId(),
        source: String = "audio_record_pcm16"
    ): String = transcribePcmOutcome(
        context,
        pcm16,
        sampleRateHz,
        language,
        traceId,
        source
    ).text

    internal suspend fun transcribePcmOutcome(
        context: Context,
        pcm16: ShortArray,
        sampleRateHz: Int = TARGET_SAMPLE_RATE,
        language: String = "auto",
        traceId: String = VoiceLatencyTraceContext.currentTraceId(),
        source: String = "audio_record_pcm16",
        requestedProfileIdOverride: String? = null
    ): LocalWhisperTranscriptionOutcome {
        return mutex.withLock {
        require(sampleRateHz == TARGET_SAMPLE_RATE) { "Local Whisper requires 16 kHz PCM16" }
        require(pcm16.isNotEmpty()) { "PCM16 audio is empty" }
        val startedAtNs = SystemClock.elapsedRealtimeNanos()
        val config = VoiceAssistantSettings.get(context)
        val requested = WhisperModelManager.model(requestedProfileIdOverride ?: config.asrModel)
        val audioDurationMs = durationMs(pcm16)
        val selectedQnnPackage = QnnWhisperPackageManager.selectedPackage(context)
        val manualInstalledQnn = shouldBypassWhisperCertificationForManualQnn(
            runtimeMode = config.asrRuntimeMode,
            acceleration = config.asrAcceleration,
            selectedProfileId = requested.id,
            qnnProfileId = selectedQnnPackage?.profileId,
            qnnInstalled = selectedQnnPackage?.let {
                QnnWhisperPackageManager.isInstalled(context, it)
            } == true
        )
        val policyDecision = if (
            VoiceFeatureFlags.isWhisperPolicyEngineEnabled(context) && !manualInstalledQnn
        ) {
            WhisperBenchmarkManager.decide(
                context = context,
                userMode = if (requestedProfileIdOverride != null) {
                    WhisperUserVoiceMode.MANUAL
                } else {
                    config.asrRuntimeMode
                },
                selectedProfileId = requested.id,
                foreground = true,
                utteranceDurationMs = audioDurationMs
            )
        } else null
        val requestedCertification = if (policyDecision != null) {
            WhisperBenchmarkManager.current(context, requested)?.certification
        } else null
        if (requestedCertification?.remoteRecommended == true &&
            policyDecision?.provider != WhisperProviderChoice.LOCAL
        ) {
            throw LocalWhisperException(
                NativeWhisperCode.UNSUPPORTED_MODEL,
                requestedCertification.failureReason ?: "This model is certified for remote use only"
            )
        }
        if (policyDecision != null && policyDecision.provider != WhisperProviderChoice.LOCAL) {
            throw LocalWhisperException(
                NativeWhisperCode.UNSUPPORTED_MODEL,
                policyDecision.reasons.joinToString(". ").ifBlank {
                    "No locally certified Whisper model is available"
                }
            )
        }
        val selected = policyDecision
            ?.fastProfileId
            ?.let(WhisperModelManager::model)
            ?: requested
        val selectedCertification = if (policyDecision != null) {
            WhisperBenchmarkManager.current(context, selected)?.certification
        } else null
        val threadCount = (policyDecision?.threadCount ?: selectedCertification?.recommendedThreadCount ?: 2)
            .coerceIn(1, minOf(16, Runtime.getRuntime().availableProcessors().coerceAtLeast(1)))
        val baseAttributes = mapOf(
            "asr_provider" to "whisper.cpp",
            "model_profile_id" to selected.id,
            "execution_mode" to "final",
            "thread_count" to threadCount.toString(),
            "audio_source" to source,
            "audio_duration_ms" to audioDurationMs.toString()
        )
        trace(context, traceId, VoiceTraceEvents.ASR_FINAL_STARTED, baseAttributes, once = true)
        try {
            require(
                WhisperModelManager.isAvailable(context, selected) ||
                    (manualInstalledQnn && selected.id == requested.id)
            ) {
                "ASR model ${selected.displayName} is not downloaded"
            }
            val normalizedLanguage = language.substringBefore('-').lowercase()
                .takeIf { it in setOf("zh", "en") } ?: "auto"
            val rawText: String
            val inferenceDurationMs: Long
            val rtf: String
            var confidence: Float? = null
            if (VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled(context)) {
                val result = decodeWithRuntimeV2(
                    context = context,
                    profile = selected,
                    pcm16 = pcm16,
                    normalizedLanguage = normalizedLanguage,
                    mode = WhisperExecutionMode.FINAL_ONLY,
                    threadCount = threadCount,
                    traceId = traceId,
                    attributes = baseAttributes
                )
                if (!result.successful) {
                    throw LocalWhisperException(result.code, result.message ?: "Whisper decode failed (${result.code})")
                }
                rawText = result.text
                confidence = result.segments
                    .map { segment -> segment.averageLogProb }
                    .filterNot(Float::isNaN)
                    .takeIf { values -> values.isNotEmpty() }
                    ?.map { value -> kotlin.math.exp(value.toDouble()) }
                    ?.average()
                    ?.toFloat()
                    ?.coerceIn(0f, 1f)
                inferenceDurationMs = result.timings.totalMs.toLong().coerceAtLeast(0L)
                rtf = String.format(Locale.US, "%.4f", result.timings.realTimeFactor)
            } else {
                rawText = transcribeWithLegacyRuntime(
                    context,
                    selected.id,
                    WhisperModelManager.ensureVerifiedFile(context, selected),
                    pcm16,
                    normalizedLanguage,
                    threadCount,
                    traceId,
                    baseAttributes
                )
                inferenceDurationMs = (SystemClock.elapsedRealtimeNanos() - startedAtNs) / 1_000_000L
                rtf = if (audioDurationMs > 0L) {
                    String.format(Locale.US, "%.4f", inferenceDurationMs.toDouble() / audioDurationMs)
                } else "0"
            }
            trace(
                context,
                traceId,
                VoiceTraceEvents.WHISPER_FULL_COMPLETED,
                baseAttributes + mapOf("duration_ms" to inferenceDurationMs.toString(), "rtf" to rtf)
            )
            val text = normalizeChineseScript(rawText.trim(), language)
            val totalDurationMs = (SystemClock.elapsedRealtimeNanos() - startedAtNs) / 1_000_000L
            trace(
                context,
                traceId,
                VoiceTraceEvents.ASR_FINAL_RECEIVED,
                baseAttributes + mapOf("duration_ms" to totalDurationMs.toString(), "success" to "true"),
                once = true
            )
            Log.i(
                TAG,
                "Local transcription completed model=${selected.id} samples=${pcm16.size} " +
                    "language=$normalizedLanguage source=$source elapsed=${totalDurationMs}ms"
            )
            LocalWhisperTranscriptionOutcome(
                text = text,
                profileId = selected.id,
                confidence = confidence
            )
        } catch (error: Throwable) {
            trace(
                context,
                traceId,
                VoiceTraceEvents.ASR_FINAL_FAILED,
                baseAttributes + mapOf(
                    "duration_ms" to ((SystemClock.elapsedRealtimeNanos() - startedAtNs) / 1_000_000L).toString(),
                    "success" to "false",
                    "error_code" to ((error as? LocalWhisperException)?.code?.name ?: error.javaClass.simpleName)
                ),
                once = true
            )
            throw error
        }
        }
    }

    internal suspend fun decodePcmWindow(
        context: Context,
        pcm16: ShortArray,
        sampleRateHz: Int,
        language: String,
        mode: WhisperExecutionMode,
        traceId: String,
        source: String,
        modelProfileId: String
    ): LocalWhisperDecodeOutcome {
        return mutex.withLock {
        require(VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled(context)) {
            "Local Whisper Runtime v2 is disabled"
        }
        require(sampleRateHz == TARGET_SAMPLE_RATE) { "Local Whisper requires 16 kHz PCM16" }
        require(pcm16.isNotEmpty()) { "PCM16 audio is empty" }
        val profile = WhisperModelManager.model(modelProfileId)
        require(WhisperModelManager.isAvailable(context, profile)) {
            "ASR model ${profile.displayName} is not downloaded"
        }
        val certifiedThreads = if (VoiceFeatureFlags.isWhisperPolicyEngineEnabled(context)) {
            WhisperBenchmarkManager.current(context, profile)?.certification?.recommendedThreadCount
        } else null
        val threadCount = (certifiedThreads ?: 2)
            .coerceIn(1, minOf(16, Runtime.getRuntime().availableProcessors().coerceAtLeast(1)))
        val normalizedLanguage = language.substringBefore('-').lowercase()
            .takeIf { it in setOf("zh", "en") } ?: "auto"
        val attributes = mapOf(
            "asr_provider" to "whisper.cpp",
            "model_profile_id" to profile.id,
            "execution_mode" to mode.name.lowercase(Locale.US),
            "thread_count" to threadCount.toString(),
            "audio_source" to source,
            "audio_duration_ms" to durationMs(pcm16).toString()
        )
        val result = decodeWithRuntimeV2(
            context = context,
            profile = profile,
            pcm16 = pcm16,
            normalizedLanguage = normalizedLanguage,
            mode = mode,
            threadCount = threadCount,
            traceId = traceId,
            attributes = attributes
        )
        trace(
            context,
            traceId,
            VoiceTraceEvents.WHISPER_FULL_COMPLETED,
            attributes + mapOf(
                "duration_ms" to result.timings.totalMs.toLong().coerceAtLeast(0L).toString(),
                "rtf" to String.format(Locale.US, "%.4f", result.timings.realTimeFactor),
                "success" to result.successful.toString()
            )
        )
        if (!result.successful) {
            throw LocalWhisperException(result.code, result.message ?: "Whisper decode failed (${result.code})")
        }
            LocalWhisperDecodeOutcome(profile.id, normalizeResultScript(result, language))
        }
    }

    fun requestAbort(reason: AbortReason = AbortReason.USER_STOP) {
        whisperRuntime?.requestAbortAll(reason)
    }

    suspend fun release() = mutex.withLock {
        whisperRuntime?.close()
        whisperRuntime = null
        releaseLegacyContext()
    }

    private suspend fun decodeWithRuntimeV2(
        context: Context,
        profile: WhisperModelProfile,
        pcm16: ShortArray,
        normalizedLanguage: String,
        mode: WhisperExecutionMode,
        threadCount: Int,
        traceId: String,
        attributes: Map<String, String>
    ): NativeWhisperResult {
        releaseLegacyContext()
        val runtime = whisperRuntime ?: AcceleratedLocalWhisperRuntime(context.applicationContext).also {
            whisperRuntime = it
        }
        val coldStart = (runtime.state.value as? WhisperRuntimeState.Ready)?.model?.profile?.id != profile.id
        if (coldStart) {
            trace(context, traceId, VoiceTraceEvents.ASR_MODEL_LOAD_STARTED, attributes + ("cold_start" to "true"))
        }
        val loadedModel = runtime.load(profile, WhisperLoadOptions(threadCount = threadCount))
        val runtimeAttributes = attributes + mapOf(
            "acceleration_backend" to loadedModel.accelerationBackend.name,
            "acceleration_detail" to loadedModel.accelerationDetail
        )
        Log.i(
            TAG,
            "Whisper backend=${loadedModel.accelerationBackend} " +
                "detail=${loadedModel.accelerationDetail} model=${profile.id}"
        )
        if (coldStart) {
            trace(
                context,
                traceId,
                VoiceTraceEvents.ASR_MODEL_LOAD_COMPLETED,
                runtimeAttributes + ("cold_start" to "true")
            )
        }
        trace(context, traceId, VoiceTraceEvents.WHISPER_FULL_STARTED, runtimeAttributes)
        return runtime.createSession(
            LocalWhisperSessionConfig(
                language = normalizedLanguage,
                noContext = true,
                singleSegment = mode == WhisperExecutionMode.REALTIME_PARTIAL,
                mode = mode
            )
        ).use { session ->
            val chunks = WhisperFinalAudioChunker.plan(
                sampleCount = pcm16.size,
                sampleRateHz = TARGET_SAMPLE_RATE,
                mode = mode
            )
            if (chunks.size == 1) {
                session.decode(WhisperDecodeRequest(pcm16 = pcm16, mode = mode))
            } else {
                val results = chunks.map { chunk ->
                    chunk to session.decode(
                        WhisperDecodeRequest(
                            pcm16 = pcm16,
                            offset = chunk.offset,
                            length = chunk.length,
                            mode = mode
                        )
                    )
                }
                WhisperFinalResultAssembler.assemble(
                    chunks = results,
                    totalSamples = pcm16.size,
                    sampleRateHz = TARGET_SAMPLE_RATE
                )
            }
        }
    }

    private suspend fun transcribeWithLegacyRuntime(
        context: Context,
        modelId: String,
        modelFile: File,
        pcm16: ShortArray,
        language: String,
        threadCount: Int,
        traceId: String,
        attributes: Map<String, String>
    ): String {
        if (legacyModelId != modelId) releaseLegacyContext()
        val coldStart = legacyContext == null
        if (coldStart) trace(context, traceId, VoiceTraceEvents.ASR_MODEL_LOAD_STARTED, attributes + ("cold_start" to "true"))
        val model = legacyContext ?: WhisperContext.createContextFromFile(modelFile.absolutePath).also {
            legacyContext = it
            legacyModelId = modelId
            WhisperModelManager.markLoaded(modelId)
        }
        if (coldStart) trace(context, traceId, VoiceTraceEvents.ASR_MODEL_LOAD_COMPLETED, attributes + ("cold_start" to "true"))
        trace(context, traceId, VoiceTraceEvents.WHISPER_FULL_STARTED, attributes)
        val floatSamples = FloatArray(pcm16.size) { pcm16[it] / 32768f }
        return model.transcribeData(floatSamples, language, printTimestamp = false)
    }

    private suspend fun releaseLegacyContext() {
        legacyContext?.release()
        legacyContext = null
        WhisperModelManager.markUnloaded(legacyModelId)
        legacyModelId = null
    }

    private fun trace(
        context: Context,
        traceId: String,
        event: String,
        attributes: Map<String, String>,
        once: Boolean = false
    ) {
        if (traceId.isNotBlank()) VoiceLatencyTelemetry.record(context, traceId, event, attributes, once)
    }

    private fun normalizeChineseScript(text: String, language: String): String {
        if (!language.equals("zh-CN", ignoreCase = true) || text.isBlank()) return text
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Transliterator.getInstance("Traditional-Simplified").transliterate(text)
        } else text
    }

    private fun normalizeResultScript(result: NativeWhisperResult, language: String): NativeWhisperResult = result.copy(
        segments = result.segments.map { segment ->
            segment.copy(text = normalizeChineseScript(segment.text, language))
        }.toTypedArray()
    )

    private fun durationMs(samples: ShortArray): Long = samples.size.toLong() * 1_000L / TARGET_SAMPLE_RATE

    internal fun decodeAudioFileToPcm16(file: File): ShortArray {
        if (file.extension.equals("wav", ignoreCase = true)) return decodePcmWave(file)
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(file.absolutePath)
            decodeExtractorToPcm16(extractor)
        } finally {
            extractor.release()
        }
    }

    internal fun decodeAudioBytesToPcm16(bytes: ByteArray, extension: String): ShortArray {
        if (extension.equals("wav", ignoreCase = true)) {
            return try {
                decodePcmWave(bytes)
            } finally {
                bytes.fill(0)
            }
        }
        val source = WipingByteArrayMediaDataSource(bytes)
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(source)
            decodeExtractorToPcm16(extractor)
        } finally {
            extractor.release()
            source.close()
        }
    }

    private fun decodeExtractorToPcm16(extractor: MediaExtractor): ShortArray {
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
                                ByteArray(info.size).also { bytes -> output.get(bytes); pcm.write(bytes) }
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
        }
        val pcmBytes = pcm.toByteArray()
        return try {
            resamplePcm16(pcmBytes, sampleRate, channels)
        } finally {
            pcmBytes.fill(0)
            pcm.reset()
        }
    }

    private fun decodePcmWave(file: File): ShortArray {
        val bytes = file.readBytes()
        return try {
            decodePcmWave(bytes)
        } finally {
            bytes.fill(0)
        }
    }

    private fun decodePcmWave(bytes: ByteArray): ShortArray {
        require(bytes.size >= 44 && String(bytes, 0, 4, Charsets.US_ASCII) == "RIFF" &&
            String(bytes, 8, 4, Charsets.US_ASCII) == "WAVE") { "Invalid PCM wave file" }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        var offset = 12
        var sampleRate = 0
        var channels = 0
        var bitsPerSample = 0
        var audioFormat = 0
        var pcmBytes: ByteArray? = null
        while (offset + 8 <= bytes.size) {
            val chunkId = String(bytes, offset, 4, Charsets.US_ASCII)
            val chunkSize = buffer.getInt(offset + 4).coerceAtLeast(0)
            val payloadOffset = offset + 8
            if (payloadOffset + chunkSize > bytes.size) break
            when (chunkId) {
                "fmt " -> if (chunkSize >= 16) {
                    audioFormat = buffer.getShort(payloadOffset).toInt() and 0xffff
                    channels = buffer.getShort(payloadOffset + 2).toInt() and 0xffff
                    sampleRate = buffer.getInt(payloadOffset + 4)
                    bitsPerSample = buffer.getShort(payloadOffset + 14).toInt() and 0xffff
                }
                "data" -> pcmBytes = bytes.copyOfRange(payloadOffset, payloadOffset + chunkSize)
            }
            offset = payloadOffset + chunkSize + (chunkSize and 1)
        }
        require(audioFormat == 1 && bitsPerSample == 16) { "Only PCM16 wave audio is supported" }
        require(sampleRate > 0 && channels > 0) { "PCM wave format is incomplete" }
        return resamplePcm16(requireNotNull(pcmBytes) { "PCM wave data is missing" }, sampleRate, channels)
    }

    private fun resamplePcm16(bytes: ByteArray, sourceRate: Int, channels: Int): ShortArray {
        val shorts = bytes.size / 2
        if (shorts == 0 || sourceRate <= 0 || channels <= 0) return ShortArray(0)
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val frames = shorts / channels
        val mono = ShortArray(frames)
        for (frame in 0 until frames) {
            var sum = 0L
            for (channel in 0 until channels) sum += buffer.get(frame * channels + channel).toLong()
            mono[frame] = (sum / channels).coerceIn(Short.MIN_VALUE.toLong(), Short.MAX_VALUE.toLong()).toShort()
        }
        if (sourceRate == TARGET_SAMPLE_RATE) return mono
        val outputSize = (frames.toLong() * TARGET_SAMPLE_RATE / sourceRate).toInt().coerceAtLeast(1)
        return ShortArray(outputSize) { index ->
            val source = index.toDouble() * sourceRate / TARGET_SAMPLE_RATE
            val left = floor(source).toInt().coerceIn(0, mono.lastIndex)
            val right = (left + 1).coerceAtMost(mono.lastIndex)
            val fraction = source - left
            (mono[left] + (mono[right] - mono[left]) * fraction)
                .roundToInt()
                .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                .toShort()
        }
    }
}

internal fun shouldBypassWhisperCertificationForManualQnn(
    runtimeMode: WhisperUserVoiceMode,
    acceleration: String,
    selectedProfileId: String,
    qnnProfileId: String?,
    qnnInstalled: Boolean
): Boolean = runtimeMode == WhisperUserVoiceMode.MANUAL &&
    acceleration == VoiceAssistantSettings.ASR_ACCELERATION_QNN &&
    qnnInstalled &&
    qnnProfileId == selectedProfileId
