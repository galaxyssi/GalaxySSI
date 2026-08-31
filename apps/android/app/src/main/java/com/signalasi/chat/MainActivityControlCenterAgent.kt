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

internal fun MainActivity.deviceProfileLabel(profile: AgentDeviceProfile): String = getString(
    when (profile.kind) {
        AgentDeviceProfileKind.PHONE -> R.string.cc_device_profile_phone
        AgentDeviceProfileKind.TABLET -> R.string.cc_device_profile_tablet
        AgentDeviceProfileKind.AUTOMOTIVE -> R.string.cc_device_profile_automotive
        AgentDeviceProfileKind.LEGACY_SAMSUNG_PHONE ->
            R.string.cc_device_profile_legacy_samsung_phone
        AgentDeviceProfileKind.LEGACY_SAMSUNG_TABLET ->
            R.string.cc_device_profile_legacy_samsung_tablet
    }
)

internal fun MainActivity.renderControlCenterSystemStatusPage() {
    val state = mobileNativeAgent.snapshot()
    val safety = mobileNativeAgent.safetySettings()
    val memory = AgentMemoryPssRuntime.snapshot()
    val tools = mobileNativeAgent.nativeToolCatalog()
    val visibleTargets = controlCenterResourceTargets(state.callableTargets)
    val availableResources = visibleTargets.count { it.status == AgentConnectorStatus.AVAILABLE }
    val linkReady = SignalASIMqttClient.isConnected() && SignalASIMqttClient.isSecureReady()
    val knowledgeCount = mobileNativeAgent.knowledgeSourceGroups().size
    val needsAttention = safety.executionPaused || !linkReady ||
        state.callableTargets.any { it.status == AgentConnectorStatus.NEEDS_SETUP }
    showControlCenterFeature(
        getString(R.string.cc_system_status_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(if (needsAttention) R.string.cc_services_need_attention else R.string.cc_all_services_normal),
                subtitle = getString(if (needsAttention) R.string.cc_services_need_attention_subtitle else R.string.cc_all_services_normal_subtitle),
                iconRes = if (needsAttention) R.drawable.ic_info_outline else R.drawable.ic_security_shield,
                tone = if (needsAttention) ControlCenterTone.AMBER else ControlCenterTone.GREEN
            ),
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_system_status_title),
                subtitle = getString(if (needsAttention) R.string.cc_services_need_attention_subtitle else R.string.cc_all_services_normal_subtitle),
                iconRes = R.drawable.ic_info_outline,
                metrics = listOf(
                    ControlCenterMetricSpec(tools.count { it.availability.status == AgentNativeToolAvailabilityStatus.AVAILABLE }.toString(), getString(R.string.cc_metric_native_tools)),
                    ControlCenterMetricSpec("$availableResources/${visibleTargets.size}", getString(R.string.cc_metric_available_resources)),
                    if (RuntimePlaintextProtection.isRuntimeDiagnosticsVisible()) {
                        ControlCenterMetricSpec(formatBytes(memory.processCurrentBytes), getString(R.string.cc_metric_agent_memory))
                    } else {
                        ControlCenterMetricSpec(knowledgeCount.toString(), getString(R.string.cc_metric_knowledge_sources))
                    }
                )
            ),
            sections = buildList {
                add(
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_core_services),
                    listOf(
                        ControlCenterRowSpec(routeAction(ControlCenterRoute.AGENT_CORE), getString(R.string.cc_service_runtime), getString(if (safety.executionPaused) R.string.cc_agent_paused_subtitle else R.string.cc_service_runtime_subtitle), R.drawable.ic_agent_node, getString(if (safety.executionPaused) R.string.on_device_agent_status_paused else R.string.cc_status_online), if (safety.executionPaused) ControlCenterTone.AMBER else ControlCenterTone.GREEN),
                        ControlCenterRowSpec(routeAction(ControlCenterRoute.NODES), getString(R.string.cc_service_link), getString(if (linkReady) R.string.cc_service_link_connected else R.string.cc_service_link_offline), R.drawable.ic_protocol_link, getString(if (linkReady) R.string.cc_status_online else R.string.cc_status_degraded), if (linkReady) ControlCenterTone.GREEN else ControlCenterTone.AMBER),
                        ControlCenterRowSpec(routeAction(ControlCenterRoute.RESOURCE_ROUTING), getString(R.string.cc_service_router), getString(R.string.cc_service_router_subtitle, availableResources, visibleTargets.size), R.drawable.ic_settings_model, getString(if (availableResources > 0) R.string.cc_status_ready else R.string.cc_status_degraded), if (availableResources > 0) ControlCenterTone.BLUE else ControlCenterTone.AMBER),
                        ControlCenterRowSpec(routeAction(ControlCenterRoute.KNOWLEDGE), getString(R.string.cc_service_knowledge), getString(R.string.cc_service_knowledge_subtitle, knowledgeCount), R.drawable.ic_agent_knowledge, getString(if (knowledgeCount > 0) R.string.cc_status_ready else R.string.status_needs_setup), if (knowledgeCount > 0) ControlCenterTone.BLUE else ControlCenterTone.NEUTRAL)
                    )
                ))
                if (RuntimePlaintextProtection.isRuntimeDiagnosticsVisible()) {
                    add(
                        ControlCenterSectionSpec(
                            getString(R.string.advanced_section_diagnostics),
                            listOf(
                                ControlCenterRowSpec(
                                    "agent.memory_telemetry",
                                    getString(R.string.cc_agent_memory_telemetry_title),
                                    getString(
                                        R.string.cc_agent_memory_telemetry_summary,
                                        formatBytes(memory.processCurrentBytes),
                                        formatBytes(memory.processPeakBytes)
                                    ),
                                    R.drawable.ic_agent_memory,
                                    getString(R.string.cc_agent_memory_pss_badge),
                                    ControlCenterTone.VIOLET
                                )
                            )
                        )
                    )
                }
            }
        )
    )
}

