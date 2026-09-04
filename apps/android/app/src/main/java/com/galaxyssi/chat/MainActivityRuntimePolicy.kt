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

internal fun MainActivity.showPermissionModeSettingsPage() {
    val settings = mobileNativeAgent.safetySettings()
    val selectedPreferenceMode = mobileNativeAgent.preferenceMode()
    val selectedExecutionMode = settings.taskExecutionMode
    showControlCenterFeature(
        getString(R.string.cc_task_execution_mode_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                getString(R.string.cc_task_execution_mode_title),
                getString(R.string.cc_task_execution_mode_subtitle),
                R.drawable.ic_agent_control,
                ControlCenterTone.GREEN
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.agent_preference_mode_section),
                    AgentPreferenceMode.entries.map { mode ->
                        val isSelected = mode == selectedPreferenceMode
                        ControlCenterRowSpec(
                            actionId = if (isSelected) "" else {
                                "agent.preference_mode:${mode.wireValue}"
                            },
                            title = agentPreferenceModeLabel(mode),
                            subtitle = agentPreferenceModeDescription(mode),
                            iconRes = agentPreferenceModeIcon(mode),
                            status = if (isSelected) {
                                getString(R.string.settings_language_selected)
                            } else {
                                ""
                            },
                            tone = if (isSelected) {
                                ControlCenterTone.GREEN
                            } else {
                                ControlCenterTone.NEUTRAL
                            },
                            showChevron = false
                        )
                    }
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_task_execution_mode_section),
                    AgentTaskExecutionMode.entries.map { mode ->
                        val isSelected = mode == selectedExecutionMode
                        ControlCenterRowSpec(
                            actionId = if (isSelected) "" else "agent.task_execution_mode:${mode.wireValue}",
                            title = taskExecutionModeLabel(mode),
                            subtitle = taskExecutionModeDescription(mode),
                            iconRes = R.drawable.ic_agent_control,
                            status = if (isSelected) getString(R.string.settings_language_selected) else "",
                            tone = if (isSelected) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL,
                            showChevron = false
                        )
                    }
                )
            )
        )
    )
}

internal fun MainActivity.agentPreferenceModeLabel(mode: AgentPreferenceMode): String = getString(
    when (mode) {
        AgentPreferenceMode.FEWER_QUESTIONS -> R.string.agent_preference_fewer_questions
        AgentPreferenceMode.CAUTIOUS -> R.string.agent_preference_cautious
        AgentPreferenceMode.AUTOMATION -> R.string.agent_preference_automation
        AgentPreferenceMode.DEVELOPER -> R.string.agent_preference_developer
    }
)

internal fun MainActivity.agentPreferenceModeDescription(mode: AgentPreferenceMode): String = getString(
    when (mode) {
        AgentPreferenceMode.FEWER_QUESTIONS ->
            R.string.agent_preference_fewer_questions_subtitle
        AgentPreferenceMode.CAUTIOUS -> R.string.agent_preference_cautious_subtitle
        AgentPreferenceMode.AUTOMATION -> R.string.agent_preference_automation_subtitle
        AgentPreferenceMode.DEVELOPER -> R.string.agent_preference_developer_subtitle
    }
)

internal fun MainActivity.agentPreferenceModeIcon(mode: AgentPreferenceMode): Int = when (mode) {
    AgentPreferenceMode.FEWER_QUESTIONS -> R.drawable.ic_agent_control
    AgentPreferenceMode.CAUTIOUS -> R.drawable.ic_security_shield
    AgentPreferenceMode.AUTOMATION -> R.drawable.ic_automation_line
    AgentPreferenceMode.DEVELOPER -> R.drawable.ic_agent_skill
}

internal fun MainActivity.taskExecutionModeDescription(mode: AgentTaskExecutionMode): String = getString(
    when (mode) {
        AgentTaskExecutionMode.PLAN_ONLY -> R.string.cc_task_execution_plan_only_subtitle
        AgentTaskExecutionMode.AUTO_COMPLETE -> R.string.cc_task_execution_auto_complete_subtitle
    }
)

