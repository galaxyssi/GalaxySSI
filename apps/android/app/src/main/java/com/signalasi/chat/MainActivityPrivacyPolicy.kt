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

internal fun MainActivity.renderControlCenterPhoneCapabilitiesPage() {
    val runtime = mobileNativeAgent.snapshot().runtimeContext
    val tools = runtime.nativeTools
    val capabilityMatrix = runtime.capabilityMatrix
    val available = capabilityMatrix.availableNativeToolIds.size
    val attention = tools.size - available
    showControlCenterFeature(
        getString(R.string.cc_phone_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(R.string.cc_phone_ready_title, available),
                subtitle = getString(R.string.cc_phone_ready_subtitle, attention),
                iconRes = R.drawable.ic_agent_control,
                tone = if (attention == 0) ControlCenterTone.GREEN else ControlCenterTone.AMBER
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_device_control),
                    listOf(
                        ControlCenterRowSpec("phone.catalog", getString(R.string.cc_camera_flash_title), getString(R.string.cc_camera_flash_subtitle), R.drawable.ic_scan, phoneCapabilityStatus(capabilityMatrix, tools, "camera", "torch"), ControlCenterTone.AMBER),
                        ControlCenterRowSpec("phone.catalog", getString(R.string.cc_audio_title), getString(R.string.cc_audio_subtitle), R.drawable.ic_input_voice, phoneCapabilityStatus(capabilityMatrix, tools, "audio", "volume"), ControlCenterTone.BLUE),
                        ControlCenterRowSpec("phone.catalog", getString(R.string.cc_alarm_timer_title), getString(R.string.cc_alarm_timer_subtitle), R.drawable.ic_agent_history, phoneCapabilityStatus(capabilityMatrix, tools, "alarm", "timer"), ControlCenterTone.GREEN),
                        ControlCenterRowSpec("phone.catalog", getString(R.string.cc_network_title), getString(R.string.cc_network_subtitle), R.drawable.ic_protocol_link, phoneCapabilityStatus(capabilityMatrix, tools, "network", "wifi", "bluetooth", "nfc"), ControlCenterTone.VIOLET)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_information_system),
                    listOf(
                        ControlCenterRowSpec("phone.catalog", getString(R.string.cc_device_status_title), getString(R.string.cc_device_status_subtitle), R.drawable.ic_device_node, phoneCapabilityStatus(capabilityMatrix, tools, "battery", "storage", "sensor"), ControlCenterTone.GREEN),
                        ControlCenterRowSpec("phone.catalog", getString(R.string.cc_location_title), getString(R.string.cc_location_subtitle), R.drawable.ic_avatar_scan, phoneCapabilityStatus(capabilityMatrix, tools, "location"), ControlCenterTone.AMBER),
                        ControlCenterRowSpec("phone.catalog", getString(R.string.cc_tool_catalog_title), getString(R.string.cc_tool_catalog_subtitle), R.drawable.ic_agent_control, tools.size.toString(), ControlCenterTone.NEUTRAL)
                    )
                )
            )
        )
    )
}

internal fun MainActivity.phoneCapabilityStatus(
    capabilityMatrix: AgentRuntimeCapabilitySnapshot,
    tools: List<AgentNativeToolDescriptor>,
    vararg keywords: String
): String {
    val matching = tools.filter { tool -> keywords.any { keyword -> tool.id.contains(keyword, true) } }
    val available = matching.count { capabilityMatrix.isNativeToolExecutable(it.id) }
    return when {
        matching.isEmpty() -> getString(R.string.cc_status_not_configured)
        available == matching.size -> getString(R.string.cc_status_available)
        available > 0 -> getString(R.string.cc_status_available_ratio, available, matching.size)
        matching.any { it.availability.status == AgentNativeToolAvailabilityStatus.REQUIRES_SETUP } -> getString(R.string.status_needs_setup)
        else -> getString(R.string.cc_status_unavailable)
    }
}