internal fun MainActivity.renderControlCenterAgentMemoryTelemetryPage() {
    if (!RuntimePlaintextProtection.isRuntimeDiagnosticsVisible()) {
        renderControlCenterSystemStatusPage()
        return
    }
    val snapshot = AgentMemoryPssRuntime.snapshot()
    val sessionBudget = snapshot.sessionBudget
    val processRows = listOf(
        ControlCenterRowSpec(
            "",
            getString(R.string.cc_agent_memory_process_total),
            getString(R.string.cc_agent_memory_process_total_subtitle),
            R.drawable.ic_settings_diagnostics,
            formatBytes(snapshot.processCurrentBytes),
            ControlCenterTone.VIOLET,
            showChevron = false
        ),
        ControlCenterRowSpec(
            "",
            getString(R.string.cc_agent_memory_native),
            getString(R.string.cc_agent_memory_native_subtitle),
            R.drawable.ic_agent_node,
            formatBytes(snapshot.nativeBytes),
            ControlCenterTone.BLUE,
            showChevron = false
        ),
        ControlCenterRowSpec(
            "",
            getString(R.string.cc_agent_memory_dalvik),
            getString(R.string.cc_agent_memory_dalvik_subtitle),
            R.drawable.ic_settings_model,
            formatBytes(snapshot.dalvikBytes),
            ControlCenterTone.GREEN,
            showChevron = false
        ),
        ControlCenterRowSpec(
            "",
            getString(R.string.cc_agent_memory_other),
            getString(R.string.cc_agent_memory_other_subtitle),
            R.drawable.ic_info_outline,
            formatBytes(snapshot.otherBytes),
            ControlCenterTone.NEUTRAL,
            showChevron = false
        )
    )
    showControlCenterFeature(
        getString(R.string.cc_agent_memory_telemetry_title),
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_agent_memory_telemetry_title),
                subtitle = getString(R.string.cc_agent_memory_telemetry_subtitle),
                iconRes = R.drawable.ic_agent_memory,
                badges = listOf(
                    ControlCenterBadgeSpec(
                        getString(R.string.cc_agent_memory_pss_badge),
                        ControlCenterTone.VIOLET
                    )
                ),
                metrics = listOf(
                    ControlCenterMetricSpec(
                        formatBytes(snapshot.processCurrentBytes),
                        getString(R.string.cc_agent_memory_current)
                    ),
                    ControlCenterMetricSpec(
                        formatBytes(snapshot.processPeakBytes),
                        getString(R.string.cc_agent_memory_peak)
                    ),
                    ControlCenterMetricSpec(
                        formatBytes(sessionBudget.latestIncrementalBytes),
                        getString(R.string.cc_agent_session_memory_latest)
                    )
                )
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_agent_memory_process_section),
                    processRows
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_agent_session_memory_section),
                    listOf(
                        ControlCenterRowSpec(
                            "",
                            getString(R.string.cc_agent_session_memory_latest),
                            getString(R.string.cc_agent_session_memory_latest_subtitle),
                            R.drawable.ic_agent_memory,
                            if (sessionBudget.sampleCount == 0) {
                                getString(R.string.cc_agent_session_memory_unmeasured)
                            } else {
                                getString(
                                    if (sessionBudget.withinBudget) {
                                        R.string.cc_agent_session_memory_target
                                    } else {
                                        R.string.cc_agent_session_memory_over
                                    },
                                    formatBytes(sessionBudget.targetBytes)
                                )
                            },
                            when {
                                sessionBudget.sampleCount == 0 -> ControlCenterTone.NEUTRAL
                                sessionBudget.withinBudget -> ControlCenterTone.GREEN
                                else -> ControlCenterTone.AMBER
                            },
                            showChevron = false
                        ),
                        ControlCenterRowSpec(
                            "",
                            getString(R.string.cc_agent_session_memory_peak),
                            getString(R.string.cc_agent_session_memory_peak_subtitle),
                            R.drawable.ic_settings_diagnostics,
                            formatBytes(sessionBudget.peakIncrementalBytes),
                            if (sessionBudget.peakIncrementalBytes <= sessionBudget.targetBytes) {
                                ControlCenterTone.GREEN
                            } else {
                                ControlCenterTone.AMBER
                            },
                            showChevron = false
                        ),
                        ControlCenterRowSpec(
                            "",
                            getString(R.string.cc_agent_session_memory_average),
                            getString(
                                R.string.cc_agent_session_memory_average_subtitle,
                                sessionBudget.sampleCount,
                                sessionBudget.exceededCount
                            ),
                            R.drawable.ic_agent_node,
                            formatBytes(sessionBudget.averageIncrementalBytes),
                            ControlCenterTone.BLUE,
                            showChevron = false
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_agent_memory_by_agent),
                    agentMemoryTelemetryRows(snapshot.byAgent)
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_agent_memory_by_session),
                    agentMemoryTelemetryRows(snapshot.bySession)
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_agent_memory_by_provider),
                    agentMemoryTelemetryRows(snapshot.byProvider)
                )
            ),
            footer = listOf(
                getString(R.string.cc_agent_memory_estimate_notice),
                getString(R.string.cc_agent_session_memory_notice)
            ).joinToString("\n\n")
        )
    )
}

