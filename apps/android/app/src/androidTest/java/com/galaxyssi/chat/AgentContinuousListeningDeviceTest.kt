package com.galaxyssi.chat

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.VoiceInteractionPhase
import com.galaxyssi.chat.voice.VoiceInteractionState
import com.galaxyssi.chat.voice.audio.PcmRecorderPhase
import com.galaxyssi.chat.voice.audio.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.flow
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

/** Real microphone and TTS; the reply fixture is transient and does not dispatch a model task. */
class AgentContinuousListeningDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)

    @Test fun noiseOnlyManualSendDoesNotTranscribeOrModifyTheDraft() = withVoice { activity ->
        main { activity.agentVoiceConversation!!.end() }
        await("Release voice session") { !activity.isVoiceCaptureActive() }
        val originalHub = activity.pcmVoiceAudioHub
        val originalDraft = activity.agentGoalInput.text.toString()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val delivered = CompletableDeferred<Unit>()
        val stopped = CompletableDeferred<Unit>()
        val recorder = object : PcmRecorder {
            override suspend fun start(config: PcmCaptureConfig) = flow {
                repeat(150) { sequence ->
                    val noise = ShortArray(320) { if (it % 2 == 0) 1_000 else -1_000 }
                    emit(AudioFrame(sequence.toLong(), 0, noise, noise.size, { it.fill(0) }))
                }
                delivered.complete(Unit)
                stopped.await()
            }
            override fun requestStop(reason: PcmStopReason) { stopped.complete(Unit) }
            override suspend fun stop(reason: PcmStopReason) { stopped.complete(Unit) }
            override fun currentState() = PcmRecorderState(phase = PcmRecorderPhase.RECORDING)
        }
        val hub = VoiceAudioHub(recorder, scope,
            vadFactory = { NeuralSpeechVad(SileroSpeechProbabilityModel(activity.assets)) })
        val trace = "noise-only-${UUID.randomUUID()}"
        try {
            main {
                activity.agentGoalInput.setText("保留这段草稿")
                activity.captureAgentVoiceDraftSnapshot()
                activity.pcmVoiceAudioHub = hub
                activity.pcmVoiceSession = hub.start(VoiceAudioSessionConfig())
                activity.recordingVoiceTraceId = trace
                activity.recordingPurpose = "agent_input"
            }
            await("Noise fixture consumed") { delivered.isCompleted }
            hub.snapshotWindow(checkNotNull(hub.activeSession()), 3_000)?.let { snapshot ->
                try { assertFalse(snapshot.speechDetected) } finally { snapshot.samples.fill(0) }
            } ?: fail("Noise snapshot missing")
            main { activity.stopPcmRecording(send = true, reason = "user_send") }
            await("Silent send finalized") { !activity.pcmCaptureStopping && activity.pcmVoiceSession == null }
            main {
                assertEquals("保留这段草稿", activity.agentGoalInput.text.toString())
                assertFalse(activity.highAccuracyAsrFinals.containsKey(trace))
                assertFalse(activity.onlineRealtimeAsrFinals.containsKey(trace))
                assertFalse(activity.agentTranscriptStore.page().entries.any {
                    it.dedupeKey == AgentVoiceTranscriptPolicy.dedupeKey(trace)
                })
            }
        } finally {
            stopped.complete(Unit)
            scope.cancel()
            main {
                activity.pcmVoiceAudioHub = originalHub
                activity.pcmVoiceSession = null
                activity.pcmCaptureStopping = false
                activity.recordingVoiceTraceId = ""
                activity.recordingPurpose = ""
                activity.clearAgentVoiceDraftSnapshot()
                activity.agentGoalInput.setText(originalDraft)
            }
        }
    }

    @Test fun waitingAndSpeakingKeepTheSameProtectedMicrophoneAndTurn() = withVoice { activity ->
        val voice = activity.agentVoiceConversation!!
        val trace = "continuous-listen-${UUID.randomUUID()}"
        val turn = "$trace-turn"
        main {
            voice.registerTrace("voice_wakeup", trace)
            voice.onTurnSubmitted(trace, turn)
        }
        await("Protected passive capture while waiting for a reply") {
            voice.bargeIn.active && activity.voiceAudioHub().currentState().let {
                it.phase == PcmRecorderPhase.RECORDING && it.acousticEchoCancelerEnabled
            }
        }
        val recorder = activity.voiceAudioHub().activeSession()
        assertNotNull(recorder)
        main {
            assertEquals(trace, voice.session.latestTraceId)
            assertEquals(turn, voice.session.latestTurnId)
            listOf(VoiceInteractionPhase.ROUTING, VoiceInteractionPhase.WAITING_MODEL_FIRST_TOKEN,
                VoiceInteractionPhase.STARTING_AGENT, VoiceInteractionPhase.AGENT_RUNNING,
                VoiceInteractionPhase.EXECUTING_LOCAL_ACTION).forEach { phase ->
                voice.onUtterance(VoiceInteractionState(sessionId = trace, phase = phase))
                assertEquals(activity.getString(R.string.voice_call_listening), voice.panel.status.text)
            }
            voice.onEntries(listOf(AgentTranscriptEntry(
                id = "$trace-final", role = AgentTranscriptRole.ASSISTANT,
                text = "这是一段连续聆听测试。回复到达后自动朗读，等待时和朗读时都保持聆听。请保持安静，用于检查扬声器回声不会成为新的问题。",
                timestampMillis = System.currentTimeMillis(), conversationId = voice.session.conversationId,
                turnId = turn, dedupeKey = AgentFinalResponseIdentity.dedupeKey(turn)
            )))
        }
        await("Real configured TTS playback", 45_000L) { activity.voiceAssistantSpeaking }
        main {
            assertEquals(recorder, activity.voiceAudioHub().activeSession())
            assertEquals(trace, activity.activeProgressiveSpeechTraceId)
            assertEquals(activity.getString(R.string.voice_call_listening), voice.panel.status.text)
            val caption = voice.panel.transcript.text.toString()
            voice.onUtterance(VoiceInteractionState(sessionId = trace, phase = VoiceInteractionPhase.AGENT_RUNNING,
                finalText = "这个旧输入不能覆盖朗读内容"))
            assertEquals(caption, voice.panel.transcript.text.toString())
        }
        await("Speech ends without closing capture or inventing another user turn", 60_000L) {
            assertEquals("Speaker output cannot supersede the submitted turn", trace, voice.session.latestTraceId)
            assertFalse("Speaker output cannot trigger input", voice.bargeIn.collectingUtterance)
            assertTrue("Capture stays open through playback", voice.bargeIn.active)
            activity.activeProgressiveSpeechSessionId.isBlank() && !activity.voiceAssistantSpeaking
        }
        main {
            assertEquals(turn, voice.session.latestTurnId)
            assertEquals(activity.getString(R.string.voice_call_listening), voice.panel.status.text)
            assertEquals(recorder, activity.voiceAudioHub().activeSession())
            voice.panel.microphone.performClick()
            assertTrue(voice.session.muted)
        }
        await("Explicit mute releases the microphone") { !activity.isVoiceCaptureActive() }
        main {
            voice.onTurnSubmitted(trace, turn)
            assertTrue(voice.session.muted)
        }
        SystemClock.sleep(500)
        main { assertFalse(activity.isVoiceCaptureActive()) }
        instrumentation.sendStatus(0, Bundle().apply {
            putString("continuous_listening", "waiting, playback and completion retain one protected capture; zero echo inputs; mute stops capture")
            putString("tts_provider", VoiceAssistantSettings.get(activity).ttsProvider)
        })
    }

    @Test fun stoppingBeforeDeferredRearmCannotReopenTheMicrophone() = withVoice { activity ->
        val voice = activity.agentVoiceConversation!!
        main {
            voice.registerTrace("voice_wakeup", "stopped-duplex")
            voice.onTurnSubmitted("stopped-duplex", "stopped-duplex-turn")
            voice.end()
        }
        SystemClock.sleep(750)
        main {
            assertFalse(voice.session.active)
            assertFalse(activity.isVoiceCaptureActive())
            assertFalse(voice.bargeIn.active)
        }
    }

    private fun withVoice(test: (MainActivity) -> Unit) {
        val context = instrumentation.targetContext
        assertEquals(PackageManager.PERMISSION_GRANTED, context.checkSelfPermission(Manifest.permission.RECORD_AUDIO))
        val originalProvider = VoiceAssistantSettings.get(context).ttsProvider
        val provider = InstrumentationRegistry.getArguments().getString("duplex_tts_provider") ?: originalProvider
        val preferences = context.getSharedPreferences("galaxyssi_voice_conversation", 0)
        val wake = preferences.getBoolean("foreground_wake", false)
        var activity: MainActivity? = null
        try {
            preferences.edit().putBoolean("foreground_wake", false).commit()
            VoiceAssistantSettings.setTtsProvider(context, provider)
            val screen = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity = screen
            await("Initial hydration", 60_000L) { !screen.initialAgentHydrationPending }
            await("TTS initialization", 15_000L) { provider != VoiceAssistantSettings.PROVIDER_ANDROID || screen.androidTtsReady }
            main { screen.showMainTab(PAGE_AGENT); screen.agentVoiceConversation!!.start() }
            await("Initial capture") { screen.isVoiceCaptureActive() }
            main { screen.stopVoiceAssistant() }
            await("Release initial ASR capture") { !screen.isVoiceCaptureActive() }
            test(screen)
        } finally {
            activity?.let { main { it.agentVoiceConversation?.end(); it.finish() } }
            VoiceAssistantSettings.setTtsProvider(context, originalProvider)
            preferences.edit().putBoolean("foreground_wake", wake).commit()
        }
    }

    private fun await(message: String, timeoutMs: Long = 10_000L, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            var ready = false
            main { ready = condition() }
            if (ready) return
            SystemClock.sleep(40)
        }
        fail(message)
    }
}