internal fun MainActivity.renderControlCenterSmartSpacesPage() {
    val homeAssistant = HomeAssistantSettingsStore.load(this)
    val homeAssistantReady = homeAssistant.configured
    val customDevices = CustomDeviceConnectorStore(this).list()
    showControlCenterFeature(
        getString(R.string.cc_smart_spaces_title),
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_home_assistant_title),
                subtitle = getString(
                    when {
                        !homeAssistant.credentialsConfigured -> R.string.cc_home_assistant_not_configured
                        homeAssistantReady -> R.string.cc_home_assistant_connected
                        else -> R.string.cc_home_assistant_disabled
                    }
                ),
                iconRes = R.drawable.ic_device_node,
                actionId = "spaces.configure",
                badges = listOf(ControlCenterBadgeSpec(
                    getString(
                        when {
                            !homeAssistant.credentialsConfigured -> R.string.cc_status_not_configured
                            homeAssistantReady -> R.string.status_enabled
                            else -> R.string.common_off
                        }
                    ),
                    if (homeAssistantReady) ControlCenterTone.GREEN else ControlCenterTone.AMBER
                )),
                metrics = listOf(
                    ControlCenterMetricSpec(customDevices.count { it.configured }.toString(), getString(R.string.count_devices, customDevices.size)),
                    ControlCenterMetricSpec(if (homeAssistant.enabled) getString(R.string.common_on) else getString(R.string.common_off), getString(R.string.common_status)),
                    ControlCenterMetricSpec(
                        getString(
                            when {
                                !homeAssistant.credentialsConfigured -> R.string.status_needs_setup
                                homeAssistantReady -> R.string.cc_status_ready
                                else -> R.string.common_off
                            }
                        ),
                        getString(R.string.cc_metric_security)
                    )
                )
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_smart_spaces_title),
                    listOf(
                        ControlCenterRowSpec("spaces.entities", getString(R.string.cc_home_entities_title), getString(R.string.cc_home_entities_subtitle), R.drawable.ic_group, if (homeAssistantReady) getString(R.string.common_view) else getString(R.string.status_needs_setup), if (homeAssistantReady) ControlCenterTone.GREEN else ControlCenterTone.AMBER, enabled = homeAssistantReady),
                        ControlCenterRowSpec("spaces.automations", getString(R.string.cc_home_automations_title), getString(R.string.cc_home_automations_subtitle), R.drawable.ic_automation_line, if (homeAssistantReady) getString(R.string.common_view) else getString(R.string.status_needs_setup), if (homeAssistantReady) ControlCenterTone.BLUE else ControlCenterTone.AMBER, enabled = homeAssistantReady),
                        ControlCenterRowSpec("spaces.configure", getString(R.string.cc_custom_devices_title), getString(R.string.cc_custom_devices_subtitle), R.drawable.ic_device_node, customDevices.size.toString(), ControlCenterTone.VIOLET)
                    )
                )
            )
        )
    )
}

internal fun MainActivity.renderControlCenterNodesPage() {
    val state = mobileNativeAgent.snapshot()
    val desktops = desktopSecuritySummaries(activePcConnectorContacts())
    val targets = controlCenterResourceTargets(state.callableTargets).distinctBy { it.id }
    val registrations = mobileNativeAgent.agentRegistrySnapshot()
    val availableTargetIds = targets
        .filter { it.status == AgentConnectorStatus.AVAILABLE }
        .mapTo(linkedSetOf()) { it.id }
    val desktopRows = desktops.map { desktop ->
        val online = desktop.agentIds.any { it in availableTargetIds }
        ControlCenterRowSpec(
            actionId = "node.desktop:${desktop.id}",
            title = desktop.name,
            subtitle = getString(R.string.count_items, desktop.agentCount),
            iconRes = R.drawable.ic_device_node,
            status = getString(if (online) R.string.cc_status_online else R.string.status_disconnected),
            tone = if (online) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL
        )
    }.ifEmpty {
        listOf(ControlCenterRowSpec("nodes.scan", getString(R.string.cc_no_desktop_title), getString(R.string.cc_no_desktop_subtitle), R.drawable.ic_scan, getString(R.string.security_scan), ControlCenterTone.AMBER))
    }
    val qnnProfiles = LocalModelManager.profiles(this).filter {
        it.preferredAccelerator == LocalModelAcceleratorKind.VENDOR_SDK
    }
    val installedQnnProfiles = qnnProfiles.count { LocalModelManager.isInstalled(this, it) }
    val localRows = listOf(
        ControlCenterRowSpec(
            actionId = "local_model.open",
            title = getString(R.string.local_model_title),
            subtitle = getString(R.string.local_model_qnn_catalog_subtitle),
            iconRes = R.drawable.ic_local_model,
            status = getString(
                R.string.local_model_qnn_installed_count,
                installedQnnProfiles,
                qnnProfiles.size
            ),
            tone = if (installedQnnProfiles == qnnProfiles.size && qnnProfiles.isNotEmpty()) {
                ControlCenterTone.GREEN
            } else {
                ControlCenterTone.BLUE
            }
        )
    ) + targets.filter { it.kind == AgentConnectorKind.MODEL && !it.id.startsWith("cloud:") }
        .map { target -> controlCenterTargetRow(target, findAgentRegistration(registrations, target.id)) }
    val cloudRows = targets.filter { it.id.startsWith("cloud:") }
        .map { target -> controlCenterTargetRow(target, findAgentRegistration(registrations, target.id)) }
        .ifEmpty {
            listOf(ControlCenterRowSpec("routing.add_cloud", getString(R.string.cc_add_cloud_provider_title), getString(R.string.cc_add_cloud_provider_subtitle), R.drawable.ic_avatar_cloud_model, "+", ControlCenterTone.VIOLET))
        }
    val available = targets.count { it.status == AgentConnectorStatus.AVAILABLE }
    showControlCenterFeature(
        getString(R.string.cc_nodes_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(R.string.cc_nodes_ready_title, available),
                subtitle = getString(R.string.cc_nodes_ready_subtitle),
                iconRes = R.drawable.ic_protocol_link,
                tone = if (available > 0) ControlCenterTone.GREEN else ControlCenterTone.AMBER
            ),
            sections = listOf(
                ControlCenterSectionSpec(getString(R.string.default_desktop_name), desktopRows),
                ControlCenterSectionSpec(getString(R.string.cc_section_this_device), localRows),
                ControlCenterSectionSpec(getString(R.string.cc_section_cloud_apis), cloudRows)
            )
        )
    )
}

