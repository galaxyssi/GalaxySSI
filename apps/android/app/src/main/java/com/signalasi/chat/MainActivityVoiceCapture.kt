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

internal fun MainActivity.preemptBackgroundWhisperForInteractiveVoice() {
    interruptSpeechForNewUtterance()
    WhisperBenchmarkManager.cancelForInteractiveVoice()
    voiceSecondPassCoordinator.cancelForInteractiveVoice()
    voiceRiskConfirmationCancellation?.invoke()
    voiceRiskConfirmationCancellation = null
    voiceRiskConfirmationDialog?.dismiss()
    voiceRiskConfirmationDialog = null
    if (isVoiceInteractionCoordinatorInitialized()) {
        val state = voiceInteractionCoordinator.snapshot()
        if (state.sessionId.isNotBlank() && !state.phase.isTerminal && state.phase != VoiceInteractionPhase.IDLE) {
            voiceInteractionCoordinator.cancel("new_utterance")
        }
    }
    LocalWhisperAsr.requestAbort(AbortReason.NEW_UTTERANCE)
}

internal fun MainActivity.startAgentVoiceInput() {
    if (!ensureRecordPermission()) return
    if (!SpeechRecognizer.isRecognitionAvailable(this)) {
        Toast.makeText(this, getString(R.string.voice_status_asr_unavailable), Toast.LENGTH_SHORT).show()
        return
    }
    preemptBackgroundWhisperForInteractiveVoice()
    captureAgentVoiceDraftSnapshot()
    stopVoiceAssistant()
    ensureSpeechRecognizer()
    val config = VoiceAssistantSettings.get(this)
    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, LanguagePolicySettings.resolve(config.asrLanguage))
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 1000L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 800L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 800L)
    }
    runCatching {
        agentVoiceListening = true
        agentRecordingInstruction.text = getString(R.string.agent_voice_listening)
        speechRecognizer?.startListening(intent)
    }.onFailure {
        agentVoiceListening = false
        clearAgentVoiceDraftSnapshot()
        agentRecordingInstruction.text = getString(R.string.agent_voice_recording_hint)
        Toast.makeText(this, it.message ?: getString(R.string.voice_status_retry_later), Toast.LENGTH_SHORT).show()
    }
}

internal fun MainActivity.stopAgentVoiceInput() {
    if (!agentVoiceListening) return
    agentVoiceListening = false
    clearAgentVoiceDraftSnapshot()
    runCatching { speechRecognizer?.cancel() }
    agentRecordingInstruction.text = getString(R.string.agent_voice_recording_hint)
}

internal fun MainActivity.handleAgentVoiceResult(text: String) {
    agentVoiceListening = false
    agentRecordingInstruction.text = getString(R.string.agent_voice_recording_hint)
    if (text.isBlank()) {
        clearAgentVoiceDraftSnapshot()
        Toast.makeText(this, getString(R.string.voice_error_no_valid_speech), Toast.LENGTH_SHORT).show()
        return
    }
    val draftSnapshot = consumeAgentVoiceDraftSnapshot()
    if (draftSnapshot != null) {
        appendAgentVoiceTranscriptToDraft(draftSnapshot, text)
    } else {
        submitAgentGoal(
            goalOverride = text,
            attachmentsOverride = agentInputAttachments.toList()
        )
    }
}

internal fun MainActivity.configureWakePage() {
    findViewById<View>(R.id.wakeTitleHitArea).setOnClickListener {
        showMainTab(PAGE_MESSAGES)
    }
    addWakeVoiceStatusViews()
    val interruptAndListen = View.OnClickListener {
        if (voiceAssistantSpeaking && VoiceFeatureFlags.isBargeInEnabled(this)) {
            interruptSpeechForNewUtterance()
            startVoiceCommandRecording()
        }
    }
    wakeAnimation.setOnClickListener(interruptAndListen)
    wakeReplyPanel?.setOnClickListener(interruptAndListen)
    wakeAnimation.visibility = View.VISIBLE
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        val source = ImageDecoder.createSource(resources, R.drawable.voice_wakeup_ice_text_fixed)
        val drawable = ImageDecoder.decodeDrawable(source)
        wakeAnimation.setImageDrawable(drawable)
        (drawable as? AnimatedImageDrawable)?.start()
    } else {
        wakeAnimation.setImageResource(R.drawable.voice_wakeup_ice_text_fixed)
    }
}

