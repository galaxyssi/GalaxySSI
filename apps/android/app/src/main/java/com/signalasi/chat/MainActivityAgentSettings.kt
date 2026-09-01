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

internal fun MainActivity.showOnDeviceAgentFeaturePage() {
    showFeaturePage(getString(R.string.on_device_agent_title))
    val safetySettings = mobileNativeAgent.safetySettings()
    val modelPlannerSettings = mobileNativeAgent.modelPlannerSettings()
    featureContent.addView(featureHeroCard(
        getString(R.string.on_device_agent_hero_title),
        getString(R.string.on_device_agent_hero_subtitle),
        R.drawable.ic_agent_node,
        "#5B6CFF",
        getString(
            if (safetySettings.executionPaused) R.string.on_device_agent_status_paused
            else R.string.on_device_agent_status_running
        )
    ))
    addSectionTitle(getString(R.string.on_device_agent_section_execution))
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_memory_capture),
        getString(R.string.on_device_agent_memory_capture_subtitle),
        R.drawable.ic_agent_node,
        safetySettings.memoryCapture
    ).apply {
        setOnClickListener { toggleAgentMemoryCapture() }
    })
    val memorySnapshot = mobileNativeAgent.memorySnapshot()
    featureContent.addView(featureValueRow(
        getString(R.string.agent_memory_title),
        getString(R.string.agent_memory_management_subtitle),
        R.drawable.ic_agent_node,
        getString(R.string.agent_memory_value, memorySnapshot.activeCount, memorySnapshot.conflicts.size)
    ).apply {
        setOnClickListener {
            showAgentMemoryPage()
            setFeatureBackAction { showOnDeviceAgentFeaturePage() }
        }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_execution_pause),
        getString(R.string.on_device_agent_execution_pause_subtitle),
        R.drawable.ic_security_shield,
        safetySettings.executionPaused
    ).apply {
        setOnClickListener { toggleAgentExecutionPaused() }
    })
    addSectionTitle(getString(R.string.on_device_agent_section_intelligence))
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_model_planner),
        getString(R.string.on_device_agent_model_planner_subtitle),
        R.drawable.ic_agent_node,
        modelPlannerSettings.enabled
    ).apply {
        setOnClickListener { toggleAgentModelPlanner() }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_model_screen_text),
        getString(R.string.on_device_agent_model_screen_text_subtitle),
        R.drawable.ic_scan,
        modelPlannerSettings.shareScreenText
    ).apply {
        setOnClickListener { toggleAgentModelScreenText() }
    })
    featureContent.addView(featureValueRow(
        getString(R.string.on_device_agent_model_source),
        getString(R.string.on_device_agent_model_source_subtitle),
        R.drawable.ic_protocol_link,
        agentModelPlannerSourceLabel(modelPlannerSettings.cloudContactId)
    ).apply {
        setOnClickListener { showAgentModelPlannerSourceDialog() }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_dynamic_replanning),
        getString(R.string.on_device_agent_dynamic_replanning_subtitle),
        R.drawable.ic_agent_node,
        modelPlannerSettings.dynamicReplanning
    ).apply {
        setOnClickListener { toggleAgentDynamicReplanning() }
    })
    featureContent.addView(featureValueRow(
        getString(R.string.on_device_agent_max_replans),
        getString(R.string.on_device_agent_max_replans_subtitle),
        R.drawable.ic_agent_node,
        modelPlannerSettings.maxReplans.toString()
    ).apply {
        setOnClickListener { cycleAgentModelMaxReplans() }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_multi_agent_coordination),
        getString(R.string.on_device_agent_multi_agent_coordination_subtitle),
        R.drawable.ic_protocol_link,
        modelPlannerSettings.multiAgentCoordination
    ).apply {
        setOnClickListener { toggleMultiAgentCoordination() }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_share_agent_outputs),
        getString(R.string.on_device_agent_share_agent_outputs_subtitle),
        R.drawable.ic_security_shield,
        modelPlannerSettings.shareAgentOutputsWithPlanner
    ).apply {
        setOnClickListener { toggleShareAgentOutputsWithPlanner() }
    })
    featureContent.addView(featureValueRow(
        getString(R.string.on_device_agent_max_agent_hops),
        getString(R.string.on_device_agent_max_agent_hops_subtitle),
        R.drawable.ic_protocol_link,
        modelPlannerSettings.maxAgentHops.toString()
    ).apply {
        setOnClickListener { cycleMaxAgentHops() }
    })
    featureContent.addView(featureValueRow(
        getString(R.string.on_device_agent_max_tool_calls),
        getString(R.string.on_device_agent_max_tool_calls_subtitle),
        R.drawable.ic_security_shield,
        modelPlannerSettings.maxToolCalls.toString()
    ).apply {
        setOnClickListener { cycleMaxToolCalls() }
    })
    featureContent.addView(featureValueRow(
        getString(R.string.on_device_agent_model_max_actions),
        getString(R.string.on_device_agent_model_max_actions_subtitle),
        R.drawable.ic_agent_node,
        modelPlannerSettings.maxActions.toString()
    ).apply {
        setOnClickListener { cycleAgentModelMaxActions() }
    })
    addSectionTitle(getString(R.string.on_device_agent_section_capabilities))
    val visualScene = mobileNativeAgent.snapshot().currentScreen.visualScene
    featureContent.addView(featureValueRow(
        getString(R.string.on_device_agent_visual_model),
        getString(R.string.on_device_agent_visual_model_subtitle),
        R.drawable.ic_scan,
        if (visualScene.available) visualScene.modelProfile else getString(R.string.permission_needs_setup)
    ).apply {
        setOnClickListener { startAgentScreenUnderstanding() }
    })
    featureContent.addView(featureValueRow(
        getString(R.string.agent_app_adapters_title),
        getString(R.string.agent_app_adapters_subtitle),
        R.drawable.ic_protocol_link,
        getString(R.string.agent_app_adapters_count, agentAdapterReadiness().count { it.value })
    ).apply {
        setOnClickListener {
            showAgentAppAdaptersPage()
            setFeatureBackAction { showOnDeviceAgentFeaturePage() }
        }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_allow_screen_observation),
        getString(R.string.on_device_agent_allow_screen_observation_subtitle),
        R.drawable.ic_scan,
        safetySettings.screenObservationAllowed
    ).apply {
        setOnClickListener { toggleAgentScreenObservation() }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_allow_local_actions),
        getString(R.string.on_device_agent_allow_local_actions_subtitle),
        R.drawable.ic_agent_node,
        safetySettings.localActionsAllowed
    ).apply {
        setOnClickListener { toggleAgentLocalActions() }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_allow_connectors),
        getString(R.string.on_device_agent_allow_connectors_subtitle),
        R.drawable.ic_protocol_link,
        safetySettings.connectorCallsAllowed
    ).apply {
        setOnClickListener { toggleAgentConnectorCalls() }
    })
    featureContent.addView(featureSwitchRow(
        getString(R.string.on_device_agent_allow_devices),
        getString(R.string.on_device_agent_allow_devices_subtitle),
        R.drawable.ic_device_node,
        safetySettings.deviceControlAllowed
    ).apply {
        setOnClickListener { toggleAgentDeviceControl() }
    })
    addSectionTitle(getString(R.string.on_device_agent_section_permissions))
    val screenAccessAllowed = SignalASIAccessibilityService.isActive()
    val notificationAccessAllowed = SignalASINotificationListenerService.currentContext().hasAccess
    val microphoneAllowed = checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    val cameraAllowed = checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    val locationAllowed = checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    featureContent.addView(featureRow(
        getString(R.string.on_device_agent_screen_access),
        getString(R.string.on_device_agent_screen_access_subtitle),
        R.drawable.ic_agent_node,
        if (screenAccessAllowed) getString(R.string.permission_allowed) else getString(R.string.permission_needs_setup)
    ).apply {
        setOnClickListener { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
    })
    featureContent.addView(featureRow(
        getString(R.string.on_device_agent_visual_capture),
        getString(R.string.on_device_agent_visual_capture_subtitle),
        R.drawable.ic_scan,
        if (AgentScreenCaptureService.isActive()) getString(R.string.permission_allowed)
        else getString(R.string.permission_needs_setup)
    ).apply {
        setOnClickListener {
            if (AgentScreenCaptureService.isActive()) {
                AgentScreenCaptureService.stop(this@showOnDeviceAgentFeaturePage)
                showOnDeviceAgentFeaturePage()
            } else {
                startAgentScreenUnderstanding()
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.on_device_agent_microphone),
        getString(R.string.on_device_agent_microphone_subtitle),
        R.drawable.ic_agent_node,
        getString(if (microphoneAllowed) R.string.permission_allowed else R.string.permission_needs_setup)
    ).apply {
        if (!microphoneAllowed) setOnClickListener {
            requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQUEST_CONTROL_CENTER_PERMISSION)
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.on_device_agent_camera),
        getString(R.string.on_device_agent_camera_subtitle),
        R.drawable.ic_scan,
        getString(if (cameraAllowed) R.string.permission_allowed else R.string.permission_needs_setup)
    ).apply {
        if (!cameraAllowed) setOnClickListener {
            requestPermissions(arrayOf(android.Manifest.permission.CAMERA), REQUEST_CONTROL_CENTER_PERMISSION)
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.on_device_agent_location),
        getString(R.string.on_device_agent_location_subtitle),
        R.drawable.ic_device_node,
        getString(if (locationAllowed) R.string.permission_while_using else R.string.permission_needs_setup)
    ).apply {
        if (!locationAllowed) setOnClickListener {
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION
                ),
                REQUEST_CONTROL_CENTER_PERMISSION
            )
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.on_device_agent_notifications),
        getString(R.string.on_device_agent_notifications_subtitle),
        R.drawable.ic_agent_node,
        if (notificationAccessAllowed) getString(R.string.permission_allowed) else getString(R.string.permission_needs_setup)
    ).apply {
        setOnClickListener { startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")) }
    })
}