internal fun MainActivity.showTaskBudgetSettingsPage() {
    val budget = AgentTaskBudgetStore(this).load()
    showControlCenterFeature(
        getString(R.string.cc_task_budget_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                getString(R.string.cc_task_budget_banner_title),
                getString(R.string.cc_task_budget_banner_subtitle),
                R.drawable.ic_agent_history,
                ControlCenterTone.VIOLET
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_task_budget_profile_section),
                    AgentTaskBudgetProfile.entries.map { profile ->
                        val selected = profile == budget.profile
                        ControlCenterRowSpec(
                            actionId = if (selected) "" else {
                                "agent.task_budget.profile:${profile.wireValue}"
                            },
                            title = taskBudgetProfileLabel(profile),
                            subtitle = taskBudgetProfileDescription(profile),
                            iconRes = R.drawable.ic_agent_control,
                            status = if (selected) {
                                getString(R.string.settings_language_selected)
                            } else {
                                ""
                            },
                            tone = if (selected) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL,
                            showChevron = false
                        )
                    }
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_task_budget_limits_section),
                    listOf(
                        ControlCenterRowSpec(
                            "agent.task_budget.time",
                            getString(R.string.cc_task_budget_time_title),
                            getString(R.string.cc_task_budget_time_subtitle),
                            R.drawable.ic_agent_history,
                            taskBudgetTimeValue(budget.maxElapsedSeconds),
                            ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            "agent.task_budget.cost",
                            getString(R.string.cc_task_budget_cost_title),
                            getString(R.string.cc_task_budget_cost_subtitle),
                            R.drawable.ic_protocol_link,
                            taskBudgetCostValue(budget.maxCostMicros),
                            ControlCenterTone.GREEN
                        ),
                        ControlCenterRowSpec(
                            "agent.task_budget.input_tokens",
                            getString(R.string.cc_task_budget_input_tokens_title),
                            getString(R.string.cc_task_budget_input_tokens_subtitle),
                            R.drawable.ic_agent_control,
                            taskBudgetCountValue(budget.maxInputTokens),
                            ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            "agent.task_budget.output_tokens",
                            getString(R.string.cc_task_budget_output_tokens_title),
                            getString(R.string.cc_task_budget_output_tokens_subtitle),
                            R.drawable.ic_agent_control,
                            taskBudgetCountValue(budget.maxOutputTokens),
                            ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            "agent.task_budget.network",
                            getString(R.string.cc_task_budget_network_title),
                            getString(R.string.cc_task_budget_network_subtitle),
                            R.drawable.ic_protocol_link,
                            taskBudgetNetworkBytesValue(budget.maxNetworkBytes),
                            ControlCenterTone.VIOLET
                        ),
                        ControlCenterRowSpec(
                            "agent.task_budget.battery",
                            getString(R.string.cc_task_budget_battery_title),
                            getString(R.string.cc_task_budget_battery_subtitle),
                            R.drawable.ic_resource_battery,
                            getString(
                                R.string.cc_task_budget_battery_value,
                                budget.minimumBatteryPercent
                            ),
                            ControlCenterTone.AMBER
                        ),
                        ControlCenterRowSpec(
                            "agent.task_budget.memory",
                            getString(R.string.cc_task_budget_memory_title),
                            getString(R.string.cc_task_budget_memory_subtitle),
                            R.drawable.ic_agent_node,
                            taskBudgetMemoryBytesValue(budget.maxMemoryBytes),
                            ControlCenterTone.BLUE
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_task_budget_resource_section),
                    listOf(
                        ControlCenterRowSpec(
                            "agent.task_budget.network_policy",
                            getString(R.string.cc_task_budget_network_policy_title),
                            getString(R.string.cc_task_budget_network_policy_subtitle),
                            R.drawable.ic_protocol_link,
                            taskBudgetNetworkPolicyLabel(budget.networkPolicy),
                            ControlCenterTone.VIOLET
                        ),
                        ControlCenterRowSpec(
                            "agent.task_budget.toggle_cloud",
                            getString(R.string.cc_task_budget_cloud_title),
                            getString(R.string.cc_task_budget_cloud_subtitle),
                            R.drawable.ic_agent_node,
                            switchValue = budget.allowCloud,
                            showChevron = false
                        ),
                        ControlCenterRowSpec(
                            "agent.task_budget.toggle_paid",
                            getString(R.string.cc_task_budget_paid_title),
                            getString(R.string.cc_task_budget_paid_subtitle),
                            R.drawable.ic_protocol_link,
                            switchValue = budget.allowPaidProviders,
                            showChevron = false
                        )
                    )
                )
            )
        )
    )
}

internal fun MainActivity.updateTaskBudget(transform: (AgentTaskBudget) -> AgentTaskBudget) {
    val store = AgentTaskBudgetStore(this)
    store.save(
        transform(store.load())
            .copy(profile = AgentTaskBudgetProfile.CUSTOM)
            .normalized()
    )
    showTaskBudgetSettingsPage()
}

