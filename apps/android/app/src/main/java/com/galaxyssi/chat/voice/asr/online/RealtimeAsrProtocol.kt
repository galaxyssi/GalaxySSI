package com.galaxyssi.chat.voice.asr.online

import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.asr.AsrAudioFrame
import com.galaxyssi.chat.voice.asr.AsrError
import com.galaxyssi.chat.voice.asr.AsrEvent
import com.galaxyssi.chat.voice.asr.AsrMetrics
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import com.galaxyssi.chat.voice.asr.AsrTransport
import com.galaxyssi.chat.voice.asr.AsrUsage
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

data class AsrAudioBatch(
    val firstSequence: Long,
    val lastSequence: Long,
    val firstCaptureTimeNanos: Long,
    val lastCaptureTimeNanos: Long,
    val samples: ShortArray,
    val sampleRateHz: Int
) {
    val durationMs: Long
        get() = samples.size.toLong() * 1_000L / sampleRateHz
}

class RealtimePcmBatcher(
    private val targetBatchMs: Int = 60,
    private val maximumBatchMs: Int = 100
) {
    private val lock = Any()
    private val frames = arrayListOf<AsrAudioFrame>()
    private var durationMs = 0L

    init {
        require(targetBatchMs in 40..100)
        require(maximumBatchMs in targetBatchMs..100)
    }

    fun offer(frame: AsrAudioFrame): List<AsrAudioBatch> = synchronized(lock) {
        val output = arrayListOf<AsrAudioBatch>()
        val previous = frames.lastOrNull()
        if (previous != null && frame.sequence != previous.sequence + 1L) flushLocked()?.let(output::add)
        frames += frame.copy(samples = frame.samples.copyOf())
        durationMs += frame.durationMs
        if (durationMs >= targetBatchMs || durationMs >= maximumBatchMs) flushLocked()?.let(output::add)
        output
    }

    fun flush(): AsrAudioBatch? = synchronized(lock) { flushLocked() }

    fun clear() = synchronized(lock) {
        frames.forEach { it.samples.fill(0) }
        frames.clear()
        durationMs = 0L
    }

    private fun flushLocked(): AsrAudioBatch? {
        if (frames.isEmpty()) return null
        val first = frames.first()
        val last = frames.last()
        val sampleCount = frames.sumOf { it.samples.size }
        val samples = ShortArray(sampleCount)
        var offset = 0
        frames.forEach { frame ->
            frame.samples.copyInto(samples, offset)
            offset += frame.samples.size
            frame.samples.fill(0)
        }
        frames.clear()
        durationMs = 0L
        return AsrAudioBatch(
            firstSequence = first.sequence,
            lastSequence = last.sequence,
            firstCaptureTimeNanos = first.captureTimeNanos,
            lastCaptureTimeNanos = last.captureTimeNanos,
            samples = samples,
            sampleRateHz = first.sampleRateHz
        )
    }
}

interface RealtimeAsrWireProtocol {
    fun startMessage(config: AsrSessionConfig, credential: EphemeralAsrCredential): String
    fun finishMessage(config: AsrSessionConfig): String
    fun abortMessage(config: AsrSessionConfig, reasonCode: String): String
    fun heartbeatMessage(config: AsrSessionConfig, sentAtEpochMs: Long): String
    fun encodeAudio(batch: AsrAudioBatch): ByteString
    fun parseServerEvent(
        text: String,
        config: AsrSessionConfig,
        credential: EphemeralAsrCredential
    ): AsrEvent?
}

object SignalAsrRealtimeProtocol : RealtimeAsrWireProtocol {
    private const val MAGIC = 0x53415352
    private const val VERSION: Short = 1

