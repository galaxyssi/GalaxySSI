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

internal fun MainActivity.renderControlCenterGlobalAgentPage() {
    val s = GlobalSuperAgentRuntime.get(this).cachedSettings()
    fun toggle(action: String, title: Int, value: Boolean, enabled: Boolean = s.enabled) =
        myAgentRow(action, title, R.drawable.ic_agent_control)
            .copy(switchValue = value, showChevron = false, enabled = enabled)
    showControlCenterFeature(getString(R.string.my_agent_cognition_advanced), ControlCenterPageSpec(sections = listOf(
        ControlCenterSectionSpec(getString(R.string.my_agent_cognition), listOf(
            toggle("global.toggle_enabled", R.string.cc_global_master_title, s.enabled, true),
            toggle("global.toggle_model_understanding", R.string.cc_global_model_understanding_title, s.modelUnderstandingEnabled),
            toggle("global.toggle_autonomous_preparation", R.string.cc_global_autonomous_preparation_title, s.autonomousPreparationEnabled),
            toggle("global.toggle_autonomous_tools", R.string.cc_global_autonomous_tools_title, s.autonomousToolExecutionEnabled, s.enabled && s.autonomousPreparationEnabled)
        )),
        ControlCenterSectionSpec(getString(R.string.my_agent_advanced_controls), listOf(
            toggle("global.toggle_dynamic_replanning", R.string.cc_global_dynamic_replanning_title, s.dynamicAutonomousReplanningEnabled, s.enabled && s.autonomousPreparationEnabled),
            toggle("global.toggle_long_horizon", R.string.cc_global_long_horizon_toggle_title, s.longHorizonPlanningEnabled),
            toggle("global.toggle_discovery", R.string.cc_global_discovery_title, s.proactiveDiscoveryEnabled, s.enabled && s.modelUnderstandingEnabled),
            toggle("global.toggle_learning", R.string.cc_global_learning_toggle_title, s.adaptiveLearningEnabled),
            toggle("global.toggle_research", R.string.cc_global_research_title, s.autonomousResearchEnabled),
            toggle("global.toggle_auto_conversations", R.string.cc_global_topics_title, s.autoCreateConversationsEnabled),
            toggle("global.toggle_notifications", R.string.cc_global_notifications_title, s.notificationsEnabled)
        ), collapsed = true),
        ControlCenterSectionSpec(getString(R.string.cc_task_budget_title), listOf(
            myAgentRow("global.daily_model_calls", R.string.cc_global_daily_model_calls_title, R.drawable.ic_agent_history),
            myAgentRow("global.concurrent_model_calls", R.string.cc_global_concurrent_model_calls_title, R.drawable.ic_agent_history),
            myAgentRow("global.daily_model_tokens", R.string.cc_global_daily_model_tokens_title, R.drawable.ic_agent_history),
            myAgentRow("global.daily_reported_cost", R.string.cc_global_daily_reported_cost_title, R.drawable.ic_agent_history),
            toggle("global.toggle_metered_research", R.string.cc_global_metered_research_title, s.allowMeteredBackgroundResearch)
        ), collapsed = true),
        ControlCenterSectionSpec(getString(R.string.my_agent_permissions), listOf(
            toggle("global.toggle_paired_cognition", R.string.cc_global_paired_cognition_title, s.allowPairedAgentCognition),
            toggle("global.toggle_cloud_cognition", R.string.cc_global_cloud_cognition_title, s.allowCloudCognition)
        ), collapsed = true)
    )))
}

internal fun MainActivity.updateGlobalAgentSettings(transform: (GlobalAgentSettings) -> GlobalAgentSettings) {
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) globalSuperAgentRuntime else GlobalSuperAgentRuntime.get(this)
    runtime.updateSettings(transform)
    if (controlCenterDestination != null) renderCurrentControlCenterDestination()
    else renderControlCenterGlobalAgentPage()
}

internal fun MainActivity.openObsidianVaultPicker() {
    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
        addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
        )
    }, REQUEST_OBSIDIAN_VAULT)
}

internal fun MainActivity.configureObsidianVault(uri: android.net.Uri) {
    runCatching { ObsidianAndroidBridge.configure(this, uri) }
        .onSuccess {
            Toast.makeText(this, R.string.cc_obsidian_connected, Toast.LENGTH_SHORT).show()
            if (controlCenterDestination?.route in setOf(ControlCenterRoute.GLOBAL_AGENT, ControlCenterRoute.OBSIDIAN_HUB))
                renderCurrentControlCenterDestination()
        }
        .onFailure { error ->
            Toast.makeText(
                this,
                getString(R.string.cc_obsidian_connect_failed, error.message.orEmpty()),
                Toast.LENGTH_LONG
            ).show()
        }
}

