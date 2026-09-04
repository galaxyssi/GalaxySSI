package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DownloadManager
import android.app.Dialog
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.drawable.AnimatedImageDrawable
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaRecorder
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.text.Editable
import android.text.InputType
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.TextUtils
import android.text.TextWatcher
import android.text.style.CharacterStyle
import android.text.style.ForegroundColorSpan
import android.text.style.RelativeSizeSpan
import android.text.style.UpdateAppearance
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.*
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.zxing.BarcodeFormat
import com.google.zxing.integration.android.IntentIntegrator
import com.google.zxing.qrcode.QRCodeWriter
import com.rementia.openwakeword.lib.WakeWordEngine
import com.rementia.openwakeword.lib.model.DetectionMode
import com.rementia.openwakeword.lib.model.WakeWordModel
import com.galaxyssi.chat.GalaxySSIMqttClient.Listener
import com.galaxyssi.chat.ui.AgentComposerUiPolicy
import com.galaxyssi.chat.ui.AppleHoldToTalkController
import com.galaxyssi.chat.ui.VoiceWaveformView
import com.galaxyssi.chat.voice.TranscriptHypothesis
import com.galaxyssi.chat.voice.VoiceFailure
import com.galaxyssi.chat.voice.VoiceFeatureFlags
import com.galaxyssi.chat.voice.VoiceInteractionCommand
import com.galaxyssi.chat.voice.VoiceInteractionCoordinator
import com.galaxyssi.chat.voice.VoiceInteractionCoordinatorRegistry
import com.galaxyssi.chat.voice.VoiceInteractionEvent
import com.galaxyssi.chat.voice.VoiceInteractionPhase
import com.galaxyssi.chat.voice.VoiceRouteDecision
import com.galaxyssi.chat.voice.VoiceRouteKind
import com.galaxyssi.chat.voice.VoiceSessionConfig
import com.galaxyssi.chat.voice.VoiceTtsRequest
import com.galaxyssi.chat.voice.VoiceTtsRequestRegistry
import com.galaxyssi.chat.voice.audio.AdaptiveEndpointConfig
import com.galaxyssi.chat.voice.audio.AndroidPcmRecorder
import com.galaxyssi.chat.voice.audio.DirectPcmFramePacket
import com.galaxyssi.chat.voice.audio.EndpointReason
import com.galaxyssi.chat.voice.audio.PcmCaptureConfig
import com.galaxyssi.chat.voice.audio.PcmSnapshot
import com.galaxyssi.chat.voice.audio.PcmStopReason
import com.galaxyssi.chat.voice.audio.PcmWaveFileAdapter
import com.galaxyssi.chat.voice.audio.VadDecision
import com.galaxyssi.chat.voice.audio.VoiceAudioHub
import com.galaxyssi.chat.voice.audio.VoiceAudioHubListener
import com.galaxyssi.chat.voice.asr.AsrNetworkType
import com.galaxyssi.chat.voice.asr.AsrProviderSelector
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import com.galaxyssi.chat.voice.asr.VoiceRecognitionPreference
import com.galaxyssi.chat.voice.asr.online.CachingRealtimeAsrCredentialSource
import com.galaxyssi.chat.voice.asr.online.HttpRealtimeAsrCredentialSource
import com.galaxyssi.chat.voice.asr.online.OnlineAsrCompletion
import com.galaxyssi.chat.voice.asr.online.OnlineRealtimeAsrTurn
import com.galaxyssi.chat.voice.asr.online.RealtimeAsrPreconnector
import com.galaxyssi.chat.voice.asr.online.RealtimeAsrProvider
import com.galaxyssi.chat.voice.asr.online.RealtimeAsrTurnAction
import com.galaxyssi.chat.voice.asr.remote.RemoteWhisperNodeClient
import com.galaxyssi.chat.voice.asr.remote.RemoteWhisperNodeRegistry
import com.galaxyssi.chat.voice.asr.remote.RemoteWhisperRoutingPolicy
import com.galaxyssi.chat.voice.asr.remote.GalaxySSILinkRemoteWhisperTransport
import com.galaxyssi.chat.voice.asr.local.AbortReason
import com.galaxyssi.chat.voice.asr.local.AsrConfig as HighAccuracyAsrConfig
import com.galaxyssi.chat.voice.asr.local.AsrEvent as HighAccuracyAsrEvent
import com.galaxyssi.chat.voice.asr.local.AsrPerformanceMode
import com.galaxyssi.chat.voice.asr.local.DefaultWhisperDecodeScheduler
import com.galaxyssi.chat.voice.asr.local.HighAccuracyAsrResult
import com.galaxyssi.chat.voice.asr.local.AsrTranscriptCompletenessPolicy
import com.galaxyssi.chat.voice.asr.local.HighAccuracyLocalAsrController
import com.galaxyssi.chat.voice.asr.local.HighAccuracyLocalAsrTurn
import com.galaxyssi.chat.voice.asr.local.LiveWhisperTranscriptionSession
import com.galaxyssi.chat.voice.asr.local.LiveWhisperTranscriptUpdate
import com.galaxyssi.chat.voice.asr.local.NativeWhisperCode
import com.galaxyssi.chat.voice.asr.local.LargeTurboQnnModelAction
import com.galaxyssi.chat.voice.asr.local.LargeTurboQnnModelManager
import com.galaxyssi.chat.voice.asr.local.LargeTurboQnnModelStatus
import com.galaxyssi.chat.voice.asr.local.QnnAsrEligibility
import com.galaxyssi.chat.voice.asr.local.QnnModelDownloadNetworkPolicy
import com.galaxyssi.chat.voice.asr.local.QnnWhisperPackageManager
import com.galaxyssi.chat.voice.asr.local.QnnWhisperPackageStatus
import com.galaxyssi.chat.voice.asr.local.WhisperDecodeScheduler
import com.galaxyssi.chat.voice.asr.local.largeTurboQnnModelAction
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkManager
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkDeferredException
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkProgress
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkRecord
import com.galaxyssi.chat.voice.benchmark.WhisperBenchmarkStage
import com.galaxyssi.chat.voice.benchmark.WhisperProviderChoice
import com.galaxyssi.chat.voice.benchmark.WhisperUserVoiceMode
import com.galaxyssi.chat.voice.correction.AndroidVoiceExecutionRecordStore
import com.galaxyssi.chat.voice.correction.CorrectionDecision
import com.galaxyssi.chat.voice.correction.DefaultVoiceCommandRiskClassifier
import com.galaxyssi.chat.voice.correction.TranscriptDiff
import com.galaxyssi.chat.voice.correction.VoiceCommandRisk
import com.galaxyssi.chat.voice.correction.VoiceCorrectionContextRecord
import com.galaxyssi.chat.voice.correction.VoiceCorrectionJournal
import com.galaxyssi.chat.voice.correction.VoiceExecutionLedger
import com.galaxyssi.chat.voice.correction.VoiceEntityType
import com.galaxyssi.chat.voice.correction.VoiceSecondPassCoordinator
import com.galaxyssi.chat.voice.correction.VoiceSecondPassRequest
import com.galaxyssi.chat.voice.correction.VoiceSecondPassResult
import com.galaxyssi.chat.voice.correction.VoiceSecondPassTriggerPolicy
import com.galaxyssi.chat.voice.audio.VoiceAudioSession
import com.galaxyssi.chat.voice.audio.VoiceAudioSessionConfig
import com.galaxyssi.chat.voice.agent.VoiceAgentEvent
import com.galaxyssi.chat.voice.agent.VoiceAgentRunBridge
import com.galaxyssi.chat.voice.agent.VoiceAgentRunListener
import com.galaxyssi.chat.voice.agent.VoiceAgentRunSnapshot
import com.galaxyssi.chat.voice.agent.VoiceAgentRunState
import com.galaxyssi.chat.voice.agent.VoiceAgentRunUpdate
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTelemetry
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTraceContext
import com.galaxyssi.chat.voice.metrics.VoiceTraceEvents
import com.galaxyssi.chat.voice.model.WhisperExecutionMode
import com.galaxyssi.chat.voice.model.WhisperCertificationLevel
import com.galaxyssi.chat.voice.model.WhisperMemoryAdmissionPolicy
import com.galaxyssi.chat.voice.model.WhisperModelFamily
import com.galaxyssi.chat.voice.model.WhisperModelFallbackPolicy
import com.galaxyssi.chat.voice.reliability.AndroidVoiceReliabilityController
import com.galaxyssi.chat.voice.reliability.VoicePipelineFeature
import com.galaxyssi.chat.voice.reliability.VoicePerformanceHealth
import com.galaxyssi.chat.voice.reliability.VoiceResourceMode
import com.galaxyssi.chat.voice.reliability.VoiceWorkloadProfile
import com.galaxyssi.chat.voice.modelstream.ModelStreamCancelReason
import com.galaxyssi.chat.voice.modelstream.CommittedSpeechChunk
import com.galaxyssi.chat.voice.modelstream.DefaultSentenceCommitter
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import com.galaxyssi.chat.voice.modelstream.ModelStreamUiMerger
import com.galaxyssi.chat.voice.modelstream.ModelStreamUiUpdate
import com.galaxyssi.chat.voice.modelstream.ModelUsage
import com.galaxyssi.chat.voice.modelstream.SentenceCommitter
import com.galaxyssi.chat.voice.tts.BargeInActions
import com.galaxyssi.chat.voice.tts.BargeInController
import com.galaxyssi.chat.voice.tts.BargeInTaskKind
import com.galaxyssi.chat.voice.tts.ProgressiveTtsUtteranceRegistry
import com.galaxyssi.chat.voice.tts.ProgressiveTtsUtteranceRequest
import com.galaxyssi.chat.voice.tts.TtsCancelReason
import com.galaxyssi.chat.voice.tts.TtsChunkPlayback
import com.galaxyssi.chat.voice.tts.TtsChunkPlaybackCallbacks
import com.galaxyssi.chat.voice.tts.TtsChunkPlayer
import com.galaxyssi.chat.voice.tts.TtsChunkScheduler
import com.galaxyssi.chat.voice.tts.TtsChunkSchedulerCallbacks
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import okhttp3.OkHttpClient
import kotlin.concurrent.thread
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.sin

