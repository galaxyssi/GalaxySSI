package com.signalasi.chat

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
import com.signalasi.chat.SignalASIMqttClient.Listener
import com.signalasi.chat.ui.AgentComposerUiPolicy
import com.signalasi.chat.ui.AppleHoldToTalkController
import com.signalasi.chat.ui.VoiceWaveformView
import com.signalasi.chat.voice.TranscriptHypothesis
import com.signalasi.chat.voice.VoiceFailure
import com.signalasi.chat.voice.VoiceFeatureFlags
import com.signalasi.chat.voice.VoiceInteractionCommand
import com.signalasi.chat.voice.VoiceInteractionCoordinator
import com.signalasi.chat.voice.VoiceInteractionCoordinatorRegistry
import com.signalasi.chat.voice.VoiceInteractionEvent
import com.signalasi.chat.voice.VoiceInteractionPhase
import com.signalasi.chat.voice.VoiceRouteDecision
import com.signalasi.chat.voice.VoiceRouteKind
import com.signalasi.chat.voice.VoiceSessionConfig
import com.signalasi.chat.voice.VoiceTtsRequest
import com.signalasi.chat.voice.VoiceTtsRequestRegistry
import com.signalasi.chat.voice.audio.AdaptiveEndpointConfig
import com.signalasi.chat.voice.audio.AndroidPcmRecorder
import com.signalasi.chat.voice.audio.DirectPcmFramePacket
import com.signalasi.chat.voice.audio.EndpointReason
import com.signalasi.chat.voice.audio.PcmCaptureConfig
import com.signalasi.chat.voice.audio.PcmSnapshot
import com.signalasi.chat.voice.audio.PcmStopReason
import com.signalasi.chat.voice.audio.PcmWaveFileAdapter
import com.signalasi.chat.voice.audio.PeerVoiceMessageAudio
import com.signalasi.chat.voice.audio.VadDecision
import com.signalasi.chat.voice.audio.VoiceAudioHub
import com.signalasi.chat.voice.audio.VoiceAudioHubListener
import com.signalasi.chat.voice.asr.AsrNetworkType
import com.signalasi.chat.voice.asr.AsrProviderSelector
import com.signalasi.chat.voice.asr.AsrSessionConfig
import com.signalasi.chat.voice.asr.VoiceRecognitionPreference
import com.signalasi.chat.voice.asr.online.CachingRealtimeAsrCredentialSource
import com.signalasi.chat.voice.asr.online.HttpRealtimeAsrCredentialSource
import com.signalasi.chat.voice.asr.online.OnlineAsrCompletion
import com.signalasi.chat.voice.asr.online.OnlineRealtimeAsrTurn
import com.signalasi.chat.voice.asr.online.RealtimeAsrPreconnector
import com.signalasi.chat.voice.asr.online.RealtimeAsrProvider
import com.signalasi.chat.voice.asr.online.RealtimeAsrTurnAction
import com.signalasi.chat.voice.asr.remote.RemoteWhisperNodeClient
import com.signalasi.chat.voice.asr.remote.RemoteWhisperNodeRegistry
import com.signalasi.chat.voice.asr.remote.RemoteWhisperRoutingPolicy
import com.signalasi.chat.voice.asr.remote.SignalASILinkRemoteWhisperTransport
import com.signalasi.chat.voice.asr.local.AbortReason
import com.signalasi.chat.voice.asr.local.AsrConfig as HighAccuracyAsrConfig
import com.signalasi.chat.voice.asr.local.AsrEvent as HighAccuracyAsrEvent
import com.signalasi.chat.voice.asr.local.AsrPerformanceMode
import com.signalasi.chat.voice.asr.local.DefaultWhisperDecodeScheduler
import com.signalasi.chat.voice.asr.local.HighAccuracyAsrResult
import com.signalasi.chat.voice.asr.local.AsrTranscriptCompletenessPolicy
import com.signalasi.chat.voice.asr.local.HighAccuracyLocalAsrController
import com.signalasi.chat.voice.asr.local.HighAccuracyLocalAsrTurn
import com.signalasi.chat.voice.asr.local.LiveWhisperTranscriptionSession
import com.signalasi.chat.voice.asr.local.LiveWhisperTranscriptUpdate
import com.signalasi.chat.voice.asr.local.NativeWhisperCode
import com.signalasi.chat.voice.asr.local.LargeTurboQnnModelAction
import com.signalasi.chat.voice.asr.local.LargeTurboQnnModelManager
import com.signalasi.chat.voice.asr.local.LargeTurboQnnModelStatus
import com.signalasi.chat.voice.asr.local.QnnAsrEligibility
import com.signalasi.chat.voice.asr.local.QnnModelDownloadNetworkPolicy
import com.signalasi.chat.voice.asr.local.QnnWhisperPackageManager
import com.signalasi.chat.voice.asr.local.QnnWhisperPackageStatus
import com.signalasi.chat.voice.asr.local.WhisperDecodeScheduler
import com.signalasi.chat.voice.asr.local.largeTurboQnnModelAction
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkManager
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkDeferredException
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkProgress
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkRecord
import com.signalasi.chat.voice.benchmark.WhisperBenchmarkStage
import com.signalasi.chat.voice.benchmark.WhisperProviderChoice
import com.signalasi.chat.voice.benchmark.WhisperUserVoiceMode
import com.signalasi.chat.voice.correction.AndroidVoiceExecutionRecordStore
import com.signalasi.chat.voice.correction.CorrectionDecision
import com.signalasi.chat.voice.correction.DefaultVoiceCommandRiskClassifier
import com.signalasi.chat.voice.correction.TranscriptDiff
import com.signalasi.chat.voice.correction.VoiceCommandRisk
import com.signalasi.chat.voice.correction.VoiceCorrectionContextRecord
import com.signalasi.chat.voice.correction.VoiceCorrectionJournal
import com.signalasi.chat.voice.correction.VoiceExecutionLedger
import com.signalasi.chat.voice.correction.VoiceEntityType
import com.signalasi.chat.voice.correction.VoiceSecondPassCoordinator
import com.signalasi.chat.voice.correction.VoiceSecondPassRequest
import com.signalasi.chat.voice.correction.VoiceSecondPassResult
import com.signalasi.chat.voice.correction.VoiceSecondPassTriggerPolicy
import com.signalasi.chat.voice.audio.VoiceAudioSession
import com.signalasi.chat.voice.audio.VoiceAudioSessionConfig
import com.signalasi.chat.voice.agent.VoiceAgentEvent
import com.signalasi.chat.voice.agent.VoiceAgentRunBridge
import com.signalasi.chat.voice.agent.VoiceAgentRunListener
import com.signalasi.chat.voice.agent.VoiceAgentRunSnapshot
import com.signalasi.chat.voice.agent.VoiceAgentRunState
import com.signalasi.chat.voice.agent.VoiceAgentRunUpdate
import com.signalasi.chat.voice.metrics.VoiceLatencyTelemetry
import com.signalasi.chat.voice.metrics.VoiceLatencyTraceContext
import com.signalasi.chat.voice.metrics.VoiceTraceEvents
import com.signalasi.chat.voice.model.WhisperExecutionMode
import com.signalasi.chat.voice.model.WhisperCertificationLevel
import com.signalasi.chat.voice.model.WhisperMemoryAdmissionPolicy
import com.signalasi.chat.voice.model.WhisperModelFamily
import com.signalasi.chat.voice.model.WhisperModelFallbackPolicy
import com.signalasi.chat.voice.reliability.AndroidVoiceReliabilityController
import com.signalasi.chat.voice.reliability.VoicePipelineFeature
import com.signalasi.chat.voice.reliability.VoicePerformanceHealth
import com.signalasi.chat.voice.reliability.VoiceResourceMode
import com.signalasi.chat.voice.reliability.VoiceWorkloadProfile
import com.signalasi.chat.voice.modelstream.ModelStreamCancelReason
import com.signalasi.chat.voice.modelstream.CommittedSpeechChunk
import com.signalasi.chat.voice.modelstream.DefaultSentenceCommitter
import com.signalasi.chat.voice.modelstream.ModelStreamEvent
import com.signalasi.chat.voice.modelstream.ModelStreamUiMerger
import com.signalasi.chat.voice.modelstream.ModelStreamUiUpdate
import com.signalasi.chat.voice.modelstream.ModelUsage
import com.signalasi.chat.voice.modelstream.SentenceCommitter
import com.signalasi.chat.voice.tts.BargeInActions
import com.signalasi.chat.voice.tts.BargeInController
import com.signalasi.chat.voice.tts.BargeInTaskKind
import com.signalasi.chat.voice.tts.ProgressiveTtsUtteranceRegistry
import com.signalasi.chat.voice.tts.ProgressiveTtsUtteranceRequest
import com.signalasi.chat.voice.tts.TtsCancelReason
import com.signalasi.chat.voice.tts.TtsChunkPlayback
import com.signalasi.chat.voice.tts.TtsChunkPlaybackCallbacks
import com.signalasi.chat.voice.tts.TtsChunkPlayer
import com.signalasi.chat.voice.tts.TtsChunkScheduler
import com.signalasi.chat.voice.tts.TtsChunkSchedulerCallbacks
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

