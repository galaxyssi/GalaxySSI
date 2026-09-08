package com.galaxyssi.chat

import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.VOICE_COORDINATOR_FLAG
import com.galaxyssi.chat.voice.VOICE_PCM_CAPTURE_FLAG
import com.galaxyssi.chat.voice.VoiceFeatureFlags
import com.galaxyssi.chat.voice.VoiceInteractionEvent
import com.galaxyssi.chat.voice.VoiceInteractionPhase
import com.galaxyssi.chat.voice.metrics.VOICE_LATENCY_TRACE_FLAG
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.UUID

/** Release-equivalent flag settings on the real app, not a release packaging test. */
class AgentVoiceReleaseDefaultsDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun disabledDiagnosticsKeepUniqueTurnIdsWithoutRecordingEvents() {
        withDisabledFlags(VOICE_LATENCY_TRACE_FLAG) {
            val first = VoiceLatencyTelemetry.startSession(context)
            val second = VoiceLatencyTelemetry.startSession(context)
            assertTrue("A call identity must not depend on diagnostic recording", first.isNotBlank())
            assertEquals(first, UUID.fromString(first).toString())
            assertNotEquals(first, second)
            assertNull(VoiceLatencyTelemetry.record(context, first, "voice_session_created"))
            val diagnostics = VoiceLatencyTelemetry.exportContentFreeDiagnostics(context)
            try {
                val events = JSONObject(diagnostics.readText()).getJSONArray("events")
                assertFalse((0 until events.length()).map(events::getJSONObject).any {
                    it.optString("trace_id") in setOf(first, second)
                })
            } finally { diagnostics.delete() }
        }
    }

    @Test fun inlineCallKeepsCoordinatorCaptionsAndFinalDeduplicationWithLegacyFlagsOff() {
        withDisabledFlags(VOICE_COORDINATOR_FLAG, VOICE_PCM_CAPTURE_FLAG) { exerciseInlineCoordinator() }
    }

    @Test fun inlineCallAlsoWorksWhenDiagnosticsAreDisabled() {
        withDisabledFlags(VOICE_COORDINATOR_FLAG, VOICE_PCM_CAPTURE_FLAG, VOICE_LATENCY_TRACE_FLAG) {
            exerciseInlineCoordinator()
        }
    }

    private fun exerciseInlineCoordinator() {
        val preferences = context.getSharedPreferences("galaxyssi_voice_conversation", 0)
        val originalWake = preferences.getBoolean("foreground_wake", false)
        preferences.edit().putBoolean("foreground_wake", false).commit()
        var activity: MainActivity? = null
        try {
            val screen = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity = screen
            instrumentation.waitForIdleSync()
            await("Conversation initialization") { !screen.initialAgentHydrationPending }
            val conversationId = screen.agentTranscriptStore.activeConversation().id
            main {
                assertFalse(VoiceFeatureFlags.isCoordinatorEnabled(screen))
                assertFalse(VoiceFeatureFlags.isPcmCaptureEnabled(screen))
                assertTrue("Never consume a user draft", screen.agentGoalInput.text.isNullOrBlank())
                screen.showMainTab(PAGE_AGENT)
                screen.agentVoiceConversation!!.entry.performClick()
            }
            await("An inline call acquires the real PCM microphone") { screen.pcmVoiceSession != null }
            val traceId = main { screen.recordingVoiceTraceId }
            assertTrue("The recording needs a stable identity", traceId.isNotBlank())
            main {
                assertEquals("The inline coordinator must not inherit the legacy feature flag",
                    traceId, screen.voiceCoordinatorSession(traceId))
                assertEquals(traceId, screen.recordingVoiceCoordinatorSessionId)
                assertTrue(screen.agentVoiceConversation!!.session.acceptsTrace(traceId))
            }
            await("The real microphone readiness callback reaches the coordinator") {
                screen.voiceInteractionCoordinator.snapshot().phase == VoiceInteractionPhase.LISTENING
            }
            main {
                val partial = TranscriptHypothesis(text = "release caption fixture", revision = 1, provider = "fixture")
                screen.dispatchVoiceCoordinator(VoiceInteractionEvent.TranscriptPartial(traceId, partial))
                assertEquals(partial.text, screen.agentVoiceConversation!!.panel.transcript.text.toString())
                screen.dispatchVoiceCoordinator(VoiceInteractionEvent.FinalizationStarted(traceId))
                val final = partial.copy(isFinal = true, revision = 2)
                assertTrue(screen.acceptVoiceCoordinatorFinal(traceId, final))
                assertFalse("A duplicate final cannot route a second task", screen.acceptVoiceCoordinatorFinal(traceId, final))
                val nextTrace = VoiceLatencyTelemetry.startSession(screen)
                assertEquals("A new utterance replaces only its prior coordinator",
                    nextTrace, screen.beginVoiceCoordinatorSession("voice_wakeup", nextTrace))
                assertFalse("The previous utterance no longer owns input", screen.acceptVoiceCoordinatorFinal(traceId, final))
                screen.dispatchVoiceCoordinator(VoiceInteractionEvent.CapturePrepared(nextTrace))
                screen.dispatchVoiceCoordinator(VoiceInteractionEvent.FinalizationStarted(nextTrace))
                assertTrue(screen.acceptVoiceCoordinatorFinal(nextTrace, final))
                assertFalse(screen.acceptVoiceCoordinatorFinal(nextTrace, final))
                // Deliberately do not route the fixture to an Agent or persist it.
                screen.agentVoiceConversation!!.end()
            }
            await("Hangup releases capture and terminates its coordinator") {
                !screen.isVoiceCaptureActive() && screen.voiceInteractionCoordinator.snapshot().phase.isTerminal
            }
            main {
                assertEquals(VoiceInteractionPhase.CANCELLED, screen.voiceInteractionCoordinator.snapshot().phase)
                assertFalse("Late final input from a hung-up call is not accepted",
                    screen.acceptVoiceCoordinatorFinal(traceId,
                        TranscriptHypothesis(text = "late fixture", revision = 3, provider = "fixture", isFinal = true)))
                assertEquals(conversationId, screen.agentTranscriptStore.activeConversation().id)
                assertFalse(VoiceFeatureFlags.isCoordinatorEnabled(screen))
                assertFalse(VoiceFeatureFlags.isPcmCaptureEnabled(screen))
            }
        } finally {
            activity?.let { screen -> main { screen.agentVoiceConversation?.end(); screen.finish() } }
            preferences.edit().putBoolean("foreground_wake", originalWake).commit()
        }
    }

    private fun withDisabledFlags(vararg keys: String, block: () -> Unit) {
        assumeTrue("This task is restricted to SM-T575", Build.MODEL == "SM-T575")
        val flags = context.getSharedPreferences("galaxyssi_voice_feature_flags", 0)
        val original = keys.associateWith { key -> if (flags.contains(key)) flags.getBoolean(key, false) else null }
        flags.edit().apply { keys.forEach { putBoolean(it, false) } }.commit()
        try { block() } finally {
            flags.edit().apply {
                original.forEach { (key, value) -> if (value == null) remove(key) else putBoolean(key, value) }
            }.commit()
        }
    }

    private fun <T> main(block: () -> T): T {
        var result: T? = null
        instrumentation.runOnMainSync { result = block() }
        @Suppress("UNCHECKED_CAST") return result as T
    }

    private fun await(message: String, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        while (SystemClock.elapsedRealtime() < deadline) {
            if (main(predicate)) return
            SystemClock.sleep(50)
        }
        fail(message)
    }
}