internal fun MainActivity.showObsidianEditCandidates() {
    val candidates = ObsidianAndroidBridge.pendingCandidates(this).take(40)
    if (candidates.isEmpty()) {
        Toast.makeText(this, R.string.cc_obsidian_no_candidates, Toast.LENGTH_SHORT).show()
        return
    }
    val labels = candidates.map { candidate ->
        candidate.title.ifBlank { candidate.relativePath.substringAfterLast('/') }
    }.toTypedArray()
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_obsidian_candidates_title)
        .setItems(labels) { _, index -> showObsidianEditCandidate(candidates[index]) }
        .setNegativeButton(android.R.string.cancel, null)
        .show()
}

internal fun MainActivity.showObsidianEditCandidate(candidate: ObsidianEditCandidate) {
    AlertDialog.Builder(this)
        .setTitle(candidate.title.ifBlank { candidate.relativePath.substringAfterLast('/') })
        .setMessage(candidate.content.take(8_000))
        .setPositiveButton(R.string.cc_obsidian_approve) { _, _ ->
            if (ObsidianAndroidBridge.approveCandidate(this, candidate.id)) {
                Toast.makeText(this, R.string.cc_obsidian_candidate_approved, Toast.LENGTH_SHORT).show()
            }
            renderCurrentControlCenterDestination()
        }
        .setNegativeButton(R.string.cc_obsidian_reject) { _, _ ->
            if (ObsidianAndroidBridge.rejectCandidate(this, candidate.id)) {
                Toast.makeText(this, R.string.cc_obsidian_candidate_rejected, Toast.LENGTH_SHORT).show()
            }
            renderCurrentControlCenterDestination()
        }
        .setNeutralButton(android.R.string.cancel, null)
        .show()
}

internal fun MainActivity.showGlobalDailyModelCallBudgetDialog() {
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) globalSuperAgentRuntime else GlobalSuperAgentRuntime.get(this)
    val values = intArrayOf(12, 24, 48, 96, 200)
    val current = runtime.settings().dailyBackgroundModelCallBudget
    val selected = values.indices.minByOrNull { kotlin.math.abs(values[it] - current) } ?: 0
    val labels = values.map { getString(R.string.cc_global_calls_per_day, it) }.toTypedArray()
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_daily_model_calls_title)
        .setSingleChoiceItems(labels, selected) { dialog, index ->
            updateGlobalAgentSettings { it.copy(dailyBackgroundModelCallBudget = values[index]) }
            dialog.dismiss()
        }
        .setNegativeButton(R.string.common_cancel, null)
        .show()
}

internal fun MainActivity.showGlobalConcurrentModelCallBudgetDialog() {
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) globalSuperAgentRuntime else GlobalSuperAgentRuntime.get(this)
    val values = intArrayOf(1, 2, 3, 4, 5, 6)
    val current = runtime.settings().maxConcurrentBackgroundModelCalls
    val selected = values.indexOf(current).coerceAtLeast(0)
    val labels = values.map { getString(R.string.cc_global_concurrent_calls, it) }.toTypedArray()
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_concurrent_model_calls_title)
        .setSingleChoiceItems(labels, selected) { dialog, index ->
            updateGlobalAgentSettings { it.copy(maxConcurrentBackgroundModelCalls = values[index]) }
            dialog.dismiss()
        }
        .setNegativeButton(R.string.common_cancel, null)
        .show()
}

internal fun MainActivity.showGlobalDailyModelTokenBudgetDialog() {
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) globalSuperAgentRuntime else GlobalSuperAgentRuntime.get(this)
    val values = longArrayOf(50_000L, 100_000L, 250_000L, 500_000L, 1_000_000L, 2_000_000L)
    val current = runtime.settings().dailyBackgroundTokenBudget
    val selected = values.indices.minByOrNull { kotlin.math.abs(values[it] - current) } ?: 0
    val labels = values.map { getString(R.string.cc_global_tokens_per_day, formatCompactCount(it)) }.toTypedArray()
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_daily_model_tokens_title)
        .setSingleChoiceItems(labels, selected) { dialog, index ->
            updateGlobalAgentSettings { it.copy(dailyBackgroundTokenBudget = values[index]) }
            dialog.dismiss()
        }
        .setNegativeButton(R.string.common_cancel, null)
        .show()
}

internal fun MainActivity.showGlobalDailyReportedCostBudgetDialog() {
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) globalSuperAgentRuntime else GlobalSuperAgentRuntime.get(this)
    val values = longArrayOf(250_000L, 500_000L, 1_000_000L, 2_000_000L, 5_000_000L, 10_000_000L)
    val current = runtime.settings().dailyBackgroundReportedCostBudgetMicros
    val selected = values.indices.minByOrNull { kotlin.math.abs(values[it] - current) } ?: 0
    val labels = values.map(::formatUsdMicros).toTypedArray()
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_daily_reported_cost_title)
        .setSingleChoiceItems(labels, selected) { dialog, index ->
            updateGlobalAgentSettings { it.copy(dailyBackgroundReportedCostBudgetMicros = values[index]) }
            dialog.dismiss()
        }
        .setNegativeButton(R.string.common_cancel, null)
        .show()
}