internal fun MainActivity.showAgentMemoryPage(filterKinds: Set<AgentMemoryKind> = emptySet()) {
    showFeaturePage(getString(R.string.agent_memory_title))
    val sourceSnapshot = mobileNativeAgent.memorySnapshot()
    val snapshot = if (filterKinds.isEmpty()) {
        sourceSnapshot
    } else {
        AgentMemorySnapshot(
            activeItems = sourceSnapshot.activeItems.filter { it.kind in filterKinds },
            conflicts = sourceSnapshot.conflicts.filter { it.kind in filterKinds },
            historyItems = sourceSnapshot.historyItems.filter { it.kind in filterKinds }
        )
    }
    featureContent.addView(featureHeroCard(
        getString(R.string.agent_memory_hero_title),
        getString(
            R.string.agent_memory_hero_subtitle,
            snapshot.activeCount,
            snapshot.conflicts.size,
            snapshot.historyCount
        ),
        R.drawable.ic_agent_node,
        "#5B6CFF",
        getString(
            if (mobileNativeAgent.safetySettings().memoryCapture) R.string.common_on
            else R.string.common_off
        )
    ))

    addSectionTitle(getString(R.string.agent_memory_section_conflicts))
    if (snapshot.conflicts.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.agent_memory_no_conflicts),
            getString(R.string.agent_memory_no_conflicts_subtitle),
            R.drawable.ic_security_shield,
            ""
        ))
    } else {
        snapshot.conflicts.forEach { conflict ->
            featureContent.addView(featureRow(
                conflict.key.ifBlank { memoryKindLabel(conflict.kind) },
                getString(
                    R.string.agent_memory_conflict_subtitle,
                    memoryKindLabel(conflict.kind),
                    conflict.candidates.size
                ),
                R.drawable.ic_security_shield,
                getString(R.string.agent_memory_review)
            ).apply {
                setOnClickListener { showAgentMemoryConflictDialog(conflict, filterKinds) }
            })
        }
    }

    addSectionTitle(getString(R.string.agent_memory_section_saved))
    if (snapshot.activeItems.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.agent_memory_empty),
            getString(R.string.agent_memory_empty_subtitle),
            R.drawable.ic_agent_node,
            ""
        ))
    } else {
        val trustStore = AgentMemoryTrustStore(this)
        snapshot.activeItems.forEach { item ->
            val key = item.key.ifBlank { getString(R.string.agent_memory_key_none) }
            val profile = trustStore.profile(item)
            val action = getString(when {
                item.privateMemory -> R.string.agent_memory_private
                item.important -> R.string.agent_memory_pinned
                else -> R.string.common_edit
            })
            featureContent.addView(featureRow(
                item.value.replace(Regex("\\s+"), " ").take(80),
                getString(
                    R.string.agent_memory_trust_item_subtitle,
                    memoryKindLabel(item.kind),
                    item.version,
                    memorySourceLabel(item.source),
                    (item.confidence.coerceIn(0.0, 1.0) * 100).toInt(),
                    item.evidenceCount,
                    profile.usages.size,
                    key
                ),
                R.drawable.ic_agent_node,
                action
            ).apply {
                setOnClickListener { showAgentMemoryItemActions(item, filterKinds) }
            })
        }
    }

    if (snapshot.historyItems.isNotEmpty()) {
        addSectionTitle(getString(R.string.agent_memory_section_history))
        snapshot.historyItems.take(20).forEach { item ->
            featureContent.addView(featureRow(
                item.value.replace(Regex("\\s+"), " ").take(80),
                getString(
                    R.string.agent_memory_history_subtitle,
                    memoryKindLabel(item.kind),
                    item.version,
                    memorySourceLabel(item.source)
                ),
                R.drawable.ic_protocol_link,
                ""
            ).apply {
                setOnClickListener { showAgentMemoryItemActions(item, filterKinds) }
            })
        }
    }
}

