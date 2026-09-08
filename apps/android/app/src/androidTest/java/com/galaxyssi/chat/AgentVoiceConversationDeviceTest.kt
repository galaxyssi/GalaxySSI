package com.galaxyssi.chat

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.AudioManager
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AudioEffect
import android.os.Build
import android.os.SystemClock
import android.provider.MediaStore
import android.view.View
import android.view.KeyEvent
import android.view.InputDevice
import com.galaxyssi.chat.voice.audio.PcmRecorderPhase
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class AgentVoiceConversationDeviceTest {
    @Test fun emptyComposerShowsVoiceEntryAndDraftChangesRestoreIt() {
        withVoiceActivity { activity ->
            InstrumentationRegistry.getInstrumentation().runOnMainSync {
                val draft = activity.agentGoalInput.text.toString()
                val voice = requireNotNull(activity.agentVoiceConversation)
                try {
                    activity.showMainTab(PAGE_AGENT)
                    activity.updateAgentSubmitButtonAppearance(false)
                    assertSame(activity.agentComposerRow, voice.entry.parent)
                    assertEquals(View.VISIBLE, voice.entry.visibility)
                    assertEquals(activity.getString(R.string.voice_call_start), voice.entry.contentDescription)
                    activity.updateAgentSubmitButtonAppearance(true)
                    assertEquals(View.GONE, voice.entry.visibility)
                    activity.updateAgentSubmitButtonAppearance(false)
                    assertEquals(View.VISIBLE, voice.entry.visibility)
                    assertFalse(voice.session.active)
                    assertEquals(draft, activity.agentGoalInput.text.toString())
                } finally {
                    activity.updateAgentSubmitButtonAppearance(draft.isNotBlank() || activity.agentInputAttachments.isNotEmpty())
                }
            }
        }
    }


    @Test fun deferredConnectorRecoveryCannotSubmitAfterActivityCloses() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val response = AgentConnectorResponse(sourceMessageId = Long.MIN_VALUE,
                contactId = "lifecycle-fixture-${java.util.UUID.randomUUID()}", content = "")
            val key = "supervised-control:${AgentConnectorResponseCodec.identity(response)}"
            instrumentation.runOnMainSync {
                activity.deferSupervisedProjectControlResponse(response)
                assertTrue(activity.agentConnectorResponsesInFlight.contains(key))
                activity.finish()
            }
            awaitState("The original Activity must be destroyed") { activity.isDestroyed }
            SystemClock.sleep(AgentSupervisedControlResponseRetryPolicy.delayMillis(0) + 500)
            instrumentation.runOnMainSync {
                assertTrue(activity.agentRuntimeRecoveryExecutor.isShutdown)
                assertFalse(activity.agentConnectorResponsesInFlight.contains(key))
                activity.deferSupervisedProjectControlResponse(response)
                assertFalse("A destroyed Activity cannot schedule another retry",
                    activity.agentConnectorResponsesInFlight.contains(key))
            }
        }
    }

    @Test fun finalReplyTelemetryUsesTerminalMetadataNotDisplayedAnswer() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val traces = linkedMapOf<String, String>()
            val originalTrace = activity.activeVoiceTraceId
            val turnId = "voice-final-test-${java.util.UUID.randomUUID()}"
            try {
                instrumentation.runOnMainSync {
                    listOf("completed", "failed", "cancelled", "timed_out", "", "running", "unknown").forEach { status ->
                        val traceId = com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry.startSession(activity)
                        assertTrue(traceId.isNotBlank())
                        traces[status] = traceId
                        activity.voiceTraceIdsByTurn[turnId] = traceId
                        val payload = org.json.JSONObject().put("turn_id", turnId)
                            .put("task_status", status).put("agent_id", "fixture")
                            .put("content", "This text is not evidence of success")
                        assertEquals(traceId, activity.recordAgentFinalResponseTelemetry(payload))
                        activity.recordAgentFinalResponseTelemetry(payload)
                    }
                }
                val diagnostic = com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry.exportContentFreeDiagnostics(activity)
                val events = try { org.json.JSONObject(diagnostic.readText()).getJSONArray("events") } finally { diagnostic.delete() }
                traces.forEach { (status, traceId) ->
                    val completed = (0 until events.length()).map(events::getJSONObject).filter {
                        it.optString("trace_id") == traceId && it.optString("event") ==
                            com.galaxyssi.chat.voice.metrics.VoiceTraceEvents.AGENT_COMPLETED
                    }
                    if (status in setOf("", "running", "unknown")) {
                        assertTrue("Unproven outcome cannot become completed telemetry", completed.isEmpty())
                    } else {
                        assertEquals("A duplicate final must be counted once", 1, completed.size)
                        assertEquals((status == "completed").toString(), completed.single().getJSONObject("attributes").optString("success"))
                    }
                }
            } finally {
                instrumentation.runOnMainSync {
                    activity.voiceTraceIdsByTurn.remove(turnId)
                    activity.activeVoiceTraceId = originalTrace
                }
            }
        }
    }

    @Test fun voiceControlsKeepConversationAndDraftAndStopCaptureOnHangup() {
        assumeTrue("This task is restricted to SM-T575", Build.MODEL == "SM-T575")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        assertEquals(PackageManager.PERMISSION_GRANTED, context.checkSelfPermission(Manifest.permission.RECORD_AUDIO))
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        val conversationId = activity.agentTranscriptStore.activeConversation().id
        var draft = ""
        try {
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                draft = activity.agentGoalInput.text.toString()
                activity.showMainTab(PAGE_AGENT)
                requireNotNull(activity.agentVoiceConversation).start()
            }
            SystemClock.sleep(1_500)
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                val voice = requireNotNull(activity.agentVoiceConversation)
                assertTrue(voice.session.active)
                assertTrue(voice.session.expanded)
                assertEquals(View.VISIBLE, voice.panel.visibility)
                assertEquals(View.GONE, activity.agentComposerRow.visibility)
                assertEquals(conversationId, voice.session.conversationId)
                assertFalse("Compact status must not dominate the transcript", voice.panel.status.typeface.isBold)
                assertEquals(context.getColor(R.color.text_secondary), voice.panel.status.currentTextColor)
                assertEquals(context.getColor(R.color.agent_voice_transcript_dot), voice.panel.microphone.imageTintList!!.defaultColor)
                listOf(voice.panel.keyboard, voice.panel.camera, voice.panel.microphone,
                    voice.panel.screen, voice.panel.hangup).forEach { button ->
                    assertTrue("Every voice action keeps a 48dp touch target", button.width >= activity.dp(48) && button.height >= activity.dp(48))
                }
            }
            screenshot("voice-panel-listening")
            instrumentation.runOnMainSync {
                val voice = requireNotNull(activity.agentVoiceConversation)
                voice.panel.collapse.performClick()
                assertTrue(voice.session.active)
                assertFalse(voice.session.expanded)
                assertEquals(View.VISIBLE, activity.agentComposerRow.visibility)
                assertEquals(View.VISIBLE, voice.entry.visibility)
                voice.entry.performClick()
                assertTrue(voice.session.expanded)
                voice.panel.keyboard.performClick()
                assertTrue(voice.session.muted)
                assertTrue(voice.panel.microphone.isSelected)
                assertEquals(context.getString(R.string.voice_call_unmute), voice.panel.microphone.tooltipText)
                assertTrue(activity.agentComposerTextMode)
                voice.entry.performClick()
                assertFalse(activity.agentComposerTextMode)
                assertTrue(voice.session.expanded)
                voice.panel.microphone.performClick()
                assertFalse(voice.session.muted)
                voice.panel.hangup.performClick()
                assertFalse(voice.session.active)
                assertEquals(View.GONE, voice.panel.visibility)
                assertEquals(View.VISIBLE, activity.agentComposerRow.visibility)
                assertEquals(conversationId, activity.agentTranscriptStore.activeConversation().id)
                assertEquals(draft, activity.agentGoalInput.text.toString())
            }
            SystemClock.sleep(1_500)
            instrumentation.runOnMainSync {
                assertFalse(activity.isVoiceCaptureActive())
                assertFalse(activity.voiceAssistantSpeaking)
            }
            screenshot("voice-panel-ended")
        } finally {
            instrumentation.runOnMainSync {
                activity.agentVoiceConversation?.end()
                activity.agentGoalInput.setText(draft)
                activity.finish()
            }
        }
    }

    @Test fun leavingAgentPageEndsVoiceWithoutStartingLegacyVoicePage() {
        assumeTrue("This task is restricted to SM-T575", Build.MODEL == "SM-T575")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        assertEquals(PackageManager.PERMISSION_GRANTED, context.checkSelfPermission(Manifest.permission.RECORD_AUDIO))
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        try {
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync {
                activity.showMainTab(PAGE_AGENT)
                val voice = requireNotNull(activity.agentVoiceConversation)
                voice.start()
                assertTrue(voice.session.active)
                activity.showMainTab(PAGE_SETTINGS)
                assertFalse(voice.session.active)
                assertEquals(View.GONE, activity.wakePage.visibility)
            }
        } finally {
            instrumentation.runOnMainSync { activity.agentVoiceConversation?.end(); activity.finish() }
        }
    }

    @Test fun backgroundRenderKeepsTheCallButStopsMicrophoneUntilResumed() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            var generation = 0L
            instrumentation.runOnMainSync {
                val voice = requireNotNull(activity.agentVoiceConversation)
                voice.start()
                generation = voice.session.generation
                voice.onForeground(false)
                voice.onNavigationChanged()
                assertFalse(voice.communicationAudio.active)
                assertEquals(AudioManager.MODE_NORMAL, activity.getSystemService(AudioManager::class.java).mode)
                assertTrue(voice.session.active)
                assertTrue(voice.session.muted)
                voice.onForeground(true)
                voice.onNavigationChanged()
                assertEquals(generation, voice.session.generation)
                assertTrue(voice.session.active)
                assertTrue(voice.session.muted)
            }
            awaitState("Background capture must release the microphone") { !activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync { activity.agentVoiceConversation!!.panel.microphone.performClick() }
            awaitState("The same call must resume capture") { activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync {
                assertEquals(generation, activity.agentVoiceConversation!!.session.generation)
                assertTrue(activity.agentVoiceConversation!!.communicationAudio.active)
            }
        }
    }

    @Test fun microphoneWhileWaitingForAnAgentStartsANewUtterance() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.runOnMainSync { activity.agentVoiceConversation!!.start() }
            awaitState("Initial microphone capture") { activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync { activity.stopVoiceAssistant() }
            awaitState("Release capture before agent work") { !activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync {
                val voice = activity.agentVoiceConversation!!
                assertFalse(voice.session.muted)
                voice.registerTrace("voice_wakeup", "voice-ui-waiting-fixture")
                voice.session.registerTurn("voice-ui-waiting-fixture", "voice-ui-waiting-turn")
                voice.panel.microphone.performClick()
                assertFalse(voice.session.muted)
            }
            awaitState("Mic button must capture additions rather than mute an idle recorder") { activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync {
                assertNotEquals("voice-ui-waiting-fixture", activity.agentVoiceConversation!!.session.latestTraceId)
            }
        }
    }

    @Test fun aCanonicalMediaOnlyFinalReturnsToListeningWithoutStartingTts() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.runOnMainSync { activity.agentVoiceConversation!!.start() }
            awaitState("Initial voice capture") { activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync { activity.stopVoiceAssistant() }
            awaitState("Release capture before visual response") { !activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync {
                val voice = activity.agentVoiceConversation!!
                voice.registerTrace("voice_wakeup", "voice-ui-media-fixture")
                voice.session.registerTurn("voice-ui-media-fixture", "voice-ui-media-turn")
                voice.onEntries(listOf(AgentTranscriptEntry(
                    id = "voice-ui-media-final", role = AgentTranscriptRole.ASSISTANT, text = "",
                    timestampMillis = System.currentTimeMillis(), conversationId = voice.session.conversationId,
                    turnId = "voice-ui-media-turn", dedupeKey = AgentFinalResponseIdentity.dedupeKey("voice-ui-media-turn"),
                    richOutputJson = AgentRichContentCodec.encode(listOf(AgentRichBlock(
                        id = "media", type = AgentRichBlockType.IMAGE, uri = "content://test/image", mimeType = "image/png"
                    )))
                )))
            }
            awaitState("Visual completion must rearm the microphone without fabricated speech") {
                activity.isVoiceCaptureActive() && !activity.voiceAssistantSpeaking &&
                    activity.activeProgressiveSpeechSessionId.isBlank() &&
                    activity.agentVoiceConversation!!.session.latestTraceId != "voice-ui-media-fixture"
            }
        }
    }

    @Test fun realPlatformTtsPlaysAnIncrementalFixtureThenReturnsToListening() = assertPlatformTtsRoundTrip()

    @Test fun realPlatformTtsContinuesAfterEchoProtectionIsLost() = assertPlatformTtsRoundTrip(disableEcho = true)

    private fun assertPlatformTtsRoundTrip(disableEcho: Boolean = false) {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val traceId = "voice-ui-tts-${java.util.UUID.randomUUID()}"
            val turnId = "$traceId-turn"
            val provider = VoiceAssistantSettings.get(activity).ttsProvider
            val audio = activity.getSystemService(AudioManager::class.java)
            val originalVolume = audio.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
            var overrideEffect: AcousticEchoCanceler? = null
            try {
                awaitState("Android TTS initialization", 15_000L) { activity.androidTtsReady }
                instrumentation.runOnMainSync {
                    VoiceAssistantSettings.setTtsProvider(activity, VoiceAssistantSettings.PROVIDER_ANDROID)
                    audio.setStreamVolume(AudioManager.STREAM_VOICE_CALL,
                        audio.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL), 0)
                    activity.agentVoiceConversation!!.start()
                    assertTrue(activity.agentVoiceConversation!!.communicationAudio.active)
                    assertEquals(AudioManager.MODE_IN_COMMUNICATION, audio.mode)
                }
                awaitState("Initial voice capture") { activity.isVoiceCaptureActive() }
                instrumentation.runOnMainSync { activity.stopVoiceAssistant() }
                awaitState("Release ASR before playback") { !activity.isVoiceCaptureActive() }
                lateinit var entry: AgentTranscriptEntry
                instrumentation.runOnMainSync {
                    val voice = activity.agentVoiceConversation!!
                    voice.registerTrace("voice_wakeup", traceId)
                    voice.session.registerTurn(traceId, turnId)
                    // A non-persisted fixture exercises real TTS, not model answer quality.
                    entry = AgentTranscriptEntry(
                        id = "agent-stream-$turnId",
                        role = AgentTranscriptRole.ASSISTANT,
                        text = "这是语音交互的流式播报测试，第一句话已经生成。",
                        timestampMillis = System.currentTimeMillis(),
                        conversationId = voice.session.conversationId,
                        turnId = turnId
                    )
                    voice.onEntries(listOf(entry))
                    assertEquals(traceId, activity.activeProgressiveSpeechTraceId)
                    assertFalse(activity.progressiveTtsScheduler.snapshot().inputClosed)
                }
                awaitState("The platform must acknowledge actual audio playback", 15_000L) {
                    activity.agentVoiceConversation!!.panel.status.text == activity.getString(R.string.voice_call_speaking)
                }
                awaitState("Real echo-protected capture must run while TTS is speaking", 10_000L) {
                    activity.agentVoiceConversation!!.bargeIn.active &&
                        activity.voiceAudioHub().currentState().phase == PcmRecorderPhase.RECORDING &&
                        activity.voiceAudioHub().currentState().acousticEchoCancelerEnabled
                }
                if (disableEcho) {
                    instrumentation.runOnMainSync {
                        val sessionId = requireNotNull(activity.voiceAudioHub().currentState().audioSessionId)
                        overrideEffect = requireNotNull(AcousticEchoCanceler.create(sessionId))
                        assertTrue(overrideEffect!!.hasControl())
                        assertEquals(AudioEffect.SUCCESS, overrideEffect!!.setEnabled(false))
                    }
                    awaitState("Losing echo protection stops only the monitor, not reply playback") {
                        !activity.agentVoiceConversation!!.bargeIn.active &&
                            !activity.voiceAudioHub().currentState().acousticEchoCancelerEnabled
                    }
                    instrumentation.runOnMainSync {
                        assertTrue(activity.voiceAssistantSpeaking)
                        assertEquals(traceId, activity.activeProgressiveSpeechTraceId)
                        assertTrue(activity.agentVoiceConversation!!.session.active)
                    }
                }
                instrumentation.runOnMainSync {
                    activity.agentVoiceConversation!!.onEntries(listOf(entry.copy(
                        id = "$traceId-final",
                        text = entry.text + "现在收到第二句话，播放完成后将继续聆听。"
                    )))
                }
                awaitState("Final audio must return to microphone capture", 45_000L) {
                    assertFalse("Speaker playback alone must not trigger barge-in",
                        activity.agentVoiceConversation!!.bargeIn.collectingUtterance)
                    !activity.agentVoiceConversation!!.bargeIn.active &&
                        activity.recordingPurpose == "voice_wakeup" &&
                        activity.agentVoiceConversation!!.session.latestTraceId != traceId &&
                        activity.isVoiceCaptureActive() && activity.activeProgressiveSpeechSessionId.isBlank() &&
                        activity.agentVoiceConversation!!.panel.status.text == activity.getString(R.string.voice_call_listening)
                }
                instrumentation.runOnMainSync {
                    assertTrue(activity.agentVoiceConversation!!.session.active)
                    assertNotEquals(traceId, activity.agentVoiceConversation!!.session.latestTraceId)
                }
            } finally {
                overrideEffect?.let { effect ->
                    runCatching { effect.enabled = true }
                    effect.release()
                }
                instrumentation.runOnMainSync {
                    VoiceAssistantSettings.setTtsProvider(activity, provider)
                    audio.setStreamVolume(AudioManager.STREAM_VOICE_CALL, originalVolume, 0)
                }
                val diagnostic = com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry.exportContentFreeDiagnostics(activity)
                val events = try { org.json.JSONObject(diagnostic.readText()).getJSONArray("events") } finally { diagnostic.delete() }
                val ownEvents = (0 until events.length()).map(events::getJSONObject).filter { it.optString("trace_id") == traceId }
                instrumentation.sendStatus(0, android.os.Bundle().apply {
                    putString("tts_acoustic_trace", org.json.JSONArray(ownEvents).toString())
                })
            }
        }
    }

    @Test fun actualEchoEffectDisableStopsTheMonitorWithoutSubmittingAudio() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val voice = activity.agentVoiceConversation!!
            var overrideEffect: AcousticEchoCanceler? = null
            var unavailable = ""
            try {
                instrumentation.runOnMainSync { voice.start() }
                awaitState("Initial capture before the effect lifecycle test") { activity.isVoiceCaptureActive() }
                instrumentation.runOnMainSync { activity.stopVoiceAssistant() }
                awaitState("Ordinary capture releases the recorder") { !activity.isVoiceCaptureActive() }
                instrumentation.runOnMainSync {
                    assertTrue(voice.bargeIn.start(com.galaxyssi.chat.voice.audio.AcousticBargeInCallbacks(
                        onDetected = { fail("No interruption is expected in the effect lifecycle fixture") },
                        onUtterance = { it.samples.fill(0); fail("No audio may be submitted") },
                        onUnavailable = { unavailable = it }
                    )))
                }
                awaitState("The real recorder must enable AEC") {
                    voice.bargeIn.active && activity.voiceAudioHub().currentState().acousticEchoCancelerEnabled
                }
                instrumentation.runOnMainSync {
                    val sessionId = requireNotNull(activity.voiceAudioHub().currentState().audioSessionId)
                    overrideEffect = requireNotNull(AcousticEchoCanceler.create(sessionId))
                    assertTrue("The test must control only its own recorder's AEC", overrideEffect!!.hasControl())
                    assertEquals(AudioEffect.SUCCESS, overrideEffect!!.setEnabled(false))
                }
                awaitState("A live AEC change must reach the recorder and stop monitoring") {
                    !activity.voiceAudioHub().currentState().acousticEchoCancelerEnabled &&
                        !voice.bargeIn.active && unavailable == "echo_protection_lost"
                }
                instrumentation.runOnMainSync {
                    assertNull(activity.voiceAudioHub().activeSession())
                    assertTrue("Losing echo protection must not end the user's call", voice.session.active)
                    assertFalse(voice.bargeIn.collectingUtterance)
                }
            } finally {
                overrideEffect?.let { effect ->
                    runCatching { effect.enabled = true }
                    effect.release()
                }
                instrumentation.runOnMainSync { voice.bargeIn.stop() }
            }
        }
    }

    @Test fun aRealLongAndroidUtteranceCanPlayBeyondTwentySeconds() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val provider = VoiceAssistantSettings.get(activity).ttsProvider
            var startedAt = 0L
            var completedAt = 0L
            var result: Pair<Boolean, String?>? = null
            try {
                awaitState("Android TTS initialization", 15_000L) { activity.androidTtsReady }
                instrumentation.runOnMainSync { activity.agentVoiceConversation!!.start() }
                awaitState("Initial capture") { activity.isVoiceCaptureActive() }
                instrumentation.runOnMainSync { activity.stopVoiceAssistant() }
                awaitState("Release microphone before long playback") { !activity.isVoiceCaptureActive() }
                instrumentation.runOnMainSync {
                    VoiceAssistantSettings.setTtsProvider(activity, VoiceAssistantSettings.PROVIDER_ANDROID)
                    val controller = AgentReplySpeechController(sessionPrefix = "voice-long-fixture")
                    val text = "这是一段用于验证长句连续播报的中文测试。二十秒之后仍应继续播放，直到听到结束提示。".repeat(4) +
                        "长句验证已结束。"
                    val command = controller.toggle(AgentReplySpeechTarget("long-fixture", "long-fixture", text, true))
                    // A single long fixture checks the real platform watchdog, not model output.
                    activity.applyAgentReplySpeechCommand(command.copy(chunks = listOf(
                        com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk(command.beginSessionId, 0, text, true)
                    )), controller, callbacks = com.galaxyssi.chat.voice.tts.TtsChunkSchedulerCallbacks(
                        onPlaybackStarted = { startedAt = SystemClock.elapsedRealtime() },
                        onFinished = { success, error ->
                            result = success to error
                            completedAt = SystemClock.elapsedRealtime()
                        }
                    ))
                }
                awaitState("Real long utterance must start", 15_000L) { startedAt > 0L }
                awaitState("Real long utterance must finish successfully", 120_000L) { result != null }
                instrumentation.runOnMainSync {
                    assertEquals(true to null, result)
                    assertTrue("Actual playback must exceed the previous fixed watchdog", completedAt - startedAt > 20_000L)
                    assertFalse(activity.voiceAssistantSpeaking)
                    assertEquals(0, activity.agentReplySpeechFeeder.pendingCount)
                }
                instrumentation.sendStatus(0, android.os.Bundle().apply {
                    putLong("long_tts_playback_ms", completedAt - startedAt)
                })
            } finally {
                instrumentation.runOnMainSync {
                    activity.stopSpeechPlaybackOnly(com.galaxyssi.chat.voice.tts.TtsCancelReason.USER_STOP)
                    VoiceAssistantSettings.setTtsProvider(activity, provider)
                }
            }
        }
    }

    @Test fun waitingIndicatorNeverStartsPlaybackOrRearmsMicrophone() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.runOnMainSync { activity.agentVoiceConversation!!.start() }
            awaitState("Initial capture") { activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync { activity.stopVoiceAssistant() }
            awaitState("Release input before the waiting state") { !activity.isVoiceCaptureActive() }
            var trace = ""
            instrumentation.runOnMainSync {
                val voice = activity.agentVoiceConversation!!
                trace = com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry.startSession(activity)
                voice.session.registerTrace(trace)
                voice.session.registerTurn(trace, "waiting-indicator-fixture")
                val waiting = AgentReplyWaitingIndicatorPolicy.apply(emptyList(), listOf(
                    PendingAgentReplyIndicator(voice.session.conversationId, "waiting-indicator-fixture", System.currentTimeMillis())
                ), voice.session.conversationId).entries
                repeat(10) { activity.observeAgentReplySpeech(waiting) }
            }
            SystemClock.sleep(2_500L)
            instrumentation.runOnMainSync {
                assertTrue(activity.activeProgressiveSpeechSessionId.isBlank())
                assertFalse(activity.voiceAssistantSpeaking)
                assertFalse("Only an actual reply may return the call to listening", activity.isVoiceCaptureActive())
                assertEquals(trace, activity.agentVoiceConversation!!.session.latestTraceId)
                assertEquals("waiting-indicator-fixture", activity.agentVoiceConversation!!.session.latestTurnId)
            }
        }
    }

    @Test fun inlineCameraKeepsVoiceMuteChoiceAndClosesOnBackground() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            assertEquals(PackageManager.PERMISSION_GRANTED, activity.checkSelfPermission(Manifest.permission.CAMERA))
            var generation = 0L
            instrumentation.runOnMainSync {
                val voice = activity.agentVoiceConversation!!
                voice.start()
                generation = voice.session.generation
            }
            awaitState("Initial microphone capture") { activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync { activity.agentVoiceConversation!!.panel.microphone.performClick() }
            awaitState("Explicit mute releases capture") { !activity.isVoiceCaptureActive() }
            AgentVoiceCameraDeviceActions.openAndConfirm(activity)
            awaitState("Real camera preview must produce frames", 15_000L) {
                activity.agentVoiceConversation!!.cameraPreview.ready && activity.agentVoiceConversation!!.cameraPreview.frames >= 3L
            }
            instrumentation.runOnMainSync {
                val voice = activity.agentVoiceConversation!!
                assertEquals(generation, voice.session.generation)
                assertTrue(voice.session.active)
                assertTrue(voice.session.muted)
                assertFalse(activity.isVoiceCaptureActive())
                assertTrue(voice.panel.camera.isSelected)
                assertEquals(View.VISIBLE, voice.cameraPreview.view.visibility)
                assertEquals(activity.packageName, instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString())
                voice.panel.microphone.performClick()
            }
            awaitState("Resume microphone") { activity.isVoiceCaptureActive() }
            val frame = kotlinx.coroutines.runBlocking { activity.agentVoiceConversation!!.cameraPreview.captureFrame() }
            try {
                assertTrue("Real camera frame must be a nonempty JPEG", frame.length() > 100L)
                val bitmap = requireNotNull(android.graphics.BitmapFactory.decodeFile(frame.absolutePath))
                try {
                    assertTrue(bitmap.width > 0 && bitmap.height > 0)
                    assertTrue(kotlin.math.max(bitmap.width, bitmap.height) <= 1280)
                } finally { bitmap.recycle() }
                val retained = File(activity.getExternalFilesDir(null), "voice-ui-tests/inline-camera-frame.jpg")
                retained.parentFile?.mkdirs()
                frame.copyTo(retained, overwrite = true)
            } finally { frame.delete() }
            screenshot("voice-inline-camera")
            instrumentation.runOnMainSync {
                val voice = activity.agentVoiceConversation!!
                if (voice.cameraPreview.flip.visibility == View.VISIBLE) voice.cameraPreview.flip.performClick()
            }
            awaitState("Camera must restart after switching lenses", 15_000L) { activity.agentVoiceConversation!!.cameraPreview.ready }
            instrumentation.runOnMainSync {
                val voice = activity.agentVoiceConversation!!
                assertEquals(generation, voice.session.generation)
                assertTrue(voice.session.active)
                assertFalse(voice.session.muted)
                voice.cameraPreview.close.performClick()
                assertFalse(voice.cameraPreview.active)
                assertEquals(View.GONE, voice.cameraPreview.view.visibility)
                assertTrue("Closing camera must not mute voice", activity.isVoiceCaptureActive())
                voice.panel.camera.performClick()
            }
            awaitState("Camera can be reopened", 15_000L) { activity.agentVoiceConversation!!.cameraPreview.ready }
            instrumentation.runOnMainSync {
                val voice = activity.agentVoiceConversation!!
                voice.onForeground(false)
                assertFalse(voice.cameraPreview.active)
                assertTrue(voice.session.active)
                voice.onForeground(true)
                assertFalse("Returning to the app must not silently reopen the camera", voice.cameraPreview.active)
                voice.panel.camera.performClick()
            }
            awaitState("Camera can be opened explicitly after background", 15_000L) { activity.agentVoiceConversation!!.cameraPreview.ready }
            instrumentation.runOnMainSync { activity.agentVoiceConversation!!.end() }
            SystemClock.sleep(300)
            instrumentation.runOnMainSync {
                assertFalse(activity.agentVoiceConversation!!.cameraPreview.active)
                assertEquals(0L, activity.agentVoiceConversation!!.cameraPreview.frames)
                assertFalse(activity.isVoiceCaptureActive())
            }
        }
    }

    @Test fun stalePlaybackRestartDoesNotBlockLaterListening() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.runOnMainSync { activity.agentVoiceConversation!!.start() }
            awaitState("Initial capture") { activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync {
                activity.stopVoiceAssistant()
                activity.voiceAssistantAwake = true
                activity.scheduleVoiceRestart(100L)
                activity.stopVoiceAssistant()
                activity.voiceAssistantAwake = true
                activity.scheduleVoiceRestart(600L)
                activity.voicePlaybackEpoch++
            }
            SystemClock.sleep(250L)
            instrumentation.runOnMainSync {
                assertTrue("Old timer cannot clear a newer timer's pending slot", activity.voiceAssistantRestartPending)
            }
            awaitState("Epoch-invalidated timer must release its pending slot") { !activity.voiceAssistantRestartPending }
            instrumentation.runOnMainSync { activity.agentVoiceConversation!!.panel.microphone.performClick() }
            awaitState("Capture can restart after stale timers") { activity.isVoiceCaptureActive() }
        }
    }

    @Test fun hangupDuringCameraFramePreparationDoesNotSubmitOrRetainAFrame() {
        withVoiceActivity { activity ->
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            assertEquals(PackageManager.PERMISSION_GRANTED, activity.checkSelfPermission(Manifest.permission.CAMERA))
            instrumentation.runOnMainSync { activity.agentVoiceConversation!!.start() }
            awaitState("Initial microphone capture") { activity.isVoiceCaptureActive() }
            instrumentation.runOnMainSync { activity.stopVoiceAssistant() }
            awaitState("Release capture before the cancellation fixture") { !activity.isVoiceCaptureActive() }
            AgentVoiceCameraDeviceActions.openAndConfirm(activity)
            awaitState("Actual preview must be ready", 15_000L) { activity.agentVoiceConversation!!.cameraPreview.ready }
            val framesDirectory = File(activity.filesDir, "agent-rich-output-v2/voice-camera")
            val originalFiles = framesDirectory.listFiles().orEmpty().map { it.name }.toSet()
            val temporaryDirectory = File(activity.cacheDir, "voice-camera-capture")
            val originalTemporaryFiles = temporaryDirectory.listFiles().orEmpty().map { it.name }.toSet()
            val conversationId = activity.agentTranscriptStore.activeConversation().id
            val traceId = "voice-camera-cancel-${java.util.UUID.randomUUID()}"
            instrumentation.runOnMainSync {
                val voice = activity.agentVoiceConversation!!
                voice.registerTrace("voice_wakeup", traceId)
                assertTrue(voice.routeTranscript("Cancelled camera frame fixture", traceId))
                voice.end()
            }
            SystemClock.sleep(1_500L)
            instrumentation.runOnMainSync {
                assertFalse(activity.agentVoiceConversation!!.session.active)
                assertFalse(activity.agentVoiceConversation!!.cameraPreview.active)
                assertFalse(activity.voiceTraceIdsByTurn.values.contains(traceId))
            }
            assertTrue("Cancelled visual input must never become a user message",
                activity.agentTranscriptStore.list(conversationId).none { it.text == "Cancelled camera frame fixture" })
            assertEquals("An unsubmitted frame must be deleted", originalFiles,
                framesDirectory.listFiles().orEmpty().map { it.name }.toSet())
            assertEquals("A cancelled plaintext capture must be deleted", originalTemporaryFiles,
                temporaryDirectory.listFiles().orEmpty().map { it.name }.toSet())
        }
    }

    private fun withVoiceActivity(test: (MainActivity) -> Unit) {
        assumeTrue("This task is restricted to SM-T575", Build.MODEL == "SM-T575")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val voicePreferences = context.getSharedPreferences("galaxyssi_voice_conversation", 0)
        val hadCameraConsent = voicePreferences.contains("camera_share_accepted")
        val originalCameraConsent = voicePreferences.getBoolean("camera_share_accepted", false)
        assertEquals(PackageManager.PERMISSION_GRANTED, context.checkSelfPermission(Manifest.permission.RECORD_AUDIO))
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ) as MainActivity
        try {
            instrumentation.waitForIdleSync()
            instrumentation.runOnMainSync { activity.showMainTab(PAGE_AGENT) }
            test(activity)
        } finally {
            instrumentation.runOnMainSync { activity.agentVoiceConversation?.end(); activity.finish() }
            voicePreferences.edit().apply {
                if (hadCameraConsent) putBoolean("camera_share_accepted", originalCameraConsent)
                else remove("camera_share_accepted")
            }.commit()
        }
    }

    private fun awaitState(message: String, timeoutMs: Long = 8_000L, predicate: () -> Boolean) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            var matches = false
            instrumentation.runOnMainSync { matches = predicate() }
            if (matches) return
            SystemClock.sleep(50)
        }
        fail(message)
    }

    private fun screenshot(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val file = File(instrumentation.targetContext.getExternalFilesDir(null), "voice-ui-tests/$name.png")
        file.parentFile?.mkdirs()
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: error("Screenshot unavailable")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }
}
