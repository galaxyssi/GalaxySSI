package com.signalasi.chat

import android.app.Activity
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

internal fun MainActivity.styleSettingsRows() {
    // Apply WeChat-style row styling
    listOf(
        R.id.languageSettingsButton,
        R.id.exportBackupButton, R.id.importBackupButton, R.id.protocolQualityButton,
        R.id.advancedOptionsButton, R.id.localModelSettingsButton,
        R.id.voiceAssistantSettingsButton, R.id.onDeviceAgentButton, R.id.destroyDataButton
    ).forEach { id ->
        findViewById<View>(id)?.let {
            if (it is TextView) {
                it.compoundDrawablePadding = 12
                it.compoundDrawableTintList = android.content.res.ColorStateList.valueOf(
                    getColorCompat(R.color.text_secondary)
                )
                it.setPadding(dp(16), 0, dp(16), 0)
            }
        }
    }
    normalizeSettingsRowVisuals()
}

internal fun MainActivity.configureSettingsControlCenter() {
    controlCenterBackStack.clear()
    controlCenterDestination = null
}

internal fun MainActivity.removeSettingsRow(card: ViewGroup, rowId: Int) {
    val row = findViewById<View>(rowId) ?: return
    val index = card.indexOfChild(row)
    if (index < 0) return
    card.removeViewAt(index)
    val dividerIndex = index.coerceAtMost(card.childCount - 1)
    if (dividerIndex >= 0 && card.getChildAt(dividerIndex).layoutParams.height <= dp(1)) {
        card.removeViewAt(dividerIndex)
    }
}

internal fun MainActivity.normalizeSettingsRowVisuals() {
    val cards = listOf(
        R.id.settingsAgentToolsCard, R.id.settingsLocalAgentCard,
        R.id.settingsProtocolCard, R.id.settingsDataCard,
        R.id.settingsIdentityCard, R.id.settingsGeneralCard,
        R.id.settingsPagesCard
    )
    cards.forEach { normalizeSettingsRows(findViewById(it)) }
    normalizeSettingsTextRow(findViewById(R.id.destroyDataButton))
    listOf(R.id.aboutSignalASIArrow).forEach { id ->
        findViewById<ImageView>(id).apply {
            setImageDrawable(settingsDrawable(R.drawable.ic_arrow_right, "#C7C7CC", 16))
            layoutParams = layoutParams.apply { width = dp(24) }
            scaleType = ImageView.ScaleType.CENTER
        }
    }
    findViewById<ViewGroup>(R.id.aboutSignalASIButton).apply {
        layoutParams = layoutParams.apply { height = dp(62) }
        val icon = getChildAt(0) as ImageView
        icon.layoutParams = icon.layoutParams.apply { width = dp(24); height = dp(24) }
        icon.background = null
        icon.setPadding(0, 0, 0, 0)
        icon.imageTintList = android.content.res.ColorStateList.valueOf(getColorCompat(R.color.text_primary))
        val title = ((getChildAt(1) as LinearLayout).getChildAt(0) as TextView)
        title.text = getString(R.string.settings_about_short)
        title.textSize = 15f
        title.setTextColor(getColorCompat(R.color.text_primary))
        title.setTypeface(title.typeface, android.graphics.Typeface.NORMAL)
    }
}

internal fun MainActivity.normalizeSettingsRows(view: View) {
    when (view) {
        is TextView -> normalizeSettingsTextRow(view)
        is ViewGroup -> for (index in 0 until view.childCount) normalizeSettingsRows(view.getChildAt(index))
    }
}

internal fun MainActivity.normalizeSettingsTextRow(row: TextView) {
    val current = row.compoundDrawablesRelative
    if (current.all { it == null }) return
    val start = current[0]?.constantState?.newDrawable(resources)?.mutate()?.apply {
        setTint(Color.parseColor("#202124"))
        setBounds(0, 0, dp(24), dp(24))
    }
    val end = settingsDrawable(R.drawable.ic_arrow_right, "#C7C7CC", 16)
    row.compoundDrawableTintList = null
    row.setCompoundDrawablesRelative(start, null, end, null)
    row.compoundDrawablePadding = dp(14)
    row.textSize = 15f
    row.setTextColor(getColorCompat(R.color.text_primary))
    row.setTypeface(row.typeface, android.graphics.Typeface.NORMAL)
}

internal fun MainActivity.settingsDrawable(resourceId: Int, color: String, sizeDp: Int) =
    requireNotNull(getDrawable(resourceId)).mutate().apply {
        setTint(Color.parseColor(color))
        setBounds(0, 0, dp(sizeDp), dp(sizeDp))
    }

internal fun MainActivity.sectionTitle(viewId: Int, textId: Int) {
    findViewById<TextView>(viewId).apply {
        setText(textId)
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 13f
        setTypeface(typeface, android.graphics.Typeface.BOLD)
        setPadding(dp(3), dp(2), 0, 0)
    }
}

internal fun MainActivity.settingsSectionTitleView(textId: Int): TextView = TextView(this).apply {
    setText(textId)
    setTextColor(getColorCompat(R.color.text_primary))
    textSize = 13f
    setTypeface(typeface, android.graphics.Typeface.BOLD)
    setPadding(dp(3), dp(14), 0, dp(6))
}

internal fun MainActivity.rebuildProfileStatusBadges() {
    val textColumn = meProfileText.parent as LinearLayout
    if (textColumn.childCount > 2) return
    textColumn.addView(LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(0, dp(6), 0, 0)
        addView(settingsBadge(R.string.settings_badge_agent_enabled, "#E8F8EF", "#27885A"))
        addView(settingsBadge(R.string.settings_badge_connection_ok, "#EAF2FF", "#3678D4").apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                dp(24)
            ).apply { marginStart = dp(7) }
        })
    })
}

internal fun MainActivity.settingsBadge(textId: Int, backgroundColor: String, textColor: String): TextView =
    TextView(this).apply {
        setText(textId)
        setTextColor(Color.parseColor(textColor))
        textSize = 11f
        gravity = Gravity.CENTER
        includeFontPadding = false
        setPadding(dp(9), 0, dp(9), 0)
        background = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(12).toFloat()
            setColor(Color.parseColor(backgroundColor))
        }
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(24))
    }