internal fun MainActivity.selectVoiceCoordinatorRoute(traceId: String, kind: VoiceRouteKind, targetId: String) {
    val sessionId = voiceCoordinatorSession(traceId)
    if (sessionId.isBlank()) return
    when (kind) {
        VoiceRouteKind.LOCAL_ACTION -> voiceExecutionLedger.claimExternalSideEffect(sessionId)
        VoiceRouteKind.REMOTE_AGENT -> voiceExecutionLedger.claimAgentRun(sessionId)
        VoiceRouteKind.CLOUD_MODEL -> Unit
    }
    dispatchVoiceCoordinator(
        VoiceInteractionEvent.RouteSelected(
            sessionId,
            VoiceRouteDecision(kind = kind, targetId = targetId)
        )
    )
}

internal fun MainActivity.failVoiceCoordinator(traceId: String, code: String, recoverable: Boolean = true) {
    val sessionId = voiceCoordinatorSession(traceId)
    if (sessionId.isBlank()) return
    val phase = voiceInteractionCoordinator.snapshot().phase
    dispatchVoiceCoordinator(
        VoiceInteractionEvent.Failed(
            sessionId,
            VoiceFailure(code = code, recoverable = recoverable, stage = phase)
        )
    )
}

internal fun MainActivity.completeVoiceCoordinator(traceId: String) {
    val sessionId = voiceCoordinatorSession(traceId)
    if (sessionId.isBlank()) return
    dispatchVoiceCoordinator(VoiceInteractionEvent.Completed(sessionId))
}

internal fun MainActivity.sharedWhisperDecodeScheduler(): WhisperDecodeScheduler = synchronized(whisperDecodeSchedulerLock) {
    whisperDecodeScheduler ?: DefaultWhisperDecodeScheduler(
        parentScope = voiceAssistantScope,
        decoder = { request ->
            LocalWhisperAsr.decodePcmWindow(
                context = this@sharedWhisperDecodeScheduler,
                pcm16 = request.pcm16,
                sampleRateHz = request.sampleRateHz,
                language = request.language,
                mode = request.mode,
                traceId = request.voiceSessionId,
                source = if (request.isFinal) "audio_record_final_pcm16" else "audio_record_partial_pcm16",
                modelProfileId = request.modelProfileId
            ).result
        },
        abortActive = LocalWhisperAsr::requestAbort
    ).also { whisperDecodeScheduler = it }
}

internal fun MainActivity.isHighAccuracyQnnSelected(): Boolean {
    val settings = VoiceAssistantSettings.get(this)
    return settings.asrAcceleration == VoiceAssistantSettings.ASR_ACCELERATION_QNN &&
        WhisperModelManager.model(settings.asrModel).family == WhisperModelFamily.LARGE_V3_TURBO
}

internal fun MainActivity.prepareHighAccuracyAsrIfSelected() {
    if (isHighAccuracyQnnSelected()) highAccuracyAsrController.prepareAsync()
}

internal fun MainActivity.startHighAccuracyAsrTurn(
    purpose: String,
    traceId: String
): HighAccuracyLocalAsrTurn? {
    if (!isHighAccuracyQnnSelected()) return null
    val settings = VoiceAssistantSettings.get(this)
    val profile = WhisperModelManager.model(settings.asrModel)
    val performanceMode = when (settings.asrRuntimeMode) {
        WhisperUserVoiceMode.FAST -> AsrPerformanceMode.FAST
        WhisperUserVoiceMode.POWER_SAVER -> AsrPerformanceMode.POWER_SAVER
        else -> AsrPerformanceMode.BALANCED
    }
    val config = HighAccuracyAsrConfig(
        language = LanguagePolicySettings.resolvedAsrLanguage(this)
            .substringBefore('-')
            .lowercase(Locale.ROOT)
            .takeIf { it == "zh" }
            ?: "auto",
        updateIntervalMs = when (performanceMode) {
            AsrPerformanceMode.FAST -> 600L
            AsrPerformanceMode.BALANCED -> 900L
            AsrPerformanceMode.POWER_SAVER -> 1_200L
        },
        firstPartialDelayMs = when (performanceMode) {
            AsrPerformanceMode.FAST -> 1_200L
            AsrPerformanceMode.BALANCED -> 1_500L
            AsrPerformanceMode.POWER_SAVER -> 2_000L
        },
        postRollMs = 400L,
        finalizationTimeoutMs = 8_000L,
        performanceMode = performanceMode
    )
    val turn = highAccuracyAsrController.startTurnIfReady(
        config = config,
        modelProfileId = profile.id,
        onPartial = { partial ->
            handleLocalAsrPartial(
                purpose = purpose,
                traceId = traceId,
                stableText = partial.stableText,
                unstableText = partial.unstableText,
                revision = partial.revision.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                providerId = "qnn_htp",
                modelProfileId = profile.id
            )
        }
    )
    if (turn == null) {
        val status = highAccuracyAsrController.preparationStatus.value
        Log.i(
            "SignalASIVoice",
            "High accuracy QNN unavailable reason=${status.reasonCode} " +
                "phase=${status.phase} attempts=${status.attempts}; retaining PCM fallback"
        )
        return null
    }
    highAccuracyAsrTurns.put(traceId, turn)?.cancel()
    Log.i("SignalASIVoice", "High accuracy QNN streaming enabled purpose=$purpose trace=$traceId")
    return turn
}