internal fun MainActivity.formatCompactCount(value: Long): String = when {
    value >= 1_000_000L -> String.format(Locale.US, "%.1fM", value / 1_000_000.0).replace(".0M", "M")
    value >= 1_000L -> String.format(Locale.US, "%.1fK", value / 1_000.0).replace(".0K", "K")
    else -> value.toString()
}

internal fun MainActivity.formatUsdMicros(value: Long): String = String.format(Locale.US, "$%.2f", value.coerceAtLeast(0L) / 1_000_000.0)

internal fun MainActivity.processGlobalAgentNow() {
    AndroidCognitionScheduler.requestImmediate(this, explicit = true)
    Toast.makeText(this, getString(R.string.cc_global_process_now_subtitle), Toast.LENGTH_SHORT).show()
}

internal fun MainActivity.showGlobalWorldItemsDialog(kind: GlobalWorldItemKind) {
    val items = globalSuperAgentRuntime.worldSnapshot().items
        .filter { it.kind == kind && it.status in setOf(GlobalWorldItemStatus.ACTIVE, GlobalWorldItemStatus.CONFLICTED) }
        .sortedByDescending(GlobalWorldItem::lastSeenAtMillis)
        .take(30)
    val title = getString(if (kind == GlobalWorldItemKind.GOAL) R.string.cc_global_goals_title else R.string.cc_global_tasks_title)
    val message = items.takeIf(List<GlobalWorldItem>::isNotEmpty)?.joinToString("\n\n") {
        "\u2022 ${it.value}\n${it.topic} \u00b7 ${it.conversationIds.size}"
    } ?: getString(R.string.cc_global_empty)
    AlertDialog.Builder(this)
        .setTitle(title)
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

internal fun MainActivity.showGlobalWorldConflictsDialog() {
    val conflicts = globalSuperAgentRuntime.worldSnapshot().items
        .filter { it.status == GlobalWorldItemStatus.CONFLICTED }
        .groupBy { it.conflictGroupId.ifBlank { it.stableKey } }
        .values
        .take(20)
    val message = conflicts.takeIf(Collection<List<GlobalWorldItem>>::isNotEmpty)?.joinToString("\n\n") { group ->
        group.joinToString("\n") { "\u2022 ${it.value}" }
    } ?: getString(R.string.cc_global_empty)
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_conflicts_title)
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

internal fun MainActivity.showGlobalConversationLinksDialog() {
    val graph = globalSuperAgentRuntime.topicGraphSnapshot()
    val nodesById = graph.nodes.associateBy(GlobalTopicNode::id)
    val nodeLines = graph.activeNodes()
        .sortedWith(compareByDescending<GlobalTopicNode> { it.kind == GlobalTopicNodeKind.PROJECT }
            .thenByDescending { it.lastSeenAtMillis })
        .take(20)
        .map { node ->
            val kind = getString(if (node.kind == GlobalTopicNodeKind.PROJECT) {
                R.string.cc_global_topic_kind_project
            } else R.string.cc_global_topic_kind_topic)
            "\u2022 $kind \u00b7 ${node.name}\n${node.conversationIds.size} \u00b7 ${(node.confidence * 100).toInt()}%"
        }
    val relationLines = graph.relations
        .sortedByDescending(GlobalTopicRelation::strength)
        .take(20)
        .mapNotNull { relation ->
            val from = nodesById[relation.fromNodeId]?.name ?: return@mapNotNull null
            val to = nodesById[relation.toNodeId]?.name ?: return@mapNotNull null
            "$from ${globalTopicRelationLabel(relation.kind)} $to \u00b7 ${(relation.strength * 100).toInt()}%"
        }
    val message = (nodeLines + relationLines).takeIf(List<String>::isNotEmpty)
        ?.joinToString("\n\n") ?: getString(R.string.cc_global_empty)
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_links_title)
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

internal fun MainActivity.showGlobalResearchTasksDialog() {
    val tasks = globalSuperAgentRuntime.researchTasks()
        .sortedByDescending(GlobalResearchTask::updatedAtMillis)
        .take(30)
    val message = tasks.takeIf(List<GlobalResearchTask>::isNotEmpty)?.joinToString("\n\n") {
        val plan = it.researchPlan
        val progress = if (plan.units.isNotEmpty()) {
            "\n" + getString(
                R.string.cc_global_research_progress,
                plan.completedUnits().size,
                plan.units.size,
                globalResearchPlanPhaseLabel(plan.phase),
                it.evidenceLedger.independentSourceCount,
                (it.evidenceLedger.overallConfidence * 100).toInt()
            ) + if (it.evidenceLedger.verified) {
                " \u00b7 ${getString(R.string.cc_global_research_verified)}"
            } else ""
        } else ""
        "\u2022 ${it.topic}\n${globalResearchStatusLabel(it.status)}$progress" +
            it.lastError.takeIf(String::isNotBlank)?.let { error -> "\n${error.take(120)}" }.orEmpty()
    } ?: getString(R.string.cc_global_empty)
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_research_queue_title)
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

internal fun MainActivity.globalResearchPlanPhaseLabel(phase: GlobalResearchPlanPhase): String = getString(when (phase) {
    GlobalResearchPlanPhase.UNPLANNED -> R.string.cc_global_research_phase_unplanned
    GlobalResearchPlanPhase.COLLECTING -> R.string.cc_global_research_phase_collecting
    GlobalResearchPlanPhase.SYNTHESIS_PENDING -> R.string.cc_global_research_phase_synthesis_pending
    GlobalResearchPlanPhase.SYNTHESIZING -> R.string.cc_global_research_phase_synthesizing
    GlobalResearchPlanPhase.COMPLETED -> R.string.cc_global_status_completed
})

internal fun MainActivity.showGlobalCognitionTasksDialog() {
    val tasks = globalSuperAgentRuntime.cognitionTasks()
        .sortedByDescending(GlobalCognitionTask::updatedAtMillis)
        .take(30)
    val message = tasks.takeIf(List<GlobalCognitionTask>::isNotEmpty)?.joinToString("\n\n") { task ->
        val topic = task.result.topic.ifBlank { task.baselineUnderstanding.topic }
        buildString {
            append("\u2022 ").append(topic)
            append("\n").append(globalCognitionStatusLabel(task.status))
            if (task.resourceId.isNotBlank()) append(" \u00b7 ").append(task.resourceId)
            if (task.result.confidence > 0.0) {
                append(" \u00b7 ").append((task.result.confidence * 100).toInt()).append('%')
            }
            task.lastError.takeIf(String::isNotBlank)?.let { append("\n").append(it.take(160)) }
        }
    } ?: getString(R.string.cc_global_empty)
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_cognition_queue_title)
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

internal fun MainActivity.showGlobalContinuityDialog() {
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) {
        globalSuperAgentRuntime
    } else GlobalSuperAgentRuntime.get(this)
    val snapshot = runtime.continuitySnapshot()
    val details = buildString {
        append(getString(
            R.string.cc_global_continuity_dialog_summary,
            snapshot.pendingEventCount,
            snapshot.retryingEvents.size,
            snapshot.quarantinedEvents.size
        ))
        if (snapshot.retryingEvents.isNotEmpty()) {
            append("\n\n").append(getString(
                R.string.cc_global_continuity_retrying_detail,
                snapshot.retryingEvents.maxOf(GlobalEventProcessingFailure::attemptCount)
            ))
        }
        if (snapshot.nextRetryAtMillis > System.currentTimeMillis()) {
            append("\n").append(getString(
                R.string.cc_global_continuity_next_retry,
                SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(snapshot.nextRetryAtMillis))
            ))
        }
        if (snapshot.quarantinedEvents.isNotEmpty()) {
            append("\n\n").append(getString(R.string.cc_global_continuity_isolated_detail))
        } else if (snapshot.pendingEventCount == 0 && snapshot.retryingEvents.isEmpty()) {
            append("\n\n").append(getString(R.string.cc_global_continuity_healthy_detail))
        }
    }
    val builder = AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_continuity_title)
        .setMessage(details)
        .setPositiveButton(android.R.string.ok, null)
    if (snapshot.quarantinedEvents.isNotEmpty()) {
        builder.setNeutralButton(R.string.cc_global_continuity_retry_action) { _, _ ->
            thread(name = "galaxyssi-global-continuity-replay") {
                val replayed = runtime.replayQuarantinedEvents()
                runOnUiThread {
                    Toast.makeText(
                        this,
                        getString(R.string.cc_global_continuity_retry_result, replayed),
                        Toast.LENGTH_SHORT
                    ).show()
                    if (controlCenterDestination?.route == ControlCenterRoute.GLOBAL_AGENT) {
                        renderControlCenterGlobalAgentPage()
                    }
                }
            }
        }
    }
    builder.show()
}

