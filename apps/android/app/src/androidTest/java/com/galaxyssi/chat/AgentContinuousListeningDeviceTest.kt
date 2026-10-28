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
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

/** Real microphone and TTS; the reply fixture is transient and does not dispatch a model task. */
class AgentContinuousListeningDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)

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
