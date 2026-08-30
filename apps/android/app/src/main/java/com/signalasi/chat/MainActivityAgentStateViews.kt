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

internal fun MainActivity.agentFeatureRow(agent: AgentUi): View {
    val identity = agent.identity
    val statusText = identity?.let { controlCenterAgentStatus(it.status) }
        ?: if (agent.connected) agent.badge else getString(R.string.status_disconnected)
    val statusColor = identity?.let { agentEndpointStatusColor(it.status) }
        ?: Color.parseColor(agent.badgeColor)
    val icon = identity?.let { controlCenterAgentAvatar(it.avatarStyle) } ?: agent.iconRes
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        isClickable = true
        isFocusable = true
        setPadding(dp(14), dp(12), dp(14), dp(12))
        background = getDrawable(R.drawable.glass_card_background)
        addView(featureIcon(icon, statusColor))
        addView(LinearLayout(this@agentFeatureRow).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(13), 0, 0, 0)
            addView(TextView(this@agentFeatureRow).apply {
                text = identity?.displayName ?: agent.title
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 16f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            })
            addView(TextView(this@agentFeatureRow).apply {
                text = agent.subtitle
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 12.5f
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
            })
            identity?.let { presentation ->
                addView(agentIdentityBadgeRow(presentation))
            }
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        addView(TextView(this@agentFeatureRow).apply {
            text = statusText
            gravity = Gravity.CENTER
            setTextColor(statusColor)
            textSize = 12f
            maxLines = 2
        }, LinearLayout.LayoutParams(dp(62), dp(42)))
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(if (identity == null) 76 else 94)
        ).apply { bottomMargin = dp(10) }
        setOnClickListener {
            if (agent.connected) {
                showContactDetail(contactById(agent.contactId))
            } else {
                showFeatureItemPage(agent.title, agent.subtitle, agent.iconRes, getString(R.string.common_connect))
            }
        }
    }
}

internal fun MainActivity.agentIdentityBadgeRow(presentation: AgentIdentityPresentation): LinearLayout =
    LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(0, dp(6), 0, 0)
        val badges = controlCenterAgentBadges(presentation)
        badges.take(3).forEachIndexed { index, badge ->
            val color = when (badge.tone) {
                ControlCenterTone.BLUE -> Color.parseColor("#286FD6")
                ControlCenterTone.VIOLET -> Color.parseColor("#7052CC")
                else -> Color.parseColor("#667085")
            }
            addView(
                statusPill(badge.text, color).apply {
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    maxWidth = dp(if (index == 2) 112 else 88)
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    dp(21)
                ).apply {
                    if (index > 0) marginStart = dp(5)
                }
            )
        }
    }

internal fun MainActivity.agentEndpointStatusColor(status: AgentEndpointStatus): Int = Color.parseColor(
    when (status) {
        AgentEndpointStatus.ONLINE, AgentEndpointStatus.IDLE -> "#14875A"
        AgentEndpointStatus.BUSY, AgentEndpointStatus.PERMISSION_REQUIRED -> "#B26B00"
        AgentEndpointStatus.UPDATING -> "#286FD6"
        AgentEndpointStatus.DEGRADED, AgentEndpointStatus.UNREACHABLE -> "#C7372F"
        AgentEndpointStatus.OFFLINE -> "#667085"
    }
)