internal fun MainActivity.addWakeVoiceStatusViews() {
    if (wakeStatusText != null) return
    wakeStatusText = TextView(this).apply {
        text = getString(R.string.voice_status_low_power)
        gravity = Gravity.CENTER
        setTextColor(Color.parseColor("#00EFDE"))
        textSize = 15f
        setTypeface(typeface, android.graphics.Typeface.BOLD)
        includeFontPadding = false
        setPadding(dp(18), 0, dp(18), 0)
        background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = dp(17).toFloat()
            setColor(Color.argb(76, 0, 239, 222))
            setStroke(dp(1), Color.argb(170, 0, 239, 222))
        }
    }
    wakeTranscriptText = TextView(this).apply {
        text = getString(R.string.voice_hint_wake)
        gravity = Gravity.START
        setTextColor(Color.parseColor("#F0FDFF"))
        textSize = 15.5f
        maxLines = 30
        includeFontPadding = false
        setLineSpacing(dp(4).toFloat(), 1.0f)
        setPadding(dp(20), dp(18), dp(20), dp(18))
    }
    val replyPanel = ScrollView(this).apply {
        isFillViewport = false
        isVerticalScrollBarEnabled = true
        overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
        elevation = dp(10).toFloat()
        alpha = 0.96f
        visibility = View.GONE
        background = android.graphics.drawable.GradientDrawable().apply {
            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
            cornerRadius = dp(22).toFloat()
            setColor(Color.argb(142, 4, 18, 28))
            setStroke(dp(1), Color.argb(150, 58, 245, 255))
        }
        addView(wakeTranscriptText, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))
    }
    wakeReplyPanel = replyPanel
    wakePage.addView(replyPanel, FrameLayout.LayoutParams(
        FrameLayout.LayoutParams.MATCH_PARENT,
        dp(360),
        Gravity.TOP or Gravity.CENTER_HORIZONTAL
    ).apply {
        leftMargin = dp(18)
        rightMargin = dp(18)
        topMargin = dp(196)
    })
}

internal fun MainActivity.startVoiceAssistant() {
    val config = VoiceAssistantSettings.get(this)
    if (!config.enabled) {
        VoiceRuntimeHealthRegistry.idle(wakeRuntimeChannel(config))
        updateWakeVoiceUi(getString(R.string.voice_status_disabled), getString(R.string.voice_status_disabled_detail))
        return
    }
    if (!ensureRecordPermission()) {
        VoiceRuntimeHealthRegistry.failure(
            wakeRuntimeChannel(config),
            "Microphone permission is required"
        )
        updateWakeVoiceUi(getString(R.string.voice_status_permission_required), getString(R.string.voice_status_permission_detail))
        return
    }
    if (config.wakeProvider == VoiceAssistantSettings.WAKE_PROVIDER_OPEN_WAKE_WORD) {
        voiceAssistantAwake = false
        voiceAssistantSpeaking = false
        startOpenWakeWordListening(config)
        return
    }
    if (!SpeechRecognizer.isRecognitionAvailable(this)) {
        VoiceRuntimeHealthRegistry.failure(
            VoiceRuntimeChannel.ANDROID_WAKE_ASR,
            "Android speech recognition is unavailable"
        )
        updateWakeVoiceUi(getString(R.string.voice_status_asr_unavailable), getString(R.string.voice_status_asr_unavailable_detail))
        return
    }
    ensureSpeechRecognizer()
    voiceAssistantAwake = false
    voiceAssistantSpeaking = false
    startWakeListening()
}

internal fun MainActivity.stopVoiceAssistant() {
    voiceAssistantRestartPending = false
    voiceAssistantListening = false
    voiceAssistantAwake = false
    voiceAssistantSpeaking = false
    if (voiceAssistantRecordingCommand) stopVoiceCommandRecording(send = false)
    voiceCommandSpeechDetected = false
    voiceCommandLastVoiceAt = 0L
    releaseWakeWordEngine()
    runCatching { speechRecognizer?.cancel() }
    runCatching { speechRecognizer?.destroy() }
    speechRecognizer = null
    progressiveTtsScheduler.cancelActive(TtsCancelReason.SESSION_CHANGED)
    progressiveAndroidTtsRequests.clear()
    microsoftTts.stop()
    androidTts?.stop()
    androidTtsRequests.clear()
    activeProgressiveSpeechSessionId = ""
    activeProgressiveSpeechTraceId = ""
    activeProgressiveSpeechProvider = ""
    releaseVoicePlaybackAudioFocus()
    VoiceRuntimeChannel.entries.forEach(VoiceRuntimeHealthRegistry::idle)
}

