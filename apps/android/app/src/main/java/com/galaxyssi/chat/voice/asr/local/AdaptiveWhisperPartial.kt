package com.galaxyssi.chat.voice.asr.local

import com.galaxyssi.chat.LocalWhisperException
import com.galaxyssi.chat.voice.audio.PcmSnapshot
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperModelFamily
import com.galaxyssi.chat.voice.model.WhisperModelProfile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

data class AdaptivePartialSnapshot(
    val enabled: Boolean,
    val intervalMs: Long,
    val windowMs: Long,
    val backlogStreak: Int,
    val recentRealTimeFactor: Double?
)

class AdaptiveWhisperPartialPolicy(
    private val profile: WhisperModelProfile,
    certifiedPartialIntervalMs: Long? = null,
    realtimeCertified: Boolean = profile.recommendedMode == WhisperExecutionMode.REALTIME_PARTIAL
) {
    private val baseIntervalMs = when (profile.family) {
        WhisperModelFamily.TINY -> profile.defaultPartialIntervalMs.coerceIn(500L, 1_000L)
        WhisperModelFamily.BASE -> profile.defaultPartialIntervalMs.coerceIn(800L, 1_500L)
        else -> profile.defaultPartialIntervalMs.coerceIn(1_500L, MAX_PARTIAL_INTERVAL_MS)
    }
    private val baseWindowMs = when (profile.family) {
        WhisperModelFamily.TINY -> profile.maxWindowMs.coerceIn(4_000L, 8_000L)
        WhisperModelFamily.BASE -> profile.maxWindowMs.coerceIn(5_000L, 10_000L)
        else -> profile.maxWindowMs.coerceIn(6_000L, 20_000L)
    }
    private val certifiedBaseIntervalMs = certifiedPartialIntervalMs
        ?.takeIf { it > 0L }
        ?.coerceIn(MIN_PARTIAL_INTERVAL_MS, MAX_PARTIAL_INTERVAL_MS)
        ?: baseIntervalMs
    private var intervalMs = certifiedBaseIntervalMs
    private var windowMs = baseWindowMs
    private var lastSubmittedAtMs = Long.MIN_VALUE
    private var backlogStreak = 0
    private var healthyStreak = 0
    private var recentRtf: Double? = null
    private var enabled = realtimeCertified

    @Synchronized
    fun shouldSubmit(nowMs: Long, capturedAudioMs: Long, queue: DecodeQueueSnapshot): Boolean {
        if (!enabled || capturedAudioMs < MIN_PARTIAL_AUDIO_MS) return false
        val backlog = queue.queuedPartials + if (queue.activeMode == WhisperExecutionMode.REALTIME_PARTIAL) 1 else 0
        if (backlog >= 2) {
            backlogStreak += 1
            healthyStreak = 0
            intervalMs = (intervalMs * 2).coerceAtMost(MAX_PARTIAL_INTERVAL_MS)
            return false
        }
        if (lastSubmittedAtMs != Long.MIN_VALUE && nowMs - lastSubmittedAtMs < intervalMs) return false
        lastSubmittedAtMs = nowMs
        return true
    }

    @Synchronized
    fun onDecodeCompleted(realTimeFactor: Double, queue: DecodeQueueSnapshot) {
        recentRtf = realTimeFactor.takeIf { it.isFinite() && it >= 0.0 }
        val backlog = queue.queuedPartials + if (queue.activeMode == WhisperExecutionMode.REALTIME_PARTIAL) 1 else 0
        if (backlog > 0) {
            backlogStreak += 1
            healthyStreak = 0
        } else {
            backlogStreak = 0
            healthyStreak += 1
        }
        when {
            realTimeFactor > 1.50 -> enabled = false
            realTimeFactor > 1.20 -> intervalMs = (certifiedBaseIntervalMs * 3).coerceAtMost(MAX_PARTIAL_INTERVAL_MS)
            realTimeFactor > 0.80 -> intervalMs = (certifiedBaseIntervalMs * 3 / 2).coerceAtMost(MAX_PARTIAL_INTERVAL_MS)
            realTimeFactor > 0.50 -> intervalMs = certifiedBaseIntervalMs
            else -> intervalMs = (certifiedBaseIntervalMs * 4 / 5).coerceAtLeast(MIN_PARTIAL_INTERVAL_MS)
        }
        if (realTimeFactor > 0.80) windowMs = (baseWindowMs * 3 / 4).coerceAtLeast(MIN_PARTIAL_WINDOW_MS)
        else if (healthyStreak >= 2) windowMs = baseWindowMs
    }

    @Synchronized
    fun snapshot(): AdaptivePartialSnapshot = AdaptivePartialSnapshot(
        enabled = enabled,
        intervalMs = intervalMs,
        windowMs = windowMs,
        backlogStreak = backlogStreak,
        recentRealTimeFactor = recentRtf
    )

    private companion object {
        const val MIN_PARTIAL_AUDIO_MS = 800L
        const val MIN_PARTIAL_INTERVAL_MS = 400L
        const val MAX_PARTIAL_INTERVAL_MS = 6_000L
        const val MIN_PARTIAL_WINDOW_MS = 3_000L
    }
}