internal fun MainActivity.dynamicConnectorAgents(excludeIds: Set<String>): List<AgentUi> {
    val contacts = AppStore.contacts(this)
    val items = mutableListOf<AgentUi>()
    for (i in 0 until contacts.length()) {
        val raw = contacts.optJSONObject(i) ?: continue
        if (raw.optBoolean("deleted", false) || raw.optString("trust_state") == "deleted") continue
        val id = raw.optString("id").ifBlank { jsonSignalasiId(raw) }
        if (id.isBlank() || id in excludeIds) continue
        val isPcConnector = raw.optString("delivery_mode") == "pc_connector" ||
            raw.optString("parent_contact") == "hermes" ||
            raw.optString("signal_session") == "pc_tunnel"
        if (!isPcConnector) continue
        val setupStatus = raw.optString("setup_status")
        val connected = raw.optString("trust_state") != "deleted"
        val badge = when (setupStatus) {
            "ready" -> getString(R.string.status_ready)
            "needs_setup" -> getString(R.string.status_needs_setup)
            else -> if (connected) getString(R.string.common_paired) else getString(R.string.status_pending_connection)
        }
        val color = when (setupStatus) {
            "ready" -> "#14C66A"
            "needs_setup" -> "#F0A500"
            else -> colorForAgentKind(raw.optString("agent_kind"))
        }
        val subtitle = raw.optString("setup_detail").ifBlank {
            raw.optString("setup_next_step").ifBlank {
                when (raw.optString("agent_kind")) {
                    "local-cli" -> getString(R.string.agent_connector_local_cli)
                    "local-model" -> getString(R.string.agent_connector_local_model)
                    "cloud-model" -> getString(R.string.agent_connector_cloud_model)
                    else -> getString(R.string.agent_connector_custom)
                }
            }
        }
        items.add(AgentUi(
            id,
            raw.optString("name", id),
            subtitle,
            iconForAgentKind(id, raw.optString("agent_kind")),
            badge,
            color,
            connected
        ))
    }
    return items.sortedWith(compareBy<AgentUi> { contactPriority(it.contactId) }.thenBy { it.title.lowercase(Locale.getDefault()) })
}

internal fun MainActivity.iconForAgentKind(id: String, kind: String): Int = when {
    agentIdFromContactId(id) == "custom-agent" || kind == "custom-cli" -> R.drawable.ic_avatar_custom_agent
    agentIdFromContactId(id) == "local-llm" || kind == "local-model" -> R.drawable.ic_avatar_custom_agent
    kind == "cloud-model" -> R.drawable.ic_avatar_custom_agent
    kind == "local-cli" -> R.drawable.ic_agent_node
    else -> R.drawable.ic_agent_node
}

internal fun MainActivity.colorForAgentKind(kind: String): String = when (kind) {
    "local-model" -> "#00A7A7"
    "cloud-model" -> "#5B6CFF"
    "local-cli" -> "#5B6CFF"
    else -> "#6C7A89"
}

internal fun MainActivity.localModelHeaderCard(): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(14), dp(16), dp(14))
        background = getDrawable(R.drawable.glass_card_background)
        addView(featureIcon(R.drawable.ic_local_model, Color.parseColor("#00A7A7")))
        addView(LinearLayout(this@localModelHeaderCard).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
            addView(TextView(this@localModelHeaderCard).apply {
                text = "MiniCPM-V 2.6"
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 17f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            })
            addView(TextView(this@localModelHeaderCard).apply {
                text = getString(R.string.agent_new_connection_subtitle)
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 12.5f
            })
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        addView(statusPill(getString(R.string.status_online), getColorCompat(R.color.signalasi_green)))
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(86)
        ).apply { bottomMargin = dp(14) }
    }
}

internal fun MainActivity.localModelStatusCard(
    profile: LocalModelRuntimeProfile,
    estimate: LocalModelRuntimeEstimate
): View {
    val readinessColor = when (estimate.readiness) {
        LocalModelRuntimeReadiness.READY -> getColorCompat(R.color.signalasi_green)
        LocalModelRuntimeReadiness.CAUTION -> Color.parseColor("#D48B18")
        LocalModelRuntimeReadiness.BLOCKED -> Color.parseColor("#D14343")
    }
    val memoryProgress = if (estimate.safeMemoryBudgetBytes > 0L) {
        ((estimate.totalRequiredBytes * 100L) / estimate.safeMemoryBudgetBytes)
            .coerceIn(0L, 100L)
            .toInt()
    } else {
        100
    }
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(16), dp(14), dp(16), dp(14))
        background = getDrawable(R.drawable.glass_card_background)
        addView(LinearLayout(this@localModelStatusCard).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(TextView(this@localModelStatusCard).apply {
                text = getString(R.string.local_model_status_title)
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 15.5f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(statusPill(localModelReadinessLabel(estimate.readiness), readinessColor))
        })
        addView(TextView(this@localModelStatusCard).apply {
            text = localModelPreflightSummary(estimate)
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 12.5f
            setPadding(0, dp(7), 0, 0)
        })
        addView(localModelMetric(
            profile.displayName,
            getString(R.string.local_model_memory_usage),
            getString(
                R.string.local_model_memory_required_value,
                formatBytes(estimate.totalRequiredBytes),
                formatBytes(estimate.safeMemoryBudgetBytes)
            ),
            memoryProgress,
            readinessColor
        ))
        addView(localModelMetric(
            getString(R.string.local_model_kv_cache),
            getString(R.string.local_model_context_tokens, estimate.recommendedContextTokens),
            formatBytes(estimate.kvCacheBytes),
            ((estimate.recommendedContextTokens * 100L) /
                estimate.requestedContextTokens.coerceAtLeast(1)).coerceIn(0L, 100L).toInt(),
            readinessColor
        ))
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(14) }
    }
}

