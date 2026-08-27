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

internal fun MainActivity.renderControlCenterVoicePage() {
    val config = VoiceAssistantSettings.get(this)
    val selectedModel = WhisperModelManager.model(config.asrModel)
    val capabilities = voiceProviderCapabilities(config)
    val asrCapability = capabilities[VoiceProviderCapabilityId.WHISPER_CPP]
    val ttsCapability = activeTtsCapability(config, capabilities)
    showControlCenterFeature(
        getString(R.string.cc_voice_title),
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = getString(R.string.voice_low_power_title),
                subtitle = getString(R.string.voice_low_power_subtitle),
                iconRes = R.drawable.ic_settings_voice,
                actionId = "voice.settings",
                badges = listOf(
                    ControlCenterBadgeSpec(getString(if (config.enabled) R.string.status_enabled else R.string.common_off), if (config.enabled) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL),
                    ControlCenterBadgeSpec(
                        voiceCapabilityStatus(asrCapability),
                        voiceCapabilityTone(asrCapability)
                    ),
                    ControlCenterBadgeSpec("TTS", ControlCenterTone.VIOLET)
                )
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.voice_section_listening),
                    listOf(
                        ControlCenterRowSpec("voice.settings", getString(R.string.voice_wake_words), WakeWordPolicy.WAKE_WORD, R.drawable.ic_input_voice, "", ControlCenterTone.BLUE),
                        ControlCenterRowSpec("voice.settings", getString(R.string.voice_wake_engine), wakeProviderLabel(config.wakeProvider), R.drawable.ic_agent_node, getString(if (config.enabled) R.string.status_enabled else R.string.common_off), if (config.enabled) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("voice.toggle_enabled", getString(R.string.voice_low_power_monitor), getString(R.string.voice_low_power_monitor_subtitle), R.drawable.ic_voice_settings, switchValue = config.enabled, showChevron = false)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.voice_section_asr),
                    listOf(
                        ControlCenterRowSpec(
                            "voice.asr",
                            getString(R.string.voice_asr_provider),
                            selectedModel.displayName,
                            R.drawable.ic_settings_voice,
                            voiceCapabilityStatus(asrCapability),
                            voiceCapabilityTone(asrCapability)
                        ),
                        ControlCenterRowSpec(
                            "voice.tts",
                            getString(R.string.voice_tts_provider),
                            ttsProviderLabel(config.ttsProvider),
                            R.drawable.ic_send_plane,
                            voiceCapabilityStatus(ttsCapability),
                            voiceCapabilityTone(ttsCapability)
                        ),
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.voice_section_target),
                    listOf(ControlCenterRowSpec("voice.settings", getString(R.string.voice_routing_mode), getString(R.string.voice_routing_mode_subtitle), R.drawable.ic_agent_node, voiceRoutingModeLabel(config.routingMode), ControlCenterTone.BLUE))
                )
            )
        )
    )
}

internal fun MainActivity.renderControlCenterDataPage() {
    val device = mobileNativeAgent.snapshot().currentScreen.deviceStatus
    val cacheBytes = directorySize(cacheDir)
    val storageSubtitle = if (device.totalStorageMb > 0L) {
        getString(R.string.cc_storage_subtitle) + " · ${formatMegabytes(device.freeStorageMb)}"
    } else {
        getString(R.string.cc_storage_subtitle)
    }
    showControlCenterFeature(
        getString(R.string.cc_data_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(R.string.cc_data_private_title),
                subtitle = getString(R.string.cc_data_private_subtitle),
                iconRes = R.drawable.ic_security_shield,
                tone = ControlCenterTone.GREEN
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_backup),
                    listOf(
                        ControlCenterRowSpec("data.export", getString(R.string.cc_create_backup_title), getString(R.string.cc_create_backup_subtitle), R.drawable.ic_settings_upload, getString(R.string.common_export), ControlCenterTone.BLUE),
                        ControlCenterRowSpec("data.import", getString(R.string.cc_import_backup_title), getString(R.string.cc_import_backup_subtitle), R.drawable.ic_settings_download, getString(R.string.common_import), ControlCenterTone.GREEN)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_section_storage),
                    listOf(
                        ControlCenterRowSpec("", getString(R.string.cc_storage_title), storageSubtitle, R.drawable.ic_device_node, if (device.freeStorageMb > 0L) formatMegabytes(device.freeStorageMb) else "", ControlCenterTone.VIOLET, showChevron = false),
                        ControlCenterRowSpec("data.cache", getString(R.string.cc_clear_cache_title), getString(R.string.cc_clear_cache_subtitle), R.drawable.ic_delete, formatBytes(cacheBytes), ControlCenterTone.AMBER)
                    )
                )
            )
        )
    )
}