internal fun MainActivity.rebuildIdentitySecurityCard() {
    val card = findViewById<LinearLayout>(R.id.settingsIdentityCard)
    (meIdText.parent as? ViewGroup)?.removeView(meIdText)
    card.removeAllViews()
    card.addView(meIdText)
    card.addView(settingsDivider())
    card.addView(dynamicSettingsRow(
        R.string.settings_trusted_devices,
        R.string.settings_trusted_devices_subtitle,
        R.drawable.ic_settings_devices
    ) { showSecurityFeaturePage() })
    card.addView(settingsDivider())
    card.addView(dynamicSettingsRow(
        R.string.settings_permission_audit,
        R.string.settings_permission_audit_subtitle,
        R.drawable.ic_security_shield
    ) { showOnDeviceAgentFeaturePage() })
}

internal fun MainActivity.rebuildGeneralCard() {
    val card = findViewById<LinearLayout>(R.id.settingsGeneralCard)
    val language = findViewById<TextView>(R.id.languageSettingsButton)
    (language.parent as? ViewGroup)?.removeView(language)
    card.removeAllViews()
    card.addView(language)
    card.addView(settingsDivider())
    card.addView(dynamicSettingsRow(
        R.string.settings_notifications,
        R.string.settings_notifications_subtitle,
        R.drawable.ic_settings_notification
    ) {
        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        })
    })
}

internal fun MainActivity.dynamicSettingsRow(titleId: Int, subtitleId: Int, iconId: Int, action: () -> Unit): TextView =
    TextView(this).apply {
        setCompoundDrawablesWithIntrinsicBounds(iconId, 0, R.drawable.ic_arrow_right, 0)
        compoundDrawablePadding = dp(14)
        setPadding(dp(16), 0, dp(16), 0)
        setOnClickListener { action() }
        settingsText(getString(titleId), getString(subtitleId))
    }

internal fun MainActivity.settingsDivider(): View = View(this).apply {
    setBackgroundColor(getColorCompat(R.color.separator))
    layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 1).apply {
        marginStart = dp(56)
    }
}

internal fun MainActivity.applySettingsCardSurfaces() {
    listOf(
        R.id.meProfileCard, R.id.settingsAgentToolsCard, R.id.settingsLocalAgentCard,
        R.id.settingsProtocolCard, R.id.settingsDataCard, R.id.settingsIdentityCard,
        R.id.settingsGeneralCard, R.id.settingsPagesCard,
        R.id.aboutSignalASIButton, R.id.destroyDataButton
    ).forEach { findViewById<View>(it).setBackgroundResource(R.drawable.settings_control_card_background) }
}

internal fun MainActivity.settingsStatusRow(viewId: Int, titleId: Int, status: String) {
    findViewById<TextView>(viewId).apply {
        settingsText(getString(titleId), status)
        setTypeface(typeface, android.graphics.Typeface.NORMAL)
    }
}

internal fun MainActivity.refreshSettingsControlCenter(force: Boolean = false) {
    val now = SystemClock.elapsedRealtime()
    val visible = activeMainTab == PAGE_SETTINGS && featurePage.visibility != View.VISIBLE
    if (!controlCenterHomeRefreshPolicy.shouldRefresh(visible, now, force)) return
    renderControlCenterHome()
}

internal fun MainActivity.refreshSettingsControlCenterAsync(navigationToken: Long) {
    val now = SystemClock.elapsedRealtime()
    val visible = activeMainTab == PAGE_SETTINGS && featurePage.visibility != View.VISIBLE
    if (!controlCenterHomeRefreshPolicy.shouldRefresh(visible, now)) return
    navigationContentExecutor.execute {
        val page = runCatching(::buildControlCenterHomePage).getOrNull()
        handler.post {
            if (page != null &&
                activeMainTab == PAGE_SETTINGS &&
                featurePage.visibility != View.VISIBLE &&
                navigationContentGate.isCurrent(navigationToken)
            ) {
                renderControlCenterHomePage(page)
            }
        }
    }
}

internal fun MainActivity.renderControlCenterHome() {
    val content = findViewById<LinearLayout>(R.id.settingsContent)
    renderControlCenterHomePage(buildControlCenterHomePage(), content)
}