internal fun MainActivity.localModelMetric(
    left: String,
    middle: String,
    right: String,
    progress: Int,
    progressColor: Int = getColorCompat(R.color.signalasi_green)
): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, dp(10), 0, 0)
        addView(LinearLayout(this@localModelMetric).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(TextView(this@localModelMetric).apply {
                text = left
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 12.5f
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            if (middle.isNotBlank()) {
                addView(TextView(this@localModelMetric).apply {
                    text = middle
                    setTextColor(getColorCompat(R.color.text_secondary))
                    textSize = 11.5f
                })
            }
            if (right.isNotBlank()) {
                addView(TextView(this@localModelMetric).apply {
                    text = right
                    setTextColor(getColorCompat(R.color.text_secondary))
                    textSize = 11.5f
                    setPadding(dp(6), 0, 0, 0)
                })
            }
        })
        addView(ProgressBar(this@localModelMetric, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            this.progress = progress
            progressTintList = android.content.res.ColorStateList.valueOf(progressColor)
            progressBackgroundTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#E5E7EB"))
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(5)
        ).apply { topMargin = dp(7) })
    }
}

internal fun MainActivity.localModelReadinessLabel(readiness: LocalModelRuntimeReadiness): String = getString(
    when (readiness) {
        LocalModelRuntimeReadiness.READY -> R.string.local_model_preflight_ready
        LocalModelRuntimeReadiness.CAUTION -> R.string.local_model_preflight_caution
        LocalModelRuntimeReadiness.BLOCKED -> R.string.local_model_preflight_blocked
    }
)

internal fun MainActivity.localModelPreflightSummary(estimate: LocalModelRuntimeEstimate): String {
    val issue = listOf(
        LocalModelRuntimeIssue.MODEL_FILE_MISSING,
        LocalModelRuntimeIssue.MODEL_FILE_INVALID,
        LocalModelRuntimeIssue.SYSTEM_LOW_MEMORY,
        LocalModelRuntimeIssue.INSUFFICIENT_MEMORY,
        LocalModelRuntimeIssue.ACCELERATOR_UNAVAILABLE,
        LocalModelRuntimeIssue.DEVICE_TOO_HOT,
        LocalModelRuntimeIssue.CRITICAL_BATTERY,
        LocalModelRuntimeIssue.CONTEXT_REDUCED,
        LocalModelRuntimeIssue.THERMAL_PRESSURE,
        LocalModelRuntimeIssue.LOW_BATTERY,
        LocalModelRuntimeIssue.POWER_SAVE_MODE
    ).firstOrNull(estimate.issues::contains)
    return getString(
        when (issue) {
            LocalModelRuntimeIssue.MODEL_FILE_MISSING ->
                R.string.local_model_issue_file_missing
            LocalModelRuntimeIssue.MODEL_FILE_INVALID ->
                R.string.local_model_issue_file_invalid
            LocalModelRuntimeIssue.SYSTEM_LOW_MEMORY ->
                R.string.local_model_issue_system_low_memory
            LocalModelRuntimeIssue.INSUFFICIENT_MEMORY ->
                R.string.local_model_issue_insufficient_memory
            LocalModelRuntimeIssue.ACCELERATOR_UNAVAILABLE ->
                R.string.local_model_issue_accelerator_unavailable
            LocalModelRuntimeIssue.DEVICE_TOO_HOT ->
                R.string.local_model_issue_device_hot
            LocalModelRuntimeIssue.CRITICAL_BATTERY ->
                R.string.local_model_issue_critical_battery
            LocalModelRuntimeIssue.CONTEXT_REDUCED ->
                R.string.local_model_issue_context_reduced
            LocalModelRuntimeIssue.THERMAL_PRESSURE ->
                R.string.local_model_issue_thermal_pressure
            LocalModelRuntimeIssue.LOW_BATTERY ->
                R.string.local_model_issue_low_battery
            LocalModelRuntimeIssue.POWER_SAVE_MODE ->
                R.string.local_model_issue_power_save
            null -> R.string.local_model_preflight_ready_detail
        },
        estimate.recommendedContextTokens
    )
}