internal fun MainActivity.presentVoiceAgentState(state: AgentUiState, traceId: String = activeVoiceTraceId) {
    if (activeMainTab != PAGE_VOICE || wakePage.visibility != View.VISIBLE) return
    val pending = state.pendingAction
    val detail = when (state.phase) {
        AgentPhase.WAITING_CONFIRMATION -> getString(
            R.string.voice_agent_confirmation_required,
            pending?.description ?: state.plan?.expectedResult.orEmpty()
        )
        AgentPhase.WAITING_RESPONSE -> state.lastActionResult?.message
            ?.ifBlank { getString(R.string.voice_agent_waiting_response) }
            ?: getString(R.string.voice_agent_waiting_response)
        AgentPhase.BLOCKED,
        AgentPhase.FAILED -> state.lastActionResult?.message
            ?.ifBlank { getString(R.string.voice_agent_failed) }
            ?: getString(R.string.voice_agent_failed)
        AgentPhase.PAUSED -> getString(R.string.voice_agent_paused)
        AgentPhase.COMPLETED -> state.lastActionResult?.message
            ?.ifBlank { state.plan?.expectedResult.orEmpty() }
            ?.ifBlank { getString(R.string.voice_agent_completed) }
            ?: getString(R.string.voice_agent_completed)
        else -> state.lastActionResult?.message
            ?.ifBlank { state.plan?.expectedResult.orEmpty() }
            ?.ifBlank { getString(R.string.voice_agent_running) }
            ?: getString(R.string.voice_agent_running)
    }.take(4_000)
    val status = when (state.phase) {
        AgentPhase.WAITING_CONFIRMATION -> getString(R.string.voice_agent_needs_confirmation)
        AgentPhase.WAITING_RESPONSE -> getString(R.string.voice_agent_waiting)
        AgentPhase.COMPLETED -> getString(R.string.voice_agent_completed)
        AgentPhase.BLOCKED,
        AgentPhase.FAILED -> getString(R.string.voice_agent_failed)
        AgentPhase.PAUSED -> getString(R.string.voice_agent_paused)
        else -> getString(R.string.voice_agent_running)
    }
    wakeReplyPinnedUntilMs = System.currentTimeMillis() + 60_000L
    updateWakeVoiceUi(status, detail)
    val config = VoiceAssistantSettings.get(this)
    val waitingForRemoteAgent = state.phase == AgentPhase.WAITING_RESPONSE
    if (waitingForRemoteAgent) {
        scheduleVoiceRestart(350L)
        return
    }
    if (config.speakReplies && detail.isNotBlank()) {
        speakWithConfiguredTts(detail.take(1_200), traceId = traceId) {
            if (state.phase in setOf(AgentPhase.COMPLETED, AgentPhase.BLOCKED, AgentPhase.FAILED)) {
                completeVoiceTrace(traceId, state.phase)
            }
            if (voiceAssistantAwake && activeMainTab == PAGE_VOICE) {
                startCommandListening()
            }
        }
    } else {
        if (state.phase in setOf(AgentPhase.COMPLETED, AgentPhase.BLOCKED, AgentPhase.FAILED)) {
            completeVoiceTrace(traceId, state.phase)
        }
        scheduleVoiceRestart(900L)
    }
}