internal fun MainActivity.buildControlCenterHomePage(): ControlCenterPageSpec {
    val state = mobileNativeAgent.snapshot()
    val tools = mobileNativeAgent.nativeToolCatalog()
    val availableTools = tools.count { it.availability.status == AgentNativeToolAvailabilityStatus.AVAILABLE }
    val toolsNeedingAttention = tools.size - availableTools
    val availableResources = controlCenterResourceTargets(state.callableTargets)
        .count { it.status == AgentConnectorStatus.AVAILABLE }
    val trustedDeviceCount = desktopSecuritySummaries(activePcConnectorContacts()).size
    val memoryCount = mobileNativeAgent.memorySnapshot().activeCount
    val knowledgeCount = mobileNativeAgent.knowledgeSourceGroups().size
    val recentTasks = state.recentTasks.size
    val safety = mobileNativeAgent.safetySettings()
    val planner = mobileNativeAgent.modelPlannerSettings()
    val privacyProtected = !planner.shareScreenText && !planner.shareAgentOutputsWithPlanner
    val secure = SignalASIMqttClient.isConnected() && SignalASIMqttClient.isSecureReady()
    val homeAssistant = HomeAssistantSettingsStore.load(this)
    val homeAssistantReady = homeAssistant.configured
    val onDeviceRuntime = AgentOnDeviceRuntimeManager(this).status()
    val localModelInstalled = LocalModelInferenceRuntime.ready(this)
    val globalRuntime = if (isGlobalSuperAgentRuntimeInitialized()) {
        globalSuperAgentRuntime
    } else GlobalSuperAgentRuntime.get(this)
    val globalDashboard = globalRuntime.dashboard()
    val globalSettings = globalRuntime.settings()
    val remoteControlDevices = desktopControlDevices()
    val remoteControlSnapshots = remoteControlDevices.map { device ->
        DesktopRemoteControl.snapshot(this, device.id)
    }
    val remoteControlStatus = when {
        remoteControlDevices.isEmpty() -> getString(R.string.status_needs_setup)
        remoteControlSnapshots.any { it.authorized } -> getString(R.string.status_enabled)
        remoteControlSnapshots.any { it.pending } -> getString(R.string.desktop_control_pending)
        remoteControlSnapshots.any { it.enabled } -> getString(R.string.desktop_control_not_authorized)
        else -> getString(R.string.desktop_control_executor_off)
    }
    val remoteControlTone = when {
        remoteControlSnapshots.any { it.authorized } -> ControlCenterTone.GREEN
        remoteControlSnapshots.any { it.pending } -> ControlCenterTone.AMBER
        remoteControlDevices.isEmpty() -> ControlCenterTone.NEUTRAL
        else -> ControlCenterTone.BLUE
    }
    val homeRows = linkedMapOf(
        ControlCenterRoute.GLOBAL_AGENT to ccRouteRow(
            ControlCenterRoute.GLOBAL_AGENT,
            getString(R.string.cc_global_agent_title),
            getString(
                R.string.cc_global_agent_home_subtitle,
                globalDashboard.topicCount,
                globalDashboard.activeGoalCount,
                globalDashboard.pendingInsightCount
            ),
            R.drawable.ic_agent_node,
            getString(if (globalSettings.enabled) R.string.cc_status_online else R.string.on_device_agent_status_paused),
            if (globalSettings.enabled) ControlCenterTone.VIOLET else ControlCenterTone.AMBER
        ),
        ControlCenterRoute.PHONE_CAPABILITIES to ccRouteRow(
            ControlCenterRoute.PHONE_CAPABILITIES,
            getString(R.string.cc_phone_title),
            getString(R.string.cc_phone_subtitle, availableTools, toolsNeedingAttention),
            R.drawable.ic_agent_control,
            "$availableTools/${tools.size}",
            if (availableTools > 0) ControlCenterTone.GREEN else ControlCenterTone.AMBER
        ),
        ControlCenterRoute.SMART_SPACES to ccRouteRow(
            ControlCenterRoute.SMART_SPACES,
            R.string.cc_spaces_title,
            R.string.cc_spaces_subtitle,
            R.drawable.ic_device_node,
            getString(
                when {
                    !homeAssistant.credentialsConfigured -> R.string.cc_status_not_configured
                    homeAssistantReady -> R.string.status_enabled
                    else -> R.string.common_off
                }
            ),
            if (homeAssistantReady) ControlCenterTone.GREEN else ControlCenterTone.AMBER
        ),
        ControlCenterRoute.RESOURCE_ROUTING to ccRouteRow(
            ControlCenterRoute.RESOURCE_ROUTING,
            R.string.cc_resource_routing_title,
            R.string.cc_resource_routing_subtitle,
            R.drawable.ic_settings_model,
            getString(if (availableResources > 0) R.string.cc_status_available else R.string.status_needs_setup),
            if (availableResources > 0) ControlCenterTone.BLUE else ControlCenterTone.AMBER
        ),
        ControlCenterRoute.ON_DEVICE_RUNTIME to ccRouteRow(
            ControlCenterRoute.ON_DEVICE_RUNTIME,
            R.string.cc_runtime_title,
            R.string.cc_runtime_subtitle,
            R.drawable.ic_settings_diagnostics,
            getString(if (onDeviceRuntime.backendReady) R.string.cc_status_ready else R.string.status_needs_setup),
            if (onDeviceRuntime.backendReady) ControlCenterTone.GREEN else ControlCenterTone.AMBER
        ),
        ControlCenterRoute.VOICE to ccRouteRow(
            ControlCenterRoute.VOICE,
            R.string.cc_voice_title,
            R.string.cc_voice_subtitle,
            R.drawable.ic_settings_voice,
            getString(if (VoiceAssistantSettings.get(this).enabled) R.string.status_enabled else R.string.common_off),
            ControlCenterTone.BLUE
        ),
        ControlCenterRoute.MEMORY to ccRouteRow(
            ControlCenterRoute.MEMORY,
            getString(R.string.cc_memory_title),
            getString(R.string.cc_memory_subtitle, memoryCount),
            R.drawable.ic_agent_memory,
            getString(if (safety.memoryCapture) R.string.status_enabled else R.string.common_off),
            if (safety.memoryCapture) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL
        ),
        ControlCenterRoute.KNOWLEDGE to ccRouteRow(
            ControlCenterRoute.KNOWLEDGE,
            getString(R.string.cc_knowledge_title),
            getString(R.string.cc_knowledge_subtitle, knowledgeCount),
            R.drawable.ic_agent_knowledge,
            knowledgeCount.toString(),
            ControlCenterTone.AMBER
        ),
        ControlCenterRoute.LEARNING to ccRouteRow(
            ControlCenterRoute.LEARNING,
            R.string.cc_learning_title,
            R.string.cc_learning_subtitle,
            R.drawable.ic_agent_skill,
            agentLearningEngine.proposals(AgentLearningProposalStatus.PENDING).size.toString(),
            ControlCenterTone.VIOLET
        ),
        ControlCenterRoute.AGENT_CORE to ccRouteRow(
            ControlCenterRoute.AGENT_CORE,
            R.string.cc_agent_identity_title,
            R.string.cc_agent_identity_subtitle,
            R.drawable.ic_agent_node,
            getString(if (safety.executionPaused) R.string.on_device_agent_status_paused else R.string.cc_status_online),
            if (safety.executionPaused) ControlCenterTone.AMBER else ControlCenterTone.GREEN
        ),
        ControlCenterRoute.MCP to ccRouteRow(
            ControlCenterRoute.MCP,
            R.string.agent_capability_library_title,
            R.string.agent_capability_library_subtitle,
            R.drawable.ic_agent_skill,
            AgentDefaultCapabilityCatalog.marketplaceItems(
                mobileNativeAgent.nativeToolCatalog(),
                agentMcpRegistry.list(),
                agentSkillRuntime.list()
            ).count {
                it.installState in setOf(
                    AgentMarketplaceInstallState.BUILT_IN,
                    AgentMarketplaceInstallState.INSTALLED
                )
            }.toString(),
            ControlCenterTone.VIOLET
        ),
        ControlCenterRoute.SELF_EVOLUTION to ccRouteRow(
            ControlCenterRoute.SELF_EVOLUTION,
            R.string.cc_evolution_title,
            R.string.cc_evolution_subtitle,
            R.drawable.ic_reset_data,
            getString(
                R.string.cc_evolution_candidate_count,
                AgentSelfEvolutionService.manager(this).list(500)
                    .count { it.status == AgentSelfEvolutionStatus.WAITING_APPROVAL }
            ),
            ControlCenterTone.VIOLET
        ),
        ControlCenterRoute.DATA_BACKUP to ccRouteRow(
            ControlCenterRoute.DATA_BACKUP,
            R.string.cc_identity_recovery_title,
            R.string.cc_identity_recovery_subtitle,
            R.drawable.ic_settings_upload,
            "",
            ControlCenterTone.VIOLET
        ),
        ControlCenterRoute.GENERAL to ccRouteRow(
            ControlCenterRoute.GENERAL,
            R.string.cc_general_title,
            R.string.cc_general_subtitle,
            R.drawable.ic_tab_settings,
            "",
            ControlCenterTone.NEUTRAL
        )
    )
    val homeLeadingRows = mapOf(
        ControlCenterHomeGroup.MODELS to listOf(
            ControlCenterRowSpec(
                actionId = "local_model.open",
                title = getString(R.string.local_model_title),
                subtitle = getString(R.string.local_model_search_subtitle),
                iconRes = R.drawable.ic_local_model,
                status = getString(
                    if (localModelInstalled) {
                        R.string.local_model_download_ready
                    } else {
                        R.string.status_needs_setup
                    }
                ),
                tone = if (localModelInstalled) ControlCenterTone.GREEN else ControlCenterTone.BLUE
            )
        )
    )
    val homeTrailingRows = mapOf(
        ControlCenterHomeGroup.CONNECTED_DEVICES to listOf(
            ControlCenterRowSpec(
                actionId = "desktop.remote_control",
                title = getString(R.string.desktop_control_title),
                subtitle = getString(R.string.desktop_control_home_subtitle),
                iconRes = R.drawable.ic_device_node,
                status = remoteControlStatus,
                tone = remoteControlTone
            )
        ),
        ControlCenterHomeGroup.SECURITY_DATA to listOf(
            ControlCenterRowSpec(
                actionId = "general.about",
                title = getString(R.string.cc_about_title),
                subtitle = getString(R.string.cc_about_subtitle),
                iconRes = R.drawable.ic_info_outline,
                status = "v${installedVersionName()}",
                tone = ControlCenterTone.NEUTRAL
            )
        )
    )

    return ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = getString(R.string.settings_my_signalasi),
                subtitle = getString(R.string.cc_product_subtitle),
                iconRes = R.drawable.signalasi_mark_large,
                preserveIconColor = true,
                titleActionId = "profile.nickname",
                trailingActionId = "profile.qr",
                trailingIconRes = R.drawable.ic_qr,
                trailingContentDescription = getString(R.string.contact_my_qr_title),
                badges = listOf(
                    ControlCenterBadgeSpec(
                        getString(if (safety.executionPaused) R.string.on_device_agent_status_paused else R.string.cc_core_ready),
                        if (safety.executionPaused) ControlCenterTone.AMBER else ControlCenterTone.GREEN
                    ),
                    ControlCenterBadgeSpec(getString(R.string.cc_trusted_devices_badge, trustedDeviceCount), ControlCenterTone.BLUE),
                    ControlCenterBadgeSpec(
                        getString(if (privacyProtected) R.string.cc_privacy_badge else R.string.cc_status_review),
                        if (privacyProtected) ControlCenterTone.NEUTRAL else ControlCenterTone.AMBER
                    )
                ),
                metrics = listOf(
                    ControlCenterMetricSpec(availableResources.toString(), getString(R.string.cc_metric_resources)),
                    ControlCenterMetricSpec(recentTasks.toString(), getString(R.string.cc_metric_today_tasks)),
                    ControlCenterMetricSpec(getString(if (secure) R.string.cc_status_secure else R.string.cc_status_normal), getString(R.string.cc_metric_security))
                )
            ),
            sections = ControlCenterHomeGrouping.orderedGroups.map { group ->
                ControlCenterSectionSpec(
                    controlCenterHomeGroupTitle(group),
                    homeLeadingRows[group].orEmpty() +
                        ControlCenterHomeGrouping.routes(group)
                            .mapNotNull { route -> homeRows[route] } +
                        homeTrailingRows[group].orEmpty()
                )
            }
    )
}