internal fun MainActivity.showGlobalAutonomousRunsDialog() {
    val runs = globalSuperAgentRuntime.autonomousRuns()
        .sortedByDescending(GlobalAutonomousRun::updatedAtMillis)
        .take(30)
    if (runs.isEmpty()) {
        AlertDialog.Builder(this)
            .setTitle(R.string.cc_global_runs_title)
            .setMessage(R.string.cc_global_empty)
            .setPositiveButton(android.R.string.ok, null)
            .show()
        return
    }
    val labels = runs.map { run ->
        getString(
            R.string.cc_global_run_row,
            run.topic.ifBlank { run.goal.take(80) },
            globalAutonomousRunStatusLabel(run.status),
            run.completedActions().size,
            run.actions.size
        )
    }.toTypedArray()
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_runs_title)
        .setItems(labels) { _, index -> showGlobalAutonomousRunDialog(runs[index]) }
        .setNegativeButton(android.R.string.cancel, null)
        .show()
}

internal fun MainActivity.showGlobalAutonomousRunDialog(run: GlobalAutonomousRun) {
    val details = run.actions.joinToString("\n\n") { action ->
        "\u2022 ${action.goal}\n${globalAutonomousActionStatusLabel(action.status)}" +
            action.dependsOnActionIds.takeIf(Set<String>::isNotEmpty)?.let {
                " \u00b7 ${getString(R.string.cc_global_dependency_count, it.size)}"
            }.orEmpty() +
            action.toolId.takeIf(String::isNotBlank)?.let {
                "\n${getString(R.string.cc_global_tool_label, it)}"
            }.orEmpty() +
            action.toolInputJson.takeIf(String::isNotBlank)?.let {
                "\n${getString(R.string.cc_global_tool_input_label, it.take(320))}"
            }.orEmpty() +
            "\n${getString(R.string.cc_global_verification_label, globalActionVerificationLabel(action.verificationStatus))}" +
            action.result.takeIf(String::isNotBlank)?.let { "\n${it.take(300)}" }.orEmpty() +
            action.evidence.takeIf(List<GlobalActionEvidence>::isNotEmpty)?.let { evidence ->
                "\n" + evidence.take(3).joinToString("\n") { "${it.kind.name.lowercase()}: ${it.summary.take(180)}" }
            }.orEmpty() +
            action.lastError.takeIf(String::isNotBlank)?.let { "\n${it.take(160)}" }.orEmpty()
    }
    val builder = AlertDialog.Builder(this)
        .setTitle(run.topic.ifBlank { getString(R.string.cc_global_runs_title) })
        .setMessage(details)
        .setNegativeButton(android.R.string.cancel, null)
    if (run.status == GlobalAutonomousRunStatus.WAITING_CONFIRMATION) {
        builder.setNeutralButton(R.string.common_reject) { _, _ ->
            globalSuperAgentRuntime.rejectAutonomousRun(run.id)
            renderControlCenterGlobalAgentPage()
        }
        builder.setPositiveButton(R.string.common_confirm) { _, _ ->
            globalSuperAgentRuntime.approveAutonomousRun(run.id)
            processGlobalAgentNow()
        }
    } else {
        builder.setPositiveButton(android.R.string.ok, null)
    }
    builder.show()
}

