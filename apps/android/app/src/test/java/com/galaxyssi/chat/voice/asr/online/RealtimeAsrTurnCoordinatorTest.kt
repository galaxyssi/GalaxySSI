package com.galaxyssi.chat.voice.asr.online

import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.asr.AsrError
import com.galaxyssi.chat.voice.asr.AsrEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RealtimeAsrTurnCoordinatorTest {
    @Test
    fun disconnectDuringSpeechRequestsOneLocalFallbackWhenPcmIsComplete() {
        val coordinator = RealtimeAsrTurnCoordinator("transcript-1")
        coordinator.onLocalSpeechStarted()
        val first = coordinator.onOnlineEvent(error("network_disconnected"))
        val duplicate = coordinator.onOnlineEvent(error("network_disconnected"))

        assertEquals("network_disconnected", (first as RealtimeAsrTurnAction.RequestLocalFallback).reasonCode)
        assertTrue(duplicate is RealtimeAsrTurnAction.None)
    }

    @Test
    fun reliableOnlineFinalPreventsLocalResubmissionAfterDisconnect() {
        val coordinator = RealtimeAsrTurnCoordinator("transcript-1")
        val committed = coordinator.onOnlineEvent(AsrEvent.Final(final("online", 2)))
        val disconnected = coordinator.onOnlineEvent(error("network_disconnected"))
        val local = coordinator.onLocalFinal(final("local", 3))

        assertTrue(committed is RealtimeAsrTurnAction.Commit)
        assertTrue(disconnected is RealtimeAsrTurnAction.None)
        assertTrue(local is RealtimeAsrTurnAction.None)
    }

    @Test
    fun partialWithoutFinalFallsBackAndLocalFinalCommitsOnce() {
        val coordinator = RealtimeAsrTurnCoordinator("transcript-1")
        coordinator.onOnlineEvent(AsrEvent.Partial(partial("hel", 1)))
        val fallback = coordinator.onInputFinishedWithoutFinal()
        val local = coordinator.onLocalFinal(final("hello", 2).copy(provider = "whisper"))

        assertEquals("online_partial_without_final", (fallback as RealtimeAsrTurnAction.RequestLocalFallback).reasonCode)
        assertTrue(local is RealtimeAsrTurnAction.Commit)
    }

    @Test
    fun incompletePcmFailsClearlyInsteadOfSubmittingTruncatedCommand() {
        val coordinator = RealtimeAsrTurnCoordinator("transcript-1")
        coordinator.onPcmBufferIntegrity(false)
        val action = coordinator.onOnlineEvent(error("network_disconnected"))

        assertEquals("pcm_fallback_incomplete", (action as RealtimeAsrTurnAction.Failed).reasonCode)
    }

    private fun error(code: String) = AsrEvent.RecoverableError(
        AsrError(code, retryable = false, providerId = "realtime")
    )

    private fun final(text: String, revision: Int) = partial(text, revision).copy(isFinal = true)

    private fun partial(text: String, revision: Int) = TranscriptHypothesis(
        text = text,
        revision = revision,
        provider = "realtime",
        transcriptId = "transcript-1"
    )
}