internal fun MainActivity.editTaskBudgetTime() {
    val budget = AgentTaskBudgetStore(this).load()
    val minutes = if (budget.maxElapsedSeconds == 0L) {
        "0"
    } else {
        String.format(Locale.US, "%.2f", budget.maxElapsedSeconds / 60.0)
            .trimEnd('0')
            .trimEnd('.')
    }
    showTextSettingDialog(getString(R.string.cc_task_budget_time_dialog), minutes) { raw ->
        val value = raw.trim().toDoubleOrNull()
        if (value == null || value < 0.0) {
            Toast.makeText(this, R.string.cc_task_budget_invalid_value, Toast.LENGTH_SHORT).show()
        } else {
            updateTaskBudget {
                it.copy(maxElapsedSeconds = (value * 60.0).toLong())
            }
        }
    }
}

internal fun MainActivity.editTaskBudgetCost() {
    val budget = AgentTaskBudgetStore(this).load()
    val dollars = if (budget.maxCostMicros == 0L) {
        "0"
    } else {
        String.format(Locale.US, "%.6f", budget.maxCostMicros / 1_000_000.0)
            .trimEnd('0')
            .trimEnd('.')
    }
    showTextSettingDialog(getString(R.string.cc_task_budget_cost_dialog), dollars) { raw ->
        val value = raw.trim().toDoubleOrNull()
        if (value == null || value < 0.0) {
            Toast.makeText(this, R.string.cc_task_budget_invalid_value, Toast.LENGTH_SHORT).show()
        } else {
            updateTaskBudget {
                it.copy(maxCostMicros = (value * 1_000_000.0).toLong())
            }
        }
    }
}

internal fun MainActivity.editTaskBudgetLong(
    titleRes: Int,
    current: Long,
    transform: (AgentTaskBudget, Long) -> AgentTaskBudget
) {
    showTextSettingDialog(getString(titleRes), current.toString()) { raw ->
        val value = raw.trim().toLongOrNull()
        if (value == null || value < 0L) {
            Toast.makeText(this, R.string.cc_task_budget_invalid_value, Toast.LENGTH_SHORT).show()
        } else {
            updateTaskBudget { transform(it, value) }
        }
    }
}

internal fun MainActivity.editTaskBudgetMib(
    titleRes: Int,
    currentBytes: Long,
    transform: (AgentTaskBudget, Long) -> AgentTaskBudget
) {
    val currentMib = if (currentBytes <= 0L) 0L else currentBytes / AgentTaskBudget.MIB
    showTextSettingDialog(getString(titleRes), currentMib.toString()) { raw ->
        val value = raw.trim().toLongOrNull()
        if (value == null || value < 0L) {
            Toast.makeText(this, R.string.cc_task_budget_invalid_value, Toast.LENGTH_SHORT).show()
        } else {
            updateTaskBudget {
                transform(
                    it,
                    if (value > Long.MAX_VALUE / AgentTaskBudget.MIB) {
                        Long.MAX_VALUE
                    } else {
                        value * AgentTaskBudget.MIB
                    }
                )
            }
        }
    }
}

internal fun MainActivity.showTaskBudgetNetworkPolicyDialog() {
    val current = AgentTaskBudgetStore(this).load().networkPolicy
    val policies = AgentTaskNetworkPolicy.entries
    val labels = policies.map(::taskBudgetNetworkPolicyLabel)
    showChoiceDialog(
        getString(R.string.cc_task_budget_network_policy_title),
        labels,
        taskBudgetNetworkPolicyLabel(current)
    ) { selected ->
        policies.getOrNull(labels.indexOf(selected))?.let { policy ->
            updateTaskBudget { it.copy(networkPolicy = policy) }
        }
    }
}

internal fun MainActivity.taskBudgetProfileLabel(profile: AgentTaskBudgetProfile): String = getString(
    when (profile) {
        AgentTaskBudgetProfile.ADAPTIVE -> R.string.cc_task_budget_profile_adaptive
        AgentTaskBudgetProfile.FAST -> R.string.cc_task_budget_profile_fast
        AgentTaskBudgetProfile.ECONOMY -> R.string.cc_task_budget_profile_economy
        AgentTaskBudgetProfile.PRIVATE -> R.string.cc_task_budget_profile_private
        AgentTaskBudgetProfile.CUSTOM -> R.string.cc_task_budget_profile_custom
    }
)

internal fun MainActivity.taskBudgetProfileDescription(profile: AgentTaskBudgetProfile): String = getString(
    when (profile) {
        AgentTaskBudgetProfile.ADAPTIVE -> R.string.cc_task_budget_profile_adaptive_subtitle
        AgentTaskBudgetProfile.FAST -> R.string.cc_task_budget_profile_fast_subtitle
        AgentTaskBudgetProfile.ECONOMY -> R.string.cc_task_budget_profile_economy_subtitle
        AgentTaskBudgetProfile.PRIVATE -> R.string.cc_task_budget_profile_private_subtitle
        AgentTaskBudgetProfile.CUSTOM -> R.string.cc_task_budget_profile_custom_subtitle
    }
)