internal fun MainActivity.agentMemoryTelemetryRows(
    values: List<AgentMemoryDimensionStats>
): List<ControlCenterRowSpec> {
    if (values.isEmpty()) {
        return listOf(
            ControlCenterRowSpec(
                "",
                getString(R.string.cc_agent_memory_no_samples),
                getString(R.string.cc_agent_memory_no_samples_subtitle),
                R.drawable.ic_info_outline,
                showChevron = false
            )
        )
    }
    return values.take(12).map { item ->
        ControlCenterRowSpec(
            "",
            item.id,
            getString(
                R.string.cc_agent_memory_dimension_subtitle,
                formatBytes(item.peakBytes),
                item.sampleCount
            ),
            R.drawable.ic_agent_node,
            formatBytes(item.currentBytes),
            if (item.estimated) ControlCenterTone.AMBER else ControlCenterTone.GREEN,
            showChevron = false
        )
    }
}

internal fun MainActivity.renderControlCenterAgentCorePage() {
    val safety = mobileNativeAgent.safetySettings()
    val planner = mobileNativeAgent.modelPlannerSettings()
    val preferenceMode = mobileNativeAgent.preferenceMode()
    showControlCenterFeature(
        getString(R.string.cc_agent_core_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(if (safety.executionPaused) R.string.cc_agent_paused else R.string.cc_agent_running),
                subtitle = getString(if (safety.executionPaused) R.string.cc_agent_paused_subtitle else R.string.cc_agent_running_subtitle),
                iconRes = R.drawable.ic_agent_node,
                tone = if (safety.executionPaused) ControlCenterTone.AMBER else ControlCenterTone.GREEN
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_autonomy),
                    listOf(ControlCenterRowSpec("agent.execution_policy", getString(R.string.cc_autonomy_title), getString(R.string.cc_autonomy_subtitle), R.drawable.ic_security_shield, agentPreferenceModeLabel(preferenceMode), ControlCenterTone.BLUE))
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_core_capabilities),
                    listOf(
                        ControlCenterRowSpec("agent.planner", getString(R.string.cc_planning_title), getString(R.string.cc_planning_subtitle, planner.maxReplans), R.drawable.ic_agent_control, getString(if (planner.dynamicReplanning) R.string.status_enabled else R.string.common_off), ControlCenterTone.BLUE),
                        ControlCenterRowSpec("agent.planner", getString(R.string.cc_multitask_title), getString(R.string.cc_multitask_subtitle), R.drawable.ic_agent_history, getString(if (planner.multiAgentCoordination) R.string.status_enabled else R.string.common_off), ControlCenterTone.GREEN),
                        ControlCenterRowSpec(routeAction(ControlCenterRoute.RESOURCE_ROUTING), getString(R.string.cc_failure_recovery_title), getString(R.string.cc_failure_recovery_subtitle), R.drawable.ic_reset_data, getString(R.string.cc_status_ready), ControlCenterTone.AMBER),
                        ControlCenterRowSpec(routeAction(ControlCenterRoute.RESOURCE_ROUTING), getString(R.string.cc_resource_routing_title), getString(R.string.cc_resource_routing_subtitle), R.drawable.ic_settings_model, "", ControlCenterTone.VIOLET)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_runtime_protection),
                    listOf(
                        ControlCenterRowSpec("agent.toggle_pause", getString(R.string.cc_pause_all_title), getString(R.string.cc_pause_all_subtitle), R.drawable.ic_agent_history, switchValue = safety.executionPaused, showChevron = false),
                        ControlCenterRowSpec("agent.planner", getString(R.string.cc_advanced_agent_settings), getString(R.string.cc_advanced_agent_settings_subtitle), R.drawable.ic_settings_diagnostics, "", ControlCenterTone.NEUTRAL)
                    )
                )
            )
        )
    )
}