internal fun MainActivity.localModelThermalValue(device: LocalModelDeviceSnapshot): String =
    device.batteryTemperatureCelsius?.let {
        String.format(Locale.US, "%.1f °C", it)
    } ?: getString(R.string.status_unknown)

internal fun MainActivity.localModelThermalDetail(device: LocalModelDeviceSnapshot): String = getString(
    when (device.thermalStatus) {
        0 -> R.string.local_model_thermal_none
        1 -> R.string.local_model_thermal_light
        2 -> R.string.local_model_thermal_moderate
        3 -> R.string.local_model_thermal_severe
        4 -> R.string.local_model_thermal_critical
        5 -> R.string.local_model_thermal_emergency
        6 -> R.string.local_model_thermal_shutdown
        else -> R.string.local_model_thermal_unknown
    }
)

internal fun MainActivity.localModelAcceleratorTitle(kind: LocalModelAcceleratorKind): String = getString(
    when (kind) {
        LocalModelAcceleratorKind.CPU -> R.string.local_model_accelerator_cpu
        LocalModelAcceleratorKind.GPU -> R.string.local_model_accelerator_gpu
        LocalModelAcceleratorKind.NNAPI -> R.string.local_model_accelerator_nnapi
        LocalModelAcceleratorKind.VENDOR_SDK -> R.string.local_model_accelerator_vendor
    }
)

internal fun MainActivity.localModelAcceleratorStatus(state: LocalModelAcceleratorState): String = getString(
    when (state) {
        LocalModelAcceleratorState.READY -> R.string.local_model_accelerator_ready
        LocalModelAcceleratorState.HARDWARE_ONLY ->
            R.string.local_model_accelerator_hardware_only
        LocalModelAcceleratorState.UNAVAILABLE ->
            R.string.local_model_accelerator_unavailable
    }
)

internal fun MainActivity.featureValueRow(title: String, subtitle: String, iconRes: Int, value: String): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), dp(10), dp(14), dp(10))
        background = getDrawable(R.drawable.glass_card_background)
        addView(featureIcon(iconRes, featureIconColor(iconRes)))
        addView(LinearLayout(this@featureValueRow).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), 0, 0, 0)
            addView(TextView(this@featureValueRow).apply {
                text = title
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 15f
            })
            if (subtitle.isNotBlank()) {
                addView(TextView(this@featureValueRow).apply {
                    text = subtitle
                    setTextColor(getColorCompat(R.color.text_secondary))
                    textSize = 12f
                })
            }
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        addView(TextView(this@featureValueRow).apply {
            text = value.ifBlank { "?" }
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = if (value.isBlank()) 22f else 12.5f
            gravity = Gravity.CENTER_VERTICAL or Gravity.END
            maxLines = 1
        }, LinearLayout.LayoutParams(dp(120), LinearLayout.LayoutParams.WRAP_CONTENT))
        minimumHeight = dp(64)
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(8) }
    }
}

internal fun MainActivity.featureSwitchRow(title: String, subtitle: String, iconRes: Int, checked: Boolean): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), dp(10), dp(14), dp(10))
        background = getDrawable(R.drawable.glass_card_background)
        addView(featureIcon(iconRes, featureIconColor(iconRes)))
        addView(LinearLayout(this@featureSwitchRow).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), 0, 0, 0)
            addView(TextView(this@featureSwitchRow).apply {
                text = title
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 15f
            })
            addView(TextView(this@featureSwitchRow).apply {
                text = subtitle
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 12f
            })
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        addView(switchPill(checked), LinearLayout.LayoutParams(dp(46), dp(26)))
        minimumHeight = dp(64)
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(8) }
    }
}