internal fun MainActivity.showAgentAppAdaptersPage() {
    showFeaturePage(getString(R.string.agent_app_adapters_title))
    val readiness = agentAdapterReadiness()
    val accessibilityReady = SignalASIAccessibilityService.isActive()
    val notificationReady = SignalASINotificationListenerService.currentContext().hasAccess
    featureContent.addView(featureHeroCard(
        getString(R.string.agent_app_adapters_hero_title),
        getString(R.string.agent_app_adapters_hero_subtitle),
        R.drawable.ic_protocol_link,
        "#16A085",
        getString(R.string.agent_app_adapters_count, readiness.count { it.value })
    ))
    addSectionTitle(getString(R.string.agent_app_adapters_section))
    featureContent.addView(featureRow(
        getString(R.string.agent_adapter_wechat),
        getString(
            R.string.agent_adapter_wechat_subtitle,
            onOffLabel(accessibilityReady),
            onOffLabel(notificationReady)
        ),
        R.drawable.ic_tab_chat,
        getString(
            if (readiness.getValue("wechat")) R.string.permission_allowed
            else R.string.permission_needs_setup
        )
    ))
    featureContent.addView(featureRow(
        getString(R.string.agent_adapter_sms),
        getString(R.string.agent_adapter_sms_subtitle),
        R.drawable.ic_tab_chat,
        getString(if (readiness.getValue("sms")) R.string.permission_allowed else R.string.permission_needs_setup)
    ))
    featureContent.addView(featureRow(
        getString(R.string.agent_adapter_phone),
        getString(R.string.agent_adapter_phone_subtitle),
        R.drawable.ic_device_node,
        getString(if (readiness.getValue("phone")) R.string.permission_allowed else R.string.permission_needs_setup)
    ))
    featureContent.addView(featureRow(
        getString(R.string.agent_adapter_browser),
        getString(R.string.agent_adapter_browser_subtitle),
        R.drawable.ic_tab_discover,
        getString(if (readiness.getValue("browser")) R.string.permission_allowed else R.string.permission_needs_setup)
    ))
    featureContent.addView(featureRow(
        getString(R.string.agent_adapter_files),
        getString(R.string.agent_adapter_files_subtitle),
        R.drawable.ic_protocol_link,
        getString(if (readiness.getValue("files")) R.string.permission_allowed else R.string.permission_needs_setup)
    ))
}

internal fun MainActivity.agentAdapterReadiness(): LinkedHashMap<String, Boolean> {
    val accessibilityReady = SignalASIAccessibilityService.isActive()
    val notificationReady = SignalASINotificationListenerService.currentContext().hasAccess
    val wechatInstalled = packageManager.getLaunchIntentForPackage("com.tencent.mm") != null
    val smsReady = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:"))
        .resolveActivity(packageManager) != null
    val phoneReady = packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY) &&
        Intent(Intent.ACTION_DIAL, Uri.parse("tel:"))
            .resolveActivity(packageManager) != null
    val browserReady = Intent(Intent.ACTION_VIEW, Uri.parse("https://signalasi.org"))
        .resolveActivity(packageManager) != null
    val filesReady = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        type = "*/*"
        addCategory(Intent.CATEGORY_OPENABLE)
    }.resolveActivity(packageManager) != null
    return linkedMapOf(
        "wechat" to (wechatInstalled && accessibilityReady && notificationReady),
        "sms" to smsReady,
        "phone" to phoneReady,
        "browser" to browserReady,
        "files" to filesReady
    )
}