internal fun MainActivity.taskBudgetNetworkPolicyLabel(policy: AgentTaskNetworkPolicy): String = getString(
    when (policy) {
        AgentTaskNetworkPolicy.ANY -> R.string.cc_task_budget_network_any
        AgentTaskNetworkPolicy.UNMETERED_ONLY -> R.string.cc_task_budget_network_unmetered
        AgentTaskNetworkPolicy.TRUSTED_ONLY -> R.string.cc_task_budget_network_trusted
        AgentTaskNetworkPolicy.OFFLINE_ONLY -> R.string.cc_task_budget_network_offline
    }
)

internal fun MainActivity.taskBudgetTimeValue(seconds: Long): String = when {
    seconds <= 0L -> getString(R.string.cc_task_budget_unlimited)
    seconds % 3_600L == 0L -> getString(
        R.string.cc_task_budget_hours_value,
        seconds / 3_600L
    )
    else -> getString(R.string.cc_task_budget_minutes_value, (seconds + 59L) / 60L)
}

internal fun MainActivity.taskBudgetCostValue(micros: Long): String =
    if (micros <= 0L) {
        getString(R.string.cc_task_budget_unlimited)
    } else {
        String.format(Locale.US, "$%.2f", micros / 1_000_000.0)
    }

internal fun MainActivity.taskBudgetCountValue(value: Long): String =
    if (value <= 0L) getString(R.string.cc_task_budget_unlimited)
    else String.format(Locale.US, "%,d", value)

internal fun MainActivity.taskBudgetNetworkBytesValue(value: Long): String =
    if (value <= 0L) getString(R.string.cc_task_budget_unlimited)
    else formatBytes(value)

internal fun MainActivity.taskBudgetMemoryBytesValue(value: Long): String =
    if (value <= 0L) getString(R.string.cc_task_budget_system_managed)
    else formatBytes(value)