internal fun MainActivity.switchPill(checked: Boolean): View {
    return FrameLayout(this).apply {
        background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(13).toFloat()
            setColor(if (checked) getColorCompat(R.color.signalasi_green) else Color.parseColor("#D1D5DB"))
        }
        addView(View(this@switchPill).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
            }
        }, FrameLayout.LayoutParams(dp(22), dp(22)).apply {
            gravity = if (checked) Gravity.END or Gravity.CENTER_VERTICAL else Gravity.START or Gravity.CENTER_VERTICAL
            leftMargin = dp(2)
            rightMargin = dp(2)
        })
    }
}

internal fun MainActivity.featureStorageRow(): View {
    val storage = LocalModelManager.storage(this)
    val usedBytes = LocalModelManager.profiles(this).sumOf { profile ->
        storage.finalFile(profile).takeIf(File::isFile)?.length().orZero() +
            storage.partialFile(profile).takeIf(File::isFile)?.length().orZero()
    }
    val fileSystemTotal = filesDir.totalSpace.coerceAtLeast(1L)
    val fileSystemAvailable = filesDir.usableSpace.coerceAtLeast(0L)
    val progressPercent = (((fileSystemTotal - fileSystemAvailable).coerceAtLeast(0L) * 100L) /
        fileSystemTotal).toInt().coerceIn(0, 100)
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(14), dp(12), dp(14), dp(12))
        background = getDrawable(R.drawable.glass_card_background)
        addView(LinearLayout(this@featureStorageRow).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(TextView(this@featureStorageRow).apply {
                text = getString(R.string.local_model_storage_usage)
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 15f
            }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(TextView(this@featureStorageRow).apply {
                text = getString(
                    R.string.local_model_memory_required_value,
                    formatBytes(usedBytes),
                    formatBytes(fileSystemAvailable)
                )
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 12f
            })
        })
        addView(ProgressBar(this@featureStorageRow, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progress = progressPercent
            progressTintList = android.content.res.ColorStateList.valueOf(getColorCompat(R.color.signalasi_green))
            progressBackgroundTintList = android.content.res.ColorStateList.valueOf(Color.parseColor("#E5E7EB"))
        }, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(5)
        ).apply { topMargin = dp(8) })
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(8) }
    }
}

internal fun MainActivity.addSectionTitle(title: String) {
    featureContent.addView(TextView(this).apply {
        text = title
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 12f
        setPadding(dp(4), dp(4), 0, dp(7))
    }, LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT
    ))
}

internal fun MainActivity.featureHeroCard(title: String, subtitle: String, iconRes: Int, colorHex: String, badge: String): View {
    val color = Color.parseColor(colorHex)
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(16), dp(16), dp(16), dp(16))
        background = getDrawable(R.drawable.glass_card_background)
        addView(featureIcon(iconRes, color), LinearLayout.LayoutParams(dp(48), dp(48)))
        addView(LinearLayout(this@featureHeroCard).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), 0, 0, 0)
            addView(TextView(this@featureHeroCard).apply {
                text = title
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 17f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            })
            addView(TextView(this@featureHeroCard).apply {
                text = subtitle
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 12.5f
                setPadding(0, dp(3), 0, 0)
            })
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        addView(statusPill(badge, color))
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(92)
        ).apply { bottomMargin = dp(14) }
    }
}

internal fun MainActivity.featureRow(title: String, subtitle: String, iconRes: Int, action: String): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        isClickable = action.isNotBlank()
        isFocusable = action.isNotBlank()
        setPadding(dp(14), dp(10), dp(14), dp(10))
        background = getDrawable(R.drawable.glass_card_background)
        addView(featureIcon(iconRes, featureIconColor(iconRes)))
        addView(LinearLayout(this@featureRow).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), 0, 0, 0)
            addView(TextView(this@featureRow).apply {
                text = title
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 15.5f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            })
            if (subtitle.isNotBlank()) {
                addView(TextView(this@featureRow).apply {
                    text = subtitle
                    setTextColor(getColorCompat(R.color.text_secondary))
                    textSize = 12f
                })
            }
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        addView(TextView(this@featureRow).apply {
            text = action
            setTextColor(getColorCompat(R.color.signalasi_green))
            textSize = 13f
            gravity = Gravity.CENTER
            maxLines = 1
        }, LinearLayout.LayoutParams(dp(58), dp(34)))
        minimumHeight = dp(72)
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(9) }
        if (action.isNotBlank()) {
            setOnClickListener {
                if (action == getString(R.string.common_copy)) {
                    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText(title, subtitle))
                    Toast.makeText(this@featureRow, getString(R.string.toast_copied), Toast.LENGTH_SHORT).show()
                } else {
                    showFeatureItemPage(title, subtitle, iconRes, action)
                }
            }
        }
    }
}

