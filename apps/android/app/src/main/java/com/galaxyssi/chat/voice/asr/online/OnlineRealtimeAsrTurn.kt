package com.galaxyssi.chat.voice.asr.online

import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.asr.AsrAbortReason
import com.galaxyssi.chat.voice.asr.AsrAudioFrame
import com.galaxyssi.chat.voice.asr.AsrEvent
import com.galaxyssi.chat.voice.asr.AsrSession
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import com.galaxyssi.chat.voice.audio.PcmFramePacket
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

sealed interface OnlineAsrCompletion {
    data class Final(val hypothesis: TranscriptHypothesis) : OnlineAsrCompletion
    data class LocalFallback(val reasonCode: String) : OnlineAsrCompletion
    data class Failed(val reasonCode: String) : OnlineAsrCompletion
}

class OnlineRealtimeAsrTurn(
    private val config: AsrSessionConfig,
    private val preconnector: RealtimeAsrPreconnector,
    private val scope: CoroutineScope,
    private val onAction: (RealtimeAsrTurnAction) -> Unit = {},
    frameQueueCapacity: Int = 48
) : AutoCloseable {
    private val frames = Channel<AsrAudioFrame>(frameQueueCapacity)
    private val coordinator = RealtimeAsrTurnCoordinator(config.transcriptId)
    private val sessionReady = CompletableDeferred<AsrSession>()
    private val final = CompletableDeferred<TranscriptHypothesis>()
    private val started = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val inputFinished = AtomicBoolean(false)
    private val activeSession = AtomicReference<AsrSession?>()
    private var frameJob: Job? = null
    private var eventJob: Job? = null

    fun start(): Boolean {
        if (!started.compareAndSet(false, true)) return !closed.get()
        scope.launch {
            val session = runCatching { preconnector.acquire(config) }.getOrElse { error ->
                sessionReady.completeExceptionally(error)
                val action = RealtimeAsrTurnAction.RequestLocalFallback("online_connect_failed")
                onAction(action)
                return@launch
            }
            if (closed.get()) {
                session.close()
                return@launch
            }
            activeSession.set(session)
            eventJob = scope.launch {
                session.events.collect { event ->
                    val action = coordinator.onOnlineEvent(event)
                    if (action !is RealtimeAsrTurnAction.None) onAction(action)
                    if (action is RealtimeAsrTurnAction.Commit) final.complete(action.hypothesis)
                }
            }
            frameJob = scope.launch {
                for (frame in frames) {
                    runCatching { session.pushPcm(frame) }.onFailure {
                        coordinator.onPcmBufferIntegrity(false)
                        onAction(RealtimeAsrTurnAction.RequestLocalFallback("online_audio_send_failed"))
                    }
                    frame.samples.fill(0)
                }
            }
            sessionReady.complete(session)
        }
        return true
    }

    fun offer(frame: PcmFramePacket): Boolean {
        if (closed.get() || inputFinished.get()) return false
        val accepted = frames.trySend(
            AsrAudioFrame(
                sequence = frame.sequence,
                captureTimeNanos = frame.captureTimeNanos,
                samples = frame.samples.copyOf(),
                sampleRateHz = frame.sampleRateHz
            )
        ).isSuccess
        if (!accepted) {
            coordinator.onPcmBufferIntegrity(false)
            onAction(RealtimeAsrTurnAction.RequestLocalFallback("online_frame_queue_overflow"))
        }
        return accepted
    }

    fun onLocalSpeechStarted() {
        coordinator.onLocalSpeechStarted()
    }

    fun onLocalSpeechEnded() {
        coordinator.onLocalSpeechEnded()
    }

    suspend fun finish(pcmBufferComplete: Boolean): OnlineAsrCompletion {
        if (closed.get()) return OnlineAsrCompletion.Failed("online_session_closed")
        coordinator.onPcmBufferIntegrity(pcmBufferComplete)
        if (inputFinished.compareAndSet(false, true)) frames.close()
        frameJob?.join()
        val session = runCatching { sessionReady.await() }.getOrNull()
            ?: return fallback("online_connect_failed")
        runCatching { session.finishInput() }.onFailure { return fallback("online_finish_failed") }
        val onlineFinal = withTimeoutOrNull(config.finalTimeoutMs) { final.await() }
        return if (onlineFinal != null) {
            OnlineAsrCompletion.Final(onlineFinal)
        } else {
            when (val action = coordinator.onInputFinishedWithoutFinal()) {
                is RealtimeAsrTurnAction.RequestLocalFallback -> OnlineAsrCompletion.LocalFallback(action.reasonCode)
                is RealtimeAsrTurnAction.Failed -> OnlineAsrCompletion.Failed(action.reasonCode)
                else -> OnlineAsrCompletion.LocalFallback("online_final_missing")
            }
        }
    }

    fun acceptLocalFinal(hypothesis: TranscriptHypothesis): RealtimeAsrTurnAction =
        coordinator.onLocalFinal(hypothesis)

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        frames.close()
        while (true) {
            val frame = frames.tryReceive().getOrNull() ?: break
            frame.samples.fill(0)
        }
        frameJob?.cancel()
        eventJob?.cancel()
        activeSession.getAndSet(null)?.requestAbort(AsrAbortReason.SESSION_CLOSED)
    }

    private fun fallback(reasonCode: String): OnlineAsrCompletion =
        when (val action = coordinator.onInputFinishedWithoutFinal()) {
            is RealtimeAsrTurnAction.Failed -> OnlineAsrCompletion.Failed(action.reasonCode)
            else -> OnlineAsrCompletion.LocalFallback(reasonCode)
        }
}