internal fun MainActivity.showAgentKnowledgePage(query: String = "") {
    showFeaturePage(getString(R.string.agent_knowledge_title))
    val stats = mobileNativeAgent.snapshot().runtimeContext.knowledgeStats
    val sourceGroups = mobileNativeAgent.knowledgeSourceGroups()
    featureContent.addView(featureHeroCard(
        getString(R.string.agent_knowledge_hero_title),
        getString(R.string.agent_knowledge_hero_subtitle),
        R.drawable.ic_protocol_link,
        "#08A88A",
        getString(R.string.agent_knowledge_source_badge, stats.sourceCount)
    ))

    addSectionTitle(getString(R.string.agent_knowledge_section_actions))
    featureContent.addView(featureRow(
        getString(R.string.agent_knowledge_import),
        getString(R.string.agent_knowledge_import_subtitle),
        R.drawable.ic_protocol_link,
        getString(R.string.agent_knowledge_add)
    ).apply { setOnClickListener { openAgentKnowledgeImportPicker() } })
    featureContent.addView(featureRow(
        getString(R.string.agent_knowledge_search),
        if (query.isBlank()) getString(R.string.agent_knowledge_search_subtitle) else query,
        R.drawable.ic_tab_discover,
        getString(R.string.agent_knowledge_search_action)
    ).apply {
        setOnClickListener {
            showTextSettingDialog(getString(R.string.agent_knowledge_search), query) { value ->
                showAgentKnowledgePage(value)
            }
        }
    })

    if (query.isNotBlank()) {
        val hits = mobileNativeAgent.searchKnowledge(query)
        addSectionTitle(getString(R.string.agent_knowledge_section_results, hits.size))
        if (hits.isEmpty()) {
            featureContent.addView(featureValueRow(
                getString(R.string.agent_knowledge_no_results),
                query,
                R.drawable.ic_tab_discover,
                ""
            ))
        } else {
            hits.forEachIndexed { index, hit ->
                featureContent.addView(featureValueRow(
                    "[${index + 1}] ${hit.item.title.substringBeforeLast(" [")}",
                    hit.excerpt,
                    R.drawable.ic_protocol_link,
                    getString(R.string.agent_knowledge_score, hit.score)
                ))
            }
        }
    }

    addSectionTitle(getString(R.string.agent_knowledge_section_sources, sourceGroups.size))
    if (sourceGroups.isEmpty()) {
        featureContent.addView(featureValueRow(
            getString(R.string.agent_knowledge_empty_title),
            getString(R.string.agent_knowledge_empty_subtitle),
            R.drawable.ic_protocol_link,
            ""
        ))
    } else {
        sourceGroups.forEach { group ->
            featureContent.addView(featureValueRow(
                group.title,
                getString(
                    R.string.agent_knowledge_source_subtitle,
                    group.chunkCount,
                    knowledgeCloudAccessLabel(group.cloudAccess),
                    knowledgeAgentAccessLabel(group.agentAccess)
                ),
                R.drawable.ic_protocol_link,
                getString(R.string.agent_knowledge_manage)
            ).apply { setOnClickListener { showAgentKnowledgeSourceActions(group) } })
        }
    }

    val audit = mobileNativeAgent.knowledgeAccessAudit(limit = 8)
    if (audit.isNotEmpty()) {
        addSectionTitle(getString(R.string.agent_knowledge_section_audit))
        audit.forEach { entry ->
            val time = SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(entry.timestampMillis))
            featureContent.addView(featureValueRow(
                entry.targetId,
                getString(
                    R.string.agent_knowledge_audit_subtitle,
                    entry.sourceCount,
                    entry.evidenceModes.joinToString(" / ") { knowledgeEvidenceModeLabel(it) },
                    entry.blockedMatchCount
                ),
                R.drawable.ic_security_shield,
                time
            ))
        }
    }
}