internal fun MainActivity.ensureSpeechRecognizer() {
    if (speechRecognizer != null) return
    speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this).apply {
        setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                voiceAssistantListening = true
                VoiceRuntimeHealthRegistry.begin(
                    VoiceRuntimeChannel.ANDROID_SYSTEM_ASR
                )
                if (
                    VoiceAssistantSettings.get(this@ensureSpeechRecognizer).wakeProvider ==
                    VoiceAssistantSettings.WAKE_PROVIDER_ANDROID_ASR
                ) {
                    VoiceRuntimeHealthRegistry.begin(
                        VoiceRuntimeChannel.ANDROID_WAKE_ASR
                    )
                }
                Log.i("SignalASIVoice", "ASR ready, awake=$voiceAssistantAwake")
            }
            override fun onBeginningOfSpeech() = Unit
            override fun onRmsChanged(rmsdB: Float) = Unit
            override fun onBufferReceived(buffer: ByteArray?) = Unit
            override fun onEndOfSpeech() {
                voiceAssistantListening = false
                VoiceRuntimeHealthRegistry.idle(
                    VoiceRuntimeChannel.ANDROID_SYSTEM_ASR
                )
                VoiceRuntimeHealthRegistry.idle(
                    VoiceRuntimeChannel.ANDROID_WAKE_ASR
                )
            }
            override fun onError(error: Int) {
                Log.w("SignalASIVoice", "ASR error=$error awake=$voiceAssistantAwake")
                voiceAssistantListening = false
                val errorDetail = speechErrorDetail(error)
                val routineStop = error == SpeechRecognizer.ERROR_CLIENT ||
                    error == SpeechRecognizer.ERROR_NO_MATCH ||
                    error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                val channels = buildList {
                    add(VoiceRuntimeChannel.ANDROID_SYSTEM_ASR)
                    if (
                        VoiceAssistantSettings.get(this@ensureSpeechRecognizer).wakeProvider ==
                        VoiceAssistantSettings.WAKE_PROVIDER_ANDROID_ASR
                    ) {
                        add(VoiceRuntimeChannel.ANDROID_WAKE_ASR)
                    }
                }
                channels.forEach { channel ->
                    if (routineStop) {
                        VoiceRuntimeHealthRegistry.idle(channel)
                    } else {
                        VoiceRuntimeHealthRegistry.failure(channel, errorDetail)
                    }
                }
                if (agentVoiceListening) {
                    agentVoiceListening = false
                    clearAgentVoiceDraftSnapshot()
                    agentRecordingInstruction.text = getString(R.string.agent_voice_recording_hint)
                    Toast.makeText(this@ensureSpeechRecognizer, errorDetail, Toast.LENGTH_SHORT).show()
                    return
                }
                if (activeMainTab == PAGE_VOICE && !voiceAssistantSpeaking) {
                    updateWakeVoiceUi(
                        if (voiceAssistantAwake) getString(R.string.voice_status_continue_listening) else getString(R.string.voice_status_low_power),
                        speechErrorDetail(error)
                    )
                    scheduleVoiceRestart(if (voiceAssistantAwake) 700L else 1000L)
                }
            }
            override fun onResults(results: Bundle?) {
                voiceAssistantListening = false
                val text = bestSpeechResult(results)
                VoiceRuntimeHealthRegistry.success(
                    VoiceRuntimeChannel.ANDROID_SYSTEM_ASR
                )
                if (
                    VoiceAssistantSettings.get(this@ensureSpeechRecognizer).wakeProvider ==
                    VoiceAssistantSettings.WAKE_PROVIDER_ANDROID_ASR
                ) {
                    VoiceRuntimeHealthRegistry.success(
                        VoiceRuntimeChannel.ANDROID_WAKE_ASR
                    )
                }
                if (RuntimePlaintextProtection.isRuntimeDiagnosticsVisible()) {
                    Log.i("SignalASIVoice", "ASR completed chars=${text.length} awake=$voiceAssistantAwake")
                }
                if (agentVoiceListening) {
                    handleAgentVoiceResult(text)
                    return
                }
                handleVoiceRecognitionText(text)
            }
            override fun onPartialResults(partialResults: Bundle?) {
                val text = bestSpeechResult(partialResults)
                if (agentVoiceListening) {
                    return
                }
                if (text.isNotBlank()) {
                    updateWakeVoiceUi(
                        if (voiceAssistantAwake) getString(R.string.voice_status_recognizing) else getString(R.string.voice_status_low_power),
                        text
                    )
                }
            }
            override fun onEvent(eventType: Int, params: Bundle?) = Unit
        })
    }
}