internal fun MainActivity.modelSwitchRow(title: String, action: String, isSelected: Boolean): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        isClickable = true
        isFocusable = true
        setPadding(dp(14), dp(9), dp(14), dp(9))
        background = getDrawable(R.drawable.glass_card_background)
        addView(featureIcon(R.drawable.ic_protocol_link, featureIconColor(R.drawable.ic_protocol_link)), LinearLayout.LayoutParams(dp(44), dp(44)))
        addView(LinearLayout(this@modelSwitchRow).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), 0, dp(6), 0)
            addView(TextView(this@modelSwitchRow).apply {
                text = title
                setTextColor(getColorCompat(R.color.text_primary))
                textSize = 14.5f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            })
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        addView(TextView(this@modelSwitchRow).apply {
            text = action
            setTextColor(getColorCompat(if (isSelected) R.color.text_secondary else R.color.signalasi_green))
            textSize = 12f
            gravity = Gravity.CENTER
            maxLines = 1
        }, LinearLayout.LayoutParams(dp(42), dp(30)))
        minimumHeight = dp(58)
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(8) }
    }
}

internal fun MainActivity.showFeatureItemPage(title: String, subtitle: String, iconRes: Int, action: String) {
    showFeaturePage(title)
    val color = when (iconRes) {
        R.drawable.ic_send_plane -> "#14C66A"
        R.drawable.ic_security_shield -> "#14C66A"
        R.drawable.ic_local_model -> "#00A7A7"
        R.drawable.ic_device_node -> "#6C7A89"
        else -> "#5B6CFF"
    }
    featureContent.addView(featureHeroCard(title, subtitle.ifBlank { getString(R.string.feature_default_subtitle) }, iconRes, color, action))
    addSectionTitle(getString(R.string.common_status))
    featureContent.addView(featureRow(getString(R.string.feature_current_status), action, iconRes, ""))
    featureContent.addView(featureRow(getString(R.string.feature_run_scope), itemScopeFor(title, action, iconRes), R.drawable.ic_device_node, ""))
    addSectionTitle(getString(R.string.feature_section_security))
    featureContent.addView(featureRow(getString(R.string.feature_identity_protection), getString(R.string.feature_identity_protection_subtitle), R.drawable.ic_security_shield, ""))
    featureContent.addView(featureRow(getString(R.string.feature_audit_log), getString(R.string.feature_audit_log_subtitle), R.drawable.ic_protocol_link, ""))
    addSectionTitle(getString(R.string.feature_section_management))
    featureContent.addView(featureRow(getString(R.string.feature_management_mode), itemManagementFor(action), R.drawable.ic_protocol_link, ""))
}

internal fun MainActivity.itemScopeFor(title: String, action: String, iconRes: Int): String {
    val lowerTitle = title.lowercase(Locale.getDefault())
    return when {
        title.contains("\u7fa4") || lowerTitle.contains("group") -> getString(R.string.feature_scope_group)
        iconRes == R.drawable.ic_local_model || title.contains("\u6a21\u578b") || lowerTitle.contains("model") || lowerTitle.contains("llm") || lowerTitle.contains("minicpm") -> getString(R.string.feature_scope_model)
        lowerTitle.contains("relay") || title.contains("\u4f20\u8f93") -> getString(R.string.feature_scope_transport)
        title.contains("\u9ea6\u514b\u98ce") || title.contains("\u76f8\u673a") || title.contains("\u4f4d\u7f6e") || title.contains("\u901a\u77e5") ||
            lowerTitle.contains("microphone") || lowerTitle.contains("camera") || lowerTitle.contains("location") || lowerTitle.contains("notification") -> getString(R.string.feature_scope_permission)
        action == getString(R.string.common_off) -> getString(R.string.feature_scope_off)
        else -> getString(R.string.feature_scope_default)
    }
}