internal fun MainActivity.renderControlCenterHomePage(
    page: ControlCenterPageSpec,
    content: LinearLayout = findViewById(R.id.settingsContent)
) {
    if (controlCenterHomeRenderCache.shouldRender(page, content.childCount > 0)) {
        controlCenterRenderer.render(content, page, ::handleControlCenterAction)
    }
    controlCenterHomeRefreshPolicy.markRendered(SystemClock.elapsedRealtime())
}

internal fun MainActivity.controlCenterHomeGroupTitle(group: ControlCenterHomeGroup): String =
    getString(
        when (group) {
            ControlCenterHomeGroup.CONNECTED_DEVICES -> R.string.cc_section_connected_devices
            ControlCenterHomeGroup.MODELS -> R.string.cc_section_models_runtime
            ControlCenterHomeGroup.VOICE_INTERACTION -> R.string.cc_section_voice_interaction
            ControlCenterHomeGroup.MEMORY_KNOWLEDGE -> R.string.cc_section_memory_knowledge
            ControlCenterHomeGroup.SKILLS_TASKS -> R.string.cc_section_skills_tasks
            ControlCenterHomeGroup.SECURITY_DATA -> R.string.cc_section_security_data
        }
    )

internal fun MainActivity.ccRouteRow(
    route: ControlCenterRoute,
    titleId: Int,
    subtitleId: Int,
    iconRes: Int,
    status: String,
    tone: ControlCenterTone
): ControlCenterRowSpec = ccRouteRow(
    route,
    getString(titleId),
    getString(subtitleId),
    iconRes,
    status,
    tone
)

internal fun MainActivity.ccRouteRow(
    route: ControlCenterRoute,
    title: String,
    subtitle: String,
    iconRes: Int,
    status: String,
    tone: ControlCenterTone
): ControlCenterRowSpec = ControlCenterRowSpec(
    actionId = routeAction(route),
    title = title,
    subtitle = subtitle,
    iconRes = iconRes,
    status = status,
    tone = tone
)

internal fun MainActivity.routeAction(route: ControlCenterRoute): String = "route:${route.wireValue}"