internal fun MainActivity.startOpenWakeWordListening(config: VoiceAssistantConfig) {
    if (activeMainTab != PAGE_VOICE || wakePage.visibility != View.VISIBLE || voiceAssistantSpeaking) return
    releaseWakeWordEngine()
    updateWakeVoiceUi(getString(R.string.voice_status_local_wake_listening), getString(R.string.voice_status_local_wake_detail))
    runCatching {
        val engine = WakeWordEngine(
            context = applicationContext,
            models = listOf(WakeWordModel(WakeWordPolicy.WAKE_WORD, config.wakeModel, threshold = config.wakeThreshold)),
            detectionMode = DetectionMode.SINGLE_BEST,
            detectionCooldownMs = 2500L,
            scope = voiceAssistantScope
        )
        wakeWordEngine = engine
        wakeWordDetectionJob = voiceAssistantScope.launch {
            engine.detections.collect { detection ->
                runOnUiThread {
                    if (activeMainTab != PAGE_VOICE || wakePage.visibility != View.VISIBLE || voiceAssistantSpeaking) return@runOnUiThread
                    Log.i("SignalASIVoice", "openWakeWord detected model=${detection.model.name} score=${detection.score}")
                    releaseWakeWordEngine()
                    onVoiceWakeDetected("openWakeWord ${detection.model.name} ${"%.2f".format(Locale.US, detection.score)}")
                }
            }
        }
        engine.start()
        voiceAssistantListening = true
        VoiceRuntimeHealthRegistry.begin(
            VoiceRuntimeChannel.OPEN_WAKE_WORD
        )
        Log.i("SignalASIVoice", "openWakeWord started model=${config.wakeModel} threshold=${config.wakeThreshold}")
    }.onFailure {
        voiceAssistantListening = false
        VoiceRuntimeHealthRegistry.failure(
            VoiceRuntimeChannel.OPEN_WAKE_WORD,
            it.message ?: it.javaClass.simpleName
        )
        Log.e("SignalASIVoice", "openWakeWord start failed", it)
        updateWakeVoiceUi(getString(R.string.voice_status_local_wake_failed), it.message ?: getString(R.string.voice_status_check_model_permission))
    }
}

internal fun MainActivity.releaseWakeWordEngine() {
    wakeWordDetectionJob?.cancel()
    wakeWordDetectionJob = null
    runCatching { wakeWordEngine?.release() }
    wakeWordEngine = null
    voiceAssistantListening = false
    VoiceRuntimeHealthRegistry.idle(
        VoiceRuntimeChannel.OPEN_WAKE_WORD
    )
}

internal fun MainActivity.startWakeListening() {
    if (activeMainTab != PAGE_VOICE || wakePage.visibility != View.VISIBLE || voiceAssistantSpeaking) return
    val config = VoiceAssistantSettings.get(this)
    if (config.wakeProvider == VoiceAssistantSettings.WAKE_PROVIDER_OPEN_WAKE_WORD) {
        voiceAssistantAwake = false
        startOpenWakeWordListening(config)
        return
    }
    voiceAssistantAwake = false
    updateWakeVoiceUi(getString(R.string.voice_status_low_power), getString(R.string.voice_hint_wake))
    startVoiceRecognition()
}

internal fun MainActivity.startCommandListening() {
    if (activeMainTab != PAGE_VOICE || wakePage.visibility != View.VISIBLE || voiceAssistantSpeaking) return
    startVoiceCommandRecording()
}