internal fun MainActivity.renderControlCenterSelfEvolutionPage() {
    val manager = AgentSelfEvolutionService.manager(this)
    val tasks = manager.list(100)
    val desktopLinks = SignalASILinkProtocol.allServerLinks(this)
        .filter { it.paired && it.fullDesktopExecutor }
    val now = System.currentTimeMillis()
    if (now - lastSelfEvolutionRemoteSyncAtMillis >= 10_000L) {
        lastSelfEvolutionRemoteSyncAtMillis = now
        desktopLinks.forEach { SignalASIMqttClient.requestDesktopEvolutionTasks(it.desktopId) }
    }
    val remoteTasks = remoteSelfEvolutionStore.list(100)
        .filter { remote -> desktopLinks.any { it.desktopId == remote.desktopId } }
    val runtime = AgentOnDeviceRuntimeManager(this).status()
    val runtimeReady = runtime.backendReady && runtime.languageReady(AgentRuntimeLanguage.SHELL)
    val health = AgentSelfEvolutionHealthAnalyzer.summarize(
        tasks + remoteTasks.map(AgentRemoteSelfEvolutionTask::task)
    )
    val candidates = health.waitingReview
    val active = health.activeTasks
    val failed = health.attentionTasks
    val recentRows = tasks.take(8).map { task ->
        ControlCenterRowSpec(
            actionId = "evolution.task:${task.taskId}",
            title = task.problem,
            subtitle = getString(
                R.string.cc_evolution_task_summary,
                task.attempts.size,
                task.maxAttempts,
                selfEvolutionStatusLabel(task.status)
            ),
            iconRes = R.drawable.ic_agent_history,
            status = selfEvolutionStatusLabel(task.status),
            tone = selfEvolutionStatusTone(task.status)
        )
    }
    val remoteRows = remoteTasks.take(8).map { remote ->
        val desktopName = desktopLinks.firstOrNull { it.desktopId == remote.desktopId }
            ?.desktopName.orEmpty()
        ControlCenterRowSpec(
            actionId = "evolution.remote:${Uri.encode(remote.desktopId)}:${Uri.encode(remote.task.taskId)}",
            title = remote.task.problem,
            subtitle = getString(
                R.string.cc_evolution_remote_task_summary,
                desktopName.ifBlank { getString(R.string.cc_evolution_desktop_executor) },
                remote.task.attempts.size,
                remote.task.maxAttempts
            ),
            iconRes = R.drawable.ic_device_node,
            status = selfEvolutionStatusLabel(remote.task.status),
            tone = selfEvolutionStatusTone(remote.task.status)
        )
    }
    showControlCenterFeature(
        getString(R.string.cc_evolution_title),
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_evolution_hero_title),
                subtitle = getString(R.string.cc_evolution_hero_subtitle),
                iconRes = R.drawable.ic_reset_data,
                badges = listOf(
                    ControlCenterBadgeSpec(
                        getString(
                            if (runtimeReady) R.string.cc_evolution_local_ready
                            else R.string.cc_evolution_runtime_needed
                        ),
                        if (runtimeReady) ControlCenterTone.GREEN else ControlCenterTone.AMBER
                    ),
                    ControlCenterBadgeSpec(
                        getString(R.string.cc_evolution_production_protected),
                        ControlCenterTone.BLUE
                    )
                ),
                metrics = listOf(
                    ControlCenterMetricSpec(active.toString(), getString(R.string.cc_evolution_metric_active)),
                    ControlCenterMetricSpec(candidates.toString(), getString(R.string.cc_evolution_metric_review)),
                    ControlCenterMetricSpec(failed.toString(), getString(R.string.cc_evolution_metric_attention))
                ),
                actionId = "evolution.create"
            ),
            banner = ControlCenterBannerSpec(
                title = getString(
                    if (runtimeReady) R.string.cc_evolution_banner_ready
                    else R.string.cc_evolution_banner_setup
                ),
                subtitle = getString(
                    if (runtimeReady) R.string.cc_evolution_banner_ready_subtitle
                    else R.string.cc_evolution_banner_setup_subtitle
                ),
                iconRes = R.drawable.ic_security_shield,
                tone = if (runtimeReady) ControlCenterTone.GREEN else ControlCenterTone.AMBER,
                actionId = if (runtimeReady) "evolution.create"
                else routeAction(ControlCenterRoute.ON_DEVICE_RUNTIME)
            ),
            sections = buildList {
                add(
                    ControlCenterSectionSpec(
                        getString(R.string.cc_evolution_section_pipeline),
                        listOf(
                            ControlCenterRowSpec(
                                "evolution.create",
                                getString(R.string.cc_evolution_new_task),
                                getString(R.string.cc_evolution_new_task_subtitle),
                                R.drawable.ic_agent_node,
                                "",
                                ControlCenterTone.VIOLET
                            ),
                            ControlCenterRowSpec(
                                routeAction(ControlCenterRoute.ON_DEVICE_RUNTIME),
                                getString(R.string.cc_evolution_local_runtime),
                                getString(R.string.cc_evolution_local_runtime_subtitle),
                                R.drawable.ic_settings_diagnostics,
                                getString(
                                    if (runtimeReady) R.string.cc_status_ready
                                    else R.string.status_needs_setup
                                ),
                                if (runtimeReady) ControlCenterTone.GREEN else ControlCenterTone.AMBER
                            ),
                            ControlCenterRowSpec(
                                "evolution.desktop.create",
                                getString(R.string.cc_evolution_desktop_executor),
                                getString(R.string.cc_evolution_desktop_executor_subtitle),
                                R.drawable.ic_device_node,
                                desktopLinks.size.toString(),
                                if (desktopLinks.isEmpty()) ControlCenterTone.NEUTRAL else ControlCenterTone.GREEN,
                                enabled = desktopLinks.isNotEmpty()
                            ),
                            ControlCenterRowSpec(
                                "",
                                getString(R.string.cc_evolution_quality_gates),
                                getString(R.string.cc_evolution_quality_gates_subtitle),
                                R.drawable.ic_security_shield,
                                getString(R.string.cc_evolution_immutable),
                                ControlCenterTone.BLUE,
                                showChevron = false
                            ),
                            ControlCenterRowSpec(
                                "",
                                getString(R.string.cc_evolution_health),
                                getString(
                                    R.string.cc_evolution_health_subtitle,
                                    health.gatePassPercent,
                                    health.retries,
                                    health.staleTasks
                                ),
                                R.drawable.ic_settings_diagnostics,
                                getString(
                                    if (health.attentionTasks == 0) R.string.cc_evolution_health_good
                                    else R.string.cc_evolution_health_attention
                                ),
                                if (health.attentionTasks == 0) ControlCenterTone.GREEN
                                else ControlCenterTone.AMBER,
                                showChevron = false
                            ),
                            ControlCenterRowSpec(
                                "",
                                getString(R.string.cc_evolution_rollback),
                                getString(R.string.cc_evolution_rollback_subtitle),
                                R.drawable.ic_reset_data,
                                getString(R.string.cc_status_ready),
                                ControlCenterTone.AMBER,
                                showChevron = false
                            )
                        )
                    )
                )
                add(
                    ControlCenterSectionSpec(
                        getString(R.string.cc_evolution_section_recent),
                        recentRows.ifEmpty {
                            listOf(
                                ControlCenterRowSpec(
                                    "evolution.create",
                                    getString(R.string.cc_evolution_empty_title),
                                    getString(R.string.cc_evolution_empty_subtitle),
                                    R.drawable.ic_agent_history,
                                    "",
                                    ControlCenterTone.NEUTRAL
                                )
                            )
                        }
                    )
                )
                if (remoteRows.isNotEmpty()) {
                    add(
                        ControlCenterSectionSpec(
                            getString(R.string.cc_evolution_section_desktop),
                            remoteRows
                        )
                    )
                }
            },
            footer = getString(R.string.cc_evolution_footer)
        )
    )
}