internal fun MainActivity.showGlobalLongHorizonGoalsDialog() {
    val goals = globalSuperAgentRuntime.longHorizonGoals()
        .sortedWith(compareByDescending<GlobalLongHorizonGoal> { it.priority }
            .thenByDescending { it.updatedAtMillis })
        .take(50)
    if (goals.isEmpty()) {
        AlertDialog.Builder(this)
            .setTitle(R.string.cc_global_long_horizon_title)
            .setMessage(R.string.cc_global_empty)
            .setPositiveButton(android.R.string.ok, null)
            .show()
        return
    }
    val labels = goals.map { goal ->
        getString(
            R.string.cc_global_long_horizon_row,
            goal.title,
            globalLongHorizonStatusLabel(goal.status),
            goal.checkpointCount
        )
    }.toTypedArray()
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_long_horizon_title)
        .setItems(labels) { _, index -> showGlobalLongHorizonGoalDialog(goals[index]) }
        .setNegativeButton(android.R.string.cancel, null)
        .show()
}

internal fun MainActivity.showGlobalLongHorizonGoalDialog(goal: GlobalLongHorizonGoal) {
    val details = buildString {
        append(globalLongHorizonStatusLabel(goal.status))
        append(" \u00b7 ").append((goal.priority * 100).toInt()).append('%')
        if (goal.progressSummary.isNotBlank()) append("\n\n").append(goal.progressSummary.take(1_000))
        if (goal.blocker.isNotBlank()) append("\n\n").append(goal.blocker.take(600))
        if (goal.dependencyGoalIds.isNotEmpty()) {
            append("\n\n").append(getString(R.string.cc_global_dependency_count, goal.dependencyGoalIds.size))
        }
        if (goal.verificationSummary.isNotBlank()) {
            append("\n\n").append(goal.verificationSummary.take(1_000))
        }
        if (goal.nextCheckAtMillis > 0L) {
            append("\n\n")
            append(SimpleDateFormat("MM-dd HH:mm", Locale.getDefault()).format(Date(goal.nextCheckAtMillis)))
        }
    }
    val builder = AlertDialog.Builder(this)
        .setTitle(goal.title)
        .setMessage(details)
        .setNegativeButton(android.R.string.cancel, null)
    if (goal.status == GlobalLongHorizonGoalStatus.PAUSED) {
        builder.setPositiveButton(R.string.cc_global_goal_resume) { _, _ ->
            globalSuperAgentRuntime.resumeLongHorizonGoal(goal.id)
            processGlobalAgentNow()
        }
    } else if (goal.status != GlobalLongHorizonGoalStatus.COMPLETED) {
        builder.setNeutralButton(R.string.cc_global_goal_pause) { _, _ ->
            globalSuperAgentRuntime.pauseLongHorizonGoal(goal.id)
            renderControlCenterGlobalAgentPage()
        }
        builder.setPositiveButton(android.R.string.ok, null)
    } else {
        builder.setPositiveButton(android.R.string.ok, null)
    }
    builder.show()
}