internal fun MainActivity.startVoiceCommandRecording() {
    if (activeMainTab != PAGE_VOICE || wakePage.visibility != View.VISIBLE) return
    if (!ensureRecordPermission() || isVoiceCaptureActive()) return
    preemptBackgroundWhisperForInteractiveVoice()
    if (VoiceFeatureFlags.isPcmCaptureEnabled(this)) {
        startPcmVoiceCommandRecording()
        return
    }
    val config = VoiceAssistantSettings.get(this)
    val contact = voiceAssistantTargetContact(config)
    val mediaProfile = AgentMediaNetworkDetector.detect(this)
    val traceId = VoiceLatencyTelemetry.startSession(
        this,
        mapOf("recording_source" to "voice_wakeup")
    )
    val coordinatorSessionId = beginVoiceCoordinatorSession("voice_wakeup", traceId)
    activeVoiceTraceId = traceId
    recordingVoiceTraceId = traceId
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.MICROPHONE_OPEN_STARTED,
        mapOf("recording_source" to "voice_wakeup"),
        once = true
    )
    val file = File(cacheDir, "voice_cmd_${System.currentTimeMillis()}.m4a")
    recordingFile = file
    recordingStartedAt = System.currentTimeMillis()
    voiceAssistantAwake = true
    voiceAssistantRecordingCommand = true
    voiceCommandSpeechDetected = false
    voiceCommandLastVoiceAt = 0L
    Log.i("SignalASIVoice", "Voice command recording started target=${contact.id} file=${file.name}")
    updateWakeVoiceUi(getString(R.string.voice_status_awake_auto_recording), getString(R.string.voice_status_auto_recording_detail))
    runCatching {
        recorder = createRecorder().apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            applyAgentAudioProfile(mediaProfile)
            setOutputFile(file.absolutePath)
            prepare()
            start()
        }
        if (coordinatorSessionId.isNotBlank()) {
            dispatchVoiceCoordinator(VoiceInteractionEvent.CapturePrepared(coordinatorSessionId))
        }
        VoiceLatencyTelemetry.record(
            this,
            traceId,
            VoiceTraceEvents.MICROPHONE_OPENED,
            mapOf("recording_source" to "voice_wakeup"),
            once = true
        )
        monitorVoiceCommandRecording()
    }.onFailure {
        voiceAssistantRecordingCommand = false
        voiceCommandSpeechDetected = false
        voiceCommandLastVoiceAt = 0L
        recorder = null
        recordingFile = null
        recordingVoiceTraceId = ""
        recordingVoiceCoordinatorSessionId = ""
        file.delete()
        failVoiceCoordinator(traceId, it.javaClass.simpleName)
        VoiceLatencyTelemetry.record(
            this,
            traceId,
            VoiceTraceEvents.SESSION_FAILED,
            mapOf("error_code" to it.javaClass.simpleName),
            once = true
        )
        Log.e("SignalASIVoice", "Voice command recording failed", it)
        updateWakeVoiceUi(getString(R.string.voice_status_recording_failed), it.message ?: getString(R.string.voice_status_check_microphone))
        scheduleVoiceRestart(1200L)
    }
}

internal fun MainActivity.startPcmVoiceCommandRecording() {
    val config = VoiceAssistantSettings.get(this)
    val contact = voiceAssistantTargetContact(config)
    voiceAssistantAwake = true
    voiceAssistantRecordingCommand = true
    voiceCommandSpeechDetected = false
    voiceCommandLastVoiceAt = 0L
    updateWakeVoiceUi(
        getString(R.string.voice_status_awake_auto_recording),
        getString(R.string.voice_status_auto_recording_detail)
    )
    if (!startPcmRecording("voice_wakeup", autoEndpoint = true)) {
        voiceAssistantRecordingCommand = false
        voiceAssistantAwake = false
        updateWakeVoiceUi(
            getString(R.string.voice_status_recording_failed),
            getString(R.string.voice_status_check_microphone)
        )
        scheduleVoiceRestart(1_200L)
        return
    }
    Log.i("SignalASIVoice", "PCM voice command requested target=${contact.id}")
}

