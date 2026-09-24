package com.galaxyssi.chat

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

internal fun MainActivity.configureSettingsControlCenter() {
    controlCenterBackStack.clear()
    controlCenterDestination = null
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

internal fun MainActivity.buildControlCenterHomePage(): ControlCenterPageSpec =
    ControlCenterPageSpec(
        hero = ControlCenterHeroSpec(
            title = getString(R.string.app_name),
            subtitle = getString(R.string.my_agent_personal_subtitle),
            iconRes = R.drawable.galaxyssi_mark_large,
            preserveIconColor = true,
            titleActionId = "profile.nickname",
            trailingActionId = "profile.qr",
            trailingIconRes = R.drawable.ic_qr,
            trailingContentDescription = getString(R.string.contact_my_qr_title)
        ),
        sections = ControlCenterHomeGrouping.orderedGroups.map { group ->
            ControlCenterSectionSpec(
                controlCenterHomeGroupTitle(group),
                ControlCenterHomeGrouping.routes(group).map { myAgentHomeRow(it) }
            )
        }
    )

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
    getString(if (group == ControlCenterHomeGroup.COMMON) R.string.my_agent_common else R.string.my_agent_settings)

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
    if (handleMyAgentDesignAction(actionId)) return
    if (actionId.startsWith("route:")) {
        ControlCenterRoute.fromWireValue(actionId.substringAfter("route:"))?.let {
            openControlCenterDestination(ControlCenterDestination(it))
        }
        return
    }
    if (handleAgentEvolutionLabAction(actionId)) return
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
        "profile.copy_id" -> copyText(GalaxySSICrypto.localGalaxySSIId(), getString(R.string.security_copied_galaxyssi_id))
        "profile.copy_fingerprint" -> copyText(GalaxySSICrypto.localIdentitySha256(), getString(R.string.security_copied_phone_fingerprint))
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
        "general.screen_assistant" -> openExistingControlCenterPage { showScreenAssistantSettingsPage() }
        "screen_assistant.accessibility" -> startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        "screen_assistant.target" -> showScreenAssistantTargetPicker()
        "screen_assistant.toggle" -> {
            if (ScreenAssistantSettings.enabled(this)) {
                ScreenAssistantSettings.setEnabled(this, false)
                showScreenAssistantSettingsPage()
            } else {
                android.app.AlertDialog.Builder(this)
                    .setTitle(R.string.screen_assistant_enable)
                    .setMessage(R.string.screen_assistant_disclosure)
                    .setPositiveButton(R.string.screen_assistant_enable) { _, _ ->
                        ScreenAssistantSettings.setEnabled(this, true)
                        showScreenAssistantSettingsPage()
                        if (!GalaxySSIAccessibilityService.isActive()) {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        }
                    }
                    .setNegativeButton(android.R.string.cancel, null)
                    .show()
            }
        }
        "general.about" -> openExistingControlCenterPage { showAboutGalaxySSIPage() }
        "general.advanced" -> openControlCenterDestination(ControlCenterDestination(ControlCenterRoute.ADVANCED))
        "apps.chat_history" -> showAgentSessionsPage()
        "security.manage" -> openExistingControlCenterPage { showSecurityFeaturePage() }
        "routing.add_cloud" -> openExistingControlCenterPage { showCloudProviderPage() }
        "routing.manage" -> openExistingControlCenterPage { showAgentFeaturePage() }
        "routing.policy" -> openExistingControlCenterPage { showRoutingPolicyPage() }
        "advanced.watch_setup" -> startActivity(Intent(this, WatchSetupActivity::class.java))
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
            ControlCenterRoute.MODEL_HUB -> renderMyAgentModelsPage()
            ControlCenterRoute.DEVICE_HUB -> renderMyAgentDevicesPage()
            ControlCenterRoute.MEMORY_HUB -> renderMyAgentMemoryHub()
            ControlCenterRoute.SKILLS_HUB -> renderMyAgentSkillsPage()
            ControlCenterRoute.SAFETY_HUB -> renderMyAgentSafetyPage()
            ControlCenterRoute.PROACTIVE_HUB -> renderMyAgentProactivePage()
            ControlCenterRoute.OBSIDIAN_HUB -> renderMyAgentObsidianPage()
            ControlCenterRoute.STORAGE_HUB -> renderMyAgentStoragePage()
            ControlCenterRoute.NOTIFICATIONS_HUB -> renderMyAgentNotificationsPage()
            ControlCenterRoute.DIAGNOSTICS_HUB -> renderMyAgentDiagnosticsPage()
            ControlCenterRoute.PERMISSIONS_HUB -> renderControlCenterPermissionsPage()
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
