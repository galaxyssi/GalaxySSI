package com.galaxyssi.chat.voice.asr.online

import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.asr.AsrEvent
import com.galaxyssi.chat.voice.asr.FinalTranscriptArbiter
import com.galaxyssi.chat.voice.asr.TranscriptArbitrationDecision
import com.galaxyssi.chat.voice.asr.TranscriptSource

sealed interface RealtimeAsrTurnAction {
    data class Display(val hypothesis: TranscriptHypothesis, val stable: Boolean) : RealtimeAsrTurnAction
    data class Commit(val hypothesis: TranscriptHypothesis) : RealtimeAsrTurnAction
    data class Correct(val hypothesis: TranscriptHypothesis) : RealtimeAsrTurnAction
    data class RequestLocalFallback(val reasonCode: String) : RealtimeAsrTurnAction
    data class Failed(val reasonCode: String) : RealtimeAsrTurnAction
    data object None : RealtimeAsrTurnAction
}

class RealtimeAsrTurnCoordinator(
    private val transcriptId: String,
    private val arbiter: FinalTranscriptArbiter = FinalTranscriptArbiter()
) {
    private val lock = Any()
    private var localSpeechStarted = false
    private var localSpeechEnded = false
    private var serverSpeechStarted = false
    private var onlineFinal = false
    private var fallbackRequested = false
    private var pcmBufferComplete = true
    private var partialObserved = false

    fun onLocalSpeechStarted() = synchronized(lock) {
        localSpeechStarted = true
    }

    fun onLocalSpeechEnded() = synchronized(lock) {
        localSpeechEnded = true
    }

    fun onPcmBufferIntegrity(complete: Boolean) = synchronized(lock) {
        pcmBufferComplete = complete
    }

    fun onOnlineEvent(event: AsrEvent): RealtimeAsrTurnAction = synchronized(lock) {
        when (event) {
            is AsrEvent.SpeechStarted -> {
                serverSpeechStarted = true
                RealtimeAsrTurnAction.None
            }
            is AsrEvent.Partial -> {
                partialObserved = true
                event.hypothesis.toDisplay(stable = false)
            }
            is AsrEvent.Stable -> {
                partialObserved = true
                event.hypothesis.toDisplay(stable = true)
            }
            is AsrEvent.Final -> {
                onlineFinal = true
                arbitrate(event.hypothesis, TranscriptSource.ONLINE_PRIMARY)
            }
            is AsrEvent.RecoverableError -> fallbackOrFailure(event.error.code)
            is AsrEvent.FatalError -> fallbackOrFailure(event.error.code)
            is AsrEvent.Closed -> if (onlineFinal) RealtimeAsrTurnAction.None else fallbackOrFailure(
                event.reasonCode.ifBlank { "online_session_closed" }
            )
            else -> RealtimeAsrTurnAction.None
        }
    }

    fun onInputFinishedWithoutFinal(): RealtimeAsrTurnAction = synchronized(lock) {
        if (onlineFinal) RealtimeAsrTurnAction.None else fallbackOrFailure(
            if (partialObserved) "online_partial_without_final" else "online_final_missing"
        )
    }

    fun onLocalFinal(hypothesis: TranscriptHypothesis): RealtimeAsrTurnAction = synchronized(lock) {
        if (!fallbackRequested && onlineFinal) return@synchronized RealtimeAsrTurnAction.None
        arbitrate(
            hypothesis.copy(transcriptId = transcriptId, isFinal = true),
            TranscriptSource.LOCAL_FALLBACK
        )
    }

    fun hasObservedSpeech(): Boolean = synchronized(lock) { localSpeechStarted || serverSpeechStarted }

    private fun fallbackOrFailure(reasonCode: String): RealtimeAsrTurnAction {
        if (fallbackRequested || onlineFinal) return RealtimeAsrTurnAction.None
        if (!pcmBufferComplete) return RealtimeAsrTurnAction.Failed("pcm_fallback_incomplete")
        fallbackRequested = true
        return RealtimeAsrTurnAction.RequestLocalFallback(reasonCode)
    }

    private fun TranscriptHypothesis.toDisplay(stable: Boolean): RealtimeAsrTurnAction {
        val normalized = copy(
            transcriptId = this@RealtimeAsrTurnCoordinator.transcriptId,
            isFinal = false
        )
        return when (arbiter.consider(normalized, TranscriptSource.ONLINE_PRIMARY)) {
            is TranscriptArbitrationDecision.DisplayOnly -> RealtimeAsrTurnAction.Display(normalized, stable)
            else -> RealtimeAsrTurnAction.None
        }
    }

    private fun arbitrate(
        hypothesis: TranscriptHypothesis,
        source: TranscriptSource
    ): RealtimeAsrTurnAction = when (
        arbiter.consider(
            hypothesis.copy(
                transcriptId = this@RealtimeAsrTurnCoordinator.transcriptId,
                isFinal = true
            ),
            source
        )
    ) {
        is TranscriptArbitrationDecision.Commit -> RealtimeAsrTurnAction.Commit(hypothesis)
        is TranscriptArbitrationDecision.Correction -> RealtimeAsrTurnAction.Correct(hypothesis)
        else -> RealtimeAsrTurnAction.None
    }
}