internal fun MainActivity.selfEvolutionStatusLabel(status: AgentSelfEvolutionStatus): String = getString(
    when (status) {
        AgentSelfEvolutionStatus.PROPOSED -> R.string.cc_evolution_status_proposed
        AgentSelfEvolutionStatus.PREPARING -> R.string.cc_evolution_status_preparing
        AgentSelfEvolutionStatus.RUNNING -> R.string.cc_evolution_status_running
        AgentSelfEvolutionStatus.VALIDATING -> R.string.cc_evolution_status_validating
        AgentSelfEvolutionStatus.WAITING_APPROVAL -> R.string.cc_evolution_status_review
        AgentSelfEvolutionStatus.PUBLISHING -> R.string.cc_evolution_status_publishing
        AgentSelfEvolutionStatus.PUBLISHED -> R.string.cc_evolution_status_published
        AgentSelfEvolutionStatus.COMPLETED -> R.string.cc_evolution_status_completed
        AgentSelfEvolutionStatus.FAILED -> R.string.cc_evolution_status_failed
        AgentSelfEvolutionStatus.BLOCKED -> R.string.cc_evolution_status_blocked
        AgentSelfEvolutionStatus.CANCELLED -> R.string.cc_evolution_status_cancelled
        AgentSelfEvolutionStatus.ROLLED_BACK -> R.string.cc_evolution_status_rolled_back
    }
)