    override fun startMessage(config: AsrSessionConfig, credential: EphemeralAsrCredential): String = JSONObject()
        .put("schema_version", 1)
        .put("event_type", "session.start")
        .put("voice_session_id", config.voiceSessionId)
        .put("transcript_id", config.transcriptId)
        .put("provider_session_id", credential.providerSessionId)
        .put("language", config.language)
        .put("encoding", "pcm_s16le")
        .put("sample_rate_hz", config.sampleRateHz)
        .put("channel_count", config.channelCount)
        .put("server_vad", true)
        .put(
            "request_server_data_deletion",
            config.privacy.requestServerDataDeletion && credential.serverDataDeletionSupported
        )
        .toString()

    override fun finishMessage(config: AsrSessionConfig): String = control(config, "input.finish")

    override fun abortMessage(config: AsrSessionConfig, reasonCode: String): String =
        control(config, "session.abort").let { source ->
            JSONObject(source).put("reason_code", reasonCode).toString()
        }

    override fun heartbeatMessage(config: AsrSessionConfig, sentAtEpochMs: Long): String =
        JSONObject(control(config, "session.heartbeat"))
            .put("sent_at_epoch_ms", sentAtEpochMs)
            .toString()

    override fun encodeAudio(batch: AsrAudioBatch): ByteString {
        val headerBytes = 4 + 2 + 2 + 8 + 8 + 8 + 8 + 4 + 4
        val buffer = ByteBuffer.allocate(headerBytes + batch.samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(MAGIC)
        buffer.putShort(VERSION)
        buffer.putShort(0)
        buffer.putLong(batch.firstSequence)
        buffer.putLong(batch.lastSequence)
        buffer.putLong(batch.firstCaptureTimeNanos)
        buffer.putLong(batch.lastCaptureTimeNanos)
        buffer.putInt(batch.sampleRateHz)
        buffer.putInt(batch.samples.size)
        batch.samples.forEach(buffer::putShort)
        return buffer.array().toByteString()
    }

    override fun parseServerEvent(
        text: String,
        config: AsrSessionConfig,
        credential: EphemeralAsrCredential
    ): AsrEvent? {
        val json = runCatching { JSONObject(text) }.getOrNull() ?: return null
        val eventType = json.optString("event_type", json.optString("type")).lowercase()
        val providerId = json.optString("provider_id", credential.providerId)
        val providerSessionId = json.optString("provider_session_id", credential.providerSessionId)
        val serverTimestamp = json.optLong("server_timestamp_ms", Long.MIN_VALUE)
            .takeUnless { it == Long.MIN_VALUE }
        return when (eventType) {
            "ready", "session.ready" -> AsrEvent.Ready(providerId, providerSessionId, AsrTransport.WEBSOCKET)
            "speech_started", "input.speech_started" -> AsrEvent.SpeechStarted(
                providerId,
                providerSessionId,
                json.optLong("sequence", Long.MIN_VALUE).takeUnless { it == Long.MIN_VALUE },
                serverTimestamp
            )
            "partial", "transcript.partial" -> AsrEvent.Partial(hypothesis(json, config, providerId, false))
            "stable", "transcript.stable" -> AsrEvent.Stable(hypothesis(json, config, providerId, false))
            "final", "transcript.final" -> AsrEvent.Final(hypothesis(json, config, providerId, true))
            "usage", "session.usage" -> AsrEvent.Usage(
                AsrUsage(
                    providerId,
                    providerSessionId,
                    json.optLong("audio_duration_ms", 0L).coerceAtLeast(0L),
                    json.optLong("billable_duration_ms", Long.MIN_VALUE).takeUnless { it == Long.MIN_VALUE },
                    serverTimestamp
                )
            )
            "recoverable_error", "error.recoverable" -> AsrEvent.RecoverableError(
                error(json, providerId, providerSessionId, retryable = true, serverTimestamp)
            )
            "fatal_error", "error.fatal" -> AsrEvent.FatalError(
                error(json, providerId, providerSessionId, retryable = false, serverTimestamp)
            )
            "closed", "session.closed" -> AsrEvent.Closed(
                providerId,
                providerSessionId,
                json.optString("reason_code")
            )
            "metrics", "session.metrics" -> AsrEvent.Metrics(
                AsrMetrics(
                    providerId = providerId,
                    providerSessionId = providerSessionId,
                    audioSentMs = json.optLong("audio_sent_ms", 0L).coerceAtLeast(0L),
                    firstPartialLatencyMs = optionalLong(json, "first_partial_latency_ms"),
                    finalLatencyMs = optionalLong(json, "final_latency_ms"),
                    reconnectCount = json.optInt("reconnect_count", 0).coerceAtLeast(0),
                    droppedAudioBatches = json.optInt("dropped_audio_batches", 0).coerceAtLeast(0),
                    serverTimestampMs = serverTimestamp
                )
            )
            else -> null
        }
    }

    fun decodeAudio(bytes: ByteString): AsrAudioBatch {
        val buffer = bytes.asByteBuffer().order(ByteOrder.LITTLE_ENDIAN)
        require(buffer.int == MAGIC) { "Invalid realtime ASR audio magic" }
        require(buffer.short == VERSION) { "Unsupported realtime ASR audio version" }
        buffer.short
        val firstSequence = buffer.long
        val lastSequence = buffer.long
        val firstCapture = buffer.long
        val lastCapture = buffer.long
        val sampleRate = buffer.int
        val sampleCount = buffer.int
        require(sampleCount >= 0 && buffer.remaining() == sampleCount * 2)
        val samples = ShortArray(sampleCount) { buffer.short }
        return AsrAudioBatch(firstSequence, lastSequence, firstCapture, lastCapture, samples, sampleRate)
    }

    private fun hypothesis(
        json: JSONObject,
        config: AsrSessionConfig,
        providerId: String,
        final: Boolean
    ): TranscriptHypothesis {
        val revision = json.optLong("revision", json.optLong("sequence", 0L))
            .coerceIn(0L, Int.MAX_VALUE.toLong())
            .toInt()
        return TranscriptHypothesis(
            text = json.optString("text"),
            revision = revision,
            provider = providerId,
            modelProfileId = json.optString("model_profile_id"),
            confidence = json.optDouble("confidence", Double.NaN).takeUnless(Double::isNaN)?.toFloat(),
            transcriptId = json.optString("transcript_id", config.transcriptId),
            stablePrefixLength = json.optInt("stable_prefix_length", 0).coerceAtLeast(0),
            isFinal = final,
            language = json.optString("language").takeIf(String::isNotBlank),
            segmentStartMs = json.optLong("segment_start_ms", 0L).coerceAtLeast(0L),
            segmentEndMs = json.optLong("segment_end_ms", 0L).coerceAtLeast(0L),
            averageLogProb = json.optDouble("average_log_prob", Double.NaN).takeUnless(Double::isNaN)?.toFloat(),
            noSpeechProbability = json.optDouble("no_speech_probability", Double.NaN).takeUnless(Double::isNaN)?.toFloat(),
            createdElapsedNs = System.nanoTime().coerceAtLeast(0L)
        )
    }

    private fun error(
        json: JSONObject,
        providerId: String,
        providerSessionId: String,
        retryable: Boolean,
        serverTimestampMs: Long?
    ) = AsrError(
        code = json.optString("code", "provider_error"),
        message = json.optString("message").take(240),
        retryable = json.optBoolean("retryable", retryable),
        providerId = providerId,
        providerSessionId = providerSessionId,
        serverTimestampMs = serverTimestampMs
    )

    private fun control(config: AsrSessionConfig, type: String): String = JSONObject()
        .put("schema_version", 1)
        .put("event_type", type)
        .put("voice_session_id", config.voiceSessionId)
        .put("transcript_id", config.transcriptId)
        .toString()

    private fun optionalLong(json: JSONObject, key: String): Long? =
        json.optLong(key, Long.MIN_VALUE).takeUnless { it == Long.MIN_VALUE }
}