internal fun MainActivity.globalCognitionStatusLabel(status: GlobalCognitionTaskStatus): String = getString(when (status) {
    GlobalCognitionTaskStatus.QUEUED -> R.string.cc_global_status_queued
    GlobalCognitionTaskStatus.RUNNING -> R.string.cc_global_status_running
    GlobalCognitionTaskStatus.WAITING_FOR_RESOURCE -> R.string.cc_global_status_waiting
    GlobalCognitionTaskStatus.COMPLETED -> R.string.cc_global_status_completed
    GlobalCognitionTaskStatus.FAILED -> R.string.cc_global_status_failed
})

internal fun MainActivity.globalAutonomousRunStatusLabel(status: GlobalAutonomousRunStatus): String = getString(when (status) {
    GlobalAutonomousRunStatus.QUEUED -> R.string.cc_global_status_queued
    GlobalAutonomousRunStatus.RUNNING -> R.string.cc_global_status_running
    GlobalAutonomousRunStatus.REPLANNING -> R.string.cc_global_status_replanning
    GlobalAutonomousRunStatus.WAITING_FOR_RESOURCE -> R.string.cc_global_status_waiting
    GlobalAutonomousRunStatus.WAITING_CONFIRMATION -> R.string.cc_global_status_confirmation
    GlobalAutonomousRunStatus.COMPLETED -> R.string.cc_global_status_completed
    GlobalAutonomousRunStatus.PARTIAL -> R.string.cc_global_status_partial
    GlobalAutonomousRunStatus.FAILED -> R.string.cc_global_status_failed
    GlobalAutonomousRunStatus.PAUSED -> R.string.on_device_agent_status_paused
})

internal fun MainActivity.globalLongHorizonStatusLabel(status: GlobalLongHorizonGoalStatus): String = getString(when (status) {
    GlobalLongHorizonGoalStatus.ACTIVE -> R.string.cc_global_status_active
    GlobalLongHorizonGoalStatus.IN_PROGRESS -> R.string.cc_global_status_in_progress
    GlobalLongHorizonGoalStatus.WAITING_DEPENDENCY -> R.string.cc_global_status_waiting_dependency
    GlobalLongHorizonGoalStatus.WAITING_CONFIRMATION -> R.string.cc_global_status_confirmation
    GlobalLongHorizonGoalStatus.BLOCKED -> R.string.cc_global_status_blocked
    GlobalLongHorizonGoalStatus.COMPLETED -> R.string.cc_global_status_completed
    GlobalLongHorizonGoalStatus.PAUSED -> R.string.on_device_agent_status_paused
})

internal fun MainActivity.globalAutonomousActionStatusLabel(status: GlobalAutonomousActionStatus): String = getString(when (status) {
    GlobalAutonomousActionStatus.PENDING -> R.string.cc_global_status_queued
    GlobalAutonomousActionStatus.RUNNING -> R.string.cc_global_status_running
    GlobalAutonomousActionStatus.WAITING_CONFIRMATION -> R.string.cc_global_status_confirmation
    GlobalAutonomousActionStatus.COMPLETED -> R.string.cc_global_status_completed
    GlobalAutonomousActionStatus.FAILED -> R.string.cc_global_status_failed
    GlobalAutonomousActionStatus.SKIPPED -> R.string.cc_global_status_skipped
})

internal fun MainActivity.globalActionVerificationLabel(status: GlobalActionVerificationStatus): String = getString(when (status) {
    GlobalActionVerificationStatus.PENDING -> R.string.cc_global_verification_pending
    GlobalActionVerificationStatus.SUPPORTED -> R.string.cc_global_verification_supported
    GlobalActionVerificationStatus.VERIFIED -> R.string.cc_global_verification_verified
    GlobalActionVerificationStatus.INSUFFICIENT -> R.string.cc_global_verification_insufficient
    GlobalActionVerificationStatus.CONTESTED -> R.string.cc_global_verification_contested
})

internal fun MainActivity.globalTopicRelationLabel(kind: GlobalTopicRelationKind): String = getString(when (kind) {
    GlobalTopicRelationKind.CONTAINS -> R.string.cc_global_relation_contains
    GlobalTopicRelationKind.RELATED_TO -> R.string.cc_global_relation_related
    GlobalTopicRelationKind.SUPPORTS -> R.string.cc_global_relation_supports
    GlobalTopicRelationKind.CONFLICTS_WITH -> R.string.cc_global_relation_conflicts
})