internal fun MainActivity.controlCenterTargetRow(
    target: AgentCallableTarget,
    registration: AgentRegistration? = null
): ControlCenterRowSpec {
    val presentation = registration?.let(AgentIdentityPresenter::present)
    return ControlCenterRowSpec(
        actionId = "routing.target:${target.id}",
        title = presentation?.displayName ?: target.title,
        subtitle = if (presentation == null) controlCenterTargetSubtitle(target) else "",
        iconRes = presentation?.let { controlCenterAgentAvatar(it.avatarStyle) }
            ?: controlCenterTargetIcon(target),
        status = presentation?.let { controlCenterAgentStatus(it.status) }
            ?: controlCenterTargetStatus(target.status),
        tone = presentation?.let { controlCenterAgentTone(it.status) }
            ?: controlCenterTargetTone(target.status),
        preserveIconColor = presentation?.avatarStyle in setOf(
            AgentAvatarStyle.CODEX,
            AgentAvatarStyle.CLAUDE,
            AgentAvatarStyle.HERMES
        ),
        badges = emptyList()
    )
}

internal fun MainActivity.renderControlCenterSecurityPage() {
    val fingerprint = SignalASICrypto.localIdentitySha256()
    val trustedDevices = desktopSecuritySummaries(activePcConnectorContacts()).size
    val trustedContacts = storedContacts().count { AppStore.canCommunicateWith(this, it.id) }
    val notificationsEnabled = appNotificationsEnabled()
    showControlCenterFeature(
        getString(R.string.cc_security_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(R.string.security_privacy_title),
                subtitle = getString(R.string.security_privacy_subtitle),
                iconRes = R.drawable.ic_security_shield,
                tone = ControlCenterTone.GREEN
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_identity),
                    listOf(
                        ControlCenterRowSpec("profile.copy_fingerprint", getString(R.string.settings_identity_fingerprint), compactFingerprint(fingerprint), R.drawable.ic_settings_fingerprint, getString(R.string.common_copy), ControlCenterTone.BLUE, showChevron = false),
                        ControlCenterRowSpec("profile.copy_id", getString(R.string.settings_signalasi_id), SignalASICrypto.localSignalasiId(), R.drawable.ic_protocol_link, getString(R.string.common_copy), ControlCenterTone.NEUTRAL, showChevron = false)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.security_section_paired_devices),
                    listOf(
                        ControlCenterRowSpec("security.manage", getString(R.string.settings_trusted_devices), getString(R.string.settings_trusted_devices_subtitle), R.drawable.ic_settings_devices, trustedDevices.toString(), ControlCenterTone.GREEN),
                        ControlCenterRowSpec("apps.contacts", getString(R.string.cc_contacts_title), getString(R.string.cc_contacts_subtitle), R.drawable.ic_tab_contacts_outline, trustedContacts.toString(), ControlCenterTone.VIOLET)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.feature_identity_protection),
                    listOf(
                        ControlCenterRowSpec("general.notifications", getString(R.string.cc_notifications_title), getString(R.string.cc_notifications_subtitle), R.drawable.ic_settings_notification, getString(if (notificationsEnabled) R.string.status_enabled else R.string.status_needs_setup), if (notificationsEnabled) ControlCenterTone.GREEN else ControlCenterTone.AMBER)
                    )
                )
            )
        )
    )
}