internal fun MainActivity.selfEvolutionStatusTone(status: AgentSelfEvolutionStatus): ControlCenterTone = when (status) {
    AgentSelfEvolutionStatus.WAITING_APPROVAL,
    AgentSelfEvolutionStatus.PUBLISHING -> ControlCenterTone.VIOLET
    AgentSelfEvolutionStatus.PREPARING,
    AgentSelfEvolutionStatus.RUNNING,
    AgentSelfEvolutionStatus.VALIDATING -> ControlCenterTone.BLUE
    AgentSelfEvolutionStatus.FAILED,
    AgentSelfEvolutionStatus.BLOCKED -> ControlCenterTone.AMBER
    AgentSelfEvolutionStatus.CANCELLED,
    AgentSelfEvolutionStatus.ROLLED_BACK -> ControlCenterTone.NEUTRAL
    AgentSelfEvolutionStatus.PROPOSED -> ControlCenterTone.NEUTRAL
    AgentSelfEvolutionStatus.PUBLISHED,
    AgentSelfEvolutionStatus.COMPLETED -> ControlCenterTone.GREEN
}

internal fun MainActivity.showCreateDesktopEvolutionTaskPicker() {
    val links = SignalASILinkProtocol.allServerLinks(this)
        .filter { it.paired && it.fullDesktopExecutor }
    if (links.isEmpty()) {
        Toast.makeText(this, getString(R.string.cc_evolution_no_desktop_executor), Toast.LENGTH_LONG).show()
        return
    }
    AlertDialog.Builder(this)
        .setTitle(getString(R.string.cc_evolution_choose_desktop))
        .setItems(links.map { it.desktopName }.toTypedArray()) { _, index ->
            showCreateSelfEvolutionTaskDialog(links[index].desktopId)
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.showCreateSelfEvolutionTaskDialog(desktopId: String = "") {
    val problemInput = EditText(this).apply {
        hint = getString(R.string.cc_evolution_problem_hint)
        minLines = 2
        maxLines = 5
    }
    val scopeInput = EditText(this).apply {
        hint = getString(R.string.cc_evolution_scope_hint)
        setText(if (desktopId.isBlank()) "apps/android/app" else "apps/desktop")
        maxLines = 4
    }
    val acceptanceInput = EditText(this).apply {
        hint = getString(R.string.cc_evolution_acceptance_hint)
        setText(getString(R.string.cc_evolution_acceptance_default))
        minLines = 2
        maxLines = 6
    }
    val form = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(20), dp(4), dp(20), 0)
        addView(problemInput)
        addView(scopeInput)
        addView(acceptanceInput)
    }
    val dialog = AlertDialog.Builder(this)
        .setTitle(
            getString(
                if (desktopId.isBlank()) R.string.cc_evolution_new_task
                else R.string.cc_evolution_new_desktop_task
            )
        )
        .setView(form)
        .setNegativeButton(getString(R.string.common_cancel), null)
        .setPositiveButton(getString(R.string.common_create), null)
        .create()
    dialog.setOnShowListener {
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            val problem = problemInput.text.toString().trim()
            val scope = scopeInput.text.toString().split(',', '\n')
                .map(String::trim).filter(String::isNotBlank)
            val acceptance = acceptanceInput.text.toString().split('\n')
                .map(String::trim).filter(String::isNotBlank)
            val outcome = runCatching {
                if (desktopId.isBlank()) {
                    AgentSelfEvolutionService.manager(this).create(
                        problem = problem,
                        scope = scope,
                        acceptance = acceptance,
                        risk = AgentSelfEvolutionRisk.MEDIUM,
                        maxAttempts = 3
                    )
                } else {
                    check(
                        SignalASIMqttClient.createDesktopEvolutionTask(
                            desktopId = desktopId,
                            problem = problem,
                            scope = scope,
                            acceptance = acceptance
                        )
                    ) { getString(R.string.cc_evolution_remote_send_failed) }
                    null
                }
            }
            if (outcome.isFailure) {
                Toast.makeText(
                    this,
                    outcome.exceptionOrNull()?.message ?: getString(R.string.cc_evolution_create_failed),
                    Toast.LENGTH_LONG
                ).show()
                return@setOnClickListener
            }
            dialog.dismiss()
            renderControlCenterSelfEvolutionPage()
            outcome.getOrNull()?.let(::showSelfEvolutionTaskDialog)
            if (desktopId.isNotBlank()) {
                Toast.makeText(
                    this,
                    getString(R.string.cc_evolution_remote_started),
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
    }
    dialog.show()
}

internal fun MainActivity.showSelfEvolutionTaskDialog(taskId: String) {
    AgentSelfEvolutionService.manager(this).get(taskId)?.let(::showSelfEvolutionTaskDialog)
        ?: Toast.makeText(this, getString(R.string.cc_evolution_task_missing), Toast.LENGTH_SHORT).show()
}

internal fun MainActivity.showSelfEvolutionTaskDialog(task: AgentSelfEvolutionTask) {
    val latest = task.attempts.lastOrNull()
    val gateSummary = latest?.gates.orEmpty().joinToString("\n") { gate ->
        "${gate.id}: ${gate.status.wireValue}"
    }.ifBlank { getString(R.string.cc_evolution_no_gates) }
    val message = getString(
        R.string.cc_evolution_task_detail,
        selfEvolutionStatusLabel(task.status),
        task.scope.joinToString("\n"),
        task.acceptance.joinToString("\n"),
        gateSummary,
        task.lastError.ifBlank { getString(R.string.common_none) }
    )
    val builder = AlertDialog.Builder(this)
        .setTitle(task.problem)
        .setMessage(message)
        .setNegativeButton(getString(R.string.common_close), null)
    if (task.status in setOf(AgentSelfEvolutionStatus.PROPOSED, AgentSelfEvolutionStatus.BLOCKED)) {
        builder.setPositiveButton(getString(R.string.cc_evolution_prepare)) { _, _ ->
            prepareSelfEvolutionTask(task.taskId)
        }
    }
    if (task.status !in setOf(
            AgentSelfEvolutionStatus.CANCELLED,
            AgentSelfEvolutionStatus.ROLLED_BACK,
            AgentSelfEvolutionStatus.PUBLISHED,
            AgentSelfEvolutionStatus.COMPLETED
        )
    ) {
        builder.setNeutralButton(getString(R.string.cc_evolution_discard)) { _, _ ->
            AgentSelfEvolutionService.manager(this).rollback(task.taskId)
            renderControlCenterSelfEvolutionPage()
        }
    }
    builder.show()
}

internal fun MainActivity.showRemoteSelfEvolutionTaskDialog(desktopId: String, taskId: String) {
    val task = remoteSelfEvolutionStore.get(desktopId, taskId)
    if (task == null) {
        Toast.makeText(this, getString(R.string.cc_evolution_task_missing), Toast.LENGTH_SHORT).show()
        return
    }
    val latest = task.attempts.lastOrNull()
    val gateSummary = latest?.gates.orEmpty().joinToString("\n") { gate ->
        "${gate.id}: ${gate.status.wireValue}"
    }.ifBlank { getString(R.string.cc_evolution_no_gates) }
    val message = getString(
        R.string.cc_evolution_task_detail,
        selfEvolutionStatusLabel(task.status),
        task.scope.joinToString("\n"),
        task.acceptance.joinToString("\n"),
        gateSummary,
        task.lastError.ifBlank { getString(R.string.common_none) }
    )
    val builder = AlertDialog.Builder(this)
        .setTitle(task.problem)
        .setMessage(message)
        .setNegativeButton(getString(R.string.common_close), null)
    if (task.status == AgentSelfEvolutionStatus.WAITING_APPROVAL) {
        builder.setPositiveButton(getString(R.string.cc_evolution_publish_pr)) { _, _ ->
            showRemoteEvolutionPublishConfirmation(desktopId, task)
        }
    } else if (task.status in setOf(
            AgentSelfEvolutionStatus.PREPARING,
            AgentSelfEvolutionStatus.RUNNING,
            AgentSelfEvolutionStatus.VALIDATING
        )
    ) {
        builder.setPositiveButton(getString(R.string.common_cancel)) { _, _ ->
            SignalASIMqttClient.controlDesktopEvolutionTask(
                desktopId,
                task.taskId,
                "cancel"
            )
        }
    }
    if (task.status !in setOf(
            AgentSelfEvolutionStatus.ROLLED_BACK,
            AgentSelfEvolutionStatus.PUBLISHED,
            AgentSelfEvolutionStatus.COMPLETED
        )
    ) {
        builder.setNeutralButton(getString(R.string.cc_evolution_discard)) { _, _ ->
            SignalASIMqttClient.controlDesktopEvolutionTask(
                desktopId,
                task.taskId,
                "rollback"
            )
        }
    }
    builder.show()
}

internal fun MainActivity.showRemoteEvolutionPublishConfirmation(
    desktopId: String,
    task: AgentSelfEvolutionTask
) {
    AlertDialog.Builder(this)
        .setTitle(getString(R.string.cc_evolution_publish_pr))
        .setMessage(
            getString(
                R.string.cc_evolution_publish_confirmation,
                task.candidateCommit.take(12),
                task.approvalHash.take(16)
            )
        )
        .setNegativeButton(getString(R.string.common_cancel), null)
        .setPositiveButton(getString(R.string.cc_evolution_publish_pr)) { _, _ ->
            val sent = SignalASIMqttClient.controlDesktopEvolutionTask(
                desktopId,
                task.taskId,
                "publish",
                task.approvalHash
            )
            Toast.makeText(
                this,
                getString(
                    if (sent) R.string.cc_evolution_publish_sent
                    else R.string.cc_evolution_remote_send_failed
                ),
                Toast.LENGTH_LONG
            ).show()
        }
        .show()
}

internal fun MainActivity.prepareSelfEvolutionTask(taskId: String) {
    Toast.makeText(this, getString(R.string.cc_evolution_preparing_notice), Toast.LENGTH_SHORT).show()
    cloudExecutor.execute {
        val outcome = runCatching { AgentSelfEvolutionService.manager(this).prepare(taskId) }
        runOnUiThread {
            if (controlCenterDestination?.route == ControlCenterRoute.SELF_EVOLUTION) {
                renderControlCenterSelfEvolutionPage()
            }
            outcome.fold(
                onSuccess = { showSelfEvolutionTaskDialog(it) },
                onFailure = {
                    Toast.makeText(
                        this,
                        it.message ?: getString(R.string.cc_evolution_prepare_failed),
                        Toast.LENGTH_LONG
                    ).show()
                }
            )
        }
    }
}