internal fun MainActivity.showGlobalInsightsDialog() {
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) {
        globalSuperAgentRuntime
    } else GlobalSuperAgentRuntime.get(this)
    val items = runtime.proactiveInboxItems(limit = 40)
    if (items.isEmpty()) {
        AlertDialog.Builder(this)
            .setTitle(R.string.agent_global_insights_title)
            .setMessage(R.string.agent_global_insights_empty)
            .setPositiveButton(android.R.string.ok, null)
            .show()
        refreshGlobalInsightIndicator()
        return
    }

    runtime.markProactiveInboxViewed(items.flatMapTo(linkedSetOf(), GlobalProactiveInboxItem::messageIds))
    refreshGlobalInsightIndicator()
    val conversations = agentTranscriptStore.conversations(includeArchived = true).associateBy(AgentConversation::id)
    val list = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(16), dp(4), dp(16), dp(8))
    }
    val scroll = ScrollView(this).apply {
        isFillViewport = false
        overScrollMode = View.OVER_SCROLL_NEVER
        addView(list, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))
    }
    var dialog: AlertDialog? = null
    items.forEach { item ->
        val sourceTitle = conversations[item.sourceConversationId]?.let(::agentConversationDisplayTitle)
            ?: item.topic.ifBlank { getString(R.string.app_name) }
        val targetLabel = getString(when (item.target) {
            GlobalProactiveTarget.CURRENT_CONVERSATION -> R.string.agent_global_insight_current_topic
            GlobalProactiveTarget.NEW_CONVERSATION -> R.string.agent_global_insight_new_topic
            GlobalProactiveTarget.GLOBAL_DIGEST -> R.string.agent_global_insight_digest
        })
        val metadata = buildString {
            append(targetLabel)
            if (item.urgent) append(" \u00b7 ").append(getString(R.string.agent_global_insight_urgent))
            append(" \u00b7 ").append(getString(R.string.agent_global_insight_source, sourceTitle))
            if (item.deliveredAtMillis > 0L) {
                append(" \u00b7 ")
                append(SimpleDateFormat("MMM d, HH:mm", Locale.getDefault()).format(Date(item.deliveredAtMillis)))
            }
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(13), dp(12), dp(13), dp(12))
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(getColor(R.color.surface_bg))
                setStroke(dp(1), getColor(R.color.separator))
            }
        }
        card.addView(TextView(this).apply {
            text = metadata
            setTextColor(getColor(R.color.text_secondary))
            textSize = 11f
            maxLines = 2
        })
        card.addView(TextView(this).apply {
            text = item.title.ifBlank { getString(R.string.agent_global_insights_title) }
            setTextColor(getColor(R.color.text_primary))
            textSize = 15f
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(0, dp(7), 0, 0)
        })
        card.addView(TextView(this).apply {
            text = item.content
            setTextColor(getColor(R.color.text_primary))
            textSize = 14f
            setLineSpacing(dp(3).toFloat(), 1f)
            setTextIsSelectable(true)
            setPadding(0, dp(6), 0, dp(8))
        })
        if (item.destinationConversationId.isNotBlank()) {
            card.addView(globalInsightActionButton(
                label = getString(R.string.agent_global_insight_open_topic),
                emphasized = true
            ) {
                dialog?.dismiss()
                openGlobalInsightTopic(item)
            }, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(40)
            ))
        }
        card.addView(TextView(this).apply {
            text = getString(R.string.agent_global_insight_feedback_hint)
            setTextColor(getColor(R.color.text_secondary))
            textSize = 11f
            setPadding(0, dp(9), 0, dp(5))
        })
        val feedbackRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        listOf(
            R.string.agent_global_feedback_helpful to GlobalAgentFeedbackKind.HELPFUL,
            R.string.agent_global_feedback_not_relevant to GlobalAgentFeedbackKind.NOT_RELEVANT,
            R.string.agent_global_feedback_too_frequent to GlobalAgentFeedbackKind.TOO_FREQUENT
        ).forEachIndexed { index, (labelId, kind) ->
            feedbackRow.addView(globalInsightActionButton(
                label = getString(labelId),
                emphasized = item.feedbackKind == kind
            ) {
                if (recordGlobalInsightFeedback(item.key, kind)) dialog?.dismiss()
            }, LinearLayout.LayoutParams(0, dp(40), 1f).apply {
                if (index > 0) leftMargin = dp(6)
            })
        }
        card.addView(feedbackRow)
        list.addView(card, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { bottomMargin = dp(10) })
    }
    dialog = AlertDialog.Builder(this)
        .setTitle(R.string.agent_global_insights_title)
        .setView(scroll)
        .setNegativeButton(R.string.common_close, null)
        .create()
    dialog.show()
    dialog.window?.setLayout(
        (resources.displayMetrics.widthPixels * 0.94f).toInt(),
        (resources.displayMetrics.heightPixels * 0.80f).toInt()
    )
}

internal fun MainActivity.showGlobalPendingInsightsDialog() {
    val messages = globalSuperAgentRuntime.pendingProactiveMessages().takeLast(30)
    val message = messages.takeIf(List<GlobalProactiveMessage>::isNotEmpty)?.joinToString("\n\n") {
        "\u2022 ${it.title}\n${it.content.take(240)}"
    } ?: getString(R.string.cc_global_empty)
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_pending_insights_title)
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