internal fun MainActivity.processVoiceAgentTranscript(success: Boolean, content: String) {
    val transcript = content.trim()
    if (!success || transcript.isBlank()) {
        updateWakeVoiceUi(
            getString(R.string.voice_status_transcription_failed),
            transcript.ifBlank { getString(R.string.voice_status_retry_later) }
        )
        scheduleVoiceRestart(1200L)
        return
    }
    updateWakeVoiceUi(getString(R.string.voice_status_transcribed), transcript)
    submitVoiceAgentGoal(transcript)
}

internal fun MainActivity.voiceAssistantTargetContact(config: VoiceAssistantConfig = VoiceAssistantSettings.get(this)): Contact {
    val contactId = if (config.routingMode == VoiceAssistantSettings.ROUTING_MODE_NATIVE_AGENT) {
        resolveVoiceAssistantSttContactId(config.targetContactId)
    } else {
        resolveVoiceAssistantTargetContactId(config.targetContactId)
    }
    return contactById(contactId)
}

internal fun MainActivity.resolveVoiceAssistantSttContactId(configuredId: String): String {
    if (configuredId.isNotBlank() &&
        AppStore.usesPcConnectorTunnel(this, configuredId) &&
        AppStore.outgoingTopicForContact(this, configuredId) != null
    ) {
        return configuredId
    }
    val contacts = AppStore.contacts(this)
    for (index in 0 until contacts.length()) {
        val raw = contacts.optJSONObject(index) ?: continue
        if (raw.optBoolean("deleted", false)) continue
        val id = raw.optString("id").ifBlank { jsonGalaxySSIId(raw) }
        if (id.isNotBlank() &&
            AppStore.usesPcConnectorTunnel(this, id) &&
            AppStore.outgoingTopicForContact(this, id) != null
        ) {
            return id
        }
    }
    return CONTACT_HERMES.id
}