data class LiveWhisperTranscriptUpdate(
    val voiceSessionId: String,
    val transcript: StabilizedTranscript,
    val modelProfileId: String,
    val realTimeFactor: Double
)

class LiveWhisperTranscriptionSession(
    private val voiceSessionId: String,
    private val profile: WhisperModelProfile,
    private val language: String,
    private val scheduler: WhisperDecodeScheduler,
    private val scope: CoroutineScope,
    private val elapsedRealtime: () -> Long,
    certifiedPartialIntervalMs: Long? = null,
    realtimeCertified: Boolean = profile.recommendedMode == WhisperExecutionMode.REALTIME_PARTIAL,
    private val onUpdate: (LiveWhisperTranscriptUpdate) -> Unit
) : AutoCloseable {
    private val policy = AdaptiveWhisperPartialPolicy(
        profile,
        certifiedPartialIntervalMs = certifiedPartialIntervalMs,
        realtimeCertified = realtimeCertified
    )
    private val segmentDecoder = WhisperSegmentDecoder()
    private val stabilizer = WhisperTextStabilizer()
    private val finalized = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val requestSequence = AtomicInteger(0)
    private val resultMutex = Mutex()
    private var lastAppliedRevision = 0

    val modelProfileId: String
        get() = profile.id

    fun partialPolicy(): AdaptivePartialSnapshot = policy.snapshot()

    fun nextPartialWindowMs(capturedAudioMs: Long): Long? {
        if (closed.get() || finalized.get()) return null
        val queue = scheduler.queueSnapshot()
        return if (policy.shouldSubmit(elapsedRealtime(), capturedAudioMs, queue)) {
            policy.snapshot().windowMs
        } else null
    }

    fun offerPartial(snapshot: PcmSnapshot) {
        if (closed.get() || finalized.get() || !snapshot.speechDetected) return
        val request = request(snapshot, WhisperExecutionMode.REALTIME_PARTIAL, WhisperDecodePriority.CURRENT_PARTIAL)
        scope.launch {
            when (val result = scheduler.submit(request)) {
                is ScheduledWhisperResult.Completed -> {
                    val decoded = segmentDecoder.decode(request, result.native)
                    policy.onDecodeCompleted(decoded.realTimeFactor, scheduler.queueSnapshot())
                    resultMutex.withLock {
                        if (closed.get() || finalized.get() || request.revision <= lastAppliedRevision) return@withLock
                        lastAppliedRevision = request.revision
                        val transcript = stabilizer.accept(decoded)
                        if (transcript.displayText.isNotBlank()) {
                            onUpdate(
                                LiveWhisperTranscriptUpdate(
                                    voiceSessionId,
                                    transcript,
                                    profile.id,
                                    decoded.realTimeFactor
                                )
                            )
                        }
                    }
                }
                is ScheduledWhisperResult.Failed -> policy.onDecodeCompleted(Double.POSITIVE_INFINITY, scheduler.queueSnapshot())
                is ScheduledWhisperResult.Dropped -> Unit
            }
        }
    }

    suspend fun finish(snapshot: PcmSnapshot): NativeWhisperResult {
        check(finalized.compareAndSet(false, true)) { "Final transcript was already requested" }
        val request = request(snapshot, WhisperExecutionMode.FINAL_ONLY, WhisperDecodePriority.CURRENT_FINAL)
        return when (val result = scheduler.submit(request)) {
            is ScheduledWhisperResult.Completed -> {
                val decoded = segmentDecoder.decode(request, result.native)
                resultMutex.withLock {
                    lastAppliedRevision = request.revision
                    val transcript = stabilizer.accept(decoded)
                    onUpdate(LiveWhisperTranscriptUpdate(voiceSessionId, transcript, profile.id, decoded.realTimeFactor))
                }
                result.native
            }
            is ScheduledWhisperResult.Failed -> throw result.error
            is ScheduledWhisperResult.Dropped -> throw LocalWhisperException(
                NativeWhisperCode.ABORTED,
                "Final Whisper decode was dropped: ${result.reason}"
            )
        }
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        scheduler.cancelSession(voiceSessionId)
    }

    private fun request(
        snapshot: PcmSnapshot,
        mode: WhisperExecutionMode,
        priority: WhisperDecodePriority
    ): ScheduledWhisperDecode {
        val revision = requestSequence.incrementAndGet()
        return ScheduledWhisperDecode(
            requestId = "$voiceSessionId:$revision",
            voiceSessionId = voiceSessionId,
            revision = revision,
            modelProfileId = profile.id,
            pcm16 = snapshot.samples,
            sampleRateHz = snapshot.sampleRateHz,
            language = language,
            mode = mode,
            priority = priority,
            windowStartSample = snapshot.captureStartSample,
            windowEndSampleExclusive = snapshot.captureEndSampleExclusive
        )
    }
}