internal fun MainActivity.renderControlCenterPrivacyPage(payload: String = "") {
    when {
        payload.startsWith("event:") -> {
            renderControlCenterPrivacyEvent(payload.substringAfter("event:"))
            return
        }
        payload.startsWith("destination:") -> {
            renderControlCenterPrivacyDestination(payload.substringAfter("destination:"))
            return
        }
    }
    val store = EncryptedAgentDataDisclosureStore(this)
    val records = store.list(80)
    val summary = AgentDataDisclosureLedger.summary(records)
    val blocked = store.blockedDestinationIds()
    val registrations = AppStoreAgentConnectorRegistry(this).registrations()
        .filter {
            it.location != AgentResourceLocation.PHONE &&
                it.kind in setOf(AgentConnectorKind.AGENT, AgentConnectorKind.MODEL)
        }
    val destinationIds = linkedSetOf<String>().apply {
        addAll(registrations.map(AgentRegistration::agentId))
        addAll(records.map(AgentDataDisclosureRecord::destinationId))
        addAll(blocked)
    }
    val destinations = destinationIds.map { destinationId ->
        val registration = registrations.firstOrNull { it.agentId == destinationId }
        val recent = records.firstOrNull { it.destinationId == destinationId }
        val title = recent?.destinationTitle
            ?: registration?.displayName
            ?: destinationId
        val model = recent?.modelId
            ?: registration?.providerProfile?.modelId
            ?: ""
        val location = recent?.location
            ?: registration?.location
            ?: AgentResourceLocation.CLOUD
        ControlCenterRowSpec(
            actionId = "privacy.destination:$destinationId",
            title = title,
            subtitle = getString(
                R.string.cc_privacy_destination_subtitle,
                privacyLocationLabel(location),
                model.ifBlank {
                    recent?.providerId
                        ?: registration?.providerId
                        ?: getString(R.string.cc_privacy_destination_unspecified)
                }
            ),
            iconRes = if (location == AgentResourceLocation.TRUSTED_DESKTOP) {
                R.drawable.ic_device_node
            } else {
                R.drawable.ic_settings_model
            },
            status = getString(
                if (destinationId in blocked) {
                    R.string.cc_privacy_blocked
                } else {
                    R.string.cc_privacy_allowed
                }
            ),
            tone = if (destinationId in blocked) ControlCenterTone.AMBER else ControlCenterTone.GREEN
        )
    }
    val recentRows = records.take(30).map { record ->
        ControlCenterRowSpec(
            actionId = "privacy.event:${record.eventId}",
            title = record.destinationTitle,
            subtitle = getString(
                R.string.cc_privacy_event_subtitle,
                privacyDataKindsLabel(record.dataKinds),
                privacyTimeLabel(record.updatedAtMillis)
            ),
            iconRes = privacyDestinationIcon(record.location),
            status = privacyDisclosureStatusLabel(record.status),
            tone = privacyDisclosureStatusTone(record.status)
        )
    }
    showControlCenterFeature(
        getString(R.string.cc_privacy_dashboard_title),
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_privacy_dashboard_title),
                subtitle = getString(R.string.cc_privacy_dashboard_hero_subtitle),
                iconRes = R.drawable.ic_security_shield,
                badges = listOf(
                    ControlCenterBadgeSpec(
                        getString(R.string.cc_privacy_metadata_only),
                        ControlCenterTone.GREEN
                    ),
                    ControlCenterBadgeSpec(
                        getString(R.string.cc_privacy_blocked_count, summary.blocked),
                        if (summary.blocked > 0) ControlCenterTone.AMBER else ControlCenterTone.NEUTRAL
                    )
                ),
                metrics = listOf(
                    ControlCenterMetricSpec(summary.total.toString(), getString(R.string.cc_privacy_metric_events)),
                    ControlCenterMetricSpec(summary.destinations.toString(), getString(R.string.cc_privacy_metric_destinations)),
                    ControlCenterMetricSpec(summary.cloud.toString(), getString(R.string.cc_privacy_metric_cloud))
                )
            ),
            banner = ControlCenterBannerSpec(
                title = getString(R.string.cc_privacy_local_title),
                subtitle = getString(R.string.cc_privacy_local_subtitle),
                iconRes = R.drawable.ic_device_node,
                tone = ControlCenterTone.GREEN
            ),
            sections = buildList {
                add(
                    ControlCenterSectionSpec(
                        getString(R.string.cc_section_privacy_boundary),
                        listOf(
                            ControlCenterRowSpec(
                                actionId = "agent.planner",
                                title = getString(R.string.cc_privacy_planner_title),
                                subtitle = getString(R.string.cc_privacy_planner_subtitle),
                                iconRes = R.drawable.ic_settings_model,
                                status = getString(R.string.cc_privacy_review),
                                tone = ControlCenterTone.BLUE
                            ),
                            ControlCenterRowSpec(
                                actionId = routeAction(ControlCenterRoute.PERMISSIONS_AUDIT),
                                title = getString(R.string.cc_permissions_title),
                                subtitle = getString(R.string.cc_privacy_permissions_subtitle),
                                iconRes = R.drawable.ic_settings_fingerprint,
                                tone = ControlCenterTone.VIOLET
                            )
                        )
                    )
                )
                add(
                    ControlCenterSectionSpec(
                        getString(R.string.cc_privacy_destinations_title),
                        destinations.ifEmpty {
                            listOf(
                                ControlCenterRowSpec(
                                    actionId = "",
                                    title = getString(R.string.cc_privacy_no_destinations),
                                    subtitle = getString(R.string.cc_privacy_no_destinations_subtitle),
                                    iconRes = R.drawable.ic_settings_model,
                                    showChevron = false
                                )
                            )
                        }
                    )
                )
                add(
                    ControlCenterSectionSpec(
                        getString(R.string.cc_privacy_recent_title),
                        recentRows.ifEmpty {
                            listOf(
                                ControlCenterRowSpec(
                                    actionId = "",
                                    title = getString(R.string.cc_privacy_no_events),
                                    subtitle = getString(R.string.cc_privacy_no_events_subtitle),
                                    iconRes = R.drawable.ic_security_shield,
                                    showChevron = false
                                )
                            )
                        }
                    )
                )
                if (records.isNotEmpty()) {
                    add(
                        ControlCenterSectionSpec(
                            getString(R.string.cc_privacy_history_title),
                            listOf(
                                ControlCenterRowSpec(
                                    actionId = "privacy.clear_history",
                                    title = getString(R.string.cc_privacy_clear_title),
                                    subtitle = getString(R.string.cc_privacy_clear_subtitle),
                                    iconRes = R.drawable.ic_delete,
                                    tone = ControlCenterTone.NEUTRAL
                                )
                            )
                        )
                    )
                }
            },
            footer = getString(R.string.cc_privacy_footer)
        )
    )
}