internal fun MainActivity.startLiveWhisperSession(purpose: String, traceId: String): LiveWhisperTranscriptionSession? {
    if (!VoiceFeatureFlags.isLocalWhisperRuntimeV2Enabled(this) ||
        !VoiceFeatureFlags.isWhisperAdaptivePartialEnabled(this)
    ) return null
    val config = VoiceAssistantSettings.get(this)
    val selected = WhisperModelManager.model(config.asrModel)
    val decision = if (VoiceFeatureFlags.isWhisperPolicyEngineEnabled(this)) {
        WhisperBenchmarkManager.decide(
            context = this,
            userMode = config.asrRuntimeMode,
            selectedProfileId = selected.id,
            foreground = true,
            decodeQueueDepth = sharedWhisperDecodeScheduler().queueSnapshot().queuedPartials
        )
    } else null
    if (decision != null &&
        (decision.provider != WhisperProviderChoice.LOCAL ||
            decision.fastMode != WhisperExecutionMode.REALTIME_PARTIAL ||
            decision.fastProfileId == null)
    ) return null
    val profile = decision?.fastProfileId?.let(WhisperModelManager::model) ?: selected
    if (!WhisperModelManager.isAvailable(this, profile)) return null
    val certification = if (decision != null) {
        WhisperBenchmarkManager.current(this, profile)?.certification
    } else null
    if (VoiceFeatureFlags.isReliabilityGovernorEnabled(this)) {
        val admission = voiceReliabilityController.admit(
            workload = VoiceWorkloadProfile(
                feature = VoicePipelineFeature.LOCAL_WHISPER_REALTIME,
                profileId = profile.id,
                estimatedIncrementalMemoryBytes = WhisperMemoryAdmissionPolicy.estimatedIncrementalBytes(
                    profile = profile,
                    certifiedPeakPssBytes = certification?.peakPssBytes ?: 0L,
                    alreadyLoaded = WhisperModelManager.isLoaded(profile)
                ),
                certifiedPeakPssBytes = certification?.peakPssBytes ?: 0L,
                localInference = true,
                highMemoryLocalModel = profile.family in setOf(
                    WhisperModelFamily.MEDIUM,
                    WhisperModelFamily.LARGE_V3,
                    WhisperModelFamily.LARGE_V3_TURBO
                ),
                allowBackground = false
            ),
            requestedEnabled = true,
            deviceCertified = decision == null || certification?.realtimeCertified == true,
            foreground = true
        )
        if (!admission.allowed) {
            Log.i(
                "SignalASIVoice",
                "Adaptive local ASR gated reason=${admission.fallbackReasonCode} profile=${profile.id}"
            )
            return null
        }
    }
    val session = LiveWhisperTranscriptionSession(
        voiceSessionId = traceId,
        profile = profile,
        language = LanguagePolicySettings.resolvedAsrLanguage(this),
        scheduler = sharedWhisperDecodeScheduler(),
        scope = voiceAssistantScope,
        elapsedRealtime = SystemClock::elapsedRealtime,
        certifiedPartialIntervalMs = decision?.partialIntervalMs ?: certification?.recommendedPartialIntervalMs,
        realtimeCertified = decision == null || certification?.realtimeCertified == true,
        onUpdate = { update -> handleLiveWhisperUpdate(purpose, traceId, update) }
    )
    liveWhisperSessions.put(traceId, session)?.close()
    Log.i("SignalASIVoice", "Adaptive partial enabled purpose=$purpose model=${profile.id} trace=$traceId")
    return session
}

internal fun MainActivity.startOnlineRealtimeAsrTurn(purpose: String, traceId: String): OnlineRealtimeAsrTurn? {
    if (!VoiceFeatureFlags.isOnlineRealtimeAsrEnabled(this) ||
        BuildConfig.REALTIME_ASR_CREDENTIAL_BROKER_URL.isBlank()
    ) return null
    val settings = VoiceAssistantSettings.get(this)
    val config = AsrSessionConfig(
        voiceSessionId = traceId,
        transcriptId = traceId,
        language = LanguagePolicySettings.resolvedAsrLanguage(this),
        preference = settings.recognitionPreference,
        networkType = currentAsrNetworkType(),
        privacy = settings.onlineAsrPrivacy
    )
    if (!AsrProviderSelector.onlineAllowed(config)) return null
    if (VoiceFeatureFlags.isReliabilityGovernorEnabled(this)) {
        val admission = voiceReliabilityController.admit(
            workload = VoiceWorkloadProfile(
                feature = VoicePipelineFeature.ONLINE_REALTIME_ASR,
                profileId = "signalasi_realtime",
                requiresNetwork = true
            ),
            requestedEnabled = true,
            foreground = true
        )
        if (!admission.allowed) {
            Log.i(
                "SignalASIVoice",
                "Realtime ASR gated reason=${admission.fallbackReasonCode}"
            )
            return null
        }
    }
    val turn = OnlineRealtimeAsrTurn(
        config = config,
        preconnector = onlineRealtimeAsrPreconnector,
        scope = voiceAssistantScope,
        onAction = { action -> handleOnlineRealtimeAsrAction(purpose, traceId, action) }
    )
    onlineRealtimeAsrTurns.put(traceId, turn)?.close()
    VoiceRuntimeHealthRegistry.begin(VoiceRuntimeChannel.ONLINE_REALTIME_ASR)
    turn.start()
    return turn
}

