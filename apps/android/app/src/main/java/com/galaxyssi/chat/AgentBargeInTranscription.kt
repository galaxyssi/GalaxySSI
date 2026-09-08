package com.galaxyssi.chat

import android.os.SystemClock
import com.galaxyssi.chat.voice.asr.local.AbortReason
import com.galaxyssi.chat.voice.asr.local.HighAccuracyLocalAsrTurn
import com.galaxyssi.chat.voice.asr.local.LiveWhisperTranscriptionSession
import com.galaxyssi.chat.voice.asr.online.OnlineRealtimeAsrTurn
import com.galaxyssi.chat.voice.audio.DirectPcmFramePacket
import com.galaxyssi.chat.voice.audio.PcmFramePacket
import com.galaxyssi.chat.voice.audio.PcmSnapshot
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/** Reuses the configured PCM recognizers without opening a second microphone. */
internal class AgentBargeInTranscription(private val activity: MainActivity, val traceId: String) {
    private val closed = AtomicBoolean(false)
    @Volatile var receivingAudio = true
        private set
    private var sourceStart: Long? = null
    private var sourceEnd = 0L
    private var receivedSamples = 0L
    private var frameSequence = 0L
    private var startedAtNanos = 0L
    private var streamComplete = true
    private val directFrame = ByteBuffer.allocateDirect(640).order(ByteOrder.LITTLE_ENDIAN)

    private var online: OnlineRealtimeAsrTurn? = null
    private var highAccuracy: HighAccuracyLocalAsrTurn? = null
    private var local: LiveWhisperTranscriptionSession? = null
    init {
        try {
            LocalWhisperAsr.requestAbort(AbortReason.NEW_UTTERANCE)
            online = activity.startOnlineRealtimeAsrTurn("voice_wakeup", traceId)
            if (online == null) highAccuracy = activity.startHighAccuracyAsrTurn("voice_wakeup", traceId)
            if (online == null && highAccuracy == null) local = activity.startLiveWhisperSession("voice_wakeup", traceId)
            online?.onLocalSpeechStarted()
        } catch (error: Throwable) {
            close()
            throw error
        }
    }

    fun offer(snapshot: PcmSnapshot) {
        if (closed.get() || !receivingAudio) return
        if (sourceStart == null) {
            sourceStart = snapshot.captureStartSample
            sourceEnd = snapshot.captureStartSample
            startedAtNanos = (SystemClock.elapsedRealtimeNanos() - snapshot.durationMs * 1_000_000L).coerceAtLeast(0L)
        }
        if (sourceEnd != snapshot.captureStartSample || snapshot.sampleRateHz != 16_000 ||
            snapshot.captureEndSampleExclusive - snapshot.captureStartSample != snapshot.samples.size.toLong()) {
            streamComplete = false
        }
        sourceEnd = snapshot.captureEndSampleExclusive
        var offset = 0
        while (offset < snapshot.samples.size) {
            val count = minOf(320, snapshot.samples.size - offset)
            val time = startedAtNanos + receivedSamples * 1_000_000_000L / snapshot.sampleRateHz
            online?.let { recognizer ->
                val frame = PcmFramePacket(frameSequence, time,
                    snapshot.samples.copyOfRange(offset, offset + count), snapshot.sampleRateHz)
                try { if (!recognizer.offer(frame)) streamComplete = false } finally { frame.samples.fill(0) }
            }
            highAccuracy?.let { recognizer ->
                directFrame.clear()
                repeat(count) { directFrame.putShort(snapshot.samples[offset + it]) }
                directFrame.flip()
                if (!recognizer.offer(DirectPcmFramePacket(frameSequence, time, directFrame, count, snapshot.sampleRateHz))) {
                    streamComplete = false
                }
            }
            frameSequence++
            receivedSamples += count
            offset += count
        }
    }

    fun requestPartial(window: (Long) -> PcmSnapshot?) {
        if (closed.get() || !receivingAudio) return
        val recognizer = local ?: return
        recognizer.nextPartialWindowMs(receivedSamples * 1_000L / 16_000L)?.let { duration ->
            window(duration)?.let(recognizer::offerPartial)
        }
    }

    suspend fun finish(snapshot: PcmSnapshot) {
        receivingAudio = false
        online?.onLocalSpeechEnded()
        activity.finishStreamingPcmAsr(traceId, snapshot, send = true,
            pcmBufferComplete = streamComplete && sourceStart == snapshot.captureStartSample &&
                sourceEnd == snapshot.captureEndSampleExclusive && receivedSamples == snapshot.samples.size.toLong(),
            mayKeepFinal = { !closed.get() })
        if (closed.get()) clearFinals()
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        receivingAudio = false
        runCatching { online?.close() }
        runCatching { highAccuracy?.cancel() }
        runCatching { local?.close() }
        runCatching { activity.onlineRealtimeAsrTurns.remove(traceId)?.close() }
        runCatching { activity.closeLiveWhisperSession(traceId) }
        clearFinals()
        directFrame.clear()
        while (directFrame.hasRemaining()) directFrame.put(0)
    }

    private fun clearFinals() {
        activity.onlineRealtimeAsrFinals.remove(traceId)
        activity.highAccuracyAsrFinals.remove(traceId)
    }
}