internal fun MainActivity.monitorVoiceCommandRecording() {
    if (!voiceAssistantRecordingCommand) return
    val activeRecorder = recorder ?: return
    val now = System.currentTimeMillis()
    val elapsed = now - recordingStartedAt
    val amplitude = runCatching { activeRecorder.maxAmplitude }.getOrDefault(0)
    val hasVoice = amplitude > 1600
    if (hasVoice) {
        if (!voiceCommandSpeechDetected) {
            voiceCoordinatorSession(recordingVoiceTraceId).takeIf(String::isNotBlank)?.let { sessionId ->
                dispatchVoiceCoordinator(
                    VoiceInteractionEvent.SpeechStarted(
                        sessionId,
                        SystemClock.elapsedRealtimeNanos()
                    )
                )
            }
            VoiceLatencyTelemetry.record(
                this,
                recordingVoiceTraceId,
                VoiceTraceEvents.SPEECH_STARTED,
                once = true
            )
            Log.i("SignalASIVoice", "Voice command speech detected amplitude=$amplitude elapsed=${elapsed}ms")
            updateWakeVoiceUi(getString(R.string.voice_status_recording), getString(R.string.voice_status_recording_detail))
        }
        voiceCommandSpeechDetected = true
        voiceCommandLastVoiceAt = now
    }
    val silenceMs = if (voiceCommandLastVoiceAt > 0L) now - voiceCommandLastVoiceAt else elapsed
    when {
        !voiceCommandSpeechDetected && elapsed >= 3000L -> {
            Log.i("SignalASIVoice", "Voice command no speech timeout elapsed=${elapsed}ms amplitude=$amplitude")
            stopVoiceCommandRecording(send = true, reason = "no_speech_timeout")
        }
        voiceCommandSpeechDetected && silenceMs >= 3000L -> {
            Log.i("SignalASIVoice", "Voice command silence timeout silence=${silenceMs}ms elapsed=${elapsed}ms")
            stopVoiceCommandRecording(send = true, reason = "silence_timeout")
        }
        elapsed >= 30_000L -> {
            Log.i("SignalASIVoice", "Voice command max duration timeout elapsed=${elapsed}ms")
            stopVoiceCommandRecording(send = true, reason = "max_duration")
        }
        else -> {
            handler.postDelayed({ monitorVoiceCommandRecording() }, 250L)
        }
    }
}

internal fun MainActivity.stopVoiceCommandRecording(send: Boolean, reason: String = "manual") {
    if (pcmVoiceSession != null && recordingPurpose == "voice_wakeup") {
        voiceAssistantRecordingCommand = false
        stopPcmRecording(send, reason)
        return
    }
    val activeRecorder = recorder
    val traceId = recordingVoiceTraceId
    val coordinatorSessionId = recordingVoiceCoordinatorSessionId.ifBlank {
        voiceCoordinatorSession(traceId)
    }
    recorder = null
    recordingVoiceTraceId = ""
    recordingVoiceCoordinatorSessionId = ""
    voiceAssistantRecordingCommand = false
    Log.i("SignalASIVoice", "Voice command recording stopping send=$send reason=$reason speechDetected=$voiceCommandSpeechDetected")
    runCatching { activeRecorder?.stop() }
    activeRecorder?.release()
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.SPEECH_ENDED,
        mapOf("endpoint_reason" to reason),
        once = true
    )
    if (coordinatorSessionId.isNotBlank()) {
        dispatchVoiceCoordinator(
            VoiceInteractionEvent.SpeechEnded(
                coordinatorSessionId,
                SystemClock.elapsedRealtimeNanos()
            )
        )
    }
    val file = recordingFile
    recordingFile = null
    if (!send || file == null || !file.exists()) {
        file?.delete()
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
        if (activeMainTab == PAGE_VOICE) startWakeListening()
        return
    }
    val config = VoiceAssistantSettings.get(this)
    val contact = voiceAssistantTargetContact(config)
    val seconds = ((System.currentTimeMillis() - recordingStartedAt) / 1000).coerceAtLeast(1)
    if (!voiceCommandSpeechDetected && seconds <= 3) {
        Log.i("SignalASIVoice", "Voice command discarded: no speech detected bytes=${file.length()}")
        file.delete()
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
        updateWakeVoiceUi(getString(R.string.voice_status_no_speech), getString(R.string.voice_status_waiting_wake))
        if (activeMainTab == PAGE_VOICE) startWakeListening()
        return
    }
    selectedContact = contact
    if (coordinatorSessionId.isNotBlank()) {
        dispatchVoiceCoordinator(VoiceInteractionEvent.FinalizationStarted(coordinatorSessionId))
    }
    val nativeAgentRoute = config.routingMode == VoiceAssistantSettings.ROUTING_MODE_NATIVE_AGENT
    val sent = if (nativeAgentRoute) {
        requestVoiceAgentTranscription(file, contact, traceId)
    } else {
        sendVoiceRecordingThroughPipeline(
            sourceFile = file,
            contact = contact,
            seconds = seconds,
            label = getString(R.string.voice_command_label, seconds),
            source = "voice_wakeup",
            traceId = traceId
        )
    }
    Log.i("SignalASIVoice", "Voice command recording stopped duration=${seconds}s sent=$sent target=${contact.id}")
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
            if (activeMainTab == PAGE_VOICE && wakePage.visibility == View.VISIBLE && !voiceAssistantSpeaking && !voiceAssistantRecordingCommand) {
                startWakeListening()
            }
        }, 800L)
    }
}