internal fun MainActivity.itemManagementFor(action: String): String {
    return when (action) {
        getString(R.string.common_view) -> getString(R.string.feature_management_view)
        getString(R.string.security_manage) -> getString(R.string.feature_management_manage)
        getString(R.string.common_copy) -> getString(R.string.feature_management_copy)
        getString(R.string.common_on), getString(R.string.status_enabled) -> getString(R.string.feature_management_enable)
        getString(R.string.common_off) -> getString(R.string.feature_management_off)
        getString(R.string.common_next_step) -> getString(R.string.feature_management_next)
        else -> getString(R.string.feature_management_default)
    }
}

internal fun MainActivity.featureIcon(iconRes: Int, color: Int): ImageView {
    if (isFullColorFeatureIcon(iconRes)) {
        return ImageView(this).apply {
            setImageResource(iconRes)
            setPadding(0, 0, 0, 0)
            scaleType = ImageView.ScaleType.CENTER_CROP
        }.also {
            it.layoutParams = LinearLayout.LayoutParams(dp(44), dp(44))
        }
    }
    return ImageView(this).apply {
        setImageResource(iconRes)
        background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(13).toFloat()
            setColor(color)
        }
        setPadding(dp(9), dp(9), dp(9), dp(9))
    }.also {
        it.imageTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
        it.layoutParams = LinearLayout.LayoutParams(dp(44), dp(44))
    }
}

internal fun MainActivity.isFullColorFeatureIcon(iconRes: Int): Boolean {
    return iconRes == R.drawable.hermes_logo ||
        iconRes == R.drawable.logo_codex_product ||
        iconRes == R.drawable.logo_claude_code ||
        iconRes == R.drawable.ic_avatar_group ||
        iconRes == R.drawable.ic_avatar_device ||
        iconRes == R.drawable.ic_avatar_news ||
        iconRes == R.drawable.ic_avatar_ai_agent ||
        iconRes == R.drawable.ic_avatar_custom_agent ||
        iconRes == R.drawable.ic_avatar_cloud_model ||
        iconRes == R.drawable.logo_provider_openai ||
        iconRes == R.drawable.logo_provider_deepseek ||
        iconRes == R.drawable.logo_provider_anthropic ||
        iconRes == R.drawable.logo_provider_gemini ||
        iconRes == R.drawable.logo_provider_qwen ||
        iconRes == R.drawable.logo_provider_openrouter ||
        iconRes == R.drawable.ic_send_plane
}

internal fun MainActivity.statusPill(textValue: String, color: Int): TextView {
    return TextView(this).apply {
        text = textValue
        gravity = Gravity.CENTER
        textSize = 11f
        setTextColor(color)
        setPadding(dp(8), 0, dp(8), 0)
        background = GradientDrawable().apply {
            cornerRadius = dp(11).toFloat()
            setColor(adjustAlpha(color, 0.10f))
        }
    }
}

internal fun MainActivity.featureIconColor(iconRes: Int): Int {
    return when (iconRes) {
        R.drawable.ic_local_model -> Color.parseColor("#00A7A7")
        R.drawable.ic_agent_node -> Color.parseColor("#5B6CFF")
        R.drawable.ic_device_node -> Color.parseColor("#6C7A89")
        R.drawable.ic_send_plane -> Color.parseColor("#14C66A")
        R.drawable.ic_security_shield -> Color.parseColor("#14C66A")
        R.drawable.ic_protocol_link -> Color.parseColor("#5B6CFF")
        R.drawable.ic_scan -> Color.parseColor("#14C66A")
        R.drawable.ic_import -> Color.parseColor("#8E8E93")
        else -> Color.parseColor("#8E8E93")
    }
}

internal fun MainActivity.adjustAlpha(color: Int, factor: Float): Int {
    return Color.argb(
        (Color.alpha(color) * factor).toInt(),
        Color.red(color),
        Color.green(color),
        Color.blue(color)
    )
}
