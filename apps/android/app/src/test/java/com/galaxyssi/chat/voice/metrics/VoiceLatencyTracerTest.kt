package com.galaxyssi.chat.voice.metrics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceLatencyTracerTest {
    @Test
    fun elapsedDurationsUseMonotonicClockInsteadOfWallClock() {
        var elapsedNs = 2_000_000_000L
        var wallClockMs = 10_000L
        val tracer = VoiceLatencyTracer(
            elapsedSource = VoiceElapsedRealtimeSource { elapsedNs },
            wallClockSource = VoiceWallClockSource { wallClockMs }
        )
        val traceId = tracer.startSession()

        elapsedNs += 125_000_000L
        wallClockMs += 60_000L
        tracer.record(traceId, event = VoiceTraceEvents.ASR_FINAL_STARTED)
        elapsedNs += 875_000_000L
        wallClockMs -= 120_000L
        tracer.record(traceId, event = VoiceTraceEvents.ASR_FINAL_RECEIVED)

        assertEquals(
            875L,
            tracer.elapsedMillis(
                traceId,
                VoiceTraceEvents.ASR_FINAL_STARTED,
                VoiceTraceEvents.ASR_FINAL_RECEIVED
            )
        )
        assertEquals(875L, tracer.diagnosticSummary().metrics.getValue("asr_total_ms").p95Ms)
    }

    @Test
    fun sensitiveFieldsAndValuesNeverEnterTrace() {
        val tracer = VoiceLatencyTracer(
            elapsedSource = VoiceElapsedRealtimeSource { 5_000_000L },
            wallClockSource = VoiceWallClockSource { 10L }
        )
        val traceId = tracer.startSession()
        val event = tracer.record(
            traceId,
            event = VoiceTraceEvents.MODEL_REQUEST_COMPLETED,
            attributes = mapOf(
                "transcript" to "private words",
                "prompt" to "delete everything",
                "file_path" to "C:\\Users\\agent\\secret.txt",
                "api_key" to "secret-token",
                "agent_provider" to "Codex",
                "duration_ms" to "1250",
                "error_code" to "HTTP_TIMEOUT",
                "transport" to "https://private.example/path"
            )
        ) ?: error("Trace event was not recorded")

        assertEquals("Codex", event.attributes["agent_provider"])
        assertEquals("1250", event.attributes["duration_ms"])
        assertEquals("HTTP_TIMEOUT", event.attributes["error_code"])
        assertFalse(event.attributes.containsKey("transcript"))
        assertFalse(event.attributes.containsKey("prompt"))
        assertFalse(event.attributes.containsKey("file_path"))
        assertFalse(event.attributes.containsKey("api_key"))
        assertFalse(event.attributes.containsKey("transport"))
        assertFalse(event.toString().contains("private words"))
        assertFalse(event.toString().contains("secret.txt"))
    }

    @Test
    fun disabledFlagProducesNoEvents() {
        val sink = InMemoryVoiceTraceEventSink()
        val tracer = VoiceLatencyTracer(
            elapsedSource = VoiceElapsedRealtimeSource { 1L },
            wallClockSource = VoiceWallClockSource { 1L },
            enabled = { false },
            sink = sink
        )

        val traceId = tracer.startSession()
        assertTrue(traceId.isNotBlank())
        assertEquals(traceId, java.util.UUID.fromString(traceId).toString())
        assertNotEquals(traceId, tracer.startSession())
        assertNull(tracer.record(traceId, event = VoiceTraceEvents.SPEECH_STARTED))
        assertTrue(sink.snapshot().isEmpty())
    }

    @Test
    fun replyPlaybackEvidenceKeepsOnlyTechnicalIdentifiersAndCharacterCounts() {
        val attributes = VoiceTracePrivacy.sanitizeAttributes(mapOf(
            "playback_session_id" to "voice-call:turn-123:1",
            "speech_characters" to "12",
            "spoken_text" to "private answer",
            "success" to "true"
        ))
        assertEquals("voice-call:turn-123:1", attributes["playback_session_id"])
        assertEquals("12", attributes["speech_characters"])
        assertEquals("true", attributes["success"])
        assertFalse(attributes.containsKey("spoken_text"))
        assertTrue(VoiceTracePrivacy.sanitizeAttributes(mapOf(
            "playback_session_id" to "https://private.example/answer",
            "speech_characters" to "private answer"
        )).isEmpty())
    }

    @Test
    fun acousticEvidenceRetainsOnlyFiniteNumbersAndActualEffectBooleans() {
        val safe = VoiceTracePrivacy.sanitizeAttributes(mapOf(
            "aec_enabled" to "true", "noise_suppression_enabled" to "false",
            "max_rms" to "0.012", "max_vad_probability" to "0.73",
            "candidate_duration_ms" to "180", "capture_outcome" to "detected",
            "audio_samples" to "private audio", "spoken_text" to "private words"
        ))
        assertEquals(6, safe.size)
        assertEquals("true", safe["aec_enabled"])
        assertEquals("false", safe["noise_suppression_enabled"])
        assertEquals("0.012", safe["max_rms"])
        assertEquals("180", safe["candidate_duration_ms"])
        assertTrue(VoiceTracePrivacy.sanitizeAttributes(mapOf(
            "aec_enabled" to "unknown", "noise_suppression_enabled" to "private",
            "max_rms" to "NaN", "max_vad_probability" to "Infinity",
            "candidate_duration_ms" to "private words"
        )).isEmpty())
    }

    @Test
    fun onceEventsAreDeduplicatedPerTrace() {
        var elapsedNs = 0L
        val tracer = VoiceLatencyTracer(
            elapsedSource = VoiceElapsedRealtimeSource { ++elapsedNs },
            wallClockSource = VoiceWallClockSource { 1L }
        )
        val traceId = tracer.startSession()

        tracer.record(traceId, event = VoiceTraceEvents.AGENT_RUN_ACCEPTED, once = true)
        tracer.record(traceId, event = VoiceTraceEvents.AGENT_RUN_ACCEPTED, once = true)

        assertEquals(
            1,
            tracer.snapshot().count { it.event == VoiceTraceEvents.AGENT_RUN_ACCEPTED }
        )
    }
}