internal fun MainActivity.showAgentPlannerSettingsPage() {
    val settings = mobileNativeAgent.modelPlannerSettings()
    val sources = configuredAgentPlannerSources()
    val plannerReady = !settings.enabled || sources.isNotEmpty()
    showControlCenterFeature(
        getString(R.string.cc_planner_settings_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                getString(if (settings.enabled) R.string.on_device_agent_model_planner else R.string.cc_planner_local_title),
                getString(
                    when {
                        !settings.enabled -> R.string.cc_planner_local_subtitle
                        plannerReady -> R.string.cc_planner_ready_subtitle
                        else -> R.string.cc_planner_needs_model_subtitle
                    }
                ),
                R.drawable.ic_agent_control,
                if (plannerReady) ControlCenterTone.BLUE else ControlCenterTone.AMBER
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.on_device_agent_section_intelligence),
                    listOf(
                        ControlCenterRowSpec("agent.planner.toggle_enabled", getString(R.string.on_device_agent_model_planner), getString(R.string.on_device_agent_model_planner_subtitle), R.drawable.ic_agent_node, switchValue = settings.enabled, showChevron = false),
                        ControlCenterRowSpec(if (sources.isEmpty()) "routing.add_cloud" else "agent.planner.model_source", getString(R.string.on_device_agent_model_source), getString(R.string.on_device_agent_model_source_subtitle), R.drawable.ic_protocol_link, if (sources.isEmpty()) getString(R.string.status_needs_setup) else agentModelPlannerSourceLabel(settings.cloudContactId), if (plannerReady) ControlCenterTone.BLUE else ControlCenterTone.AMBER),
                        ControlCenterRowSpec("agent.planner.toggle_replanning", getString(R.string.on_device_agent_dynamic_replanning), getString(R.string.on_device_agent_dynamic_replanning_subtitle), R.drawable.ic_agent_control, switchValue = settings.dynamicReplanning, showChevron = false),
                        ControlCenterRowSpec("agent.planner.max_replans", getString(R.string.on_device_agent_max_replans), getString(R.string.on_device_agent_max_replans_subtitle), R.drawable.ic_reset_data, settings.maxReplans.toString(), ControlCenterTone.BLUE),
                        ControlCenterRowSpec("agent.planner.toggle_multi_agent", getString(R.string.on_device_agent_multi_agent_coordination), getString(R.string.on_device_agent_multi_agent_coordination_subtitle), R.drawable.ic_protocol_link, switchValue = settings.multiAgentCoordination, showChevron = false)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_task_control),
                    listOf(
                        ControlCenterRowSpec("agent.planner.max_actions", getString(R.string.on_device_agent_model_max_actions), getString(R.string.on_device_agent_model_max_actions_subtitle), R.drawable.ic_agent_history, settings.maxActions.toString(), ControlCenterTone.BLUE),
                        ControlCenterRowSpec("agent.planner.max_tools", getString(R.string.on_device_agent_max_tool_calls), getString(R.string.on_device_agent_max_tool_calls_subtitle), R.drawable.ic_agent_control, settings.maxToolCalls.toString(), ControlCenterTone.VIOLET),
                        ControlCenterRowSpec("agent.planner.max_hops", getString(R.string.on_device_agent_max_agent_hops), getString(R.string.on_device_agent_max_agent_hops_subtitle), R.drawable.ic_protocol_link, settings.maxAgentHops.toString(), ControlCenterTone.AMBER),
                        ControlCenterRowSpec("agent.planner.max_iterations", getString(R.string.on_device_agent_max_loop_iterations), getString(R.string.on_device_agent_max_loop_iterations_subtitle), R.drawable.ic_reset_data, settings.maxLoopIterations.toString(), ControlCenterTone.BLUE),
                        ControlCenterRowSpec("agent.planner.max_retries", getString(R.string.on_device_agent_max_phase_retries), getString(R.string.on_device_agent_max_phase_retries_subtitle), R.drawable.ic_agent_history, settings.maxPhaseRetries.toString(), ControlCenterTone.AMBER),
                        ControlCenterRowSpec(
                            "agent.planner.no_progress_timeout",
                            getString(R.string.on_device_agent_no_progress_timeout),
                            getString(R.string.on_device_agent_no_progress_timeout_subtitle),
                            R.drawable.ic_agent_control,
                            if (settings.noProgressTimeoutSeconds % 60 == 0) {
                                getString(
                                    R.string.on_device_agent_no_progress_minutes,
                                    settings.noProgressTimeoutSeconds / 60
                                )
                            } else {
                                getString(
                                    R.string.on_device_agent_no_progress_seconds,
                                    settings.noProgressTimeoutSeconds
                                )
                            },
                            ControlCenterTone.VIOLET
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_privacy_boundary),
                    listOf(
                        ControlCenterRowSpec("agent.planner.toggle_screen_text", getString(R.string.on_device_agent_model_screen_text), getString(R.string.on_device_agent_model_screen_text_subtitle), R.drawable.ic_scan, switchValue = settings.shareScreenText, showChevron = false),
                        ControlCenterRowSpec("agent.planner.toggle_share_outputs", getString(R.string.on_device_agent_share_agent_outputs), getString(R.string.on_device_agent_share_agent_outputs_subtitle), R.drawable.ic_security_shield, switchValue = settings.shareAgentOutputsWithPlanner, showChevron = false)
                    )
                )
            )
        )
    )
}

internal fun MainActivity.renderControlCenterExecutionPolicyPage() {
    val safety = mobileNativeAgent.safetySettings()
    val taskBudget = AgentTaskBudgetStore(this).load()
    val planner = mobileNativeAgent.modelPlannerSettings()
    val privacyProtected = !planner.shareScreenText && !planner.shareAgentOutputsWithPlanner
    val notificationsEnabled = appNotificationsEnabled()
    showControlCenterFeature(
        getString(R.string.cc_execution_policy_title),
        ControlCenterPageSpec(
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_task_control),
                    listOf(
                        ControlCenterRowSpec("agent.task_execution_mode", getString(R.string.cc_task_execution_mode_title), getString(R.string.cc_task_execution_mode_subtitle), R.drawable.ic_agent_control, taskExecutionModeLabel(safety.taskExecutionMode), ControlCenterTone.GREEN),
                        ControlCenterRowSpec("", getString(R.string.cc_max_concurrency_title), getString(R.string.cc_max_concurrency_subtitle), R.drawable.ic_agent_history, "3 + 1", ControlCenterTone.BLUE, showChevron = false),
                        ControlCenterRowSpec("agent.planner", getString(R.string.cc_tool_budget_title), getString(R.string.cc_tool_budget_subtitle), R.drawable.ic_agent_control, planner.maxToolCalls.toString(), ControlCenterTone.VIOLET),
                        ControlCenterRowSpec("general.notifications", getString(R.string.cc_long_task_notifications_title), getString(R.string.cc_long_task_notifications_subtitle), R.drawable.ic_settings_notification, getString(if (notificationsEnabled) R.string.status_enabled else R.string.status_needs_setup), if (notificationsEnabled) ControlCenterTone.GREEN else ControlCenterTone.AMBER)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_privacy_boundary),
                    listOf(ControlCenterRowSpec("agent.planner", getString(R.string.cc_sensitive_local_title), getString(R.string.cc_sensitive_local_subtitle), R.drawable.ic_security_shield, getString(if (privacyProtected) R.string.status_enabled else R.string.cc_status_review), if (privacyProtected) ControlCenterTone.GREEN else ControlCenterTone.AMBER))
                )
            )
        )
    )
}