internal fun MainActivity.handleOnlineRealtimeAsrAction(
    purpose: String,
    traceId: String,
    action: RealtimeAsrTurnAction
) {
    when (action) {
        is RealtimeAsrTurnAction.Display -> runOnUiThread {
            if (recordingVoiceTraceId != traceId || pcmVoiceSession == null) return@runOnUiThread
            val sessionId = voiceCoordinatorSession(traceId)
            if (sessionId.isNotBlank()) {
                dispatchVoiceCoordinator(
                    if (action.stable) {
                        VoiceInteractionEvent.TranscriptStable(sessionId, action.hypothesis)
                    } else {
                        VoiceInteractionEvent.TranscriptPartial(sessionId, action.hypothesis)
                    }
                )
            }
            val stableText = if (action.stable) action.hypothesis.text else ""
            val unstableText = if (action.stable) "" else action.hypothesis.text
            when (purpose) {
                "agent_input" -> Unit
                "voice_wakeup" -> updateWakeVoiceUi(
                    getString(R.string.voice_status_recording),
                    action.hypothesis.text
                )
                else -> if (isHoldToTalkControllerInitialized()) {
                    holdToTalkController.updateTranscript(stableText, unstableText)
                }
            }
        }
        is RealtimeAsrTurnAction.Commit -> {
            onlineRealtimeAsrFinals[traceId] = action.hypothesis
            VoiceRuntimeHealthRegistry.success(VoiceRuntimeChannel.ONLINE_REALTIME_ASR)
            if (VoiceFeatureFlags.isReliabilityGovernorEnabled(this)) {
                voiceReliabilityController.reportSuccess(
                    VoicePipelineFeature.ONLINE_REALTIME_ASR,
                    "signalasi_realtime"
                )
            }
        }
        is RealtimeAsrTurnAction.Correct -> Unit
        is RealtimeAsrTurnAction.RequestLocalFallback -> {
            VoiceRuntimeHealthRegistry.failure(
                VoiceRuntimeChannel.ONLINE_REALTIME_ASR,
                action.reasonCode
            )
            if (VoiceFeatureFlags.isReliabilityGovernorEnabled(this)) {
                voiceReliabilityController.reportFailure(
                    VoicePipelineFeature.ONLINE_REALTIME_ASR,
                    "signalasi_realtime",
                    error = null,
                    reasonCode = action.reasonCode
                )
            }
            Log.i("SignalASIVoice", "Realtime ASR switched to retained local PCM reason=${action.reasonCode}")
        }
        is RealtimeAsrTurnAction.Failed -> {
            VoiceRuntimeHealthRegistry.failure(
                VoiceRuntimeChannel.ONLINE_REALTIME_ASR,
                action.reasonCode
            )
            if (VoiceFeatureFlags.isReliabilityGovernorEnabled(this)) {
                voiceReliabilityController.reportFailure(
                    VoicePipelineFeature.ONLINE_REALTIME_ASR,
                    "signalasi_realtime",
                    error = null,
                    reasonCode = action.reasonCode
                )
            }
            Log.w("SignalASIVoice", "Realtime ASR unavailable reason=${action.reasonCode}")
        }
        RealtimeAsrTurnAction.None -> Unit
    }
}

internal fun MainActivity.currentAsrNetworkType(): AsrNetworkType {
    val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        ?: return AsrNetworkType.OFFLINE
    val network = manager.activeNetwork ?: return AsrNetworkType.OFFLINE
    val capabilities = manager.getNetworkCapabilities(network) ?: return AsrNetworkType.OFFLINE
    if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
        return AsrNetworkType.OFFLINE
    }
    return when {
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> AsrNetworkType.WIFI
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> AsrNetworkType.MOBILE
        capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) -> AsrNetworkType.OTHER_VALIDATED
        else -> AsrNetworkType.OFFLINE
    }
}

internal fun MainActivity.handleLiveWhisperUpdate(
    purpose: String,
    traceId: String,
    update: LiveWhisperTranscriptUpdate
) {
    val transcript = update.transcript
    if (transcript.final || transcript.displayText.isBlank()) return
    handleLocalAsrPartial(
        purpose = purpose,
        traceId = traceId,
        stableText = transcript.stableText,
        unstableText = transcript.unstableText,
        revision = transcript.revision,
        providerId = "whisper.cpp",
        modelProfileId = update.modelProfileId,
        realTimeFactor = update.realTimeFactor
    )
}

internal fun MainActivity.handleLocalAsrPartial(
    purpose: String,
    traceId: String,
    stableText: String,
    unstableText: String,
    revision: Int,
    providerId: String,
    modelProfileId: String,
    realTimeFactor: Double? = null
) {
    if (stableText.isBlank() && unstableText.isBlank()) return
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.ASR_FIRST_PARTIAL,
        buildMap {
            put("asr_provider", providerId)
            put("model_profile_id", modelProfileId)
            realTimeFactor?.let { put("rtf", String.format(Locale.US, "%.4f", it)) }
        },
        once = true
    )
    runOnUiThread {
        if (recordingVoiceTraceId != traceId || pcmVoiceSession == null) return@runOnUiThread
        val coordinatorSessionId = voiceCoordinatorSession(traceId)
        if (coordinatorSessionId.isNotBlank()) {
            val hypothesis = TranscriptHypothesis(
                text = stableText + unstableText,
                revision = revision,
                provider = providerId,
                modelProfileId = modelProfileId
            )
            dispatchVoiceCoordinator(VoiceInteractionEvent.TranscriptPartial(coordinatorSessionId, hypothesis))
            if (stableText.isNotBlank()) {
                dispatchVoiceCoordinator(
                    VoiceInteractionEvent.TranscriptStable(
                        coordinatorSessionId,
                        hypothesis.copy(text = stableText)
                    )
                )
                VoiceLatencyTelemetry.record(
                    this,
                    traceId,
                    VoiceTraceEvents.ASR_FIRST_STABLE,
                    mapOf(
                        "asr_provider" to providerId,
                        "model_profile_id" to modelProfileId
                    ),
                    once = true
                )
            }
        }
        when (purpose) {
            "agent_input" -> Unit
            "voice_wakeup" -> updateWakeVoiceUi(
                getString(R.string.voice_status_recording),
                stableText + unstableText
            )
            else -> if (isHoldToTalkControllerInitialized()) {
                holdToTalkController.updateTranscript(stableText, unstableText)
            }
        }
    }
}

internal fun MainActivity.closeLiveWhisperSession(traceId: String) {
    if (traceId.isBlank()) return
    liveWhisperSessions.remove(traceId)?.close()
    highAccuracyAsrTurns.remove(traceId)?.cancel()
    highAccuracyAsrFinals.remove(traceId)
}

internal fun MainActivity.startRecording(purpose: String): Boolean {
    if (isVoiceCaptureActive()) return false
    val personContact = selectedContact?.let { contact ->
        AppStore.isPersonContact(this, contact.id)
    } == true
    if (PeerVoiceMessageAudio.shouldUseDedicatedCapture(purpose, personContact)) {
        return startPeerVoiceMessageRecording()
    }
    if (purpose == "agent_input") captureAgentVoiceDraftSnapshot()
    preemptBackgroundWhisperForInteractiveVoice()
    if (VoiceFeatureFlags.isPcmCaptureEnabled(this)) {
        return startPcmRecording(purpose, autoEndpoint = false).also { started ->
            if (!started && purpose == "agent_input") clearAgentVoiceDraftSnapshot()
        }
    }
    val mediaProfile = AgentMediaNetworkDetector.detect(this)
    val traceId = VoiceLatencyTelemetry.startSession(
        this,
        mapOf("recording_source" to purpose)
    )
    val coordinatorSessionId = beginVoiceCoordinatorSession(purpose, traceId)
    activeVoiceTraceId = traceId
    recordingVoiceTraceId = traceId
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.MICROPHONE_OPEN_STARTED,
        mapOf("recording_source" to purpose),
        once = true
    )
    val file = File(cacheDir, "voice_${System.currentTimeMillis()}.m4a")
    var candidate: MediaRecorder? = null
    return runCatching {
        candidate = createRecorder().apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            applyAgentAudioProfile(mediaProfile)
            setOutputFile(file.absolutePath)
            prepare()
            start()
        }
        recorder = candidate
        recordingFile = file
        recordingStartedAt = System.currentTimeMillis()
        recordingPurpose = purpose
        if (coordinatorSessionId.isNotBlank()) {
            dispatchVoiceCoordinator(VoiceInteractionEvent.CapturePrepared(coordinatorSessionId))
            dispatchVoiceCoordinator(
                VoiceInteractionEvent.SpeechStarted(
                    coordinatorSessionId,
                    SystemClock.elapsedRealtimeNanos()
                )
            )
        }
        VoiceLatencyTelemetry.record(
            this,
            traceId,
            VoiceTraceEvents.MICROPHONE_OPENED,
            mapOf("recording_source" to purpose),
            once = true
        )
        VoiceLatencyTelemetry.record(
            this,
            traceId,
            VoiceTraceEvents.SPEECH_STARTED,
            mapOf("recording_source" to purpose),
            once = true
        )
        Log.i("SignalASIVoice", "Recording started purpose=$purpose file=${file.name}")
        true
    }.getOrElse {
        runCatching { candidate?.reset() }
        runCatching { candidate?.release() }
        recorder = null
        recordingFile = null
        recordingPurpose = ""
        recordingVoiceTraceId = ""
        recordingVoiceCoordinatorSessionId = ""
        if (purpose == "agent_input") clearAgentVoiceDraftSnapshot()
        file.delete()
        failVoiceCoordinator(traceId, it.javaClass.simpleName)
        VoiceLatencyTelemetry.record(
            this,
            traceId,
            VoiceTraceEvents.SESSION_FAILED,
            mapOf("error_code" to it.javaClass.simpleName),
            once = true
        )
        Log.e("SignalASIVoice", "Chat recording start failed", it)
        false
    }
}