internal fun MainActivity.startVoiceRecognition() {
    if (activeMainTab != PAGE_VOICE || wakePage.visibility != View.VISIBLE || voiceAssistantSpeaking) return
    if (!ensureRecordPermission()) return
    if (voiceAssistantListening) {
        Log.i("SignalASIVoice", "ASR start ignored: already listening")
        return
    }
    val now = System.currentTimeMillis()
    if (now - lastVoiceRecognitionStartAt < 900L) {
        scheduleVoiceRestart(950L - (now - lastVoiceRecognitionStartAt))
        return
    }
    val config = VoiceAssistantSettings.get(this)
    ensureSpeechRecognizer()
    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, LanguagePolicySettings.resolve(config.asrLanguage))
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 1200L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 800L)
        putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 800L)
    }
    runCatching {
        lastVoiceRecognitionStartAt = System.currentTimeMillis()
        speechRecognizer?.startListening(intent)
        voiceAssistantListening = true
        Log.i(
            "SignalASIVoice",
            "ASR start language=${LanguagePolicySettings.resolve(config.asrLanguage)} awake=$voiceAssistantAwake"
        )
    }.onFailure {
        voiceAssistantListening = false
        VoiceRuntimeHealthRegistry.failure(
            VoiceRuntimeChannel.ANDROID_SYSTEM_ASR,
            it.message ?: it.javaClass.simpleName
        )
        if (config.wakeProvider == VoiceAssistantSettings.WAKE_PROVIDER_ANDROID_ASR) {
            VoiceRuntimeHealthRegistry.failure(
                VoiceRuntimeChannel.ANDROID_WAKE_ASR,
                it.message ?: it.javaClass.simpleName
            )
        }
        Log.e("SignalASIVoice", "ASR start failed", it)
        updateWakeVoiceUi(getString(R.string.voice_status_asr_start_failed), it.message ?: getString(R.string.voice_status_retry_later))
        scheduleVoiceRestart(1200L)
    }
}

internal fun MainActivity.handleVoiceRecognitionText(text: String) {
    if (text.isBlank()) {
        scheduleVoiceRestart(500L)
        return
    }
    if (!voiceAssistantAwake) {
        if (containsWakeWord(text)) {
            onVoiceWakeDetected(text)
        } else {
            updateWakeVoiceUi(getString(R.string.voice_status_low_power), text)
            scheduleVoiceRestart(600L)
        }
        return
    }
    onVoiceCommand(text)
}

internal fun MainActivity.onVoiceWakeDetected(text: String) {
    VoiceRuntimeHealthRegistry.success(
        wakeRuntimeChannel(VoiceAssistantSettings.get(this))
    )
    voiceAssistantAwake = true
    updateWakeVoiceUi(getString(R.string.voice_status_awake), text)
    speakWakeWelcomeThenListen(VoiceAssistantSettings.get(this).welcomeText)
}

internal fun MainActivity.speakWakeWelcomeThenListen(text: String) {
    var progressed = false
    fun continueToCommand() {
        if (progressed) return
        progressed = true
        microsoftTts.stop()
        androidTts?.stop()
        voiceAssistantSpeaking = false
        startCommandListening()
    }
    handler.postDelayed({
        if (voiceAssistantAwake && activeMainTab == PAGE_VOICE) {
            Log.i("SignalASIVoice", "Wake welcome timeout, continue to command recording")
            continueToCommand()
        }
    }, 4500L)
    speakWithConfiguredTts(text, timeoutMs = 4500L, fallbackToAndroid = false) {
        Log.i("SignalASIVoice", "Wake welcome finished, continue to command recording")
        continueToCommand()
    }
}