internal fun MainActivity.renderControlCenterGeneralPage() {
    val textScale = AppDisplaySettings.textScale(this)
    val notificationsEnabled = appNotificationsEnabled()
    showControlCenterFeature(
        getString(R.string.cc_general_page_title),
        ControlCenterPageSpec(
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.settings_control_general),
                    listOf(
                        ControlCenterRowSpec("general.language", getString(R.string.language_policy_title), languagePolicySummary(), R.drawable.ic_settings_language, "", ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("general.appearance", getString(R.string.cc_appearance_title), getString(R.string.cc_appearance_subtitle), R.drawable.ic_tab_discover, getString(R.string.cc_managed_by_android), ControlCenterTone.BLUE),
                        ControlCenterRowSpec("general.text_size", getString(R.string.cc_text_size_title), appTextScaleLabel(textScale), R.drawable.ic_info_outline, "", ControlCenterTone.NEUTRAL)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_notifications_title),
                    listOf(ControlCenterRowSpec("general.notifications", getString(R.string.cc_notifications_title), getString(R.string.cc_notifications_subtitle), R.drawable.ic_settings_notification, getString(if (notificationsEnabled) R.string.status_enabled else R.string.status_needs_setup), if (notificationsEnabled) ControlCenterTone.GREEN else ControlCenterTone.AMBER))
                ),
                ControlCenterSectionSpec(
                    getString(R.string.settings_about_section),
                    listOf(
                        ControlCenterRowSpec("general.about", getString(R.string.cc_about_title), getString(R.string.cc_about_subtitle), R.drawable.ic_info_outline, "v${installedVersionName()}", ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("general.advanced", getString(R.string.cc_developer_title), getString(R.string.cc_developer_subtitle), R.drawable.ic_settings_diagnostics, "", ControlCenterTone.NEUTRAL)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.settings_reset_short),
                    listOf(ControlCenterRowSpec(routeAction(ControlCenterRoute.RESET), getString(R.string.cc_reset_title), getString(R.string.cc_reset_subtitle), R.drawable.ic_reset_data, "", ControlCenterTone.RED))
                )
            )
        )
    )
}

internal fun MainActivity.showTextSizeSettingsPage() {
    val selected = AppDisplaySettings.textScale(this)
    showControlCenterFeature(
        getString(R.string.cc_text_size_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                getString(R.string.cc_text_size_preview_title),
                getString(R.string.cc_text_size_preview_subtitle),
                R.drawable.ic_info_outline,
                ControlCenterTone.GREEN
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_text_size_section),
                    AppDisplaySettings.TextScaleMode.entries.map { mode ->
                        val isSelected = mode == selected
                        ControlCenterRowSpec(
                            actionId = if (isSelected) "" else "general.text_scale:${mode.wireValue}",
                            title = appTextScaleLabel(mode),
                            subtitle = appTextScaleDescription(mode),
                            iconRes = R.drawable.ic_info_outline,
                            status = if (isSelected) getString(R.string.settings_language_selected) else "",
                            tone = if (isSelected) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL,
                            showChevron = false
                        )
                    }
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_text_size_preview_section),
                    listOf(
                        ControlCenterRowSpec(
                            actionId = "",
                            title = getString(R.string.cc_text_size_preview_sample_title),
                            subtitle = getString(R.string.cc_text_size_preview_sample_subtitle),
                            iconRes = R.drawable.ic_agent_node,
                            showChevron = false
                        )
                    )
                )
            )
        )
    )
}

internal fun MainActivity.appTextScaleLabel(mode: AppDisplaySettings.TextScaleMode): String = getString(
    when (mode) {
        AppDisplaySettings.TextScaleMode.SYSTEM -> R.string.cc_text_size_system
        AppDisplaySettings.TextScaleMode.STANDARD -> R.string.cc_text_size_standard
        AppDisplaySettings.TextScaleMode.COMFORTABLE -> R.string.cc_text_size_comfortable
        AppDisplaySettings.TextScaleMode.LARGE -> R.string.cc_text_size_large
        AppDisplaySettings.TextScaleMode.EXTRA_LARGE -> R.string.cc_text_size_extra_large
    }
)

internal fun MainActivity.appTextScaleDescription(mode: AppDisplaySettings.TextScaleMode): String = getString(
    when (mode) {
        AppDisplaySettings.TextScaleMode.SYSTEM -> R.string.cc_text_size_system_subtitle
        AppDisplaySettings.TextScaleMode.STANDARD -> R.string.cc_text_size_standard_subtitle
        AppDisplaySettings.TextScaleMode.COMFORTABLE -> R.string.cc_text_size_comfortable_subtitle
        AppDisplaySettings.TextScaleMode.LARGE -> R.string.cc_text_size_large_subtitle
        AppDisplaySettings.TextScaleMode.EXTRA_LARGE -> R.string.cc_text_size_extra_large_subtitle
    }
)

internal fun MainActivity.recreateIntoControlCenterChild(child: String) {
    intent.putExtra(EXTRA_REOPEN_CONTROL_CENTER_CHILD, child)
    recreate()
}

internal fun MainActivity.reopenRequestedControlCenterChild(sourceIntent: Intent?) {
    val child = sourceIntent?.getStringExtra(EXTRA_REOPEN_CONTROL_CENTER_CHILD).orEmpty()
    if (child.isBlank()) return
    sourceIntent?.removeExtra(EXTRA_REOPEN_CONTROL_CENTER_CHILD)
    showMainTab(PAGE_SETTINGS)
    openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.GENERAL))
    when (child) {
        CONTROL_CENTER_CHILD_TEXT_SIZE -> openExistingControlCenterPage { showTextSizeSettingsPage() }
    }
}