internal fun MainActivity.renderControlCenterPrivacyDestination(destinationId: String) {
    val store = EncryptedAgentDataDisclosureStore(this)
    val records = store.list(250).filter { it.destinationId == destinationId }
    val recent = records.firstOrNull()
    val registration = AppStoreAgentConnectorRegistry(this).registrations()
        .firstOrNull { it.agentId == destinationId }
    val title = recent?.destinationTitle ?: registration?.displayName ?: destinationId
    val location = recent?.location ?: registration?.location ?: AgentResourceLocation.CLOUD
    val trust = recent?.trust ?: registration?.trust ?: AgentResourceTrust.UNKNOWN
    val provider = recent?.providerId
        ?: registration?.providerId
        ?: ""
    val model = recent?.modelId
        ?: registration?.providerProfile?.modelId
        ?: ""
    val blocked = destinationId in store.blockedDestinationIds()
    val observedKinds = records.flatMapTo(linkedSetOf()) { it.dataKinds }
    showControlCenterFeature(
        title,
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = title,
                subtitle = getString(
                    R.string.cc_privacy_destination_subtitle,
                    privacyLocationLabel(location),
                    model.ifBlank { provider.ifBlank { getString(R.string.cc_privacy_destination_unspecified) } }
                ),
                iconRes = privacyDestinationIcon(location),
                badges = listOf(
                    ControlCenterBadgeSpec(
                        getString(if (blocked) R.string.cc_privacy_blocked else R.string.cc_privacy_allowed),
                        if (blocked) ControlCenterTone.AMBER else ControlCenterTone.GREEN
                    )
                ),
                metrics = listOf(
                    ControlCenterMetricSpec(records.size.toString(), getString(R.string.cc_privacy_metric_events)),
                    ControlCenterMetricSpec(observedKinds.size.toString(), getString(R.string.cc_privacy_metric_data_types)),
                    ControlCenterMetricSpec(privacyProtectionShortLabel(recent?.protection, location), getString(R.string.cc_privacy_metric_protection))
                )
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_privacy_destination_details),
                    listOf(
                        ControlCenterRowSpec("", getString(R.string.cc_privacy_provider), provider.ifBlank { getString(R.string.cc_privacy_destination_unspecified) }, R.drawable.ic_settings_model, showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.cc_privacy_model), model.ifBlank { getString(R.string.cc_privacy_destination_unspecified) }, R.drawable.ic_agent_node, showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.cc_privacy_location), privacyLocationLabel(location), R.drawable.ic_device_node, showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.cc_privacy_trust), privacyTrustLabel(trust), R.drawable.ic_security_shield, showChevron = false)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_privacy_observed_data_title),
                    if (observedKinds.isEmpty()) {
                        listOf(
                            ControlCenterRowSpec("", getString(R.string.cc_privacy_no_events), getString(R.string.cc_privacy_no_events_subtitle), R.drawable.ic_info_outline, showChevron = false)
                        )
                    } else {
                        observedKinds.sortedBy(AgentDisclosedDataKind::wireValue).map { kind ->
                            ControlCenterRowSpec("", privacyDataKindLabel(kind), getString(R.string.cc_privacy_metadata_not_content), privacyDataKindIcon(kind), showChevron = false)
                        }
                    }
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_privacy_control_title),
                    listOf(
                        ControlCenterRowSpec(
                            actionId = "privacy.toggle_destination:$destinationId",
                            title = getString(R.string.cc_privacy_allow_destination),
                            subtitle = getString(R.string.cc_privacy_allow_destination_subtitle),
                            iconRes = R.drawable.ic_security_shield,
                            switchValue = !blocked,
                            showChevron = false,
                            tone = if (blocked) ControlCenterTone.AMBER else ControlCenterTone.GREEN
                        )
                    )
                )
            ),
            footer = getString(R.string.cc_privacy_block_scope_footer)
        )
    )
}