internal fun MainActivity.onVoiceCommand(text: String) {
    val config = VoiceAssistantSettings.get(this)
    if (config.routingMode == VoiceAssistantSettings.ROUTING_MODE_NATIVE_AGENT) {
        submitVoiceAgentGoal(text)
        return
    }
    val contact = voiceAssistantTargetContact(config)
    updateWakeVoiceUi(getString(R.string.voice_status_sent_to, contact.name), text)
    sendOutgoingText(contact, text, activeVoiceTraceId)
    scheduleVoiceRestart(1200L)
}

internal fun MainActivity.submitVoiceAgentGoal(text: String, traceId: String = activeVoiceTraceId) {
    val goal = text.trim()
    if (goal.isBlank()) {
        scheduleVoiceRestart(500L)
        return
    }
    val conversation = agentTranscriptStore.activeConversation()
    activeVoiceTraceId = traceId
    VoiceLatencyTelemetry.record(
        this,
        traceId,
        VoiceTraceEvents.ROUTE_STARTED,
        once = true
    )
    val conversationContext = agentTranscriptStore.preparedContext(conversation.id)
    val clarification = AgentClarificationPolicy.decide(
        goal,
        hasConversationContext = conversation.summary.isNotBlank() ||
            conversationContext?.summary?.isNotBlank() == true ||
            conversationContext?.turns?.isNotEmpty() == true,
        preferenceMode = mobileNativeAgent.preferenceMode()
    )
    if (clarification.mode == AgentClarificationMode.ASK_LOCALLY) {
        val question = agentClarificationQuestion(clarification.question)
        wakeReplyPinnedUntilMs = System.currentTimeMillis() + 60_000L
        updateWakeVoiceUi(getString(R.string.voice_agent_waiting), question)
        val config = VoiceAssistantSettings.get(this)
        if (config.speakReplies) {
            speakWithConfiguredTts(question, traceId = traceId) {
                if (voiceAssistantAwake && activeMainTab == PAGE_VOICE) {
                    startCommandListening()
                }
            }
        } else {
            completeVoiceTrace(traceId)
            scheduleVoiceRestart(900L)
        }
        return
    }
    if (agentOperationInFlight) {
        updateWakeVoiceUi(getString(R.string.voice_agent_busy), goal)
        scheduleVoiceRestart(1000L)
        return
    }
    updateWakeVoiceUi(getString(R.string.voice_agent_planning), goal)
    runAgentOperationAsync(
        operation = {
            VoiceLatencyTraceContext.withTrace(traceId) {
                mobileNativeAgent.submitGoal(goal)
            }
        },
        onComplete = { state ->
            val coordinatorRouteKind = if (state.phase == AgentPhase.WAITING_RESPONSE) {
                VoiceRouteKind.REMOTE_AGENT
            } else {
                VoiceRouteKind.LOCAL_ACTION
            }
            selectVoiceCoordinatorRoute(
                traceId,
                coordinatorRouteKind,
                state.plan?.selectedAgentOrModel.orEmpty()
            )
            val coordinatorSessionId = voiceCoordinatorSession(traceId)
            if (coordinatorSessionId.isNotBlank()) {
                when (state.phase) {
                    AgentPhase.WAITING_RESPONSE -> state.lastActionResult
                        ?.metadata
                        ?.get("voice_agent_run_id")
                        .orEmpty()
                        .takeIf(String::isNotBlank)
                        ?.let { runId ->
                            dispatchVoiceCoordinator(
                                VoiceInteractionEvent.AgentRunCreated(
                                    coordinatorSessionId,
                                    runId
                                )
                            )
                        }
                    AgentPhase.COMPLETED -> dispatchVoiceCoordinator(
                        VoiceInteractionEvent.LocalActionCompleted(coordinatorSessionId)
                    )
                    AgentPhase.BLOCKED,
                    AgentPhase.FAILED -> failVoiceCoordinator(traceId, "mobile_agent_${state.phase.name.lowercase()}")
                    else -> Unit
                }
            }
            VoiceLatencyTelemetry.record(
                this,
                traceId,
                VoiceTraceEvents.ROUTE_SELECTED,
                mapOf(
                    "agent_provider" to state.plan?.selectedAgentOrModel.orEmpty()
                        .substringAfterLast(':')
                        .ifBlank { "signalasi_mobile" }
                ),
                once = true
            )
            presentVoiceAgentState(state, traceId)
        }
    )
}