internal fun MainActivity.renderControlCenterAdvancedPage() {
    showControlCenterFeature(
        getString(R.string.advanced_options_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(R.string.cc_advanced_diagnostics_title),
                subtitle = getString(R.string.cc_advanced_diagnostics_subtitle),
                iconRes = R.drawable.ic_settings_diagnostics,
                tone = ControlCenterTone.NEUTRAL
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.advanced_section_diagnostics),
                    listOf(
                        ControlCenterRowSpec("advanced.voice_performance", getString(R.string.voice_performance_title), getString(R.string.voice_performance_subtitle), R.drawable.ic_settings_diagnostics, getString(R.string.common_view), ControlCenterTone.GREEN),
                        ControlCenterRowSpec("advanced.web_sources", getString(R.string.web_sources_title), getString(R.string.web_sources_subtitle), R.drawable.ic_process_network, getString(R.string.web_sources_count, AgentWebIntelligenceEngineCatalog.entries.size), ControlCenterTone.GREEN),
                        ControlCenterRowSpec("advanced.protocol", getString(R.string.advanced_protocol_logs), getString(R.string.advanced_protocol_logs_subtitle), R.drawable.ic_protocol_link, getString(R.string.common_view), ControlCenterTone.BLUE),
                        ControlCenterRowSpec("advanced.audit", getString(R.string.advanced_agent_permission_audit), getString(R.string.advanced_agent_permission_audit_subtitle), R.drawable.ic_security_shield, getString(R.string.common_view), ControlCenterTone.VIOLET),
                        ControlCenterRowSpec("advanced.permissions", getString(R.string.cc_permissions_title), getString(R.string.cc_permissions_summary, controlCenterGrantedPermissionCount(), 4), R.drawable.ic_settings_fingerprint, getString(R.string.common_view), ControlCenterTone.AMBER)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_advanced_maintenance_section),
                    listOf(
                        ControlCenterRowSpec("advanced.app_details", getString(R.string.cc_advanced_app_details_title), getString(R.string.cc_advanced_app_details_subtitle), R.drawable.ic_info_outline, "", ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("advanced.cache", getString(R.string.cc_clear_cache_title), getString(R.string.cc_clear_cache_subtitle), R.drawable.ic_delete, formatBytes(directorySize(cacheDir)), ControlCenterTone.AMBER)
                    )
                )
            ),
            footer = getString(R.string.cc_advanced_footer)
        )
    )
}

internal fun MainActivity.showVoicePerformanceDashboardPage() {
    val dashboard = voiceReliabilityController.dashboard(foreground = true)
    showFeaturePage(getString(R.string.voice_performance_title))
    featureContent.addView(featureHeroCard(
        getString(R.string.voice_performance_hero_title),
        getString(R.string.voice_performance_hero_subtitle),
        R.drawable.ic_settings_diagnostics,
        "#14C66A",
        voicePerformanceHealthLabel(dashboard.health)
    ))
    addSectionTitle(getString(R.string.voice_performance_health_section))
    featureContent.addView(featureValueRow(
        getString(R.string.voice_performance_success_rate),
        getString(R.string.voice_performance_session_count, dashboard.sessionCount),
        R.drawable.ic_process_analysis,
        String.format(Locale.US, "%.1f%%", dashboard.successRate * 100.0)
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.voice_performance_fallback_rate),
        getString(R.string.voice_performance_failure_rate_value, dashboard.failureRate * 100.0),
        R.drawable.ic_process_network,
        String.format(Locale.US, "%.1f%%", dashboard.fallbackRate * 100.0)
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.voice_performance_resource_mode),
        if (dashboard.resourceReasons.isEmpty()) {
            getString(R.string.voice_performance_no_constraints)
        } else {
            getString(R.string.voice_performance_active_constraints, dashboard.resourceReasons.size)
        },
        R.drawable.ic_process_terminal,
        voicePerformanceResourceModeLabel(dashboard.resourceMode)
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.voice_performance_circuits),
        getString(R.string.voice_performance_circuits_subtitle),
        R.drawable.ic_security_shield,
        dashboard.openCircuits.size.toString()
    ))
    addSectionTitle(getString(R.string.voice_performance_latency_section))
    val visibleMetrics = dashboard.metrics.filter { metric ->
        metric.id in voicePerformanceVisibleMetrics
    }
    if (visibleMetrics.isEmpty()) {
        featureContent.addView(featureValueRow(
            getString(R.string.voice_performance_no_samples),
            getString(R.string.voice_performance_no_samples_subtitle),
            R.drawable.ic_settings_diagnostics,
            "-"
        ))
    } else {
        visibleMetrics.forEach { metric ->
            featureContent.addView(featureValueRow(
                voicePerformanceMetricLabel(metric.id),
                getString(R.string.voice_performance_metric_samples, metric.samples),
                R.drawable.ic_settings_diagnostics,
                getString(R.string.voice_performance_latency_value, metric.p50Ms, metric.p95Ms)
            ))
        }
    }
}

internal fun MainActivity.voicePerformanceHealthLabel(health: VoicePerformanceHealth): String = getString(
    when (health) {
        VoicePerformanceHealth.HEALTHY -> R.string.voice_performance_health_healthy
        VoicePerformanceHealth.WATCH -> R.string.voice_performance_health_watch
        VoicePerformanceHealth.DEGRADED -> R.string.voice_performance_health_degraded
        VoicePerformanceHealth.BLOCKED -> R.string.voice_performance_health_blocked
        VoicePerformanceHealth.NO_DATA -> R.string.voice_performance_health_no_data
    }
)