internal fun MainActivity.renderControlCenterPrivacyEvent(eventId: String) {
    val store = EncryptedAgentDataDisclosureStore(this)
    val record = store.find(eventId) ?: run {
        renderControlCenterPrivacyPage()
        return
    }
    val blocked = record.destinationId in store.blockedDestinationIds()
    showControlCenterFeature(
        getString(R.string.cc_privacy_event_title),
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = record.destinationTitle,
                subtitle = getString(
                    R.string.cc_privacy_event_subtitle,
                    privacyDataKindsLabel(record.dataKinds),
                    privacyTimeLabel(record.updatedAtMillis)
                ),
                iconRes = privacyDestinationIcon(record.location),
                badges = listOf(
                    ControlCenterBadgeSpec(
                        privacyDisclosureStatusLabel(record.status),
                        privacyDisclosureStatusTone(record.status)
                    ),
                    ControlCenterBadgeSpec(
                        privacyProtectionShortLabel(record.protection, record.location),
                        ControlCenterTone.BLUE
                    )
                )
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_privacy_shared_data_title),
                    record.dataKinds.sortedBy(AgentDisclosedDataKind::wireValue).map { kind ->
                        ControlCenterRowSpec(
                            actionId = "",
                            title = privacyDataKindLabel(kind),
                            subtitle = getString(R.string.cc_privacy_metadata_not_content),
                            iconRes = privacyDataKindIcon(kind),
                            showChevron = false
                        )
                    }.ifEmpty {
                        listOf(
                            ControlCenterRowSpec("", getString(R.string.cc_privacy_no_data), getString(R.string.cc_privacy_no_data_subtitle), R.drawable.ic_info_outline, showChevron = false)
                        )
                    }
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_privacy_event_details),
                    listOf(
                        ControlCenterRowSpec("", getString(R.string.cc_privacy_purpose), record.purpose, R.drawable.ic_agent_history, showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.cc_privacy_text_size), getString(R.string.cc_privacy_character_count, record.textCharacters), R.drawable.ic_info_outline, showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.cc_privacy_attachments), getString(R.string.cc_privacy_attachment_summary, record.attachmentCount, AgentInputAttachment.humanSize(record.attachmentBytes)), R.drawable.ic_more_horizontal, showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.cc_privacy_protection), privacyProtectionLabel(record.protection), R.drawable.ic_security_shield, showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.cc_privacy_time), privacyExactTimeLabel(record.updatedAtMillis), R.drawable.ic_agent_history, showChevron = false)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_privacy_control_title),
                    listOf(
                        ControlCenterRowSpec(
                            actionId = "privacy.toggle_destination:${record.destinationId}",
                            title = getString(R.string.cc_privacy_allow_destination),
                            subtitle = getString(R.string.cc_privacy_allow_destination_subtitle),
                            iconRes = R.drawable.ic_security_shield,
                            switchValue = !blocked,
                            showChevron = false,
                            tone = if (blocked) ControlCenterTone.AMBER else ControlCenterTone.GREEN
                        )
                    )
                )
            ),
            footer = getString(R.string.cc_privacy_event_footer)
        )
    )
}

internal fun MainActivity.privacyDataKindsLabel(kinds: Set<AgentDisclosedDataKind>): String =
    kinds.sortedBy(AgentDisclosedDataKind::wireValue)
        .take(3)
        .joinToString(getString(R.string.cc_privacy_kind_separator)) { privacyDataKindLabel(it) }
        .ifBlank { getString(R.string.cc_privacy_no_data) }