internal fun MainActivity.resolveVoiceAssistantTargetContactId(configuredId: String): String {
    val configured = configuredId.ifBlank { CONTACT_HERMES.id }
    if (configured != CONTACT_HERMES.id && AppStore.canCommunicateWith(this, configured)) {
        return configured
    }

    val contacts = AppStore.contacts(this)
    for (i in 0 until contacts.length()) {
        val raw = contacts.optJSONObject(i) ?: continue
        if (raw.optBoolean("deleted", false) || raw.optString("trust_state") == "deleted") continue
        val id = raw.optString("id").ifBlank { jsonGalaxySSIId(raw) }
        if (id.isBlank() || id == CONTACT_HERMES.id || !AppStore.canCommunicateWith(this, id)) continue

        val agentId = raw.optString("agent_id")
        val desktopId = raw.optString("desktop_id")
        val deliveryMode = raw.optString("delivery_mode")
        val name = raw.optString("name", id)
        val isHermesAgent = agentId == CONTACT_HERMES.id ||
            id.substringAfter(':', "") == CONTACT_HERMES.id ||
            name.contains("Hermes", ignoreCase = true)
        val usesDesktopTunnel = desktopId.isNotBlank() ||
            deliveryMode == "pc_connector" ||
            raw.optString("parent_contact") == CONTACT_HERMES.id ||
            raw.optString("signal_session") == "pc_tunnel"
        if (isHermesAgent && usesDesktopTunnel) return id
    }

    return configured.takeIf { AppStore.canCommunicateWith(this, it) } ?: CONTACT_HERMES.id
}

internal fun MainActivity.shouldUseProgressiveCloudSpeech(traceId: String): Boolean {
    val config = VoiceAssistantSettings.get(this)
    return traceId.isNotBlank() &&
        config.speakReplies &&
        voiceAssistantAwake &&
        activeMainTab == PAGE_VOICE &&
        VoiceFeatureFlags.isSentenceCommitterEnabled(this) &&
        VoiceFeatureFlags.isProgressiveTtsEnabled(this)
}

internal fun MainActivity.beginProgressiveCloudSpeech(state: ActiveCloudStream) {
    progressiveTtsScheduler.begin(
        state.requestId,
        TtsChunkSchedulerCallbacks(
            onPlaybackStarted = { chunk ->
                if (activeProgressiveSpeechSessionId == state.requestId) {
                    voiceAssistantSpeaking = true
                    updateWakeVoiceUi(getString(R.string.voice_status_speaking), chunk.speechText.take(80))
                    voiceCoordinatorSession(state.voiceTraceId).takeIf(String::isNotBlank)?.let { sessionId ->
                        dispatchVoiceCoordinator(VoiceInteractionEvent.PlaybackStarted(sessionId, state.requestId))
                    }
                }
            },
            onUnderrun = { count ->
                VoiceLatencyTelemetry.record(
                    this,
                    state.voiceTraceId,
                    VoiceTraceEvents.TTS_QUEUE_UNDERRUN,
                    mapOf("underrun_count" to count.toString())
                )
            },
            onFinished = { success, errorCode ->
                if (activeProgressiveSpeechSessionId == state.requestId) {
                    VoiceLatencyTelemetry.record(
                        this,
                        state.voiceTraceId,
                        VoiceTraceEvents.TTS_COMPLETED,
                        mapOf(
                            "tts_provider" to activeProgressiveSpeechProvider,
                            "success" to success.toString(),
                            "error_code" to errorCode.orEmpty()
                        ),
                        once = true
                    )
                    if (success) {
                        VoiceRuntimeHealthRegistry.success(progressiveTtsRuntimeChannel())
                    } else {
                        VoiceRuntimeHealthRegistry.failure(
                            progressiveTtsRuntimeChannel(),
                            errorCode.orEmpty().ifBlank { "Progressive TTS playback failed" }
                        )
                    }
                    resumeVoiceAssistantAfterSpeech(state.requestId, state.voiceTraceId)
                }
            },
            onCancelled = {
                if (activeProgressiveSpeechSessionId == state.requestId) {
                    activeProgressiveSpeechSessionId = ""
                    activeProgressiveSpeechTraceId = ""
                    activeProgressiveSpeechProvider = ""
                    voiceAssistantSpeaking = false
                    releaseVoicePlaybackAudioFocus()
                }
            }
        )
    )
    activeProgressiveSpeechSessionId = state.requestId
    activeProgressiveSpeechTraceId = state.voiceTraceId
    activeProgressiveSpeechProvider = VoiceAssistantSettings.get(this).ttsProvider
}

internal fun MainActivity.enqueueProgressiveSpeech(
    state: ActiveCloudStream,
    chunks: List<CommittedSpeechChunk>
) {
    if (!state.progressiveSpeechEnabled || chunks.isEmpty()) return
    state.sentenceCommitRunnable?.let(handler::removeCallbacks)
    state.sentenceCommitRunnable = null
    chunks.forEach { chunk ->
        val result = progressiveTtsScheduler.enqueue(state.requestId, chunk)
        if (result == com.galaxyssi.chat.voice.tts.TtsEnqueueResult.ACCEPTED ||
            result == com.galaxyssi.chat.voice.tts.TtsEnqueueResult.COALESCED
        ) {
            VoiceLatencyTelemetry.record(
                this,
                state.voiceTraceId,
                VoiceTraceEvents.MODEL_FIRST_SENTENCE_COMMITTED,
                mapOf(
                    "chunk_sequence" to chunk.sequence.toString(),
                    "chunk_characters" to chunk.speechText.length.toString()
                ),
                once = true
            )
        }
    }
}