internal fun MainActivity.voicePerformanceResourceModeLabel(mode: VoiceResourceMode): String = getString(
    when (mode) {
        VoiceResourceMode.NORMAL -> R.string.voice_performance_resource_normal
        VoiceResourceMode.CONSERVE -> R.string.voice_performance_resource_conserve
        VoiceResourceMode.DEGRADED -> R.string.voice_performance_resource_degraded
        VoiceResourceMode.BLOCKED -> R.string.voice_performance_resource_blocked
    }
)

internal fun MainActivity.voicePerformanceMetricLabel(metricId: String): String = getString(
    when (metricId) {
        "asr_total_ms" -> R.string.voice_performance_metric_asr
        "model_first_delta_ms" -> R.string.voice_performance_metric_model
        "tts_first_audio_ms" -> R.string.voice_performance_metric_tts
        "agent_accept_ms" -> R.string.voice_performance_metric_agent_accept
        "agent_first_progress_ms" -> R.string.voice_performance_metric_agent_progress
        "agent_first_output_ms" -> R.string.voice_performance_metric_agent_output
        else -> R.string.voice_performance_title
    }
)

internal fun MainActivity.showWebIntelligenceSourcesPage() {
    showFeaturePage(getString(R.string.web_sources_title))
    val credentials = AgentEncryptedWebIntelligenceCredentials(this)
    val sourceStats = AgentEncryptedWebIntelligenceStore(this).stats()
    val learnedCount = (sourceStats["learned_source_count"] as? Number)?.toInt() ?: 0
    val verifiedCount =
        (sourceStats["verified_learned_source_count"] as? Number)?.toInt() ?: 0
    featureContent.addView(featureHeroCard(
        getString(R.string.web_sources_hero_title),
        getString(R.string.web_sources_hero_subtitle),
        R.drawable.ic_process_network,
        "#14C66A",
        getString(
            R.string.web_sources_count,
            AgentWebIntelligenceEngineCatalog.entries.size
        )
    ))
    addSectionTitle(getString(R.string.web_sources_title))
    featureContent.addView(featureValueRow(
        getString(R.string.web_sources_domain_coverage),
        getString(R.string.web_sources_domain_coverage_subtitle),
        R.drawable.ic_resource_network,
        getString(
            R.string.web_sources_category_count,
            AgentWebIntelligenceVertical.entries.count {
                it != AgentWebIntelligenceVertical.LOCAL
            }
        )
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.web_sources_learning),
        getString(R.string.web_sources_learning_subtitle),
        R.drawable.ic_process_network,
        getString(
            R.string.web_sources_learning_value,
            verifiedCount,
            (learnedCount - verifiedCount).coerceAtLeast(0)
        )
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.web_sources_compatibility),
        getString(R.string.web_sources_compatibility_subtitle),
        R.drawable.ic_process_network,
        getString(R.string.web_sources_compatibility_value)
    ))
    featureContent.addView(featureValueRow(
        getString(R.string.web_sources_brave_key),
        getString(R.string.web_sources_brave_key_subtitle),
        R.drawable.ic_avatar_cloud_model,
        webCredentialStatus(
            credentials.configured(AgentEncryptedWebIntelligenceCredentials.BRAVE_API_KEY)
        )
    ).apply {
        setOnClickListener {
            showWebCredentialDialog(
                getString(R.string.web_sources_brave_key),
                AgentEncryptedWebIntelligenceCredentials.BRAVE_API_KEY
            )
        }
    })
    featureContent.addView(featureValueRow(
        getString(R.string.web_sources_github_token),
        getString(R.string.web_sources_github_token_subtitle),
        R.drawable.ic_resource_network,
        webCredentialStatus(
            credentials.configured(AgentEncryptedWebIntelligenceCredentials.GITHUB_TOKEN)
        )
    ).apply {
        setOnClickListener {
            showWebCredentialDialog(
                getString(R.string.web_sources_github_token),
                AgentEncryptedWebIntelligenceCredentials.GITHUB_TOKEN
            )
        }
    })
}

internal fun MainActivity.webCredentialStatus(configured: Boolean): String =
    getString(
        if (configured) R.string.web_sources_configured
        else R.string.web_sources_not_configured
    )

internal fun MainActivity.showWebCredentialDialog(title: String, key: String) {
    val credentials = AgentEncryptedWebIntelligenceCredentials(this)
    val input = EditText(this).apply {
        hint = getString(R.string.web_sources_secret_hint)
        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        setPadding(dp(18), dp(10), dp(18), dp(10))
    }
    android.app.AlertDialog.Builder(this)
        .setTitle(title)
        .setView(input)
        .setPositiveButton(getString(R.string.common_save)) { _, _ ->
            val value = input.text?.toString()?.trim().orEmpty()
            if (value.isNotBlank()) {
                credentials.setCredential(key, value)
                Toast.makeText(this, R.string.web_sources_saved, Toast.LENGTH_SHORT).show()
            }
            showWebIntelligenceSourcesPage()
        }
        .setNeutralButton(getString(R.string.web_sources_clear)) { _, _ ->
            credentials.setCredential(key, "")
            Toast.makeText(this, R.string.web_sources_cleared, Toast.LENGTH_SHORT).show()
            showWebIntelligenceSourcesPage()
        }
        .setNegativeButton(getString(R.string.common_cancel), null)
        .show()
}