internal fun MainActivity.renderControlCenterRoutingPage() {
    val targets = controlCenterResourceTargets(mobileNativeAgent.snapshot().callableTargets)
    val registrations = mobileNativeAgent.agentRegistrySnapshot()
    val available = targets.count { it.status == AgentConnectorStatus.AVAILABLE }
    val resourceRows = targets
        .filterNot { it.id == "phone" || it.id == "local-system" }
        .distinctBy { it.id }
        .sortedWith(compareBy<AgentCallableTarget> { it.status != AgentConnectorStatus.AVAILABLE }.thenBy { it.title.lowercase(Locale.ROOT) })
        .take(12)
        .map { target -> controlCenterTargetRow(target, findAgentRegistration(registrations, target.id)) }
    showControlCenterFeature(
        getString(R.string.cc_resource_routing_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = if (available > 0) getString(R.string.cc_routing_enabled) else getString(R.string.cc_no_resources_title),
                subtitle = if (available > 0) getString(R.string.cc_routing_enabled_subtitle) else getString(R.string.cc_no_resources_subtitle),
                iconRes = R.drawable.ic_settings_model,
                tone = if (available > 0) ControlCenterTone.BLUE else ControlCenterTone.AMBER
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_current_strategy),
                    listOf(ControlCenterRowSpec("routing.policy", getString(R.string.cc_balanced_strategy_title), getString(R.string.cc_balanced_strategy_subtitle), R.drawable.ic_agent_control, getString(R.string.cc_status_automatic), ControlCenterTone.BLUE))
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_available_resources),
                    resourceRows.ifEmpty {
                        listOf(ControlCenterRowSpec("routing.add_cloud", getString(R.string.cc_add_cloud_provider_title), getString(R.string.cc_add_cloud_provider_subtitle), R.drawable.ic_avatar_cloud_model, getString(R.string.common_next_step), ControlCenterTone.AMBER))
                    }
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_rules),
                    listOf(
                        ControlCenterRowSpec("routing.policy", getString(R.string.cc_route_by_task_title), getString(R.string.cc_route_by_task_subtitle), R.drawable.ic_protocol_link, getString(R.string.common_view), ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("routing.add_cloud", getString(R.string.cc_add_cloud_provider_title), getString(R.string.cc_add_cloud_provider_subtitle), R.drawable.ic_avatar_cloud_model, "+", ControlCenterTone.VIOLET),
                        ControlCenterRowSpec("routing.manage", getString(R.string.cc_nodes_title), getString(R.string.cc_nodes_subtitle), R.drawable.ic_agent_node, "", ControlCenterTone.BLUE)
                    )
                )
            )
        )
    )
}

internal fun MainActivity.showRoutingPolicyPage() {
    showControlCenterFeature(
        getString(R.string.cc_route_by_task_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                getString(R.string.cc_routing_policy_banner_title),
                getString(R.string.cc_routing_policy_banner_subtitle),
                R.drawable.ic_agent_control,
                ControlCenterTone.BLUE
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_current_strategy),
                    listOf(
                        routingPolicyInfoRow(R.string.cc_routing_balanced_title, R.string.cc_routing_balanced_subtitle, ControlCenterTone.BLUE),
                        routingPolicyInfoRow(R.string.cc_routing_fast_title, R.string.cc_routing_fast_subtitle, ControlCenterTone.GREEN),
                        routingPolicyInfoRow(R.string.cc_routing_economy_title, R.string.cc_routing_economy_subtitle, ControlCenterTone.AMBER),
                        routingPolicyInfoRow(R.string.cc_routing_quality_title, R.string.cc_routing_quality_subtitle, ControlCenterTone.VIOLET),
                        routingPolicyInfoRow(R.string.cc_routing_private_title, R.string.cc_routing_private_subtitle, ControlCenterTone.NEUTRAL)
                    )
                )
            )
        )
    )
}

internal fun MainActivity.routingPolicyInfoRow(title: Int, subtitle: Int, tone: ControlCenterTone) =
    ControlCenterRowSpec(
        actionId = "",
        title = getString(title),
        subtitle = getString(subtitle),
        iconRes = R.drawable.ic_protocol_link,
        tone = tone,
        showChevron = false
    )