internal fun MainActivity.playProgressiveTtsChunk(
    chunk: CommittedSpeechChunk,
    callbacks: TtsChunkPlaybackCallbacks
): TtsChunkPlayback {
    val cancelled = AtomicBoolean(false)
    val completed = AtomicBoolean(false)
    val traceId = activeProgressiveSpeechTraceId.takeIf {
        activeProgressiveSpeechSessionId == chunk.requestId
    }.orEmpty()
    val finish: (Boolean, String?) -> Unit = { success, errorCode ->
        if (!cancelled.get() && completed.compareAndSet(false, true)) {
            callbacks.onCompleted(success, errorCode)
        }
    }
    if (!acquireVoicePlaybackAudioFocus()) {
        finish(false, "AUDIO_FOCUS_DENIED")
        return TtsChunkPlayback { }
    }
    runCatching { speechRecognizer?.cancel() }
    voiceAssistantListening = false
    voiceAssistantSpeaking = true
    val config = VoiceAssistantSettings.get(this)
    val startAndroidFallback = {
        activeProgressiveSpeechProvider = "android_system"
        playProgressiveAndroidTtsChunk(chunk, traceId, callbacks.onStarted, finish)
    }
    if (config.ttsProvider == VoiceAssistantSettings.PROVIDER_MICROSOFT_EDGE) {
        activeProgressiveSpeechProvider = "microsoft_edge"
        VoiceRuntimeHealthRegistry.begin(VoiceRuntimeChannel.MICROSOFT_EDGE_TTS)
        val voice = LanguagePolicySettings.microsoftVoice(config.ttsLanguage, config.microsoftVoice)
        microsoftTts.speak(
            chunk.speechText,
            voice,
            traceId,
            prefetchKey = progressiveTtsPrefetchKey(chunk),
            onPlaybackStarted = { runOnUiThread { callbacks.onStarted() } },
            recordCompletion = false
        ) { success, error ->
            runOnUiThread {
                when {
                    cancelled.get() -> Unit
                    success -> finish(true, null)
                    error == "cancelled" -> finish(false, "TTS_CANCELLED")
                    else -> startAndroidFallback()
                }
            }
        }
    } else {
        startAndroidFallback()
    }
    return TtsChunkPlayback { reason ->
        if (cancelled.compareAndSet(false, true)) {
            progressiveAndroidTtsRequests.clear()
            microsoftTts.stop()
            androidTts?.stop()
            completed.set(true)
            Log.i("GalaxySSIVoice", "Progressive TTS chunk cancelled reason=${reason.name}")
        }
    }
}

internal fun MainActivity.playProgressiveAndroidTtsChunk(
    chunk: CommittedSpeechChunk,
    traceId: String,
    onStarted: () -> Unit,
    onFinished: (Boolean, String?) -> Unit
) {
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.TTS_REQUEST_STARTED,
        mapOf("tts_provider" to "android_system"),
        once = true
    )
    if (!androidTtsReady) {
        onFinished(false, "TTS_NOT_READY")
        return
    }
    VoiceRuntimeHealthRegistry.begin(VoiceRuntimeChannel.ANDROID_SYSTEM_TTS)
    configureAndroidTtsLanguage()
    val utteranceId = "galaxyssi_progressive_${chunk.requestId.hashCode()}_${chunk.sequence}"
    progressiveAndroidTtsRequests.begin(
        ProgressiveTtsUtteranceRequest(
            utteranceId = utteranceId,
            sessionId = chunk.requestId,
            onStarted = {
                VoiceLatencyTelemetry.record(
                    this,
                    traceId,
                    VoiceTraceEvents.TTS_FIRST_AUDIO,
                    mapOf("tts_provider" to "android_system"),
                    once = true
                )
                VoiceLatencyTelemetry.record(
                    this,
                    traceId,
                    VoiceTraceEvents.TTS_PLAYBACK_STARTED,
                    mapOf("tts_provider" to "android_system"),
                    once = true
                )
                onStarted()
            },
            onFinished = { success ->
                onFinished(success, if (success) null else "TTS_PLAYBACK_FAILED")
            }
        )
    )
    val result = androidTts?.speak(
        chunk.speechText,
        TextToSpeech.QUEUE_FLUSH,
        Bundle(),
        utteranceId
    )
    if (result == TextToSpeech.ERROR) {
        progressiveAndroidTtsRequests.finish(utteranceId)
        onFinished(false, "TTS_REJECTED")
        return
    }
    handler.postDelayed({
        val request = progressiveAndroidTtsRequests.finish(utteranceId) ?: return@postDelayed
        androidTts?.stop()
        request.onFinished(false)
    }, 20_000L)
}

internal fun MainActivity.progressiveTtsRuntimeChannel(): VoiceRuntimeChannel =
    if (activeProgressiveSpeechProvider == "microsoft_edge") {
        VoiceRuntimeChannel.MICROSOFT_EDGE_TTS
    } else {
        VoiceRuntimeChannel.ANDROID_SYSTEM_TTS
    }

internal fun MainActivity.resumeVoiceAssistantAfterSpeech(sessionId: String, traceId: String) {
    if (activeProgressiveSpeechSessionId != sessionId) return
    activeProgressiveSpeechSessionId = ""
    activeProgressiveSpeechTraceId = ""
    activeProgressiveSpeechProvider = ""
    resumeVoiceAssistantListening(traceId)
}