internal fun MainActivity.startPcmRecording(purpose: String, autoEndpoint: Boolean): Boolean {
    if (isVoiceCaptureActive()) return false
    LocalWhisperAsr.requestAbort(AbortReason.NEW_UTTERANCE)
    val traceId = VoiceLatencyTelemetry.startSession(
        this,
        mapOf("recording_source" to purpose)
    )
    val coordinatorSessionId = beginVoiceCoordinatorSession(purpose, traceId)
    val onlineAsrTurn = startOnlineRealtimeAsrTurn(purpose, traceId)
    val highAccuracyAsrTurn = if (onlineAsrTurn == null) {
        startHighAccuracyAsrTurn(purpose, traceId)
    } else null
    val liveWhisperSession = if (onlineAsrTurn == null && highAccuracyAsrTurn == null) {
        startLiveWhisperSession(purpose, traceId)
    } else null
    val partialSpeechStartedAt = AtomicLong(0L)
    activeVoiceTraceId = traceId
    recordingVoiceTraceId = traceId
    recordingStartedAt = System.currentTimeMillis()
    recordingPurpose = purpose
    recordingFile = null
    pcmVoiceAmplitude = 0
    pcmCaptureStopping = false
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.MICROPHONE_OPEN_STARTED,
        mapOf("recording_source" to purpose),
        once = true
    )
    val endpointConfig = AdaptiveEndpointConfig(
        noSpeechTimeoutMs = 2_500L,
        minimumSpeechMs = 240L,
        shortUtteranceSilenceMs = 850L,
        normalUtteranceSilenceMs = 650L,
        longUtteranceSilenceMs = 500L,
        maxDurationMs = 60_000L,
        preRollMs = 300,
        postRollMs = 400
    )
    val session = voiceAudioHub().start(
        VoiceAudioSessionConfig(
            capture = PcmCaptureConfig(
                frameDurationMs = if (highAccuracyAsrTurn != null) 10 else 20,
                maxDurationMs = endpointConfig.maxDurationMs
            ),
            endpoint = endpointConfig,
            autoEndpoint = autoEndpoint
        ),
        object : VoiceAudioHubListener {
            override val acceptsDirectPcmFrames: Boolean = highAccuracyAsrTurn != null
            override val acceptsPcmFrames: Boolean = onlineAsrTurn != null

            override fun onDirectPcmFrame(session: VoiceAudioSession, frame: DirectPcmFramePacket) {
                highAccuracyAsrTurn?.offer(frame)
            }

            override fun onPcmFrame(
                session: VoiceAudioSession,
                frame: com.signalasi.chat.voice.audio.PcmFramePacket
            ) {
                onlineAsrTurn?.offer(frame)
            }

            override fun onCaptureReady(session: VoiceAudioSession, state: com.signalasi.chat.voice.audio.PcmRecorderState) {
                runOnUiThread {
                    if (pcmVoiceSession?.id != session.id) return@runOnUiThread
                    if (coordinatorSessionId.isNotBlank()) {
                        dispatchVoiceCoordinator(VoiceInteractionEvent.CapturePrepared(coordinatorSessionId))
                    }
                    VoiceLatencyTelemetry.record(
                        this@startPcmRecording,
                        traceId,
                        VoiceTraceEvents.MICROPHONE_OPENED,
                        mapOf("recording_source" to purpose),
                        once = true
                    )
                    VoiceLatencyTelemetry.record(
                        this@startPcmRecording,
                        traceId,
                        VoiceTraceEvents.PCM_CAPTURE_READY,
                        mapOf(
                            "recording_source" to purpose,
                            "audio_source" to state.audioSource.toString(),
                            "input_route" to state.inputRoute
                        ),
                        once = true
                    )
                    Log.i(
                        "SignalASIVoice",
                        "PCM capture ready purpose=$purpose source=${state.audioSource} route=${state.inputRoute}"
                    )
                }
            }

            override fun onAudioLevel(session: VoiceAudioSession, decision: VadDecision) {
                pcmVoiceAmplitude = decision.peak
                val speechStartedAt = partialSpeechStartedAt.get()
                if (decision.isSpeech && speechStartedAt > 0L) liveWhisperSession?.let { live ->
                    val capturedAudioMs = (SystemClock.elapsedRealtime() - speechStartedAt).coerceAtLeast(0L)
                    live.nextPartialWindowMs(capturedAudioMs)?.let { windowMs ->
                        voiceAudioHub().snapshotWindow(session, windowMs)?.let(live::offerPartial)
                    }
                }
                val now = SystemClock.elapsedRealtime()
                if (now - lastPcmAudioLevelDispatchAt >= 100L && coordinatorSessionId.isNotBlank()) {
                    lastPcmAudioLevelDispatchAt = now
                    dispatchVoiceCoordinator(
                        VoiceInteractionEvent.AudioLevel(coordinatorSessionId, decision.rms)
                    )
                }
            }

            override fun onSpeechStarted(session: VoiceAudioSession, sequence: Long) {
                onlineAsrTurn?.onLocalSpeechStarted()
                partialSpeechStartedAt.compareAndSet(0L, SystemClock.elapsedRealtime())
                runOnUiThread {
                    if (pcmVoiceSession?.id != session.id) return@runOnUiThread
                    if (purpose == "voice_wakeup") {
                        voiceCommandSpeechDetected = true
                        voiceCommandLastVoiceAt = System.currentTimeMillis()
                        updateWakeVoiceUi(
                            getString(R.string.voice_status_recording),
                            getString(R.string.voice_status_recording_detail)
                        )
                    }
                    if (coordinatorSessionId.isNotBlank()) {
                        dispatchVoiceCoordinator(
                            VoiceInteractionEvent.SpeechStarted(
                                coordinatorSessionId,
                                SystemClock.elapsedRealtimeNanos()
                            )
                        )
                    }
                    VoiceLatencyTelemetry.record(
                        this@startPcmRecording,
                        traceId,
                        VoiceTraceEvents.SPEECH_STARTED,
                        mapOf("recording_source" to purpose),
                        once = true
                    )
                }
            }

            override fun onSpeechEndedCandidate(session: VoiceAudioSession, sequence: Long) {
                onlineAsrTurn?.onLocalSpeechEnded()
            }

            override fun onEndpoint(session: VoiceAudioSession, reason: EndpointReason) {
                handler.post {
                    if (pcmVoiceSession?.id != session.id || purpose != "voice_wakeup") return@post
                    VoiceLatencyTelemetry.record(
                        this@startPcmRecording,
                        traceId,
                        VoiceTraceEvents.VAD_ENDPOINT,
                        mapOf("endpoint_reason" to endpointReasonCode(reason)),
                        once = true
                    )
                    val send = reason != EndpointReason.NO_SPEECH_TIMEOUT && voiceCommandSpeechDetected
                    stopVoiceCommandRecording(send, endpointReasonCode(reason))
                }
            }

            override fun onInputRouteChanged(session: VoiceAudioSession, route: String) {
                Log.i("SignalASIVoice", "PCM input route changed purpose=$purpose route=$route")
            }

            override fun onFailure(session: VoiceAudioSession, error: Throwable) {
                onlineRealtimeAsrTurns.remove(traceId)?.close()
                runOnUiThread { handlePcmCaptureFailure(session, purpose, traceId, error) }
            }
        }
    ) ?: run {
        onlineRealtimeAsrTurns.remove(traceId)?.close()
        closeLiveWhisperSession(traceId)
        recordingPurpose = ""
        recordingVoiceTraceId = ""
        recordingVoiceCoordinatorSessionId = ""
        failVoiceCoordinator(traceId, "pcm_capture_busy")
        return false
    }
    pcmVoiceSession = session
    Log.i("SignalASIVoice", "PCM recording requested purpose=$purpose session=${session.id}")
    return true
}

