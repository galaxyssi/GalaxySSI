package com.galaxyssi.chat

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.*
import com.galaxyssi.chat.voice.audio.PcmSnapshot
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkAudioLoader
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class AgentVoiceLiveCaptionDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun nativePartialReachesTheActiveCallWithLegacyFlagsOff() = withVoiceActivity { screen ->
        val trace = main { screen.recordingVoiceTraceId }
        val live = main { screen.liveWhisperSessions[trace] }
        assertNotNull("An inline call needs local partials without legacy flags", live)
        main {
            assertTrue(screen.ownsInlineWhisperRuntime(trace))
            assertNull("A different recording purpose cannot borrow the call's runtime",
                screen.startLiveWhisperSession("agent_input", trace))
            assertNull(screen.startLiveWhisperSession("voice_wakeup", "unowned-caption-trace"))
        }
        val audio = WhisperBenchmarkAudioLoader.load(context).pcm16
        try {
            val snapshot = PcmSnapshot(audio, 16_000, true, 0L, audio.size.toLong(), 0L, audio.size.toLong())
            assertNotNull(live!!.nextPartialWindowMs(snapshot.durationMs))
            val started = SystemClock.elapsedRealtime()
            // Authored PCM enters the real native decoder, not a transcript/UI callback.
            live.offerPartial(snapshot)
            await("Native partial must reach the visible call before finalization", 25_000L) {
                val state = screen.voiceInteractionCoordinator.snapshot()
                state.sessionId == trace && state.asrProvider == "whisper.cpp" &&
                    state.partialText.isNotBlank() &&
                    screen.agentVoiceConversation!!.panel.transcript.text.toString() == state.partialText
            }
            main {
                val state = screen.voiceInteractionCoordinator.snapshot()
                assertNull("This is a streaming caption, not a final transcription", state.finalText)
                assertNotNull("The real microphone remains open", screen.pcmVoiceSession)
                assertTrue(screen.agentVoiceConversation!!.session.latestTurnId.isBlank())
                instrumentation.sendStatus(0, Bundle().apply {
                    putString("caption_source", "authored_pcm_native_whisper_to_active_call")
                    putString("caption_model", live.modelProfileId)
                    putString("caption_text", state.partialText)
                    putLong("caption_elapsed_ms", SystemClock.elapsedRealtime() - started)
                    putString("caption_rtf", live.partialPolicy().recentRealTimeFactor.toString())
                })
                screen.agentVoiceConversation!!.panel.microphone.performClick()
                assertFalse(screen.ownsInlineWhisperRuntime(trace))
                assertNull(screen.startLiveWhisperSession("voice_wakeup", trace))
            }
            await("Muting releases the live decoder and microphone") {
                !screen.isVoiceCaptureActive() && screen.liveWhisperSessions[trace] == null
            }
            val caption = main { screen.agentVoiceConversation!!.panel.transcript.text.toString() }
            main {
                screen.handleLocalAsrPartial("voice_wakeup", trace, "late caption fixture", "", 999,
                    "fixture", live.modelProfileId)
                assertEquals("A revoked trace cannot change the muted caption", caption,
                    screen.agentVoiceConversation!!.panel.transcript.text.toString())
                screen.agentVoiceConversation!!.end()
                assertFalse(screen.ownsInlineWhisperRuntime(trace))
            }
        } finally {
            main { screen.agentVoiceConversation?.end() }
            await("The native decoder drains before fixture audio is cleared") {
                val queue = screen.sharedWhisperDecodeScheduler().queueSnapshot()
                queue.activeRequestId == null && queue.queued == 0
            }
            audio.fill(0)
        }
    }

    @Test fun queuedDecodeRechecksOwnershipAfterMute() = withVoiceActivity { screen ->
        val trace = main { screen.recordingVoiceTraceId }
        val model = VoiceAssistantSettings.get(context).asrModel
        val firstEntered = CompletableDeferred<Unit>()
        val queuedStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val pcm = ShortArray(1_600)
        runBlocking {
            withTimeout(15_000L) {
                val first = async(Dispatchers.Default) {
                    runCatching {
                        LocalWhisperAsr.decodePcmWindow(context, pcm, 16_000, "zh",
                            WhisperExecutionMode.REALTIME_PARTIAL, "blocked-fixture", "test", model,
                            allowInlineVoiceRuntime = {
                                firstEntered.complete(Unit)
                                releaseFirst.await()
                                false
                            })
                    }.exceptionOrNull()
                }
                firstEntered.await()
                val queued = async(Dispatchers.Default) {
                    queuedStarted.complete(Unit)
                    runCatching {
                        LocalWhisperAsr.decodePcmWindow(context, pcm, 16_000, "zh",
                            WhisperExecutionMode.REALTIME_PARTIAL, trace, "test", model,
                            allowInlineVoiceRuntime = {
                                withContext(Dispatchers.Main.immediate) { screen.ownsInlineWhisperRuntime(trace) }
                            })
                    }.exceptionOrNull()
                }
                queuedStarted.await()
                try {
                    main {
                        assertTrue(screen.ownsInlineWhisperRuntime(trace))
                        screen.agentVoiceConversation!!.panel.microphone.performClick()
                        assertFalse(screen.ownsInlineWhisperRuntime(trace))
                    }
                } finally { releaseFirst.complete(Unit) }
                assertEquals("Local Whisper Runtime v2 is disabled", first.await()?.message)
                assertEquals("A queued request must not keep a stale enabled Boolean",
                    "Local Whisper Runtime v2 is disabled", queued.await()?.message)
            }
        }
    }

    @Test fun runtimeRechecksAfterLoadingBeforeNativeDecode() = withVoiceActivity { screen ->
        val trace = main { screen.recordingVoiceTraceId }
        var checks = 0
        val failure = runBlocking {
            withTimeout(25_000L) {
                runCatching {
                    LocalWhisperAsr.decodePcmWindow(context, ShortArray(1_600), 16_000, "zh",
                        WhisperExecutionMode.REALTIME_PARTIAL, trace, "test",
                        VoiceAssistantSettings.get(context).asrModel,
                        allowInlineVoiceRuntime = { ++checks == 1 })
                }.exceptionOrNull()
            }
        }
        assertEquals("Ownership must be checked again after model/session preparation", 2, checks)
        assertEquals("Local Whisper Runtime v2 is disabled", failure?.message)
    }

    private fun withVoiceActivity(test: (MainActivity) -> Unit) {
        assumeTrue("Only SM-T575 is authorized", Build.MODEL == "SM-T575")
        val flags = context.getSharedPreferences("galaxyssi_voice_feature_flags", 0)
        val keys = listOf(VOICE_COORDINATOR_FLAG, VOICE_PCM_CAPTURE_FLAG,
            VOICE_LOCAL_WHISPER_RUNTIME_V2_FLAG, VOICE_WHISPER_ADAPTIVE_PARTIAL_V1_FLAG,
            VOICE_WHISPER_AUTO_BENCHMARK_V1_FLAG, VOICE_WHISPER_POLICY_ENGINE_V1_FLAG,
            VOICE_ONLINE_REALTIME_ASR_V1_FLAG, VOICE_RELIABILITY_GOVERNOR_V1_FLAG)
        val previous = keys.associateWith { if (flags.contains(it)) flags.getBoolean(it, false) else null }
        val wake = context.getSharedPreferences("galaxyssi_voice_conversation", 0)
        val previousWake = if (wake.contains("foreground_wake")) wake.getBoolean("foreground_wake", false) else null
        val previousModel = VoiceAssistantSettings.get(context).asrModel
        flags.edit().apply { keys.forEach { putBoolean(it, false) } }.commit()
        wake.edit().putBoolean("foreground_wake", false).commit()
        var activity: MainActivity? = null
        var ownsCall = false
        try {
            val screen = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
            activity = screen
            instrumentation.waitForIdleSync()
            await("Conversation initialization") { !screen.initialAgentHydrationPending }
            main {
                assertFalse("Never replace an existing user call", screen.agentVoiceConversation!!.session.active)
                assertTrue("Never consume a user draft", screen.agentGoalInput.text.isNullOrBlank())
                assertFalse("This regression specifically exercises the local Whisper route", screen.isHighAccuracyQnnSelected())
                screen.showMainTab(PAGE_AGENT)
                ownsCall = true
                screen.agentVoiceConversation!!.entry.performClick()
            }
            await("An inline call acquires the real PCM microphone") {
                screen.pcmVoiceSession != null &&
                    screen.voiceInteractionCoordinator.snapshot().phase == VoiceInteractionPhase.LISTENING
            }
            test(screen)
            assertEquals(previousModel, VoiceAssistantSettings.get(context).asrModel)
            keys.forEach { assertFalse("No global voice flag may be enabled: $it", flags.getBoolean(it, true)) }
        } finally {
            activity?.let { screen -> main {
                if (ownsCall) {
                    screen.agentVoiceConversation?.end()
                    screen.finish()
                }
            } }
            flags.edit().apply { previous.forEach { (key, value) ->
                if (value == null) remove(key) else putBoolean(key, value)
            } }.commit()
            wake.edit().apply {
                if (previousWake == null) remove("foreground_wake") else putBoolean("foreground_wake", previousWake)
            }.commit()
        }
    }

    private fun <T> main(block: () -> T): T {
        var result: T? = null
        instrumentation.runOnMainSync { result = block() }
        @Suppress("UNCHECKED_CAST") return result as T
    }

    private fun await(message: String, timeoutMs: Long = 15_000L, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            if (main(predicate)) return
            SystemClock.sleep(50)
        }
        fail(message)
    }
}