internal fun MainActivity.resumeVoiceAssistantListening(traceId: String) {
    voiceAssistantSpeaking = false
    releaseVoicePlaybackAudioFocus()
    completeVoiceTrace(traceId)
    if (voiceAssistantAwake && activeMainTab == PAGE_VOICE && wakePage.visibility == View.VISIBLE) {
        handler.post(::startCommandListening)
    }
}

internal fun MainActivity.acquireVoicePlaybackAudioFocus(): Boolean {
    if (ttsAudioFocusRequest != null) return true
    val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        .setWillPauseWhenDucked(true)
        .setOnAudioFocusChangeListener { change ->
            if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
                handler.post {
                    stopSpeechPlaybackOnly(TtsCancelReason.USER_STOP)
                    releaseVoicePlaybackAudioFocus()
                }
            }
        }
        .build()
    return if (ttsAudioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
        ttsAudioFocusRequest = request
        true
    } else {
        false
    }
}

internal fun MainActivity.releaseVoicePlaybackAudioFocus() {
    val request = ttsAudioFocusRequest ?: return
    ttsAudioFocusRequest = null
    runCatching { ttsAudioManager.abandonAudioFocusRequest(request) }
}

internal fun MainActivity.stopSpeechPlaybackOnly(reason: TtsCancelReason): Boolean {
    val wasSpeaking = voiceAssistantSpeaking || progressiveTtsScheduler.snapshot().sessionId.isNotBlank()
    progressiveTtsScheduler.cancelActive(reason)
    progressiveAndroidTtsRequests.clear()
    microsoftTts.stop()
    androidTts?.stop()
    androidTtsRequests.clear()
    voiceAssistantSpeaking = false
    return wasSpeaking
}

internal fun MainActivity.interruptSpeechForNewUtterance() {
    if (!VoiceFeatureFlags.isBargeInEnabled(this)) return
    val ordinaryStreams = activeCloudStreams.values
        .filter { it.voiceTraceId.isNotBlank() }
        .map { it.contact.id }
        .distinct()
    val wasSpeaking = voiceAssistantSpeaking || progressiveTtsScheduler.snapshot().sessionId.isNotBlank()
    if (!wasSpeaking && ordinaryStreams.isEmpty()) return
    val traceId = activeProgressiveSpeechTraceId.ifBlank { activeVoiceTraceId }
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.TTS_BARGE_IN_STARTED,
        once = true
    )
    val result = bargeInController.interrupt(
        if (ordinaryStreams.isNotEmpty()) BargeInTaskKind.ORDINARY_MODEL else BargeInTaskKind.NONE,
        BargeInActions(
            stopSpeech = { stopSpeechPlaybackOnly(TtsCancelReason.VOICE_BARGE_IN) },
            cancelOrdinaryModel = {
                ordinaryStreams.forEach { contactId ->
                    cancelActiveCloudStream(contactId, ModelStreamCancelReason.VOICE_BARGE_IN)
                }
            },
            releaseAudioFocus = ::releaseVoicePlaybackAudioFocus
        )
    )
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.TTS_BARGE_IN_COMPLETED,
        mapOf(
            "elapsed_ms" to result.elapsedMs.toString(),
            "model_cancelled" to result.ordinaryModelCancelled.toString()
        ),
        once = true
    )
}

internal fun MainActivity.maybeSpeakIncomingReply(msg: ChatMessage) {
    maybeSpeakIncomingReply(msg, activeVoiceTraceId)
}

internal fun MainActivity.maybeSpeakIncomingReply(msg: ChatMessage, traceId: String) {
    val config = VoiceAssistantSettings.get(this)
    if (!config.speakReplies || !voiceAssistantAwake || activeMainTab != PAGE_VOICE) {
        completeVoiceTrace(traceId)
        return
    }
    if (msg.isMine || msg.contact.id == CONTACT_SYSTEM.id || msg.content.isBlank()) return
    speakWithConfiguredTts(msg.content.take(600), traceId = traceId) {
        completeVoiceTrace(traceId)
        startCommandListening()
    }
}

internal fun MainActivity.showVoiceAssistantReply(msg: ChatMessage) {
    if (activeMainTab != PAGE_VOICE || wakePage.visibility != View.VISIBLE) return
    if (msg.isMine || msg.contact.id == CONTACT_SYSTEM.id || msg.content.isBlank()) return
    val targetId = resolveVoiceAssistantTargetContactId(VoiceAssistantSettings.get(this).targetContactId)
    if (msg.contact.id != targetId) return
    wakeReplyPinnedUntilMs = System.currentTimeMillis() + 60_000L
    updateWakeVoiceUi(getString(R.string.voice_status_reply_received), msg.content)
}