internal fun MainActivity.showAgentKnowledgeSourceActions(group: AgentKnowledgeSourceGroup) {
    val options = arrayOf(
        getString(R.string.agent_knowledge_cloud_access),
        getString(R.string.agent_knowledge_agent_access)
    )
    android.app.AlertDialog.Builder(this)
        .setTitle(group.title)
        .setItems(options) { _, which ->
            if (which == 0) showAgentKnowledgeCloudAccessDialog(group)
            else showAgentKnowledgeAgentAccessDialog(group)
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.showAgentKnowledgeCloudAccessDialog(group: AgentKnowledgeSourceGroup) {
    val policies = AgentKnowledgeCloudAccess.entries
    val labels = policies.map(::knowledgeCloudAccessLabel)
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_knowledge_cloud_access))
        .setSingleChoiceItems(labels.toTypedArray(), policies.indexOf(group.cloudAccess)) { dialog, which ->
            mobileNativeAgent.updateKnowledgeSourceAccess(
                group.itemIds,
                policies[which],
                group.agentAccess,
                group.allowedAgentIds
            )
            dialog.dismiss()
            showAgentKnowledgePage()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.showAgentKnowledgeAgentAccessDialog(group: AgentKnowledgeSourceGroup) {
    val policies = AgentKnowledgeAgentAccess.entries
    val labels = policies.map(::knowledgeAgentAccessLabel)
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_knowledge_agent_access))
        .setSingleChoiceItems(labels.toTypedArray(), policies.indexOf(group.agentAccess)) { dialog, which ->
            dialog.dismiss()
            val selected = policies[which]
            if (selected == AgentKnowledgeAgentAccess.SELECTED_AGENTS) {
                showTextSettingDialog(
                    getString(R.string.agent_knowledge_selected_agents),
                    group.allowedAgentIds.joinToString(", ")
                ) { rawIds ->
                    mobileNativeAgent.updateKnowledgeSourceAccess(
                        group.itemIds,
                        group.cloudAccess,
                        selected,
                        rawIds.split(',').map { it.trim() }.filter { it.isNotBlank() }
                    )
                    showAgentKnowledgePage()
                }
            } else {
                mobileNativeAgent.updateKnowledgeSourceAccess(
                    group.itemIds,
                    group.cloudAccess,
                    selected
                )
                showAgentKnowledgePage()
            }
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.knowledgeCloudAccessLabel(value: AgentKnowledgeCloudAccess): String = getString(
    when (value) {
        AgentKnowledgeCloudAccess.DENY -> R.string.agent_knowledge_access_local_only
        AgentKnowledgeCloudAccess.SUMMARY_ONLY -> R.string.agent_knowledge_access_summary
        AgentKnowledgeCloudAccess.FULL -> R.string.agent_knowledge_access_full
    }
)

internal fun MainActivity.knowledgeAgentAccessLabel(value: AgentKnowledgeAgentAccess): String = getString(
    when (value) {
        AgentKnowledgeAgentAccess.LOCAL_ONLY -> R.string.agent_knowledge_agent_local_only
        AgentKnowledgeAgentAccess.SELECTED_AGENTS -> R.string.agent_knowledge_agent_selected
        AgentKnowledgeAgentAccess.ANY_PAIRED_AGENT -> R.string.agent_knowledge_agent_any
    }
)

internal fun MainActivity.knowledgeEvidenceModeLabel(value: AgentKnowledgeEvidenceMode): String = getString(
    when (value) {
        AgentKnowledgeEvidenceMode.FULL -> R.string.agent_knowledge_access_full
        AgentKnowledgeEvidenceMode.SUMMARY -> R.string.agent_knowledge_access_summary
    }
)

internal fun MainActivity.showAgentMemoryConflictDialog(
    conflict: AgentMemoryConflict,
    filterKinds: Set<AgentMemoryKind> = emptySet()
) {
    val candidates = conflict.candidates.sortedBy { it.version }
    val options = candidates.map { item ->
        getString(
            R.string.agent_memory_use_candidate_trust,
            item.version,
            item.value.replace(Regex("\\s+"), " ").take(90),
            memorySourceLabel(item.source),
            (item.confidence.coerceIn(0.0, 1.0) * 100).toInt(),
            item.evidenceCount
        )
    } + getString(R.string.agent_memory_merge_values)
    android.app.AlertDialog.Builder(this)
        .setTitle(conflict.key.ifBlank { getString(R.string.agent_memory_conflict_title) })
        .setItems(options.toTypedArray()) { _, which ->
            if (which < candidates.size) {
                resolveAgentMemoryConflict(conflict, candidates[which], null, filterKinds)
            } else {
                val initial = candidates.joinToString("\n") { it.value }
                showTextSettingDialog(getString(R.string.agent_memory_merge_title), initial) { merged ->
                    resolveAgentMemoryConflict(conflict, candidates.last(), merged, filterKinds)
                }
            }
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.resolveAgentMemoryConflict(
    conflict: AgentMemoryConflict,
    selected: AgentMemoryItem,
    mergedValue: String?,
    filterKinds: Set<AgentMemoryKind> = emptySet()
) {
    val resolved = mobileNativeAgent.resolveMemoryConflict(conflict.groupId, selected.id, mergedValue)
    Toast.makeText(
        this,
        getString(
            if (resolved != null) R.string.agent_memory_merge_saved
            else R.string.agent_memory_conflict_resolution_failed
        ),
        Toast.LENGTH_SHORT
    ).show()
    showAgentMemoryPage(filterKinds)
}

internal fun MainActivity.showAgentMemoryItemActions(
    item: AgentMemoryItem,
    filterKinds: Set<AgentMemoryKind> = emptySet()
) {
    val profile = AgentMemoryTrustStore(this).profile(item)
    val usageSummary = profile.usages.take(5).joinToString("\n") { usage ->
        val time = SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(usage.selectedAtMillis))
        val answer = usage.answerPreview.ifBlank { getString(R.string.agent_memory_trust_answer_pending) }
        "$time · ${answer.take(120)}"
    }.ifBlank { getString(R.string.agent_memory_trust_never_used) }
    val verifiedTime = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault())
        .format(Date(profile.lastVerifiedAtMillis))
    val detail = listOf(
        "${getString(R.string.agent_memory_trust_why)}: ${profile.whyRemembered}",
        "${getString(R.string.agent_memory_trust_source)}: ${memorySourceLabel(profile.source)}",
        "${getString(R.string.agent_memory_trust_state)}: ${profile.currentState}",
        "${getString(R.string.agent_memory_trust_confidence)}: ${(item.confidence.coerceIn(0.0, 1.0) * 100).toInt()}%",
        "${getString(R.string.agent_memory_trust_evidence)}: ${item.evidenceCount}",
        "${getString(R.string.agent_memory_trust_last_verified)}: $verifiedTime",
        "${getString(R.string.agent_memory_trust_origin_conversation)}: ${item.originConversationId.ifBlank { "-" }}",
        "${getString(R.string.agent_memory_trust_origin_event)}: ${item.originEventId.ifBlank { "-" }}",
        "${getString(R.string.agent_memory_trust_used_by)}:\n$usageSummary"
    ).joinToString("\n\n")
    val actions = buildList {
        if (item.status == AgentMemoryStatus.ACTIVE) add("edit" to getString(R.string.common_edit))
        if (item.status == AgentMemoryStatus.ACTIVE) {
            add("important" to getString(
                if (item.important) R.string.agent_memory_remove_important
                else R.string.agent_memory_mark_important
            ))
        }
        add("private" to getString(
            if (item.privateMemory) R.string.agent_memory_make_shareable
            else R.string.agent_memory_make_private
        ))
        if (item.status != AgentMemoryStatus.SUPERSEDED) {
            add("deprecate" to getString(R.string.agent_memory_deprecate))
        }
        add("delete" to getString(R.string.common_delete))
    }
    android.app.AlertDialog.Builder(this)
        .setTitle(item.value.replace(Regex("\\s+"), " ").take(100))
        .setMessage(detail)
        .setItems(actions.map { it.second }.toTypedArray()) { _, which ->
            when (actions[which].first) {
                "edit" -> showTextSettingDialog(
                    getString(R.string.agent_memory_edit_title),
                    item.value
                ) { value ->
                    val result = mobileNativeAgent.updateMemoryItem(item.id, value, item.key)
                    Toast.makeText(
                        this,
                        getString(
                            when {
                                result?.conflict != null -> R.string.agent_memory_conflict_created
                                result != null -> R.string.agent_memory_updated
                                else -> R.string.agent_memory_conflict_resolution_failed
                            }
                        ),
                        Toast.LENGTH_SHORT
                    ).show()
                    showAgentMemoryPage(filterKinds)
                }
                "important" -> {
                    mobileNativeAgent.setMemoryItemImportant(item.id, !item.important)
                    showAgentMemoryPage(filterKinds)
                }
                "private" -> {
                    mobileNativeAgent.setMemoryItemPrivate(item.id, !item.privateMemory)
                    showAgentMemoryPage(filterKinds)
                }
                "deprecate" -> {
                    mobileNativeAgent.deprecateMemoryItem(item.id)
                    showAgentMemoryPage(filterKinds)
                }
                "delete" -> confirmAgentMemoryDeletion(item, filterKinds)
            }
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.confirmAgentMemoryDeletion(
    item: AgentMemoryItem,
    filterKinds: Set<AgentMemoryKind> = emptySet()
) {
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.agent_memory_delete_title))
        .setMessage(getString(R.string.agent_memory_delete_message, item.value.take(120)))
        .setPositiveButton(getString(R.string.common_delete)) { _, _ ->
            if (mobileNativeAgent.deleteMemoryItem(item.id)) {
                Toast.makeText(this, getString(R.string.agent_memory_deleted), Toast.LENGTH_SHORT).show()
            }
            showAgentMemoryPage(filterKinds)
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.memoryKindLabel(kind: AgentMemoryKind): String = getString(
    when (kind) {
        AgentMemoryKind.IDENTITY -> R.string.agent_memory_kind_identity
        AgentMemoryKind.CONTACT -> R.string.agent_memory_kind_contact
        AgentMemoryKind.TASK -> R.string.agent_memory_kind_task
        AgentMemoryKind.PREFERENCE -> R.string.agent_memory_kind_preference
        AgentMemoryKind.WORKFLOW -> R.string.agent_memory_kind_workflow
        AgentMemoryKind.KNOWLEDGE -> R.string.agent_memory_kind_knowledge
        AgentMemoryKind.SAFETY -> R.string.agent_memory_kind_safety
    }
)

internal fun MainActivity.memorySourceLabel(source: String): String = getString(
    when {
        source == "agent_memory_command" -> R.string.agent_memory_source_explicit
        source == "memory_edit" -> R.string.agent_memory_source_edit
        source.startsWith("memory_conflict_") -> R.string.agent_memory_source_resolution
        else -> R.string.agent_memory_source_agent
    }
)

internal fun MainActivity.toggleAgentMemoryCapture() {
    val next = !mobileNativeAgent.safetySettings().memoryCapture
    mobileNativeAgent.updateMemoryCapture(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.toggleAgentExecutionPaused() {
    val next = !mobileNativeAgent.safetySettings().executionPaused
    mobileNativeAgent.updateExecutionPaused(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.toggleAgentModelPlanner() {
    val next = !mobileNativeAgent.modelPlannerSettings().enabled
    mobileNativeAgent.updateModelPlannerEnabled(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.toggleAgentModelScreenText() {
    val next = !mobileNativeAgent.modelPlannerSettings().shareScreenText
    mobileNativeAgent.updateModelPlannerScreenText(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.cycleAgentModelMaxActions() {
    val current = mobileNativeAgent.modelPlannerSettings().maxActions
    val next = when {
        current < 4 -> 4
        current < 8 -> 8
        current < 12 -> 12
        else -> 4
    }
    mobileNativeAgent.updateModelPlannerMaxActions(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.showAgentModelPlannerSourceDialog(
    onChanged: () -> Unit = { showOnDeviceAgentFeaturePage() }
) {
    val settings = mobileNativeAgent.modelPlannerSettings()
    val sources = configuredAgentPlannerSources()
    val ids = listOf("") + sources.map { it.first }
    val labels = listOf(getString(R.string.on_device_agent_model_source_automatic)) +
        sources.map { it.second }
    val selected = ids.indexOf(settings.cloudContactId).coerceAtLeast(0)
    android.app.AlertDialog.Builder(this)
        .setTitle(getString(R.string.on_device_agent_model_source))
        .setSingleChoiceItems(labels.toTypedArray(), selected) { dialog, which ->
            mobileNativeAgent.updateModelPlannerCloudContact(ids[which])
            dialog.dismiss()
            onChanged()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.agentModelPlannerSourceLabel(contactId: String): String =
    configuredAgentPlannerSources().firstOrNull { it.first == contactId }?.second
        ?: getString(R.string.on_device_agent_model_source_automatic)

internal fun MainActivity.configuredAgentPlannerSources(): List<Pair<String, String>> {
    val contacts = AppStore.contacts(this)
    return buildList {
        for (index in 0 until contacts.length()) {
            val contact = contacts.optJSONObject(index) ?: continue
            if (contact.optBoolean("deleted", false)) continue
            if (contact.optString("delivery_mode") != "cloud_api") continue
            if (contact.optString("setup_status").ifBlank { "ready" } != "ready") continue
            val id = contact.optString("id").ifBlank { contact.optString("signalasi_id") }
            val selected = AppStore.selectedCloudModelContact(this@configuredAgentPlannerSources, id) ?: contact
            if (id.isBlank() || !CloudModelCredentialPolicy.isAutoRoutable(selected)) continue
            val provider = selected.optString("cloud_provider")
                .ifBlank { selected.optString("display_name") }
                .ifBlank { selected.optString("name") }
                .ifBlank { id }
            val model = selected.optString("cloud_model")
            add(id to "$provider / $model")
        }
    }
}

internal fun MainActivity.toggleAgentDynamicReplanning() {
    val next = !mobileNativeAgent.modelPlannerSettings().dynamicReplanning
    mobileNativeAgent.updateModelPlannerDynamicReplanning(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.cycleAgentModelMaxReplans() {
    val current = mobileNativeAgent.modelPlannerSettings().maxReplans
    val next = when {
        current < 3 -> 3
        current < 5 -> 5
        else -> 1
    }
    mobileNativeAgent.updateModelPlannerMaxReplans(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.toggleMultiAgentCoordination() {
    val next = !mobileNativeAgent.modelPlannerSettings().multiAgentCoordination
    mobileNativeAgent.updateMultiAgentCoordination(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.toggleShareAgentOutputsWithPlanner() {
    val next = !mobileNativeAgent.modelPlannerSettings().shareAgentOutputsWithPlanner
    mobileNativeAgent.updateShareAgentOutputsWithPlanner(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.cycleMaxAgentHops() {
    val current = mobileNativeAgent.modelPlannerSettings().maxAgentHops
    val next = when {
        current < 4 -> 4
        current < 8 -> 8
        else -> 2
    }
    mobileNativeAgent.updateMaxAgentHops(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.cycleMaxToolCalls() {
    val current = mobileNativeAgent.modelPlannerSettings().maxToolCalls
    val next = when {
        current < 16 -> 16
        current < 32 -> 32
        else -> 8
    }
    mobileNativeAgent.updateMaxToolCalls(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.toggleAgentScreenObservation() {
    val next = !mobileNativeAgent.safetySettings().screenObservationAllowed
    mobileNativeAgent.updateScreenObservationAllowed(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.toggleAgentLocalActions() {
    val next = !mobileNativeAgent.safetySettings().localActionsAllowed
    mobileNativeAgent.updateLocalActionsAllowed(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.toggleAgentConnectorCalls() {
    val next = !mobileNativeAgent.safetySettings().connectorCallsAllowed
    mobileNativeAgent.updateConnectorCallsAllowed(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.toggleAgentDeviceControl() {
    val next = !mobileNativeAgent.safetySettings().deviceControlAllowed
    mobileNativeAgent.updateDeviceControlAllowed(next)
    showOnDeviceAgentFeaturePage()
}

internal fun MainActivity.taskExecutionModeLabel(mode: AgentTaskExecutionMode): String = when (mode) {
    AgentTaskExecutionMode.PLAN_ONLY -> getString(R.string.task_execution_mode_plan_only)
    AgentTaskExecutionMode.AUTO_COMPLETE -> getString(R.string.task_execution_mode_auto_complete)
}

internal fun MainActivity.showLanguageSettingsPage() {
    val policy = LanguagePolicySettings.get(this)
    showFeaturePage(getString(R.string.language_policy_title))
    featureContent.addView(featureHeroCard(
        getString(R.string.language_policy_title),
        getString(R.string.language_policy_subtitle),
        R.drawable.ic_settings_language,
        "#14C66A",
        languagePolicySummary()
    ))
    addSectionTitle(getString(R.string.language_policy_interface_section))
    featureContent.addView(languageChoiceRow(
        getString(R.string.settings_language_auto),
        AppLanguage.AUTO
    ))
    featureContent.addView(languageChoiceRow(
        getString(R.string.settings_language_zh),
        AppLanguage.ZH_CN
    ))
    featureContent.addView(languageChoiceRow(
        getString(R.string.settings_language_en),
        AppLanguage.EN
    ))

    addSectionTitle(getString(R.string.language_policy_voice_section))
    featureContent.addView(featureRow(
        getString(R.string.language_policy_response_language),
        getString(R.string.language_policy_response_subtitle),
        R.drawable.ic_agent_node,
        languagePolicyCompactLabel(policy.responseLanguage)
    ).apply {
        setOnClickListener {
            showLanguagePolicyDialog(
                getString(R.string.language_policy_response_language),
                policy.responseLanguage
            ) {
                VoiceAssistantSettings.setResponseLanguage(this@showLanguageSettingsPage, it)
                Toast.makeText(this@showLanguageSettingsPage, getString(R.string.language_policy_saved), Toast.LENGTH_SHORT).show()
                showLanguageSettingsPage()
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.language_policy_asr_language),
        getString(R.string.language_policy_asr_subtitle),
        R.drawable.ic_settings_voice,
        languagePolicyCompactLabel(policy.asrLanguage)
    ).apply {
        setOnClickListener {
            showLanguagePolicyDialog(getString(R.string.language_policy_asr_language), policy.asrLanguage) {
                VoiceAssistantSettings.setAsrLanguage(this@showLanguageSettingsPage, it)
                showLanguageSettingsPage()
            }
        }
    })
    featureContent.addView(featureRow(
        getString(R.string.language_policy_tts_language),
        getString(R.string.language_policy_tts_subtitle),
        R.drawable.ic_send_plane,
        languagePolicyCompactLabel(policy.ttsLanguage)
    ).apply {
        setOnClickListener {
            showLanguagePolicyDialog(getString(R.string.language_policy_tts_language), policy.ttsLanguage) {
                VoiceAssistantSettings.setTtsLanguage(this@showLanguageSettingsPage, it)
                configureAndroidTtsLanguage()
                showLanguageSettingsPage()
            }
        }
    })
}

internal fun MainActivity.languageChoiceRow(title: String, language: String): View {
    val selected = AppLanguage.current(this) == language
    return featureRow(
        title,
        if (selected) getString(R.string.settings_language_selected) else "",
        R.drawable.ic_protocol_link,
        if (selected) getString(R.string.settings_language_selected) else getString(R.string.settings_language_use)
    ).apply {
        setOnClickListener {
            if (!selected) {
                AppLanguage.set(this@languageChoiceRow, language)
                val refreshIntent = Intent(this@languageChoiceRow, MessageService::class.java).apply {
                    action = MessageService.ACTION_REFRESH_LANGUAGE
                }
                startService(refreshIntent)
                Toast.makeText(this@languageChoiceRow, getString(R.string.language_changed), Toast.LENGTH_SHORT).show()
                recreate()
            }
        }
    }
}

internal fun MainActivity.languagePolicySummary(): String {
    val policy = LanguagePolicySettings.get(this)
    return if (
        AppLanguage.current(this) == AppLanguage.AUTO &&
        policy.responseLanguage == LanguagePolicySettings.AUTO &&
        policy.asrLanguage == LanguagePolicySettings.AUTO &&
        policy.ttsLanguage == LanguagePolicySettings.AUTO
    ) {
        getString(R.string.language_policy_auto_short)
    } else {
        getString(R.string.language_policy_configured_short)
    }
}

internal fun MainActivity.languagePolicyCompactLabel(value: String): String {
    val normalized = LanguagePolicySettings.choices.firstOrNull { it.equals(value, true) }
        ?: LanguagePolicySettings.AUTO
    return getString(
        when (normalized) {
            LanguagePolicySettings.ZH_CN -> R.string.language_policy_zh_cn_short
            LanguagePolicySettings.EN_US -> R.string.language_policy_en_us_short
            LanguagePolicySettings.ZH_HK -> R.string.language_policy_zh_hk_short
            LanguagePolicySettings.ZH_TW -> R.string.language_policy_zh_tw_short
            else -> R.string.language_policy_auto_short
        }
    )
}

internal fun MainActivity.languagePolicyLabel(value: String): String {
    val normalized = LanguagePolicySettings.choices.firstOrNull { it.equals(value, true) }
        ?: LanguagePolicySettings.AUTO
    if (normalized == LanguagePolicySettings.AUTO) {
        val resolved = LanguagePolicySettings.resolve(normalized)
        val effective = languagePolicyLabel(
            when {
                resolved.equals(LanguagePolicySettings.ZH_HK, true) -> LanguagePolicySettings.ZH_HK
                resolved.equals(LanguagePolicySettings.ZH_TW, true) -> LanguagePolicySettings.ZH_TW
                resolved.startsWith("zh", true) -> LanguagePolicySettings.ZH_CN
                else -> LanguagePolicySettings.EN_US
            }
        )
        return getString(R.string.language_policy_effective, effective)
    }
    return getString(
        when (normalized) {
            LanguagePolicySettings.ZH_CN -> R.string.language_policy_zh_cn
            LanguagePolicySettings.EN_US -> R.string.language_policy_en_us
            LanguagePolicySettings.ZH_HK -> R.string.language_policy_zh_hk
            LanguagePolicySettings.ZH_TW -> R.string.language_policy_zh_tw
            else -> R.string.language_policy_auto
        }
    )
}

internal fun MainActivity.showLanguagePolicyDialog(
    title: String,
    current: String,
    onChoose: (String) -> Unit
) {
    val values = LanguagePolicySettings.choices
    val labels = values.map(::languagePolicyLabel)
    val selected = values.indexOfFirst { it.equals(current, true) }.coerceAtLeast(0)
    android.app.AlertDialog.Builder(this)
        .setTitle(title)
        .setSingleChoiceItems(labels.toTypedArray(), selected) { dialog, which ->
            onChoose(values[which])
            dialog.dismiss()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.showFeaturePage(title: String, preserveDesktopControlId: String? = null) {
    navigationContentGate.invalidate()
    showingFriendRequests = false
    activeFriendRequestContactId = ""
    handler.removeCallbacks(voiceHealthRefresh)
    handler.removeCallbacks(localModelDownloadRefresh)
    localModelRowBindings.clear()
    voiceHealthRows.clear()
    activeDesktopControlId
        ?.takeIf { it != preserveDesktopControlId }
        ?.let(DesktopRemoteControl::stopScreenshotStream)
    activeDesktopControlId = preserveDesktopControlId
    activeDesktopPerceptionId = null
    activeDesktopScreenView = null
    activeDesktopScreenPlaceholder = null
    if (!renderingControlCenterDestination &&
        featurePage.visibility == View.VISIBLE &&
        controlCenterDestination != null
    ) {
        controlCenterBackStack.addLast(checkNotNull(controlCenterDestination))
        controlCenterDestination = null
    }
    stopVoiceAssistant()
    wakePage.visibility = View.GONE
    mainPage.visibility = View.GONE
    chatPage.visibility = View.GONE
    featurePage.visibility = View.VISIBLE
    featureTitle.text = title
    featureContent.removeAllViews()
    featureContent.gravity = Gravity.NO_GRAVITY
    setFeatureBackAction()
}

internal fun MainActivity.setFeatureBackAction(action: (() -> Unit)? = null) {
    featureBackAction = action
    featureBackButton.setOnClickListener { performFeatureBack() }
}

internal fun MainActivity.performFeatureBack() {
    val action = featureBackAction
    featureBackAction = null
    if (action != null) {
        action()
    } else if (controlCenterDestination != null || controlCenterBackStack.isNotEmpty()) {
        navigateControlCenterBack()
    } else {
        hideFeaturePage()
    }
}

internal fun MainActivity.hideFeaturePage() {
    activeDesktopControlId?.let(DesktopRemoteControl::stopScreenshotStream)
    activeDesktopControlId = null
    activeDesktopPerceptionId = null
    activeDesktopScreenView = null
    activeDesktopScreenPlaceholder = null
    featureBackAction = null
    showingFriendRequests = false
    activeFriendRequestContactId = ""
    controlCenterDestination = null
    controlCenterBackStack.clear()
    featurePage.visibility = View.GONE
    wakePage.visibility = if (activeMainTab == PAGE_VOICE) View.VISIBLE else View.GONE
    mainPage.visibility = View.VISIBLE
    if (activeMainTab == PAGE_VOICE) {
        mainPage.visibility = View.GONE
        startVoiceAssistant()
    }
}

internal fun MainActivity.addSegmentTabs(labels: List<String>) {
    val row = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(2), 0, dp(2), dp(12))
    }
    labels.forEachIndexed { index, label ->
        row.addView(TextView(this).apply {
            text = label
            gravity = Gravity.CENTER
            setTextColor(getColorCompat(if (index == 0) R.color.signalasi_green else R.color.text_secondary))
            textSize = 14f
            if (index == 0) setTypeface(typeface, android.graphics.Typeface.BOLD)
        }, LinearLayout.LayoutParams(0, dp(38), 1f))
    }
    featureContent.addView(row)
}