internal fun MainActivity.controlCenterTargetSubtitle(target: AgentCallableTarget): String {
    val capabilities = target.capabilities.take(3).joinToString(" · ") {
        controlCenterCapabilityLabel(it)
    }
    return capabilities.ifBlank { controlCenterTargetKindLabel(target.kind) }
}

internal fun MainActivity.controlCenterResourceTargets(
    targets: List<AgentCallableTarget>
): List<AgentCallableTarget> = targets.filterNot { target ->
    target.id == "cloud-models"
}

internal fun MainActivity.controlCenterCapabilityLabel(capability: AgentCapability): String = getString(
    when (capability) {
        AgentCapability.CHAT -> R.string.cc_capability_chat
        AgentCapability.REASONING -> R.string.cc_capability_reasoning
        AgentCapability.LIVE_DATA -> R.string.cc_capability_live_data
        AgentCapability.TOOL_USE -> R.string.cc_capability_tool_use
        AgentCapability.MCP -> R.string.cc_capability_mcp
        AgentCapability.SKILL -> R.string.cc_capability_skill
        AgentCapability.LOCAL_INFERENCE -> R.string.cc_capability_local_inference
        AgentCapability.RESEARCH -> R.string.cc_capability_research
        AgentCapability.CODE -> R.string.cc_capability_code
        AgentCapability.TASK_EXECUTION -> R.string.cc_capability_task_execution
        AgentCapability.SMART_HOME -> R.string.cc_capability_smart_home
        AgentCapability.DEVICE_CONTROL -> R.string.cc_capability_device_control
        AgentCapability.KNOWLEDGE_SEARCH -> R.string.cc_capability_knowledge_search
        AgentCapability.SCREEN_READING -> R.string.cc_capability_screen_reading
        AgentCapability.CLIPBOARD -> R.string.cc_capability_clipboard
        AgentCapability.SYSTEM_SETTINGS -> R.string.cc_capability_system_settings
        AgentCapability.APP_NAVIGATION -> R.string.cc_capability_app_navigation
        AgentCapability.ALARM -> R.string.cc_capability_alarm
    }
)

internal fun MainActivity.controlCenterTargetKindLabel(kind: AgentConnectorKind): String = getString(
    when (kind) {
        AgentConnectorKind.MODEL -> R.string.cc_kind_model
        AgentConnectorKind.AGENT -> R.string.cc_kind_agent
        AgentConnectorKind.DEVICE -> R.string.cc_kind_device
        AgentConnectorKind.KNOWLEDGE -> R.string.cc_kind_knowledge
    }
)

internal fun MainActivity.controlCenterTargetStatus(status: AgentConnectorStatus): String = getString(
    when (status) {
        AgentConnectorStatus.AVAILABLE -> R.string.cc_status_available
        AgentConnectorStatus.NEEDS_SETUP -> R.string.status_needs_setup
        AgentConnectorStatus.DISCONNECTED -> R.string.status_disconnected
    }
)

internal fun MainActivity.controlCenterTargetTone(status: AgentConnectorStatus): ControlCenterTone = when (status) {
    AgentConnectorStatus.AVAILABLE -> ControlCenterTone.GREEN
    AgentConnectorStatus.NEEDS_SETUP -> ControlCenterTone.AMBER
    AgentConnectorStatus.DISCONNECTED -> ControlCenterTone.NEUTRAL
}

internal fun MainActivity.controlCenterAgentStatus(status: AgentEndpointStatus): String = getString(
    when (status) {
        AgentEndpointStatus.ONLINE -> R.string.status_online
        AgentEndpointStatus.IDLE -> R.string.cc_agent_status_idle
        AgentEndpointStatus.BUSY -> R.string.cc_agent_status_busy
        AgentEndpointStatus.DEGRADED -> R.string.cc_status_degraded
        AgentEndpointStatus.UPDATING -> R.string.cc_agent_status_updating
        AgentEndpointStatus.PERMISSION_REQUIRED -> R.string.status_needs_setup
        AgentEndpointStatus.OFFLINE -> R.string.status_disconnected
        AgentEndpointStatus.UNREACHABLE -> R.string.cc_agent_status_unreachable
    }
)

internal fun MainActivity.controlCenterAgentTone(status: AgentEndpointStatus): ControlCenterTone = when (status) {
    AgentEndpointStatus.ONLINE, AgentEndpointStatus.IDLE -> ControlCenterTone.GREEN
    AgentEndpointStatus.BUSY, AgentEndpointStatus.PERMISSION_REQUIRED -> ControlCenterTone.AMBER
    AgentEndpointStatus.UPDATING -> ControlCenterTone.BLUE
    AgentEndpointStatus.DEGRADED, AgentEndpointStatus.UNREACHABLE -> ControlCenterTone.RED
    AgentEndpointStatus.OFFLINE -> ControlCenterTone.NEUTRAL
}