internal fun MainActivity.privacyDataKindLabel(kind: AgentDisclosedDataKind): String = getString(
    when (kind) {
        AgentDisclosedDataKind.MESSAGE_TEXT -> R.string.cc_privacy_kind_message
        AgentDisclosedDataKind.CONVERSATION_HISTORY -> R.string.cc_privacy_kind_history
        AgentDisclosedDataKind.SYSTEM_INSTRUCTIONS -> R.string.cc_privacy_kind_system
        AgentDisclosedDataKind.TOOL_OUTPUT -> R.string.cc_privacy_kind_tool
        AgentDisclosedDataKind.SCREEN_CONTEXT -> R.string.cc_privacy_kind_screen
        AgentDisclosedDataKind.MEMORY_CONTEXT -> R.string.cc_privacy_kind_memory
        AgentDisclosedDataKind.KNOWLEDGE_CONTEXT -> R.string.cc_privacy_kind_knowledge
        AgentDisclosedDataKind.DEVICE_CONTEXT -> R.string.cc_privacy_kind_device
        AgentDisclosedDataKind.IMAGE -> R.string.cc_privacy_kind_image
        AgentDisclosedDataKind.AUDIO -> R.string.cc_privacy_kind_audio
        AgentDisclosedDataKind.VIDEO -> R.string.cc_privacy_kind_video
        AgentDisclosedDataKind.DOCUMENT -> R.string.cc_privacy_kind_document
        AgentDisclosedDataKind.OTHER_FILE -> R.string.cc_privacy_kind_file
    }
)

internal fun MainActivity.privacyDataKindIcon(kind: AgentDisclosedDataKind): Int = when (kind) {
    AgentDisclosedDataKind.MEMORY_CONTEXT -> R.drawable.ic_agent_memory
    AgentDisclosedDataKind.KNOWLEDGE_CONTEXT -> R.drawable.ic_agent_knowledge
    AgentDisclosedDataKind.AUDIO -> R.drawable.ic_input_voice
    AgentDisclosedDataKind.IMAGE, AgentDisclosedDataKind.SCREEN_CONTEXT -> R.drawable.ic_scan
    AgentDisclosedDataKind.DEVICE_CONTEXT -> R.drawable.ic_device_node
    AgentDisclosedDataKind.TOOL_OUTPUT -> R.drawable.ic_agent_control
    else -> R.drawable.ic_info_outline
}

internal fun MainActivity.privacyDestinationIcon(location: AgentResourceLocation): Int =
    if (location == AgentResourceLocation.TRUSTED_DESKTOP) {
        R.drawable.ic_device_node
    } else {
        R.drawable.ic_settings_model
    }

internal fun MainActivity.privacyLocationLabel(location: AgentResourceLocation): String = getString(
    when (location) {
        AgentResourceLocation.PHONE -> R.string.cc_privacy_location_phone
        AgentResourceLocation.TRUSTED_DESKTOP -> R.string.cc_privacy_location_desktop
        AgentResourceLocation.PRIVATE_NETWORK -> R.string.cc_privacy_location_private
        AgentResourceLocation.CLOUD -> R.string.cc_privacy_location_cloud
    }
)

internal fun MainActivity.privacyTrustLabel(trust: AgentResourceTrust): String = getString(
    when (trust) {
        AgentResourceTrust.PHONE_SYSTEM -> R.string.cc_privacy_trust_phone
        AgentResourceTrust.VERIFIED_PAIRED -> R.string.cc_privacy_trust_verified
        AgentResourceTrust.PRIVATE_CONFIGURED -> R.string.cc_privacy_trust_private
        AgentResourceTrust.CLOUD_CONFIGURED -> R.string.cc_privacy_trust_cloud
        AgentResourceTrust.UNKNOWN -> R.string.cc_privacy_trust_unknown
    }
)

internal fun MainActivity.privacyProtectionLabel(protection: AgentDisclosureProtection): String = getString(
    when (protection) {
        AgentDisclosureProtection.ON_DEVICE -> R.string.cc_privacy_protection_on_device
        AgentDisclosureProtection.SIGNAL_E2EE -> R.string.cc_privacy_protection_signal
        AgentDisclosureProtection.TLS -> R.string.cc_privacy_protection_tls
    }
)

internal fun MainActivity.privacyProtectionShortLabel(
    protection: AgentDisclosureProtection?,
    location: AgentResourceLocation
): String = privacyProtectionLabel(
    protection ?: if (location == AgentResourceLocation.TRUSTED_DESKTOP) {
        AgentDisclosureProtection.SIGNAL_E2EE
    } else {
        AgentDisclosureProtection.TLS
    }
)