internal fun MainActivity.controlCenterGrantedPermissionCount(): Int = listOf(
    SignalASIAccessibilityService.isActive(),
    SignalASINotificationListenerService.currentContext().hasAccess,
    checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED,
    checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
).count { it }

internal fun MainActivity.appNotificationsEnabled(): Boolean =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() == true
    } else {
        true
    }

internal fun MainActivity.validatedInternetAvailable(): Boolean {
    val connectivity = getSystemService(ConnectivityManager::class.java) ?: return false
    val network = connectivity.activeNetwork ?: return false
    return connectivity.getNetworkCapabilities(network)
        ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true
}

internal fun MainActivity.showControlCenterDesktop(desktopId: String) {
    val desktop = desktopSecuritySummaries(activePcConnectorContacts()).firstOrNull { it.id == desktopId }
    if (desktop == null) {
        renderCurrentControlCenterDestination()
        return
    }
    openExistingControlCenterPage { showDesktopSecurityDetail(desktop) }
}

internal fun MainActivity.showNativeToolCatalogPage() {
    val runtime = mobileNativeAgent.snapshot().runtimeContext
    val tools = runtime.nativeTools
    val sections = tools
        .groupBy { it.location }
        .entries
        .sortedBy { it.key.ordinal }
        .map { (location, descriptors) ->
            ControlCenterSectionSpec(
                nativeToolLocationLabel(location),
                descriptors.sortedBy { it.title.lowercase(Locale.ROOT) }.map { tool ->
                    val available = runtime.isNativeToolExecutable(tool.id)
                    val effectiveStatus = nativeToolEffectiveAvailability(tool)
                    ControlCenterRowSpec(
                        actionId = "tool.detail:${tool.id}",
                        title = tool.title,
                        subtitle = tool.description,
                        iconRes = nativeToolIcon(tool),
                        status = getString(nativeToolAvailabilityLabel(effectiveStatus)),
                        tone = when {
                            !available -> nativeToolAvailabilityTone(effectiveStatus)
                            tool.risk == AgentNativeToolRisk.HIGH -> ControlCenterTone.RED
                            tool.risk == AgentNativeToolRisk.MEDIUM -> ControlCenterTone.AMBER
                            else -> ControlCenterTone.GREEN
                        }
                    )
                }
            )
        }
    showControlCenterFeature(
        getString(R.string.cc_tool_catalog_title),
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_tool_catalog_title),
                subtitle = getString(R.string.cc_tool_catalog_subtitle),
                iconRes = R.drawable.ic_agent_control,
                metrics = listOf(
                    ControlCenterMetricSpec(tools.size.toString(), getString(R.string.cc_metric_native_tools)),
                    ControlCenterMetricSpec(runtime.capabilityMatrix.availableNativeToolIds.size.toString(), getString(R.string.cc_metric_available_resources)),
                    ControlCenterMetricSpec(tools.count { it.risk == AgentNativeToolRisk.HIGH }.toString(), getString(R.string.cc_tool_risk_high))
                )
            ),
            sections = sections
        )
    )
}

internal fun MainActivity.showNativeToolDetailPage(toolId: String) {
    val tool = mobileNativeAgent.nativeToolCatalog().firstOrNull { it.id == toolId } ?: return
    val effectiveStatus = nativeToolEffectiveAvailability(tool)
    showControlCenterFeature(
        tool.title,
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = tool.title,
                subtitle = tool.description,
                iconRes = nativeToolIcon(tool),
                badges = listOf(
                    ControlCenterBadgeSpec(nativeToolRiskLabel(tool.risk), nativeToolRiskTone(tool.risk)),
                    ControlCenterBadgeSpec(nativeToolLocationLabel(tool.location), ControlCenterTone.BLUE),
                    ControlCenterBadgeSpec(
                        getString(nativeToolAvailabilityLabel(effectiveStatus)),
                        nativeToolAvailabilityTone(effectiveStatus)
                    )
                )
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.section_details),
                    listOf(
                        ControlCenterRowSpec("", getString(R.string.cc_tool_id), tool.id, R.drawable.ic_protocol_link, "v${tool.version}", ControlCenterTone.NEUTRAL, showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.feature_run_scope), nativeToolLocationLabel(tool.location), R.drawable.ic_device_node, "", ControlCenterTone.BLUE, showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.on_device_agent_section_permissions), getString(R.string.cc_tool_permissions, tool.requiredPermissions.size, nativeToolRiskLabel(tool.risk)), R.drawable.ic_security_shield, "", nativeToolRiskTone(tool.risk), showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.common_status), tool.availability.reason, R.drawable.ic_info_outline, getString(nativeToolAvailabilityLabel(effectiveStatus)), nativeToolAvailabilityTone(effectiveStatus), showChevron = false)
                    )
                )
            )
        )
    )
    setFeatureBackAction { showNativeToolCatalogPage() }
}

internal fun MainActivity.nativeToolLocationLabel(location: AgentNativeToolLocation): String = getString(
    when (location) {
        AgentNativeToolLocation.PHONE -> R.string.cc_tools_phone
        AgentNativeToolLocation.DESKTOP -> R.string.cc_tools_desktop
        AgentNativeToolLocation.APPLICATION -> R.string.cc_tools_application
        AgentNativeToolLocation.ANDROID_SYSTEM -> R.string.cc_tools_android_system
        AgentNativeToolLocation.ACCESSIBILITY_SERVICE -> R.string.cc_tools_accessibility
        AgentNativeToolLocation.UNKNOWN -> R.string.cc_tools_other
    }
)