internal fun MainActivity.controlCenterAgentBadges(
    presentation: AgentIdentityPresentation
): List<ControlCenterBadgeSpec> {
    val capabilityBadges = presentation.capabilities.take(2).mapIndexed { index, capability ->
        ControlCenterBadgeSpec(
            controlCenterCapabilityLabel(capability),
            if (index == 0) ControlCenterTone.BLUE else ControlCenterTone.VIOLET
        )
    }
    val executionBadge = ControlCenterBadgeSpec(
        getString(
            R.string.cc_agent_cost_latency,
            controlCenterAgentCost(presentation.cost),
            controlCenterAgentLatency(presentation.latency)
        ),
        ControlCenterTone.NEUTRAL
    )
    return capabilityBadges + executionBadge
}

internal fun MainActivity.controlCenterAgentCost(cost: AgentResourceCost): String = getString(
    when (cost) {
        AgentResourceCost.FREE -> R.string.cc_agent_cost_free
        AgentResourceCost.LOW -> R.string.cc_agent_cost_low
        AgentResourceCost.MEDIUM -> R.string.cc_agent_cost_medium
        AgentResourceCost.HIGH -> R.string.cc_agent_cost_high
    }
)

internal fun MainActivity.controlCenterAgentLatency(latency: AgentResourceLatency): String = getString(
    when (latency) {
        AgentResourceLatency.INSTANT -> R.string.cc_agent_latency_instant
        AgentResourceLatency.FAST -> R.string.cc_agent_latency_fast
        AgentResourceLatency.NORMAL -> R.string.cc_agent_latency_normal
        AgentResourceLatency.SLOW -> R.string.cc_agent_latency_slow
    }
)

internal fun MainActivity.controlCenterAgentAvatar(style: AgentAvatarStyle): Int = when (style) {
    AgentAvatarStyle.CODEX -> R.drawable.logo_codex_product
    AgentAvatarStyle.CLAUDE -> R.drawable.logo_claude_code
    AgentAvatarStyle.HERMES -> R.drawable.hermes_logo
    AgentAvatarStyle.OPENCLAW -> R.drawable.ic_avatar_custom_agent
    AgentAvatarStyle.LOCAL_MODEL -> R.drawable.ic_local_model
    AgentAvatarStyle.CLOUD_MODEL -> R.drawable.ic_avatar_cloud_model
    AgentAvatarStyle.DEVICE -> R.drawable.ic_device_node
    AgentAvatarStyle.GENERIC -> R.drawable.ic_agent_node
}

internal fun MainActivity.findAgentRegistration(
    registrations: List<AgentRegistration>,
    targetId: String
): AgentRegistration? = registrations.firstOrNull { it.agentId == targetId }
    ?: registrations.firstOrNull {
        it.agentId.endsWith(":$targetId") || targetId.endsWith(":${it.agentId}")
    }

internal fun MainActivity.controlCenterTargetIcon(target: AgentCallableTarget): Int = when {
    target.id.contains("codex", true) -> R.drawable.logo_codex_product
    target.id.contains("claude", true) -> R.drawable.logo_claude_code
    target.id.contains("hermes", true) -> R.drawable.hermes_logo
    target.kind == AgentConnectorKind.MODEL && target.id.startsWith("cloud:") -> R.drawable.ic_avatar_cloud_model
    target.kind == AgentConnectorKind.MODEL -> R.drawable.ic_local_model
    target.kind == AgentConnectorKind.DEVICE -> R.drawable.ic_device_node
    else -> R.drawable.ic_agent_node
}

internal fun MainActivity.showControlCenterTarget(targetId: String) {
    val target = mobileNativeAgent.snapshot().callableTargets.firstOrNull { it.id == targetId }
    if (target == null) {
        openExistingControlCenterPage { showAgentFeaturePage() }
        return
    }
    when {
        target.id.startsWith("cloud:") -> openExistingControlCenterPage {
            showCloudModelPage(target.id.substringAfter("cloud:"))
        }
        AppStore.contactById(this, target.id) != null -> openExistingControlCenterPage {
            showContactDetail(contactById(target.id))
        }
        else -> openExistingControlCenterPage {
            showFeatureItemPage(
                target.title,
                controlCenterTargetSubtitle(target),
                controlCenterTargetIcon(target),
                controlCenterTargetStatus(target.status)
            )
        }
    }
}