internal fun MainActivity.handleControlCenterAction(actionId: String) {
    if (actionId.startsWith("route:")) {
        ControlCenterRoute.fromWireValue(actionId.substringAfter("route:"))?.let {
            openControlCenterDestination(ControlCenterDestination(it))
        }
        return
    }
    controlCenterHomeRefreshPolicy.invalidate()
    when (actionId) {
        "global.toggle_enabled" -> updateGlobalAgentSettings { it.copy(enabled = !it.enabled) }
        "global.toggle_proactive" -> updateGlobalAgentSettings {
            it.copy(proactiveInsightsEnabled = !it.proactiveInsightsEnabled)
        }
        "global.toggle_model_understanding" -> updateGlobalAgentSettings {
            it.copy(modelUnderstandingEnabled = !it.modelUnderstandingEnabled)
        }
        "global.toggle_autonomous_preparation" -> updateGlobalAgentSettings {
            it.copy(autonomousPreparationEnabled = !it.autonomousPreparationEnabled)
        }
        "global.toggle_autonomous_tools" -> updateGlobalAgentSettings {
            it.copy(autonomousToolExecutionEnabled = !it.autonomousToolExecutionEnabled)
        }
        "global.toggle_dynamic_replanning" -> updateGlobalAgentSettings {
            it.copy(dynamicAutonomousReplanningEnabled = !it.dynamicAutonomousReplanningEnabled)
        }
        "global.toggle_long_horizon" -> updateGlobalAgentSettings {
            it.copy(longHorizonPlanningEnabled = !it.longHorizonPlanningEnabled)
        }
        "global.toggle_discovery" -> updateGlobalAgentSettings {
            it.copy(proactiveDiscoveryEnabled = !it.proactiveDiscoveryEnabled)
        }
        "global.toggle_paired_cognition" -> updateGlobalAgentSettings {
            it.copy(allowPairedAgentCognition = !it.allowPairedAgentCognition)
        }
        "global.toggle_cloud_cognition" -> updateGlobalAgentSettings {
            it.copy(allowCloudCognition = !it.allowCloudCognition)
        }
        "global.toggle_learning" -> updateGlobalAgentSettings {
            it.copy(adaptiveLearningEnabled = !it.adaptiveLearningEnabled)
        }
        "global.toggle_research" -> updateGlobalAgentSettings {
            it.copy(autonomousResearchEnabled = !it.autonomousResearchEnabled)
        }
        "global.toggle_auto_conversations" -> updateGlobalAgentSettings {
            it.copy(autoCreateConversationsEnabled = !it.autoCreateConversationsEnabled)
        }
        "global.toggle_notifications" -> updateGlobalAgentSettings {
            it.copy(notificationsEnabled = !it.notificationsEnabled)
        }
        "global.toggle_metered_research" -> updateGlobalAgentSettings {
            it.copy(allowMeteredBackgroundResearch = !it.allowMeteredBackgroundResearch)
        }
        "global.daily_model_calls" -> showGlobalDailyModelCallBudgetDialog()
        "global.concurrent_model_calls" -> showGlobalConcurrentModelCallBudgetDialog()
        "global.daily_model_tokens" -> showGlobalDailyModelTokenBudgetDialog()
        "global.daily_reported_cost" -> showGlobalDailyReportedCostBudgetDialog()
        "global.process_now" -> processGlobalAgentNow()
        "global.world.goals" -> showGlobalWorldItemsDialog(GlobalWorldItemKind.GOAL)
        "global.world.tasks" -> showGlobalWorldItemsDialog(GlobalWorldItemKind.TASK)
        "global.world.conflicts" -> showGlobalWorldConflictsDialog()
        "global.world.links" -> showGlobalConversationLinksDialog()
        "global.research" -> showGlobalResearchTasksDialog()
        "global.cognition" -> showGlobalCognitionTasksDialog()
        "global.runs" -> showGlobalAutonomousRunsDialog()
        "global.long_horizon" -> showGlobalLongHorizonGoalsDialog()
        "global.insights" -> showGlobalPendingInsightsDialog()
        "global.learning" -> showGlobalLearningDialog()
        "global.continuity" -> showGlobalContinuityDialog()
        "obsidian.configure" -> openObsidianVaultPicker()
        "obsidian.sync" -> {
            AndroidCognitionScheduler.requestObsidianProjection(this)
            Toast.makeText(this, R.string.cc_obsidian_sync_scheduled, Toast.LENGTH_SHORT).show()
        }
        "obsidian.candidates" -> showObsidianEditCandidates()
        "obsidian.disconnect" -> {
            ObsidianAndroidBridge.disconnect(this)
            renderControlCenterGlobalAgentPage()
        }
        "profile.nickname" -> openExistingControlCenterPage { showEditNicknameDialog() }
        "profile.qr" -> openExistingControlCenterPage { showMyQrPayload() }
        "profile.copy_id" -> copyText(SignalASICrypto.localSignalasiId(), getString(R.string.security_copied_signalasi_id))
        "profile.copy_fingerprint" -> copyText(SignalASICrypto.localIdentitySha256(), getString(R.string.security_copied_phone_fingerprint))
        "agent.execution_policy" -> openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.EXECUTION_POLICY))
        "agent.task_execution_mode" -> openExistingControlCenterPage { showPermissionModeSettingsPage() }
        "agent.task_budget" -> openExistingControlCenterPage { showTaskBudgetSettingsPage() }
        "agent.task_budget.time" -> editTaskBudgetTime()
        "agent.task_budget.cost" -> editTaskBudgetCost()
        "agent.task_budget.input_tokens" -> editTaskBudgetLong(
            R.string.cc_task_budget_input_tokens_title,
            AgentTaskBudgetStore(this).load().maxInputTokens
        ) { budget, value -> budget.copy(maxInputTokens = value) }
        "agent.task_budget.output_tokens" -> editTaskBudgetLong(
            R.string.cc_task_budget_output_tokens_title,
            AgentTaskBudgetStore(this).load().maxOutputTokens
        ) { budget, value -> budget.copy(maxOutputTokens = value) }
        "agent.task_budget.network" -> editTaskBudgetMib(
            R.string.cc_task_budget_network_title,
            AgentTaskBudgetStore(this).load().maxNetworkBytes
        ) { budget, value -> budget.copy(maxNetworkBytes = value) }
        "agent.task_budget.battery" -> editTaskBudgetLong(
            R.string.cc_task_budget_battery_title,
            AgentTaskBudgetStore(this).load().minimumBatteryPercent.toLong()
        ) { budget, value -> budget.copy(minimumBatteryPercent = value.toInt().coerceIn(0, 100)) }
        "agent.task_budget.memory" -> editTaskBudgetMib(
            R.string.cc_task_budget_memory_title,
            AgentTaskBudgetStore(this).load().maxMemoryBytes
        ) { budget, value -> budget.copy(maxMemoryBytes = value) }
        "agent.task_budget.network_policy" -> showTaskBudgetNetworkPolicyDialog()
        "agent.task_budget.toggle_cloud" -> updateTaskBudget {
            it.copy(allowCloud = !it.allowCloud)
        }
        "agent.task_budget.toggle_paid" -> updateTaskBudget {
            it.copy(allowPaidProviders = !it.allowPaidProviders)
        }
        "agent.toggle_pause" -> {
            val next = !mobileNativeAgent.safetySettings().executionPaused
            mobileNativeAgent.updateExecutionPaused(next)
            renderCurrentControlCenterDestination()
        }
        "agent.planner" -> openExistingControlCenterPage { showAgentPlannerSettingsPage() }
        "agent.planner.toggle_enabled" -> {
            mobileNativeAgent.updateModelPlannerEnabled(!mobileNativeAgent.modelPlannerSettings().enabled)
            showAgentPlannerSettingsPage()
        }
        "agent.planner.toggle_screen_text" -> {
            mobileNativeAgent.updateModelPlannerScreenText(!mobileNativeAgent.modelPlannerSettings().shareScreenText)
            showAgentPlannerSettingsPage()
        }
        "agent.planner.model_source" -> showAgentModelPlannerSourceDialog { showAgentPlannerSettingsPage() }
        "agent.planner.toggle_replanning" -> {
            mobileNativeAgent.updateModelPlannerDynamicReplanning(!mobileNativeAgent.modelPlannerSettings().dynamicReplanning)
            showAgentPlannerSettingsPage()
        }
        "agent.planner.max_replans" -> {
            val current = mobileNativeAgent.modelPlannerSettings().maxReplans
            mobileNativeAgent.updateModelPlannerMaxReplans(if (current < 3) 3 else if (current < 5) 5 else 1)
            showAgentPlannerSettingsPage()
        }
        "agent.planner.toggle_multi_agent" -> {
            mobileNativeAgent.updateMultiAgentCoordination(!mobileNativeAgent.modelPlannerSettings().multiAgentCoordination)
            showAgentPlannerSettingsPage()
        }
        "agent.planner.toggle_share_outputs" -> {
            mobileNativeAgent.updateShareAgentOutputsWithPlanner(!mobileNativeAgent.modelPlannerSettings().shareAgentOutputsWithPlanner)
            showAgentPlannerSettingsPage()
        }
        "agent.planner.max_hops" -> {
            val current = mobileNativeAgent.modelPlannerSettings().maxAgentHops
            mobileNativeAgent.updateMaxAgentHops(if (current < 4) 4 else if (current < 8) 8 else 2)
            showAgentPlannerSettingsPage()
        }
        "agent.planner.max_tools" -> {
            val current = mobileNativeAgent.modelPlannerSettings().maxToolCalls
            mobileNativeAgent.updateMaxToolCalls(if (current < 16) 16 else if (current < 32) 32 else 8)
            showAgentPlannerSettingsPage()
        }
        "agent.planner.max_actions" -> {
            val current = mobileNativeAgent.modelPlannerSettings().maxActions
            mobileNativeAgent.updateModelPlannerMaxActions(if (current < 8) 8 else if (current < 12) 12 else 4)
            showAgentPlannerSettingsPage()
        }
        "evolution.create" -> showCreateSelfEvolutionTaskDialog()
        "evolution.desktop.create" -> showCreateDesktopEvolutionTaskPicker()
        "agent.planner.max_iterations" -> {
            val current = mobileNativeAgent.modelPlannerSettings().maxLoopIterations
            val next = when {
                current < 8 -> 8
                current < 16 -> 16
                current < 24 -> 24
                else -> 4
            }
            mobileNativeAgent.updateMaxLoopIterations(next)
            showAgentPlannerSettingsPage()
        }
        "agent.planner.max_retries" -> {
            val current = mobileNativeAgent.modelPlannerSettings().maxPhaseRetries
            val next = when {
                current < 1 -> 1
                current < 2 -> 2
                current < 3 -> 3
                current < 5 -> 5
                else -> 0
            }
            mobileNativeAgent.updateMaxPhaseRetries(next)
            showAgentPlannerSettingsPage()
        }
        "agent.planner.no_progress_timeout" -> {
            val current = mobileNativeAgent.modelPlannerSettings().noProgressTimeoutSeconds
            val next = when {
                current < 300 -> 300
                current < 600 -> 600
                current < 1_200 -> 1_200
                current < 3_600 -> 3_600
                else -> 120
            }
            mobileNativeAgent.updateNoProgressTimeoutSeconds(next)
            showAgentPlannerSettingsPage()
        }
        "agent.memory_telemetry" -> openExistingControlCenterPage {
            renderControlCenterAgentMemoryTelemetryPage()
        }
        "memory.manage" -> openExistingControlCenterPage { showAgentMemoryPage() }
        "memory.inbox" -> openExistingControlCenterPage { showGlobalMemoryInboxPage() }
        "memory.temporal.current" -> openExistingControlCenterPage {
            showGlobalMemoryTemporalPage(GlobalMemoryTemporalState.CURRENT)
        }
        "memory.temporal.planned" -> openExistingControlCenterPage {
            showGlobalMemoryTemporalPage(GlobalMemoryTemporalState.PLANNED)
        }
        "memory.temporal.historical" -> openExistingControlCenterPage {
            showGlobalMemoryTemporalPage(GlobalMemoryTemporalState.HISTORICAL)
        }
        "memory.temporal.deprecated" -> openExistingControlCenterPage {
            showGlobalMemoryTemporalPage(GlobalMemoryTemporalState.DEPRECATED)
        }
        "memory.temporal.pending" -> openExistingControlCenterPage {
            showGlobalMemoryInboxPage(GlobalMemoryCandidateStatus.PENDING_REVIEW)
        }
        "memory.temporal.conflicted" -> openExistingControlCenterPage {
            showGlobalMemoryInboxPage(GlobalMemoryCandidateStatus.CONFLICTED)
        }
        "memory.evolution_history" -> openExistingControlCenterPage { showGlobalMemoryEvolutionHistoryPage() }
        "memory.graph" -> openExistingControlCenterPage { showGlobalMemoryGraphPage() }
        "memory.audit" -> openExistingControlCenterPage { showGlobalMemoryAuditPage() }
        "memory.toggle_capture" -> {
            val next = !mobileNativeAgent.safetySettings().memoryCapture
            mobileNativeAgent.updateMemoryCapture(next)
            renderCurrentControlCenterDestination()
        }
        "learning.toggle_capture" -> {
            val next = !mobileNativeAgent.safetySettings().memoryCapture
            mobileNativeAgent.updateMemoryCapture(next)
            renderCurrentControlCenterDestination()
        }
        "runtime.catalog_refresh" -> refreshRuntimePackCatalog()
        "runtime.lifecycle" -> showRuntimeLifecycleDialog()
        "runtime.import" -> openRuntimePackPicker()
        "runtime.software_search" -> showRuntimeSoftwareSearchDialog()
        "runtime.software_clear_search" -> {
            controlCenterDestination = ControlCenterDestination(ControlCenterRoute.SOFTWARE_CENTER)
            renderCurrentControlCenterDestination()
        }
        "local_model.open" -> openExistingControlCenterPage { showLocalModelFeaturePage() }
        "phone.catalog" -> openExistingControlCenterPage { showNativeToolCatalogPage() }
        "apps.adapters" -> openExistingControlCenterPage { showAgentAppAdaptersPage() }
        "desktop.remote_control" -> openExistingControlCenterPage { showDesktopControlPicker() }
        "spaces.configure" -> openExistingControlCenterPage { showDeviceFeaturePage() }
        "spaces.entities" -> showHomeAssistantCollectionPage("entities")
        "spaces.automations" -> showHomeAssistantCollectionPage("automations")
        "nodes.scan" -> {
            scanMode = "security"
            startSecurityScan()
        }
        "permissions.accessibility" -> startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        "permissions.notifications" -> startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
        "permissions.microphone" -> requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQUEST_CONTROL_CENTER_PERMISSION)
        "permissions.camera" -> requestPermissions(arrayOf(android.Manifest.permission.CAMERA), REQUEST_CONTROL_CENTER_PERMISSION)
        "audit.operations" -> openExistingControlCenterPage { showAgentAuditOperationsPage() }
        "voice.settings" -> openExistingControlCenterPage { showVoiceAssistantSettingsPage() }
        "voice.asr" -> openExistingControlCenterPage { showAsrProviderPage() }
        "voice.tts" -> openExistingControlCenterPage { showTtsProviderPage() }
        "voice.toggle_enabled" -> {
            val next = !VoiceAssistantSettings.get(this).enabled
            if (next && checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                pendingVoiceEnableFromControlCenter = true
                requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQUEST_CONTROL_CENTER_PERMISSION)
            } else {
                VoiceAssistantSettings.setEnabled(this, next)
                renderCurrentControlCenterDestination()
            }
        }
        "data.export" -> openExistingControlCenterPage { showExportBackupDialog() }
        "data.import" -> openBackupImportPicker()
        "data.cache" -> clearRebuildableCache()
        "general.language" -> openExistingControlCenterPage { showLanguageSettingsPage() }
        "general.notifications" -> startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        })
        "general.appearance" -> startActivity(Intent(Settings.ACTION_DISPLAY_SETTINGS))
        "general.text_size" -> openExistingControlCenterPage { showTextSizeSettingsPage() }
        "general.about" -> openExistingControlCenterPage { showAboutSignalASIPage() }
        "general.advanced" -> openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.ADVANCED))
        "apps.chat_history" -> showAgentSessionsPage()
        "security.manage" -> openExistingControlCenterPage { showSecurityFeaturePage() }
        "routing.add_cloud" -> openExistingControlCenterPage { showCloudProviderPage() }
        "routing.manage" -> openExistingControlCenterPage { showAgentFeaturePage() }
        "routing.policy" -> openExistingControlCenterPage { showRoutingPolicyPage() }
        "advanced.protocol" -> openExistingControlCenterPage { showSignalLinkProtocolPage() }
        "advanced.web_sources" -> openExistingControlCenterPage { showWebIntelligenceSourcesPage() }
        "advanced.voice_performance" -> openExistingControlCenterPage { showVoicePerformanceDashboardPage() }
        "advanced.app_details" -> startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        })
        "advanced.cache" -> clearRebuildableCache()
        "reset.begin" -> showResetConfirmationDialog()
        else -> when {
            actionId.startsWith("agent.preference_mode:") -> {
                val mode = AgentPreferenceMode.fromWireValue(actionId.substringAfter(':'))
                mobileNativeAgent.updatePreferenceMode(mode)
                showPermissionModeSettingsPage()
            }
            actionId.startsWith("agent.task_execution_mode:") -> {
                val mode = AgentTaskExecutionMode.fromWireValue(actionId.substringAfter(':'))
                mobileNativeAgent.updateTaskExecutionMode(mode)
                showPermissionModeSettingsPage()
            }
            actionId.startsWith("agent.task_budget.profile:") -> {
                val profile = AgentTaskBudgetProfile.fromWireValue(actionId.substringAfterLast(':'))
                val store = AgentTaskBudgetStore(this)
                if (profile == AgentTaskBudgetProfile.CUSTOM) {
                    store.save(store.load().copy(profile = profile))
                } else {
                    store.select(profile)
                }
                showTaskBudgetSettingsPage()
            }
            actionId.startsWith("general.text_scale:") -> {
                AppDisplaySettings.setTextScale(
                    this,
                    AppDisplaySettings.TextScaleMode.fromWireValue(actionId.substringAfter(':'))
                )
                recreateIntoControlCenterChild(CONTROL_CENTER_CHILD_TEXT_SIZE)
            }
            actionId.startsWith("evolution.task:") -> {
                showSelfEvolutionTaskDialog(actionId.substringAfter("evolution.task:"))
            }
            actionId.startsWith("evolution.remote:") -> {
                val encoded = actionId.removePrefix("evolution.remote:")
                val desktopId = Uri.decode(encoded.substringBefore(':'))
                val taskId = Uri.decode(encoded.substringAfter(':', ""))
                showRemoteSelfEvolutionTaskDialog(desktopId, taskId)
            }
            actionId.startsWith("memory.group:") -> {
                val kinds = when (actionId.substringAfter("memory.group:")) {
                    "identity" -> setOf(AgentMemoryKind.IDENTITY, AgentMemoryKind.PREFERENCE)
                    "people" -> setOf(AgentMemoryKind.CONTACT)
                    "work" -> setOf(AgentMemoryKind.TASK, AgentMemoryKind.WORKFLOW)
                    "knowledge" -> setOf(AgentMemoryKind.KNOWLEDGE, AgentMemoryKind.SAFETY)
                    else -> emptySet()
                }
                if (kinds.isNotEmpty()) {
                    openExistingControlCenterPage { showAgentMemoryPage(kinds) }
                }
            }
            actionId.startsWith("learning.proposal:") -> {
                showLearningProposalDialog(actionId.substringAfter("learning.proposal:"))
            }
            actionId.startsWith("runtime.pack:") -> {
                showRuntimePackDialog(actionId.substringAfter("runtime.pack:"))
            }
            actionId.startsWith("runtime.catalog_pack:") -> {
                showRuntimeCatalogPackDialog(actionId.substringAfter("runtime.catalog_pack:"))
            }
            actionId.startsWith("runtime.auto_install:") -> {
                autoInstallRuntimePack(actionId.substringAfter("runtime.auto_install:"))
            }
            actionId.startsWith("runtime.receipt:") -> {
                showRuntimeReceiptDialog(actionId.substringAfter("runtime.receipt:"))
            }
            actionId.startsWith("routing.target:") -> showControlCenterTarget(actionId.substringAfter("routing.target:"))
            actionId.startsWith("tool.detail:") -> showNativeToolDetailPage(actionId.substringAfter("tool.detail:"))
            actionId.startsWith("node.desktop:") -> showControlCenterDesktop(actionId.substringAfter("node.desktop:"))
            actionId.startsWith("ha.entity:") -> showHomeAssistantEntityDetailPage(actionId.substringAfter("ha.entity:"))
        }
    }
}