internal fun MainActivity.nativeToolAvailabilityLabel(status: AgentNativeToolAvailabilityStatus): Int = when (status) {
    AgentNativeToolAvailabilityStatus.AVAILABLE -> R.string.cc_status_available
    AgentNativeToolAvailabilityStatus.REQUIRES_SETUP -> R.string.status_needs_setup
    AgentNativeToolAvailabilityStatus.UNAVAILABLE -> R.string.cc_status_unavailable
}

internal fun MainActivity.nativeToolEffectiveAvailability(tool: AgentNativeToolDescriptor): AgentNativeToolAvailabilityStatus =
    if (tool.risk == AgentNativeToolRisk.BLOCKED) {
        AgentNativeToolAvailabilityStatus.UNAVAILABLE
    } else {
        tool.availability.status
    }

internal fun MainActivity.nativeToolAvailabilityTone(status: AgentNativeToolAvailabilityStatus): ControlCenterTone = when (status) {
    AgentNativeToolAvailabilityStatus.AVAILABLE -> ControlCenterTone.GREEN
    AgentNativeToolAvailabilityStatus.REQUIRES_SETUP -> ControlCenterTone.AMBER
    AgentNativeToolAvailabilityStatus.UNAVAILABLE -> ControlCenterTone.NEUTRAL
}

internal fun MainActivity.nativeToolRiskLabel(risk: AgentNativeToolRisk): String = getString(
    when (risk) {
        AgentNativeToolRisk.LOW -> R.string.cc_tool_risk_low
        AgentNativeToolRisk.MEDIUM -> R.string.cc_tool_risk_medium
        AgentNativeToolRisk.HIGH -> R.string.cc_tool_risk_high
        AgentNativeToolRisk.BLOCKED -> R.string.cc_tool_risk_blocked
    }
)

internal fun MainActivity.nativeToolRiskTone(risk: AgentNativeToolRisk): ControlCenterTone = when (risk) {
    AgentNativeToolRisk.LOW -> ControlCenterTone.GREEN
    AgentNativeToolRisk.MEDIUM -> ControlCenterTone.AMBER
    AgentNativeToolRisk.HIGH, AgentNativeToolRisk.BLOCKED -> ControlCenterTone.RED
}

internal fun MainActivity.nativeToolIcon(tool: AgentNativeToolDescriptor): Int = when {
    tool.id.contains("camera") || tool.id.contains("torch") -> R.drawable.ic_scan
    tool.id.contains("audio") || tool.id.contains("microphone") -> R.drawable.ic_input_voice
    tool.id.contains("notification") -> R.drawable.ic_settings_notification
    tool.id.contains("contact") -> R.drawable.ic_tab_contacts_outline
    tool.id.contains("message") || tool.id.contains("sms") -> R.drawable.ic_tab_chat
    tool.id.contains("file") || tool.id.contains("storage") -> R.drawable.ic_import
    tool.id.contains("network") || tool.id.contains("wifi") || tool.id.contains("bluetooth") -> R.drawable.ic_protocol_link
    tool.id.contains("security") || tool.risk == AgentNativeToolRisk.HIGH -> R.drawable.ic_security_shield
    else -> R.drawable.ic_agent_control
}

internal fun MainActivity.showAgentAuditOperationsPage() {
    val state = mobileNativeAgent.snapshot()
    val nativeToolDescriptors = mobileNativeAgent.nativeToolCatalog().associateBy { it.id }
    val nativeToolRows = mobileNativeAgent.nativeToolAudit(limit = 50).map { record ->
        val descriptor = nativeToolDescriptors[record.toolId]
        ControlCenterRowSpec(
            actionId = "",
            title = descriptor?.title ?: record.toolId,
            subtitle = getString(
                R.string.cc_tool_audit_detail,
                nativeToolAuditStatusLabel(record.status),
                record.durationMillis
            ),
            iconRes = descriptor?.let(::nativeToolIcon) ?: R.drawable.ic_agent_control,
            status = securityTime(record.finishedAtEpochMillis),
            tone = nativeToolAuditTone(record.status),
            showChevron = false
        )
    }
    val auditRows = state.auditTrail.asReversed().take(20).map { entry ->
        ControlCenterRowSpec(
            actionId = "",
            title = controlCenterAuditEventLabel(entry.event),
            subtitle = entry.detail.ifBlank { securityTime(entry.timestampMillis) },
            iconRes = R.drawable.ic_protocol_link,
            status = securityTime(entry.timestampMillis),
            tone = ControlCenterTone.BLUE,
            showChevron = false
        )
    }
    val taskRows = state.recentTasks.take(20).map { task ->
        ControlCenterRowSpec(
            actionId = "",
            title = task.goal,
            subtitle = task.targetTitle,
            iconRes = R.drawable.ic_agent_history,
            status = agentTaskStatusText(task),
            tone = if (task.phase == AgentPhase.COMPLETED) ControlCenterTone.GREEN else if (task.phase == AgentPhase.FAILED) ControlCenterTone.RED else ControlCenterTone.AMBER,
            showChevron = false
        )
    }
    showControlCenterFeature(
        getString(R.string.feature_audit_log),
        ControlCenterPageSpec(
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_tool_audit_title),
                    nativeToolRows.ifEmpty {
                        listOf(
                            ControlCenterRowSpec(
                                "",
                                getString(R.string.cc_audit_empty),
                                getString(R.string.cc_audit_empty_subtitle),
                                R.drawable.ic_info_outline,
                                "",
                                showChevron = false
                            )
                        )
                    }
                ),
                ControlCenterSectionSpec(
                    getString(R.string.feature_audit_log),
                    auditRows.ifEmpty { listOf(ControlCenterRowSpec("", getString(R.string.cc_audit_empty), getString(R.string.cc_audit_empty_subtitle), R.drawable.ic_info_outline, "", showChevron = false)) }
                ),
                ControlCenterSectionSpec(getString(R.string.cc_tasks_title), taskRows)
            )
        )
    )
}