internal fun MainActivity.voiceAudioHub(): VoiceAudioHub = pcmVoiceAudioHub ?: VoiceAudioHub(
    recorder = AndroidPcmRecorder(this),
    scope = voiceAssistantScope
).also { pcmVoiceAudioHub = it }

internal fun MainActivity.isVoiceCaptureActive(): Boolean =
    recorder != null || peerVoiceRecorder != null || pcmVoiceSession != null || pcmCaptureStopping

internal fun MainActivity.currentVoiceAmplitude(): Int =
    when {
        pcmVoiceSession != null -> pcmVoiceAmplitude
        peerVoiceRecorder != null -> peerVoiceRecorder?.currentAmplitude() ?: 0
        else -> recorder?.maxAmplitude ?: 0
    }

internal fun MainActivity.endpointReasonCode(reason: EndpointReason): String = when (reason) {
    EndpointReason.TRAILING_SILENCE -> "trailing_silence"
    EndpointReason.NO_SPEECH_TIMEOUT -> "no_speech_timeout"
    EndpointReason.MAX_DURATION -> "max_duration"
}

internal fun MainActivity.handlePcmCaptureFailure(
    session: VoiceAudioSession,
    purpose: String,
    traceId: String,
    error: Throwable
) {
    if (pcmVoiceSession?.id != session.id || pcmCaptureStopping) return
    closeLiveWhisperSession(traceId)
    pcmVoiceSession = null
    pcmVoiceAmplitude = 0
    recordingPurpose = ""
    recordingVoiceTraceId = ""
    recordingVoiceCoordinatorSessionId = ""
    if (purpose == "voice_wakeup") {
        voiceAssistantRecordingCommand = false
        voiceCommandSpeechDetected = false
        updateWakeVoiceUi(
            getString(R.string.voice_status_recording_failed),
            error.message ?: getString(R.string.voice_status_check_microphone)
        )
        scheduleVoiceRestart(1_200L)
    }
    failVoiceCoordinator(traceId, (error as? com.signalasi.chat.voice.audio.PcmCaptureException)?.code ?: error.javaClass.simpleName)
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.SESSION_FAILED,
        mapOf("error_code" to error.javaClass.simpleName),
        once = true
    )
    Log.e("SignalASIVoice", "PCM capture failed purpose=$purpose", error)
}

internal fun MainActivity.showVoiceOverlay() {
    val waveView = object : View(this) {
        private var phase = 0f
        private val paint = Paint().apply {
            color = 0xFFFFFFFF.toInt()
            style = Paint.Style.FILL
            isAntiAlias = true
        }

        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            val amp = currentVoiceAmplitude().coerceIn(0, 32767) / 32767f
            val cy = h / 2f
            val maxAmp = h * 0.4f * (amp * 0.8f + 0.2f)
            val step = 2f
            var x = 0f
            while (x < w) {
                val y = cy + sin(phase + x * 0.08f).toFloat() * maxAmp
                canvas.drawCircle(x, y, 4.5f, paint)
                x += step
            }
            phase += 0.03f
            postInvalidateDelayed(80)
        }
    }
    waveView.setBackgroundColor(0xBF07C160.toInt())
    val size = dp(270)
    voiceOverlay = Dialog(this, android.R.style.Theme_Translucent_NoTitleBar).apply {
        setContentView(waveView)
        window?.setLayout(size, dp(120))
        window?.setGravity(Gravity.CENTER)
        setCancelable(false)
        setCanceledOnTouchOutside(false)
        show()
    }
    waveView.post { waveView.invalidate() }
}

internal fun MainActivity.hideVoiceOverlay() {
    voiceOverlay?.dismiss()
    voiceOverlay = null
}

internal fun MainActivity.showAgentVoiceTranscriptionPending(
    traceId: String
): PendingAgentVoiceTranscription {
    val conversationId = agentTranscriptStore.activeConversation().id
    val identity = traceId.ifBlank { UUID.randomUUID().toString() }
    val draftSnapshot = consumeAgentVoiceDraftSnapshot()
    val appendToDraft = draftSnapshot != null
    val attachments = if (appendToDraft) emptyList() else agentInputAttachments.toList()
    val pending = PendingAgentVoiceTranscription(
        conversationId = conversationId,
        dedupeKey = AgentVoiceTranscriptPolicy.dedupeKey(identity),
        attachments = attachments,
        draftSnapshot = draftSnapshot,
        pendingEntryVisible = !appendToDraft
    )
    if (appendToDraft) return pending
    if (attachments.isNotEmpty()) {
        val attachmentIds = attachments.mapTo(hashSetOf(), AgentInputAttachment::id)
        agentInputAttachments.removeAll { it.id in attachmentIds }
        renderAgentInputAttachments()
    }
    agentTranscriptAutoFollow = true
    agentTranscriptStore.append(
        AgentTranscriptRole.USER,
        getString(R.string.voice_status_recognizing),
        dedupeKey = pending.dedupeKey,
        conversationId = pending.conversationId,
        richOutputJson = AgentRichContentCodec.encode(attachments.map(AgentInputAttachment::richBlock))
    )
    refreshAgentTranscriptWindow(pending.conversationId)
    return pending
}