internal fun MainActivity.openControlCenterDestination(
    destination: ControlCenterDestination,
    pushCurrent: Boolean = true
) {
    if (!destination.route.isAvailable) {
        controlCenterDestination = null
        controlCenterBackStack.clear()
        hideFeaturePage()
        showMainTab(PAGE_SETTINGS)
        return
    }
    if (pushCurrent) {
        controlCenterDestination?.let(controlCenterBackStack::addLast)
    }
    controlCenterDestination = destination
    renderCurrentControlCenterDestination()
}

internal fun MainActivity.renderCurrentControlCenterDestination() {
    val destination = controlCenterDestination ?: return
    if (!destination.route.isAvailable) {
        controlCenterDestination = null
        controlCenterBackStack.clear()
        hideFeaturePage()
        showMainTab(PAGE_SETTINGS)
        return
    }
    renderingControlCenterDestination = true
    try {
        when (destination.route) {
            ControlCenterRoute.SYSTEM_STATUS -> renderControlCenterSystemStatusPage()
            ControlCenterRoute.GLOBAL_AGENT -> renderControlCenterGlobalAgentPage()
            ControlCenterRoute.AGENT_CORE -> renderControlCenterAgentCorePage()
            ControlCenterRoute.SELF_EVOLUTION -> renderControlCenterSelfEvolutionPage()
            ControlCenterRoute.EXECUTION_POLICY -> renderControlCenterExecutionPolicyPage()
            ControlCenterRoute.RESOURCE_ROUTING -> renderControlCenterRoutingPage()
            ControlCenterRoute.MEMORY -> renderControlCenterMemoryPage()
            ControlCenterRoute.LEARNING -> renderControlCenterLearningPage()
            ControlCenterRoute.KNOWLEDGE -> showAgentKnowledgePage()
            ControlCenterRoute.MCP -> showCapabilityLibraryPage(
                when (destination.payload) {
                    CAPABILITY_KIND_MCP -> AgentCapabilityCatalogKind.MCP
                    CAPABILITY_KIND_AUTOMATION -> AgentCapabilityCatalogKind.AUTOMATION
                    else -> AgentCapabilityCatalogKind.NATIVE_TOOL
                }
            )
            ControlCenterRoute.TASKS -> showAgentRecentTasksPage()
            ControlCenterRoute.PHONE_CAPABILITIES -> renderControlCenterPhoneCapabilitiesPage()
            ControlCenterRoute.ON_DEVICE_RUNTIME -> renderControlCenterRuntimePage()
            ControlCenterRoute.SOFTWARE_CENTER -> renderControlCenterSoftwareCenterPage(destination.payload)
            ControlCenterRoute.SMART_SPACES -> renderControlCenterSmartSpacesPage()
            ControlCenterRoute.NODES -> renderControlCenterNodesPage()
            ControlCenterRoute.SECURITY -> renderControlCenterSecurityPage()
            ControlCenterRoute.PRIVACY -> renderControlCenterPrivacyPage(destination.payload)
            ControlCenterRoute.PERMISSIONS_AUDIT -> renderControlCenterPermissionsPage()
            ControlCenterRoute.VOICE -> renderControlCenterVoicePage()
            ControlCenterRoute.DATA_BACKUP -> renderControlCenterDataPage()
            ControlCenterRoute.GENERAL -> renderControlCenterGeneralPage()
            ControlCenterRoute.ADVANCED -> renderControlCenterAdvancedPage()
            ControlCenterRoute.RESET -> renderControlCenterResetPage()
        }
    } finally {
        renderingControlCenterDestination = false
    }
    setFeatureBackAction()
}

internal fun MainActivity.openExistingControlCenterPage(render: () -> Unit) {
    controlCenterDestination?.let(controlCenterBackStack::addLast)
    controlCenterDestination = null
    renderingControlCenterDestination = true
    try {
        render()
    } finally {
        renderingControlCenterDestination = false
    }
    setFeatureBackAction()
}

internal fun MainActivity.navigateControlCenterBack() {
    if (controlCenterBackStack.isNotEmpty()) {
        openControlCenterDestination(controlCenterBackStack.removeLast(), pushCurrent = false)
    } else {
        controlCenterDestination = null
        hideFeaturePage()
        showMainTab(PAGE_SETTINGS)
    }
}

internal fun MainActivity.exitControlCenterToTab(tab: String) {
    controlCenterDestination = null
    controlCenterBackStack.clear()
    showMainTab(tab)
}

internal fun MainActivity.showControlCenterFeature(title: String, page: ControlCenterPageSpec) {
    showFeaturePage(title)
    controlCenterRenderer.render(featureContent, page, ::handleControlCenterAction)
}
