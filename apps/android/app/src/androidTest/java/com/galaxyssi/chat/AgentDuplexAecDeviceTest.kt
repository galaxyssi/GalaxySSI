package com.galaxyssi.chat

import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.UUID

/** Physical speaker/microphone tests; no injected PCM or mocked AEC status. */
class AgentDuplexAecDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)

    @Test fun speakerOnlyDoesNotBecomeUserInput() = exercise(expectInterruption = false)

    @Test fun liveHumanSpeechInterruptsTheSpeaker() {
        assumeTrue("Explicit human acoustic participation is required",
            InstrumentationRegistry.getArguments().getString("humanReady") == "true")
        exercise(expectInterruption = true)
    }

    private fun exercise(expectInterruption: Boolean) {
        check(Build.MODEL == "SM-T575")
        val context = instrumentation.targetContext
        val provider = InstrumentationRegistry.getArguments().getString("provider") ?: VoiceAssistantSettings.PROVIDER_ANDROID
        val settings = VoiceAssistantSettings.get(context)
        val preferences = context.getSharedPreferences("galaxyssi_voice_conversation", 0)
        val wake = preferences.getBoolean("foreground_wake", false)
        preferences.edit().putBoolean("foreground_wake", false).commit()
        val audio = context.getSystemService(AudioManager::class.java)
        val volume = audio.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
        val mode = audio.mode
        val trace = "duplex-aec-${UUID.randomUUID()}"
        val turn = "$trace-turn"
        var activity: MainActivity? = null
        try {
            VoiceAssistantSettings.setTtsProvider(context, provider)
            val screen = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity = screen
            await("Initial hydration", 60_000) { !screen.initialAgentHydrationPending }
            await("TTS ready", 15_000) { provider != VoiceAssistantSettings.PROVIDER_ANDROID || screen.androidTtsReady }
            main {
                screen.showMainTab(PAGE_AGENT)
                audio.setStreamVolume(AudioManager.STREAM_VOICE_CALL, audio.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL), 0)
                screen.agentVoiceConversation!!.start()
                assertTrue(screen.agentVoiceConversation!!.communicationAudio.active)
                assertEquals(AudioManager.MODE_IN_COMMUNICATION, audio.mode)
            }
            await("Real microphone opened", 10_000) { screen.isVoiceCaptureActive() }
            main { screen.stopVoiceAssistant() }
            await("Recorder released before playback", 10_000) { !screen.isVoiceCaptureActive() }
            val phrase = if (expectInterruption)
                "这是全双工插话测试。听到这句话以后，请说暂停一下，我有新的问题。" else
                "这是扬声器回声测试，现在只有平板在说话，麦克风同时工作，请保持安静。"
            main {
                val voice = screen.agentVoiceConversation!!
                voice.registerTrace("voice_wakeup", trace)
                voice.session.registerTurn(trace, turn)
                voice.onEntries(listOf(AgentTranscriptEntry(
                    id = "$trace-final", role = AgentTranscriptRole.ASSISTANT,
                    text = List(16) { phrase }.joinToString(""),
                    timestampMillis = System.currentTimeMillis(),
                    conversationId = voice.session.conversationId, turnId = turn)))
            }
            await("Real TTS playback", 45_000) { screen.agentVoiceConversation!!.panel.status.text == screen.getString(R.string.voice_call_speaking) }
            await("Simultaneous AEC capture", 10_000) {
                screen.agentVoiceConversation!!.bargeIn.active && screen.voiceAudioHub().currentState().acousticEchoCancelerEnabled
            }
            assertEquals("Physical test requires the built-in speaker",
                android.media.AudioDeviceInfo.TYPE_BUILTIN_SPEAKER, audio.communicationDevice?.type)
            instrumentation.sendStatus(0, Bundle().apply {
                putString("duplex_stage", if (expectInterruption) "SPEAK_NOW" else "KEEP_QUIET")
                putString("trace", trace)
                putString("provider", provider)
            })
            val quietDurationMs = InstrumentationRegistry.getArguments().getString("quietDurationMs")
                ?.toLongOrNull()?.coerceIn(15_000L, 60_000L) ?: 15_000L
            val deadline = SystemClock.elapsedRealtime() + if (expectInterruption) 30_000L else quietDurationMs
            var detected = false
            var reconfiguringSince = 0L
            var reconfigurationCount = 0
            while (SystemClock.elapsedRealtime() < deadline) {
                main {
                    val voice = screen.agentVoiceConversation!!
                    detected = voice.session.latestTraceId != trace || voice.bargeIn.collectingUtterance
                    if (!expectInterruption) {
                        assertFalse("TTS speaker echo must not start an input turn", detected)
                        assertTrue("The test must keep the real microphone active", voice.bargeIn.active)
                        // The bounded recorder renews every 50 s; unprotected audio must never become input.
                        if (screen.voiceAudioHub().currentState().acousticEchoCancelerEnabled) {
                            reconfiguringSince = 0L
                        } else {
                            if (reconfiguringSince == 0L) {
                                reconfiguringSince = SystemClock.elapsedRealtime()
                                reconfigurationCount++
                            }
                            assertTrue("AEC must recover within 1 s during bounded recorder renewal",
                                SystemClock.elapsedRealtime() - reconfiguringSince < 1_000L)
                            assertTrue("Unexpected repeated AEC loss", reconfigurationCount <= 1)
                        }
                        assertTrue("The test must keep the real speaker active", screen.voiceAssistantSpeaking)
                        assertEquals(trace, screen.activeProgressiveSpeechTraceId)
                    }
                }
                if (expectInterruption && detected) break
                SystemClock.sleep(40)
            }
            if (expectInterruption) {
                assertTrue("A real human voice must interrupt the TTS", detected)
                await("Barge-in stops TTS", 2_000) { !screen.voiceAssistantSpeaking }
                SystemClock.sleep(5_000)
                main {
                    assertFalse("Barge-in must not finish the activity", screen.isFinishing || screen.isDestroyed)
                    assertTrue("Barge-in must preserve the voice call", screen.agentVoiceConversation!!.session.active)
                }
            }
            if (!expectInterruption) assertEquals("AEC must be restored before completing the test", 0L, reconfiguringSince)
            main { screen.agentVoiceConversation!!.end() }
            await("Hangup releases recording", 10_000) { !screen.isVoiceCaptureActive() }
            assertEquals("Hangup restores audio mode", mode, audio.mode)
            instrumentation.sendStatus(0, Bundle().apply {
                putString("duplex_result", if (expectInterruption) "human_barge_in" else "${quietDurationMs}ms_speaker_only_zero_input")
            })
        } catch (error: Throwable) {
            instrumentation.sendStatus(0, Bundle().apply { putString("duplex_failure", error.toString()) })
            throw error
        } finally {
            activity?.let { screen ->
                runCatching {
                    val file = VoiceLatencyTelemetry.exportContentFreeDiagnostics(screen)
                    val events = org.json.JSONObject(file.readText()).getJSONArray("events")
                    val current = org.json.JSONArray()
                    for (index in 0 until events.length()) {
                        val event = events.getJSONObject(index)
                        if (event.optString("trace_id") == trace) current.put(event)
                    }
                    instrumentation.sendStatus(0, Bundle().apply { putString("duplex_diagnostics", current.toString()) })
                }.onFailure { error ->
                    instrumentation.sendStatus(0, Bundle().apply { putString("duplex_diagnostics_error", error.toString()) })
                }
                main { screen.agentVoiceConversation?.end(); screen.finish() }
            }
            VoiceAssistantSettings.setTtsProvider(context, settings.ttsProvider)
            audio.setStreamVolume(AudioManager.STREAM_VOICE_CALL, volume, 0)
            preferences.edit().putBoolean("foreground_wake", wake).commit()
        }
    }

    private fun await(message: String, timeout: Long, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < deadline) {
            var ready = false
            main { ready = condition() }
            if (ready) return
            SystemClock.sleep(40)
        }
        fail(message)
    }
}