internal fun MainActivity.privacyDisclosureStatusLabel(status: AgentDisclosureStatus): String = getString(
    when (status) {
        AgentDisclosureStatus.PREPARING -> R.string.cc_privacy_status_preparing
        AgentDisclosureStatus.QUEUED -> R.string.cc_privacy_status_queued
        AgentDisclosureStatus.SENT -> R.string.cc_privacy_status_sent
        AgentDisclosureStatus.BLOCKED -> R.string.cc_privacy_status_blocked
        AgentDisclosureStatus.FAILED -> R.string.cc_privacy_status_failed
    }
)

internal fun MainActivity.privacyDisclosureStatusTone(status: AgentDisclosureStatus): ControlCenterTone = when (status) {
    AgentDisclosureStatus.SENT -> ControlCenterTone.GREEN
    AgentDisclosureStatus.PREPARING, AgentDisclosureStatus.QUEUED -> ControlCenterTone.BLUE
    AgentDisclosureStatus.BLOCKED, AgentDisclosureStatus.FAILED -> ControlCenterTone.AMBER
}

internal fun MainActivity.privacyTimeLabel(timestamp: Long): String {
    if (timestamp <= 0L) return getString(R.string.cc_privacy_time_unknown)
    val elapsed = (System.currentTimeMillis() - timestamp).coerceAtLeast(0L)
    return when {
        elapsed < 60_000L -> getString(R.string.cc_privacy_time_now)
        elapsed < 3_600_000L -> getString(R.string.cc_privacy_time_minutes, elapsed / 60_000L)
        elapsed < 86_400_000L -> getString(R.string.cc_privacy_time_hours, elapsed / 3_600_000L)
        else -> privacyExactTimeLabel(timestamp)
    }
}

internal fun MainActivity.privacyExactTimeLabel(timestamp: Long): String =
    if (timestamp <= 0L) {
        getString(R.string.cc_privacy_time_unknown)
    } else {
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(timestamp))
    }

internal fun MainActivity.renderControlCenterPermissionsPage() {
    val accessibility = SignalASIAccessibilityService.isActive()
    val notificationAccess = SignalASINotificationListenerService.currentContext().hasAccess
    val microphone = checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    val camera = checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    val granted = listOf(accessibility, notificationAccess, microphone, camera).count { it }
    showControlCenterFeature(
        getString(R.string.cc_permissions_title),
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_permissions_title),
                subtitle = getString(R.string.cc_permissions_summary, granted, 4),
                iconRes = R.drawable.ic_settings_fingerprint,
                metrics = listOf(
                    ControlCenterMetricSpec("$granted/4", getString(R.string.cc_section_android_permissions)),
                    ControlCenterMetricSpec(mobileNativeAgent.snapshot().auditTrail.size.toString(), getString(R.string.feature_audit_log)),
                    ControlCenterMetricSpec(getString(R.string.cc_status_secure), getString(R.string.cc_metric_security))
                )
            ),
            sections = buildList {
                add(ControlCenterSectionSpec(
                        getString(R.string.cc_section_android_permissions),
                        listOf(
                            permissionRow("permissions.accessibility", R.string.cc_accessibility_title, R.string.cc_accessibility_subtitle, R.drawable.ic_agent_control, accessibility),
                            permissionRow("permissions.notifications", R.string.cc_notification_access_title, R.string.cc_notification_access_subtitle, R.drawable.ic_settings_notification, notificationAccess),
                            permissionRow("permissions.microphone", R.string.cc_microphone_permission_title, R.string.cc_microphone_permission_subtitle, R.drawable.ic_input_voice, microphone),
                            permissionRow("permissions.camera", R.string.cc_camera_permission_title, R.string.cc_camera_permission_subtitle, R.drawable.ic_scan, camera)
                        )
                    )
                )
                add(ControlCenterSectionSpec(
                        getString(R.string.feature_audit_log),
                        listOf(ControlCenterRowSpec("audit.operations", getString(R.string.cc_recent_operations_title), getString(R.string.cc_recent_operations_subtitle), R.drawable.ic_agent_history, getString(R.string.common_view), ControlCenterTone.VIOLET))
                    )
                )
            }
        )
    )
}

internal fun MainActivity.permissionRow(action: String, title: Int, subtitle: Int, icon: Int, granted: Boolean) =
    ControlCenterRowSpec(
        actionId = action,
        title = getString(title),
        subtitle = getString(subtitle),
        iconRes = icon,
        status = getString(if (granted) R.string.permission_allowed else R.string.permission_needs_setup),
        tone = if (granted) ControlCenterTone.GREEN else ControlCenterTone.AMBER
    )