internal fun MainActivity.speakWithConfiguredTts(
    text: String,
    timeoutMs: Long = 20_000L,
    fallbackToAndroid: Boolean = true,
    traceId: String = activeVoiceTraceId,
    after: () -> Unit
) {
    if (text.isBlank()) {
        after()
        return
    }
    runCatching { speechRecognizer?.cancel() }
    voiceAssistantListening = false
    voiceAssistantSpeaking = true
    updateWakeVoiceUi(getString(R.string.voice_status_speaking), text.take(60))
    val config = VoiceAssistantSettings.get(this)
    if (config.ttsProvider == VoiceAssistantSettings.PROVIDER_MICROSOFT_EDGE) {
        VoiceRuntimeHealthRegistry.begin(
            VoiceRuntimeChannel.MICROSOFT_EDGE_TTS
        )
        var completed = false
        handler.postDelayed({
            if (!completed && voiceAssistantSpeaking) {
                completed = true
                microsoftTts.stop()
                VoiceRuntimeHealthRegistry.failure(
                    VoiceRuntimeChannel.MICROSOFT_EDGE_TTS,
                    "Microsoft Edge TTS timed out"
                )
                voiceAssistantSpeaking = false
                after()
            }
        }, timeoutMs)
        val voice = LanguagePolicySettings.microsoftVoice(config.ttsLanguage, config.microsoftVoice)
        microsoftTts.speak(
            text,
            voice,
            traceId,
            onPlaybackStarted = {
                voiceCoordinatorSession(traceId).takeIf(String::isNotBlank)?.let { sessionId ->
                    dispatchVoiceCoordinator(
                        VoiceInteractionEvent.PlaybackStarted(sessionId, "microsoft_edge")
                    )
                }
            }
        ) { success, error ->
            runOnUiThread {
                if (completed) return@runOnUiThread
                if (success) {
                    completed = true
                    VoiceRuntimeHealthRegistry.success(
                        VoiceRuntimeChannel.MICROSOFT_EDGE_TTS
                    )
                    voiceAssistantSpeaking = false
                    after()
                } else if (fallbackToAndroid) {
                    completed = true
                    VoiceRuntimeHealthRegistry.failure(
                        VoiceRuntimeChannel.MICROSOFT_EDGE_TTS,
                        error ?: "Microsoft Edge TTS failed"
                    )
                    speakWithAndroidTts(text, traceId, after)
                } else {
                    completed = true
                    VoiceRuntimeHealthRegistry.failure(
                        VoiceRuntimeChannel.MICROSOFT_EDGE_TTS,
                        error ?: "Microsoft Edge TTS failed"
                    )
                    voiceAssistantSpeaking = false
                    after()
                }
            }
        }
    } else {
        speakWithAndroidTts(text, traceId, after)
    }
}

internal fun MainActivity.speakWithAndroidTts(text: String, traceId: String, after: () -> Unit) {
    activeVoiceTraceId = traceId
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.TTS_REQUEST_STARTED,
        mapOf("tts_provider" to "android_system"),
        once = true
    )
    if (!androidTtsReady) {
        VoiceRuntimeHealthRegistry.failure(
            VoiceRuntimeChannel.ANDROID_SYSTEM_TTS,
            "Android TTS is not ready"
        )
        voiceAssistantSpeaking = false
        after()
        return
    }
    VoiceRuntimeHealthRegistry.begin(
        VoiceRuntimeChannel.ANDROID_SYSTEM_TTS
    )
    val utteranceId = "galaxyssi_voice_${System.currentTimeMillis()}"
    androidTtsRequests.begin(
        VoiceTtsRequest(
            utteranceId = utteranceId,
            traceId = traceId,
            onFinished = after
        )
    )
    configureAndroidTtsLanguage()
    val speakResult = androidTts?.speak(
        text,
        TextToSpeech.QUEUE_FLUSH,
        Bundle(),
        utteranceId
    )
    if (speakResult == TextToSpeech.ERROR) {
        androidTtsRequests.discard(utteranceId)
        VoiceRuntimeHealthRegistry.failure(
            VoiceRuntimeChannel.ANDROID_SYSTEM_TTS,
            "Android TTS rejected the utterance"
        )
        voiceAssistantSpeaking = false
        VoiceLatencyTelemetry.record(
            this,
            traceId,
            VoiceTraceEvents.TTS_COMPLETED,
            mapOf(
                "tts_provider" to "android_system",
                "success" to "false",
                "error_code" to "TTS_REJECTED"
            ),
            once = true
        )
        after()
        return
    }
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.TTS_FIRST_AUDIO,
        mapOf("tts_provider" to "android_system"),
        once = true
    )
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.TTS_PLAYBACK_STARTED,
        mapOf("tts_provider" to "android_system"),
        once = true
    )
    voiceCoordinatorSession(traceId).takeIf(String::isNotBlank)?.let { sessionId ->
        dispatchVoiceCoordinator(
            VoiceInteractionEvent.PlaybackStarted(sessionId, utteranceId)
        )
    }
    handler.postDelayed({
        val request = androidTtsRequests.finish(utteranceId)
        if (request != null) {
            androidTts?.stop()
            VoiceRuntimeHealthRegistry.failure(
                VoiceRuntimeChannel.ANDROID_SYSTEM_TTS,
                "Android TTS timed out"
            )
            voiceAssistantSpeaking = false
            VoiceLatencyTelemetry.record(
                this,
                request.traceId,
                VoiceTraceEvents.TTS_COMPLETED,
                mapOf(
                    "tts_provider" to "android_system",
                    "success" to "false",
                    "error_code" to "TTS_TIMEOUT"
                ),
                once = true
            )
            request.onFinished()
        }
    }, 20_000L)
}

internal fun MainActivity.configureAndroidTtsLanguage() {
    val languageTag = LanguagePolicySettings.resolvedTtsLanguage(this)
    androidTts?.language = Locale.forLanguageTag(languageTag)
}