internal fun MainActivity.nativeToolAuditStatusLabel(status: AgentNativeToolResultStatus): String = getString(
    when (status) {
        AgentNativeToolResultStatus.SUCCEEDED -> R.string.cc_tool_audit_succeeded
        AgentNativeToolResultStatus.FAILED -> R.string.cc_tool_audit_failed
        AgentNativeToolResultStatus.VERIFICATION_FAILED -> R.string.cc_tool_audit_verification_failed
        AgentNativeToolResultStatus.REJECTED -> R.string.cc_tool_audit_rejected
        AgentNativeToolResultStatus.UNAVAILABLE -> R.string.cc_tool_audit_unavailable
        AgentNativeToolResultStatus.CANCELLED -> R.string.cc_tool_audit_cancelled
        AgentNativeToolResultStatus.TIMED_OUT -> R.string.cc_tool_audit_timed_out
    }
)

internal fun MainActivity.nativeToolAuditTone(status: AgentNativeToolResultStatus): ControlCenterTone = when (status) {
    AgentNativeToolResultStatus.SUCCEEDED -> ControlCenterTone.GREEN
    AgentNativeToolResultStatus.CANCELLED,
    AgentNativeToolResultStatus.UNAVAILABLE -> ControlCenterTone.AMBER
    AgentNativeToolResultStatus.FAILED,
    AgentNativeToolResultStatus.VERIFICATION_FAILED,
    AgentNativeToolResultStatus.REJECTED,
    AgentNativeToolResultStatus.TIMED_OUT -> ControlCenterTone.RED
}

internal fun MainActivity.controlCenterAuditEventLabel(event: AgentAuditEvent): String = getString(
    when (event) {
        AgentAuditEvent.SCREEN_OBSERVED,
        AgentAuditEvent.SCREEN_VERIFIED -> R.string.cc_audit_screen
        AgentAuditEvent.CHECKPOINT_SAVED,
        AgentAuditEvent.CHECKPOINT_RESTORED,
        AgentAuditEvent.CHECKPOINT_RESTORE_FAILED,
        AgentAuditEvent.ACTION_RECOVERY_STARTED,
        AgentAuditEvent.ACTION_RECOVERY_COMPLETED,
        AgentAuditEvent.ACTION_RECOVERY_MANUAL_REQUIRED -> R.string.cc_audit_recovery
        AgentAuditEvent.PLAN_REPLANNED,
        AgentAuditEvent.PLAN_REPLAN_LIMIT_REACHED,
        AgentAuditEvent.PLAN_EDITED,
        AgentAuditEvent.PLAN_EDIT_REJECTED,
        AgentAuditEvent.REASONING_SUMMARY -> R.string.cc_audit_planning
        AgentAuditEvent.TOOL_STARTED,
        AgentAuditEvent.TOOL_COMPLETED,
        AgentAuditEvent.TOOL_OUTPUT_HANDOFF,
        AgentAuditEvent.TOOL_GRAPH_BLOCKED,
        AgentAuditEvent.AUTONOMY_GUARD_BLOCKED,
        AgentAuditEvent.INVOCATION_AUDIT,
        AgentAuditEvent.CONNECTOR_RESPONSE_RECEIVED,
        AgentAuditEvent.RESPONSE_SELF_CHECK_PASSED,
        AgentAuditEvent.RESPONSE_SELF_CHECK_FAILED -> R.string.cc_audit_resource
        AgentAuditEvent.GOAL_RECEIVED -> R.string.cc_audit_goal
        AgentAuditEvent.MEMORY_SKIPPED,
        AgentAuditEvent.MEMORY_FORGOTTEN,
        AgentAuditEvent.MEMORY_UPDATED,
        AgentAuditEvent.MEMORY_CONFLICT_DETECTED,
        AgentAuditEvent.MEMORY_CONFLICT_RESOLVED -> R.string.cc_audit_memory
        AgentAuditEvent.KNOWLEDGE_IMPORTED,
        AgentAuditEvent.KNOWLEDGE_ACCESSED,
        AgentAuditEvent.KNOWLEDGE_ACCESS_UPDATED -> R.string.cc_audit_knowledge
        AgentAuditEvent.WORKFLOW_UPDATED,
        AgentAuditEvent.WORKFLOW_RUN -> R.string.cc_audit_workflow
        AgentAuditEvent.ACTION_EXECUTED,
        AgentAuditEvent.ACTION_BLOCKED -> R.string.cc_audit_action
        AgentAuditEvent.TASK_CANCELLED,
        AgentAuditEvent.TASK_PAUSED,
        AgentAuditEvent.TASK_RESUMED,
        AgentAuditEvent.TASK_INTERRUPTED -> R.string.cc_audit_task
        AgentAuditEvent.SETTINGS_UPDATED -> R.string.cc_audit_settings
    }
)