internal fun MainActivity.globalInsightActionButton(
    label: String,
    emphasized: Boolean,
    onClick: () -> Unit
): TextView = TextView(this).apply {
    text = label
    gravity = Gravity.CENTER
    maxLines = 2
    textSize = 12f
    setTextColor(getColor(if (emphasized) R.color.agent_insight_text else R.color.text_primary))
    background = GradientDrawable().apply {
        cornerRadius = dp(7).toFloat()
        setColor(getColor(if (emphasized) R.color.agent_insight_bg else R.color.page_bg))
        setStroke(dp(1), getColor(if (emphasized) R.color.agent_insight_stroke else R.color.separator))
    }
    setOnClickListener { onClick() }
}

internal fun MainActivity.openGlobalInsightTopic(item: GlobalProactiveInboxItem) {
    openAgentConversation(item.destinationConversationId)
}

internal fun MainActivity.openAgentConversation(conversationId: String) {
    conversationWindow.beforeSelection()
    val destination = agentTranscriptStore.resolveMergedConversationId(conversationId) ?: return
    agentTranscriptStore.conversation(destination)?.takeIf {
        it.status == AgentConversationStatus.ARCHIVED
    }?.let { agentTranscriptStore.restoreConversation(destination) }
    if (!agentTranscriptStore.switchConversation(destination)) return
    conversationWindow.selected(destination)
    resetAgentTranscriptRendering(destination)
    showMainTab(PAGE_AGENT)
    refreshAgentConversationHeader()
    refreshAgentTranscriptWindow(destination)
    refreshGlobalInsightIndicator()
}

internal fun MainActivity.refreshGlobalInsightIndicator(countOverride: Int? = null) {
    if (!isAgentInsightBarInitialized() || !isAgentInsightTextInitialized()) return
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) {
        globalSuperAgentRuntime
    } else return
    if (countOverride == null) {
        if (!globalInsightCountRefreshInProgress.compareAndSet(false, true)) return
        navigationContentExecutor.execute {
            val count = runCatching(runtime::newProactiveInsightCount).getOrNull()
            handler.post {
                globalInsightCountRefreshInProgress.set(false)
                if (count != null && !isFinishing && !isDestroyed) {
                    refreshGlobalInsightIndicator(count)
                }
            }
        }
        return
    }
    val count = countOverride
    agentInsightBar.visibility = if (count > 0) View.VISIBLE else View.GONE
    if (count > 0) {
        agentInsightText.text = resources.getQuantityString(R.plurals.agent_global_new_insights, count, count)
    }
}

internal fun MainActivity.showGlobalLearningDialog() {
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) {
        globalSuperAgentRuntime
    } else GlobalSuperAgentRuntime.get(this)
    val profile = runtime.adaptiveProfile()
    val topicSummary = profile.topicAffinity.entries
        .sortedByDescending { kotlin.math.abs(it.value) }
        .take(8)
        .joinToString("\n") { (topic, affinity) ->
            "\u2022 $topic \u00b7 ${if (affinity >= 0.0) "+" else ""}${(affinity * 100).toInt()}%"
        }
    val message = buildString {
        append(getString(
            R.string.cc_global_learning_summary,
            profile.sampleCount,
            profile.helpfulCount,
            profile.notRelevantCount,
            profile.tooFrequentCount
        ))
        if (topicSummary.isNotBlank()) {
            append("\n\n")
            append(getString(R.string.cc_global_learning_topics))
            append("\n")
            append(topicSummary)
        }
    }
    AlertDialog.Builder(this)
        .setTitle(R.string.cc_global_learning_title)
        .setMessage(message)
        .setPositiveButton(android.R.string.ok, null)
        .setNeutralButton(R.string.cc_global_learning_reset) { _, _ ->
            AlertDialog.Builder(this)
                .setTitle(R.string.cc_global_learning_reset)
                .setMessage(R.string.cc_global_learning_reset_confirm)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.cc_global_learning_reset) { _, _ ->
                    runtime.clearAdaptiveFeedback()
                    renderControlCenterGlobalAgentPage()
                }
                .show()
        }
        .show()
}

internal fun MainActivity.globalResearchStatusLabel(status: GlobalResearchTaskStatus): String = getString(when (status) {
    GlobalResearchTaskStatus.QUEUED -> R.string.cc_global_status_queued
    GlobalResearchTaskStatus.RUNNING -> R.string.cc_global_status_running
    GlobalResearchTaskStatus.SCHEDULED -> R.string.cc_global_status_scheduled
    GlobalResearchTaskStatus.WAITING_FOR_RESOURCE -> R.string.cc_global_status_waiting
    GlobalResearchTaskStatus.COMPLETED -> R.string.cc_global_status_completed
    GlobalResearchTaskStatus.FAILED -> R.string.cc_global_status_failed
    GlobalResearchTaskStatus.PAUSED -> R.string.on_device_agent_status_paused
})