internal fun MainActivity.onAndroidTtsFinished(utteranceId: String?, success: Boolean) {
    val request = androidTtsRequests.finish(utteranceId) ?: return
    voiceAssistantSpeaking = false
    if (success) {
        VoiceRuntimeHealthRegistry.success(VoiceRuntimeChannel.ANDROID_SYSTEM_TTS)
    } else {
        VoiceRuntimeHealthRegistry.failure(
            VoiceRuntimeChannel.ANDROID_SYSTEM_TTS,
            "Android TTS utterance failed"
        )
    }
    VoiceLatencyTelemetry.record(
        this,
        request.traceId,
        VoiceTraceEvents.TTS_COMPLETED,
        mapOf(
            "tts_provider" to "android_system",
            "success" to success.toString(),
            "error_code" to if (success) "" else "TTS_PLAYBACK_FAILED"
        ),
        once = true
    )
    request.onFinished()
}

internal fun MainActivity.completeVoiceTrace(traceId: String, phase: AgentPhase? = null) {
    val failed = phase in setOf(AgentPhase.BLOCKED, AgentPhase.FAILED)
    if (failed) {
        failVoiceCoordinator(traceId, "mobile_agent_${phase?.name?.lowercase(Locale.ROOT)}")
    } else {
        completeVoiceCoordinator(traceId)
    }
    if (traceId.isBlank()) return
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        if (failed) VoiceTraceEvents.SESSION_FAILED else VoiceTraceEvents.SESSION_COMPLETED,
        mapOf(
            "success" to (!failed).toString(),
            "task_status" to (phase?.name?.lowercase(Locale.ROOT) ?: "completed")
        ),
        once = true
    )
    if (activeVoiceTraceId == traceId) activeVoiceTraceId = ""
}

internal fun MainActivity.scheduleVoiceRestart(delayMs: Long) {
    if (voiceAssistantRestartPending || activeMainTab != PAGE_VOICE || wakePage.visibility != View.VISIBLE || voiceAssistantSpeaking) return
    voiceAssistantRestartPending = true
    handler.postDelayed({
        voiceAssistantRestartPending = false
        if (activeMainTab != PAGE_VOICE || wakePage.visibility != View.VISIBLE || voiceAssistantSpeaking) return@postDelayed
        if (voiceAssistantAwake) startCommandListening() else startWakeListening()
    }, delayMs)
}

internal fun MainActivity.bestSpeechResult(bundle: Bundle?): String {
    return bundle
        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        ?.firstOrNull()
        ?.trim()
        .orEmpty()
}

internal fun MainActivity.speechErrorLabel(error: Int): String = when (error) {
    SpeechRecognizer.ERROR_AUDIO -> getString(R.string.voice_error_audio)
    SpeechRecognizer.ERROR_CLIENT -> getString(R.string.voice_error_client)
    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> getString(R.string.voice_error_permission)
    SpeechRecognizer.ERROR_NETWORK -> getString(R.string.voice_error_network)
    SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> getString(R.string.voice_error_network_timeout)
    SpeechRecognizer.ERROR_NO_MATCH -> getString(R.string.voice_error_no_match)
    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> getString(R.string.voice_error_busy)
    SpeechRecognizer.ERROR_SERVER -> getString(R.string.voice_error_server)
    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> getString(R.string.voice_error_speech_timeout)
    else -> getString(R.string.voice_error_unknown, error)
}

internal fun MainActivity.speechErrorDetail(error: Int): String {
    val label = speechErrorLabel(error)
    return when (error) {
        SpeechRecognizer.ERROR_NETWORK,
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
        SpeechRecognizer.ERROR_SERVER -> getString(R.string.voice_error_system_retry, label)
        SpeechRecognizer.ERROR_NO_MATCH,
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> getString(R.string.voice_error_no_valid_speech)
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
        SpeechRecognizer.ERROR_CLIENT -> getString(R.string.voice_error_recovering)
        else -> getString(R.string.voice_error_waiting, label)
    }
}

internal fun MainActivity.containsWakeWord(text: String): Boolean = WakeWordPolicy.matches(text)

internal fun MainActivity.updateWakeVoiceUi(status: String, detail: String) {
    val replyPinned = System.currentTimeMillis() < wakeReplyPinnedUntilMs
    val isReplyUpdate = status == getString(R.string.voice_status_reply_received) || status == getString(R.string.voice_status_speaking)
    val isUserActionUpdate = status.startsWith(getString(R.string.voice_status_awake_listening).substringBefore("，")) ||
        status.startsWith(getString(R.string.voice_status_awake_auto_recording).substringBefore("，")) ||
        status.startsWith(getString(R.string.voice_status_recording)) ||
        status.startsWith(getString(R.string.voice_status_command_sent)) ||
        status.startsWith(getString(R.string.voice_status_sent_to, "")) ||
        status.startsWith(getString(R.string.voice_status_recording_failed)) ||
        status.startsWith(getString(R.string.voice_status_no_speech))
    if (replyPinned && !isReplyUpdate && !isUserActionUpdate) {
        wakeStatusText?.text = status
        return
    }
    if (isUserActionUpdate) wakeReplyPinnedUntilMs = 0L
    wakeStatusText?.text = status
    wakeTranscriptText?.text = detail
    if (isReplyUpdate || isUserActionUpdate) {
        wakeReplyPanel?.visibility = View.VISIBLE
    }
}