internal fun MainActivity.dismissAgentVoiceTranscriptionPending(
    pending: PendingAgentVoiceTranscription?
) {
    pending ?: return
    if (pending.pendingEntryVisible) {
        deleteAgentTranscriptByDedupeKey(pending.conversationId, pending.dedupeKey)
    }
    if (pending.attachments.isNotEmpty()) {
        val existingUris = agentInputAttachments.mapTo(hashSetOf()) { it.uri.toString() }
        val availableSlots = (MAX_AGENT_ATTACHMENTS - agentInputAttachments.size).coerceAtLeast(0)
        val restored = pending.attachments
            .filter { it.uri.toString() !in existingUris }
            .take(availableSlots)
        if (restored.isNotEmpty()) {
            agentInputAttachments.addAll(0, restored)
            renderAgentInputAttachments()
        }
    }
    if (agentTranscriptStore.activeConversation().id == pending.conversationId) {
        refreshAgentTranscriptWindow(pending.conversationId)
    }
}

internal fun MainActivity.stopPcmRecording(send: Boolean, reason: String) {
    val session = pcmVoiceSession ?: return
    if (pcmCaptureStopping) return
    pcmCaptureStopping = true
    val purpose = recordingPurpose
    val traceId = recordingVoiceTraceId
    if (!send && purpose == "agent_input") clearAgentVoiceDraftSnapshot()
    val pendingAgentVoice = if (send && purpose == "agent_input") {
        showAgentVoiceTranscriptionPending(traceId)
    } else {
        null
    }
    val coordinatorSessionId = recordingVoiceCoordinatorSessionId.ifBlank {
        voiceCoordinatorSession(traceId)
    }
    val stopReason = pcmStopReason(send, reason)
    val hub = voiceAudioHub()
    hub.requestStop(session, stopReason)
    Log.i("SignalASIVoice", "PCM capture stopping purpose=$purpose send=$send reason=$reason")
    voiceAssistantScope.launch {
        val captureResult = runCatching { hub.stop(session, stopReason) }
        val result = captureResult.getOrNull()
        val highAccuracyTurn = highAccuracyAsrTurns.remove(traceId)
        val highAccuracyCompletion = if (send && result?.snapshot?.samples?.isNotEmpty() == true &&
            highAccuracyTurn != null
        ) {
            runCatching { highAccuracyTurn.finish() }
                .onFailure { error ->
                    Log.w("SignalASIVoice", "High accuracy QNN final failed; retained PCM will be used", error)
                }
                .getOrNull()
        } else {
            highAccuracyTurn?.cancel()
            null
        }
        highAccuracyCompletion?.let { completion ->
            val completeness = AsrTranscriptCompletenessPolicy.evaluate(
                text = completion.text,
                decoderComplete = completion.complete,
                decodedAudioMs = completion.durationMs,
                capturedSpeechMs = result?.snapshot?.speechDurationMs
            )
            if (completeness.accepted) {
                highAccuracyAsrFinals[traceId] = completion
            } else {
                Log.w(
                    "SignalASIVoice",
                    "QNN final rejected reason=${completeness.reasonCode} " +
                        "termination=${completion.termination.name.lowercase()} " +
                        "decodedMs=${completion.durationMs} " +
                        "speechMs=${result?.snapshot?.speechDurationMs ?: -1L} " +
                        "missingMs=${completeness.missingCoverageMs}; retained PCM will be used"
                )
            }
        }
        val onlineTurn = onlineRealtimeAsrTurns.remove(traceId)
        val onlineCompletion = if (send && result?.snapshot?.samples?.isNotEmpty() == true && onlineTurn != null) {
            runCatching { onlineTurn.finish(pcmBufferComplete = captureResult.isSuccess) }.getOrNull()
        } else null
        when (onlineCompletion) {
            is OnlineAsrCompletion.Final -> onlineRealtimeAsrFinals[traceId] = onlineCompletion.hypothesis
            is OnlineAsrCompletion.Failed -> VoiceRuntimeHealthRegistry.failure(
                VoiceRuntimeChannel.ONLINE_REALTIME_ASR,
                onlineCompletion.reasonCode
            )
            else -> Unit
        }
        onlineTurn?.close()
        val waveFile = if (send && result?.snapshot?.samples?.isNotEmpty() == true) {
            runCatching {
                PcmWaveFileAdapter.write(
                    result.snapshot,
                    cacheDir,
                    "voice_${System.currentTimeMillis()}"
                )
            }.getOrNull()
        } else null
        runOnUiThread {
            if (pcmVoiceSession?.id != session.id) {
                waveFile?.delete()
                dismissAgentVoiceTranscriptionPending(pendingAgentVoice)
                return@runOnUiThread
            }
            pcmVoiceSession = null
            pcmCaptureStopping = false
            pcmVoiceAmplitude = 0
            recordingFile = null
            recordingPurpose = ""
            recordingVoiceTraceId = ""
            recordingVoiceCoordinatorSessionId = ""
            VoiceLatencyTelemetry.record(
                this@stopPcmRecording,
                traceId,
                VoiceTraceEvents.SPEECH_ENDED,
                mapOf("endpoint_reason" to reason),
                once = true
            )
            result?.let { completed ->
                VoiceLatencyTelemetry.record(
                    this@stopPcmRecording,
                    traceId,
                    VoiceTraceEvents.PCM_CAPTURE_STOPPED,
                    mapOf(
                        "recording_source" to purpose,
                        "endpoint_reason" to reason,
                        "audio_source" to completed.audioSource.toString(),
                        "input_route" to completed.inputRoute,
                        "audio_duration_ms" to completed.snapshot.durationMs.toString(),
                        "short_read_count" to completed.diagnostics.shortReadCount.toString(),
                        "zero_read_count" to completed.diagnostics.zeroReadCount.toString(),
                        "dropped_frame_count" to completed.diagnostics.droppedFrameCount.toString(),
                        "overrun_count" to completed.diagnostics.suspectedOverrunCount.toString(),
                        "route_change_count" to completed.diagnostics.inputRouteChangeCount.toString()
                    ),
                    once = true
                )
            }
            if (coordinatorSessionId.isNotBlank() && (result?.snapshot?.speechDetected == true || send)) {
                dispatchVoiceCoordinator(
                    VoiceInteractionEvent.SpeechEnded(
                        coordinatorSessionId,
                        SystemClock.elapsedRealtimeNanos()
                    )
                )
            }
            when {
                reason == "no_speech_timeout" -> {
                    waveFile?.delete()
                    dismissAgentVoiceTranscriptionPending(pendingAgentVoice)
                    completeSilentPcmCommand(traceId, coordinatorSessionId)
                }
                !send -> {
                    waveFile?.delete()
                    dismissAgentVoiceTranscriptionPending(pendingAgentVoice)
                    cancelPcmCapture(traceId, coordinatorSessionId, reason)
                }
                captureResult.isFailure || result == null || waveFile == null -> {
                    waveFile?.delete()
                    dismissAgentVoiceTranscriptionPending(pendingAgentVoice)
                    failPcmFinalization(
                        traceId,
                        coordinatorSessionId,
                        captureResult.exceptionOrNull()?.javaClass?.simpleName ?: "pcm_snapshot_failed",
                        purpose
                    )
                }
                purpose == "agent_input" -> finalizePcmAgentInput(
                    waveFile,
                    traceId,
                    coordinatorSessionId,
                    result.snapshot.samples,
                    result.snapshot.sampleRateHz,
                    checkNotNull(pendingAgentVoice)
                )
                purpose == "voice_wakeup" -> finalizePcmVoiceCommand(
                    waveFile,
                    result.snapshot.durationMs,
                    traceId,
                    coordinatorSessionId,
                    result.snapshot.samples,
                    result.snapshot.sampleRateHz
                )
                else -> finalizePcmChatMessage(
                    waveFile,
                    result.snapshot.durationMs,
                    traceId,
                    coordinatorSessionId,
                    result.snapshot.samples,
                    result.snapshot.sampleRateHz
                )
            }
        }
    }
}

