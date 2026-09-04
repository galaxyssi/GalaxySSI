package com.galaxyssi.chat.voice.metrics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
        assertNull(tracer.record(traceId, event = VoiceTraceEvents.SPEECH_STARTED))
        assertTrue(sink.snapshot().isEmpty())
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