internal fun MainActivity.showHomeAssistantCollectionPage(collection: String) {
    val title = if (collection == "automations") getString(R.string.cc_home_automations_title) else getString(R.string.cc_home_entities_title)
    showControlCenterFeature(
        title,
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(getString(R.string.cc_loading), getString(R.string.cc_home_assistant_connected), R.drawable.ic_device_node),
            sections = emptyList()
        )
    )
    thread(name = "signalasi-home-assistant-$collection") {
        val result = if (collection == "automations") {
            HomeAssistantDeviceClient.listAutomations(this)
        } else {
            HomeAssistantDeviceClient.listEntities(this)
        }
        runOnUiThread {
            if (featurePage.visibility != View.VISIBLE || featureTitle.text.toString() != title) return@runOnUiThread
            val rows = result.entities.take(80).map { entity ->
                ControlCenterRowSpec(
                    actionId = "ha.entity:${entity.entityId}",
                    title = entity.friendlyName.ifBlank { entity.entityId },
                    subtitle = entity.entityId,
                    iconRes = R.drawable.ic_device_node,
                    status = entity.state,
                    tone = if (entity.state.equals("unavailable", true)) ControlCenterTone.AMBER else ControlCenterTone.GREEN
                )
            }
            controlCenterRenderer.render(
                featureContent,
                ControlCenterPageSpec(
                    banner = if (result.success) null else ControlCenterBannerSpec(getString(R.string.cc_home_load_failed), result.message, R.drawable.ic_info_outline, ControlCenterTone.AMBER),
                    sections = listOf(ControlCenterSectionSpec(
                        title,
                        rows.ifEmpty { listOf(ControlCenterRowSpec("", getString(R.string.cc_home_empty), result.message, R.drawable.ic_info_outline, "", showChevron = false)) }
                    ))
                ),
                ::handleControlCenterAction
            )
        }
    }
}

internal fun MainActivity.showHomeAssistantEntityDetailPage(entityId: String) {
    val parentTitle = featureTitle.text.toString()
    showControlCenterFeature(
        entityId,
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(getString(R.string.cc_loading), entityId, R.drawable.ic_device_node),
            sections = emptyList()
        )
    )
    setFeatureBackAction {
        showHomeAssistantCollectionPage(if (parentTitle == getString(R.string.cc_home_automations_title)) "automations" else "entities")
    }
    thread(name = "signalasi-home-assistant-entity") {
        val result = HomeAssistantDeviceClient.readEntity(this, entityId)
        runOnUiThread {
            if (featurePage.visibility != View.VISIBLE || featureTitle.text.toString() != entityId) return@runOnUiThread
            val entity = result.entities.firstOrNull()
            val displayTitle = entity?.friendlyName?.ifBlank { entityId } ?: entityId
            controlCenterRenderer.render(
                featureContent,
                ControlCenterPageSpec(
                    hero = ControlCenterHeroSpec(
                        title = displayTitle,
                        subtitle = entityId,
                        iconRes = R.drawable.ic_device_node,
                        badges = listOf(ControlCenterBadgeSpec(entity?.state ?: result.message, if (result.success) ControlCenterTone.GREEN else ControlCenterTone.AMBER))
                    ),
                    sections = listOf(ControlCenterSectionSpec(
                        getString(R.string.section_details),
                        listOf(ControlCenterRowSpec("", getString(R.string.common_status), getString(R.string.cc_entity_state, entity?.state ?: result.message), R.drawable.ic_info_outline, "", showChevron = false))
                    ))
                ),
                ::handleControlCenterAction
            )
        }
    }
}

internal fun MainActivity.clearRebuildableCache() {
    cacheDir.listFiles().orEmpty().forEach { runCatching { it.deleteRecursively() } }
    Toast.makeText(this, getString(R.string.cc_cache_cleared), Toast.LENGTH_SHORT).show()
    renderCurrentControlCenterDestination()
}

internal fun MainActivity.directorySize(root: File): Long = runCatching {
    root.walkTopDown().filter(File::isFile).sumOf(File::length)
}.getOrDefault(0L)

internal fun MainActivity.formatMegabytes(value: Long): String = if (value >= 1024L) {
    String.format(Locale.US, "%.1f GB", value / 1024.0)
} else {
    "$value MB"
}

internal fun MainActivity.formatBytes(value: Long): String = when {
    value >= 1024L * 1024L * 1024L -> String.format(Locale.US, "%.1f GB", value / (1024.0 * 1024.0 * 1024.0))
    value >= 1024L * 1024L -> String.format(Locale.US, "%.1f MB", value / (1024.0 * 1024.0))
    value >= 1024L -> String.format(Locale.US, "%.1f KB", value / 1024.0)
    else -> "$value B"
}

internal fun MainActivity.compactFingerprint(value: String): String {
    val clean = value.filter(Char::isLetterOrDigit)
    return if (clean.length > 14) "${clean.take(6)}…${clean.takeLast(5)}" else clean
}

internal fun MainActivity.installedVersionName(): String = runCatching {
    packageManager.getPackageInfo(packageName, 0).versionName.orEmpty()
}.getOrDefault("").ifBlank { "0.1" }