internal fun MainActivity.pcmStopReason(send: Boolean, reason: String): PcmStopReason = when (reason) {
    "trailing_silence" -> PcmStopReason.ADAPTIVE_ENDPOINT
    "no_speech_timeout" -> PcmStopReason.NO_SPEECH_TIMEOUT
    "max_duration" -> PcmStopReason.MAX_DURATION
    "app_background" -> PcmStopReason.APP_BACKGROUND
    "audio_interrupted" -> PcmStopReason.AUDIO_INTERRUPTED
    else -> if (send) PcmStopReason.USER_SEND else PcmStopReason.USER_CANCEL
}

internal fun MainActivity.finalizePcmChatMessage(
    file: File,
    durationMs: Long,
    traceId: String,
    coordinatorSessionId: String,
    pcmSamples: ShortArray,
    sampleRateHz: Int
) {
    if (coordinatorSessionId.isNotBlank()) {
        dispatchVoiceCoordinator(VoiceInteractionEvent.FinalizationStarted(coordinatorSessionId))
    }
    val seconds = ((durationMs + 999L) / 1_000L).coerceAtLeast(1L)
    val contact = selectedContact ?: CONTACT_HERMES
    sendVoiceRecordingThroughPipeline(
        sourceFile = file,
        contact = contact,
        seconds = seconds,
        label = "${getString(R.string.message_voice_prefix)} ${seconds}s",
        source = "chat_hold_to_talk_pcm",
        traceId = traceId,
        pcmSamples = pcmSamples,
        sampleRateHz = sampleRateHz
    )
}

internal fun MainActivity.finalizePcmAgentInput(
    file: File,
    traceId: String,
    coordinatorSessionId: String,
    pcmSamples: ShortArray,
    sampleRateHz: Int,
    pending: PendingAgentVoiceTranscription
) {
    if (coordinatorSessionId.isNotBlank()) {
        dispatchVoiceCoordinator(VoiceInteractionEvent.FinalizationStarted(coordinatorSessionId))
    }
    requestAgentInputTranscription(
        file,
        traceId,
        pcmSamples,
        sampleRateHz,
        pending
    )
}

internal fun MainActivity.finalizePcmVoiceCommand(
    file: File,
    durationMs: Long,
    traceId: String,
    coordinatorSessionId: String,
    pcmSamples: ShortArray,
    sampleRateHz: Int
) {
    if (coordinatorSessionId.isNotBlank()) {
        dispatchVoiceCoordinator(VoiceInteractionEvent.FinalizationStarted(coordinatorSessionId))
    }
    val config = VoiceAssistantSettings.get(this)
    val contact = voiceAssistantTargetContact(config)
    val seconds = ((durationMs + 999L) / 1_000L).coerceAtLeast(1L)
    selectedContact = contact
    val nativeAgentRoute = config.routingMode == VoiceAssistantSettings.ROUTING_MODE_NATIVE_AGENT
    val sent = if (nativeAgentRoute) {
        requestVoiceAgentTranscription(file, contact, traceId, pcmSamples, sampleRateHz)
    } else {
        sendVoiceRecordingThroughPipeline(
            sourceFile = file,
            contact = contact,
            seconds = seconds,
            label = getString(R.string.voice_command_label, seconds),
            source = "voice_wakeup_pcm",
            traceId = traceId,
            pcmSamples = pcmSamples,
            sampleRateHz = sampleRateHz
        )
    }
    updateWakeVoiceUi(
        when {
            !sent -> getString(R.string.voice_status_transcription_failed)
            nativeAgentRoute -> getString(R.string.voice_status_transcribing)
            else -> getString(R.string.voice_status_command_sent)
        },
        when {
            !sent -> getString(R.string.voice_status_retry_later)
            nativeAgentRoute -> getString(R.string.voice_status_waiting_transcript, contact.name)
            else -> getString(R.string.voice_status_waiting_reply, contact.name)
        }
    )
    voiceCommandSpeechDetected = false
    voiceCommandLastVoiceAt = 0L
    if (!nativeAgentRoute || !sent) {
        handler.postDelayed({
            if (activeMainTab == PAGE_VOICE && wakePage.visibility == View.VISIBLE &&
                !voiceAssistantSpeaking && !voiceAssistantRecordingCommand
            ) {
                startWakeListening()
            }
        }, 800L)
    }
}

internal fun MainActivity.completeSilentPcmCommand(traceId: String, coordinatorSessionId: String) {
    closeLiveWhisperSession(traceId)
    voiceAssistantRecordingCommand = false
    voiceCommandSpeechDetected = false
    voiceCommandLastVoiceAt = 0L
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.SESSION_COMPLETED,
        mapOf("endpoint_reason" to "no_speech"),
        once = true
    )
    if (coordinatorSessionId.isNotBlank()) {
        dispatchVoiceCoordinator(VoiceInteractionEvent.Completed(coordinatorSessionId))
    }
    updateWakeVoiceUi(
        getString(R.string.voice_status_no_speech),
        getString(R.string.voice_status_waiting_wake)
    )
    if (activeMainTab == PAGE_VOICE) startWakeListening()
}

internal fun MainActivity.cancelPcmCapture(traceId: String, coordinatorSessionId: String, reason: String) {
    closeLiveWhisperSession(traceId)
    voiceAssistantRecordingCommand = false
    voiceCommandSpeechDetected = false
    voiceCommandLastVoiceAt = 0L
    if (coordinatorSessionId.isNotBlank()) {
        dispatchVoiceCoordinator(VoiceInteractionEvent.Cancelled(coordinatorSessionId, reason))
    }
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.SESSION_CANCELLED,
        mapOf("endpoint_reason" to reason),
        once = true
    )
    if (activeMainTab == PAGE_VOICE && reason != "app_background") startWakeListening()
}

internal fun MainActivity.failPcmFinalization(
    traceId: String,
    coordinatorSessionId: String,
    errorCode: String,
    purpose: String
) {
    closeLiveWhisperSession(traceId)
    if (coordinatorSessionId.isNotBlank()) failVoiceCoordinator(traceId, errorCode)
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.SESSION_FAILED,
        mapOf("error_code" to errorCode),
        once = true
    )
    if (purpose == "voice_wakeup") {
        voiceAssistantRecordingCommand = false
        updateWakeVoiceUi(
            getString(R.string.voice_status_recording_failed),
            getString(R.string.voice_status_retry_later)
        )
        scheduleVoiceRestart(1_200L)
    }
}
