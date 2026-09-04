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

internal fun MainActivity.renderControlCenterMemoryPage() {
    val snapshot = mobileNativeAgent.memorySnapshot()
    val globalMemory = GlobalSuperAgentRuntime.get(this)
    val memoryInbox = globalMemory.memoryInboxSnapshot()
    val pendingCandidates = memoryInbox.pending()
    val evolutionRecords = globalMemory.memoryEvolutionRecordsSnapshot()
    val entityGraph = globalMemory.entityMemoryGraphSnapshot()
    val memoryAudit = globalMemory.memoryAuditSnapshot()
    val world = globalMemory.worldSnapshot()
    val temporal = GlobalMemoryTemporalPolicy.snapshot(world, memoryInbox)
    val currentCount = temporal.count(GlobalMemoryTemporalState.CURRENT)
    val plannedCount = temporal.count(GlobalMemoryTemporalState.PLANNED)
    val historicalCount = temporal.count(GlobalMemoryTemporalState.HISTORICAL)
    val deprecatedCount = temporal.count(GlobalMemoryTemporalState.DEPRECATED)
    val pendingCount = temporal.count(GlobalMemoryTemporalState.PENDING)
    val conflictedCount = temporal.count(GlobalMemoryTemporalState.CONFLICTED)
    val captureEnabled = mobileNativeAgent.safetySettings().memoryCapture
    val countFor: (Set<AgentMemoryKind>) -> Int = { kinds ->
        snapshot.activeItems.count { it.kind in kinds }
    }
    showControlCenterFeature(
        getString(R.string.cc_memory_title),
        ControlCenterPageSpec(
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_memory_overview_title),
                subtitle = getString(R.string.cc_memory_overview_subtitle),
                iconRes = R.drawable.ic_agent_memory,
                badges = listOf(
                    ControlCenterBadgeSpec(
                        getString(if (captureEnabled) R.string.cc_memory_capture_on else R.string.cc_memory_capture_off),
                        if (captureEnabled) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL
                    ),
                    ControlCenterBadgeSpec(
                        getString(R.string.cc_memory_conflict_badge, conflictedCount),
                        if (conflictedCount == 0) ControlCenterTone.BLUE else ControlCenterTone.AMBER
                    )
                ),
                metrics = listOf(
                    ControlCenterMetricSpec(currentCount.toString(), getString(R.string.cc_memory_metric_current)),
                    ControlCenterMetricSpec(plannedCount.toString(), getString(R.string.cc_memory_metric_planned)),
                    ControlCenterMetricSpec(pendingCount.toString(), getString(R.string.cc_memory_metric_pending))
                ),
                actionId = "memory.manage"
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_memory_section_categories),
                    listOf(
                        ControlCenterRowSpec(
                            "memory.group:identity",
                            getString(R.string.cc_memory_identity_preferences_title),
                            getString(R.string.cc_memory_identity_preferences_subtitle),
                            R.drawable.ic_avatar_profile,
                            countFor(setOf(AgentMemoryKind.IDENTITY, AgentMemoryKind.PREFERENCE)).toString(),
                            ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            "memory.group:people",
                            getString(R.string.cc_memory_people_title),
                            getString(R.string.cc_memory_people_subtitle),
                            R.drawable.ic_tab_contacts_outline,
                            countFor(setOf(AgentMemoryKind.CONTACT)).toString(),
                            ControlCenterTone.GREEN
                        ),
                        ControlCenterRowSpec(
                            "memory.group:work",
                            getString(R.string.cc_memory_work_title),
                            getString(R.string.cc_memory_work_subtitle),
                            R.drawable.ic_agent_history,
                            countFor(setOf(AgentMemoryKind.TASK, AgentMemoryKind.WORKFLOW)).toString(),
                            ControlCenterTone.VIOLET
                        ),
                        ControlCenterRowSpec(
                            "memory.group:knowledge",
                            getString(R.string.cc_memory_knowledge_title),
                            getString(R.string.cc_memory_knowledge_subtitle),
                            R.drawable.ic_agent_knowledge,
                            countFor(setOf(AgentMemoryKind.KNOWLEDGE, AgentMemoryKind.SAFETY)).toString(),
                            ControlCenterTone.AMBER
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_memory_section_controls),
                    listOf(
                        ControlCenterRowSpec(
                            "memory.toggle_capture",
                            getString(R.string.cc_memory_capture_title),
                            getString(R.string.cc_memory_capture_subtitle),
                            R.drawable.ic_security_shield,
                            switchValue = captureEnabled,
                            showChevron = false
                        ),
                        ControlCenterRowSpec(
                            "memory.manage",
                            getString(R.string.cc_memory_manage_title),
                            getString(R.string.cc_memory_manage_subtitle),
                            R.drawable.ic_agent_memory,
                            getString(R.string.common_view),
                            ControlCenterTone.BLUE
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_memory_section_lifecycle),
                    listOf(
                        ControlCenterRowSpec(
                            "memory.temporal.current",
                            getString(R.string.cc_memory_state_current_title),
                            getString(R.string.cc_memory_state_current_subtitle),
                            R.drawable.ic_agent_memory,
                            currentCount.toString(),
                            ControlCenterTone.GREEN
                        ),
                        ControlCenterRowSpec(
                            "memory.temporal.planned",
                            getString(R.string.cc_memory_state_planned_title),
                            getString(R.string.cc_memory_state_planned_subtitle),
                            R.drawable.ic_agent_history,
                            plannedCount.toString(),
                            ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            "memory.temporal.historical",
                            getString(R.string.cc_memory_state_historical_title),
                            getString(R.string.cc_memory_state_historical_subtitle),
                            R.drawable.ic_agent_history,
                            historicalCount.toString(),
                            ControlCenterTone.NEUTRAL
                        ),
                        ControlCenterRowSpec(
                            "memory.temporal.deprecated",
                            getString(R.string.cc_memory_state_deprecated_title),
                            getString(R.string.cc_memory_state_deprecated_subtitle),
                            R.drawable.ic_agent_history,
                            deprecatedCount.toString(),
                            ControlCenterTone.NEUTRAL
                        ),
                        ControlCenterRowSpec(
                            "memory.temporal.pending",
                            getString(R.string.cc_memory_state_review_title),
                            getString(R.string.cc_memory_state_pending_subtitle),
                            R.drawable.ic_security_shield,
                            pendingCount.toString(),
                            if (pendingCount == 0) ControlCenterTone.GREEN else ControlCenterTone.AMBER
                        ),
                        ControlCenterRowSpec(
                            "memory.temporal.conflicted",
                            getString(R.string.cc_memory_state_conflicted_title),
                            getString(R.string.cc_memory_state_conflicted_subtitle),
                            R.drawable.ic_security_shield,
                            conflictedCount.toString(),
                            if (conflictedCount == 0) ControlCenterTone.GREEN else ControlCenterTone.AMBER
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_memory_section_evolution),
                    listOf(
                        ControlCenterRowSpec(
                            "memory.inbox",
                            getString(R.string.cc_memory_inbox_title),
                            getString(R.string.cc_memory_inbox_subtitle),
                            R.drawable.ic_agent_memory,
                            pendingCandidates.size.toString(),
                            if (pendingCandidates.isEmpty()) ControlCenterTone.GREEN else ControlCenterTone.AMBER
                        ),
                        ControlCenterRowSpec(
                            "memory.evolution_history",
                            getString(R.string.cc_memory_evolution_history_title),
                            getString(R.string.cc_memory_evolution_history_subtitle),
                            R.drawable.ic_agent_history,
                            evolutionRecords.size.toString(),
                            ControlCenterTone.VIOLET
                        ),
                        ControlCenterRowSpec(
                            "memory.graph",
                            getString(R.string.cc_memory_graph_title),
                            getString(R.string.cc_memory_graph_subtitle),
                            R.drawable.ic_protocol_link,
                            getString(R.string.cc_memory_graph_status, entityGraph.nodes.size, entityGraph.relations.size),
                            ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            "memory.audit",
                            getString(R.string.cc_memory_audit_title),
                            getString(R.string.cc_memory_audit_subtitle),
                            R.drawable.ic_security_shield,
                            memoryAudit.findings.size.toString(),
                            if (memoryAudit.findings.isEmpty()) ControlCenterTone.GREEN else ControlCenterTone.AMBER
                        )
                    )
                )
            )
        )
    )
}

internal fun MainActivity.showGlobalMemoryInboxPage(statusFilter: GlobalMemoryCandidateStatus? = null) {
    val runtime = GlobalSuperAgentRuntime.get(this)
    val pending = runtime.memoryInboxSnapshot().pending()
        .filter { statusFilter == null || it.status == statusFilter }
    showFeaturePage(getString(R.string.cc_memory_inbox_title))
    featureContent.addView(featureHeroCard(
        getString(R.string.cc_memory_inbox_hero_title),
        getString(R.string.cc_memory_inbox_hero_subtitle),
        R.drawable.ic_agent_memory,
        "#5B6CFF",
        pending.size.toString()
    ))
    addSectionTitle(getString(R.string.cc_memory_inbox_pending_section))
    if (pending.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.cc_memory_inbox_empty),
            getString(R.string.cc_memory_inbox_empty_subtitle),
            R.drawable.ic_security_shield,
            ""
        ))
        return
    }
    pending.forEach { candidate ->
        featureContent.addView(featureRow(
            candidate.item.value.ifBlank { candidate.item.topic }.replace(Regex("\\s+"), " ").take(90),
            getString(
                R.string.cc_memory_candidate_subtitle_detailed,
                "${memoryCandidateKindLabel(candidate.kind)} · ${memoryNamespaceLabel(candidate.item)}",
                memoryTemporalStateLabel(candidate.temporalState),
                memoryEvolutionActionLabel(candidate.action),
                candidate.item.evidenceCount
            ),
            R.drawable.ic_agent_memory,
            getString(R.string.agent_memory_review)
        ).apply {
            setOnClickListener { showGlobalMemoryCandidateDialog(candidate, statusFilter) }
        })
    }
}

internal fun MainActivity.showGlobalMemoryCandidateDialog(
    candidate: GlobalMemoryCandidate,
    statusFilter: GlobalMemoryCandidateStatus? = null
) {
    val detail = getString(
        R.string.cc_memory_candidate_dialog_message_detailed,
        "${memoryCandidateKindLabel(candidate.kind)} · ${memoryNamespaceLabel(candidate.item)}",
        candidate.item.topic.ifBlank { getString(R.string.agent_memory_key_none) },
        memoryCandidateRiskLabel(candidate.risk),
        memoryTemporalStateLabel(candidate.temporalState),
        memoryEvolutionActionLabel(candidate.action),
        candidate.targetItemIds.size,
        candidate.item.evidenceCount,
        candidate.reason.ifBlank { getString(R.string.cc_memory_candidate_reason_default) },
        candidate.item.value.ifBlank { getString(R.string.cc_memory_candidate_private_value) }
    )
    AlertDialog.Builder(this)
        .setTitle(getString(R.string.cc_memory_candidate_dialog_title))
        .setMessage(detail)
        .setPositiveButton(R.string.cc_memory_candidate_approve) { _, _ ->
            val approved = GlobalSuperAgentRuntime.get(this).approveMemoryCandidate(candidate.id)
            Toast.makeText(
                this,
                getString(if (approved) R.string.cc_memory_candidate_approved else R.string.cc_memory_candidate_unchanged),
                Toast.LENGTH_SHORT
            ).show()
            showGlobalMemoryInboxPage(statusFilter)
        }
        .setNegativeButton(R.string.common_reject) { _, _ ->
            val rejected = GlobalSuperAgentRuntime.get(this).rejectMemoryCandidate(candidate.id)
            Toast.makeText(
                this,
                getString(if (rejected) R.string.cc_memory_candidate_rejected else R.string.cc_memory_candidate_unchanged),
                Toast.LENGTH_SHORT
            ).show()
            showGlobalMemoryInboxPage(statusFilter)
        }
        .setNeutralButton(R.string.common_cancel, null)
        .show()
}

internal fun MainActivity.showGlobalMemoryTemporalPage(state: GlobalMemoryTemporalState) {
    val runtime = GlobalSuperAgentRuntime.get(this)
    val snapshot = GlobalMemoryTemporalPolicy.snapshot(
        runtime.worldSnapshot(),
        runtime.memoryInboxSnapshot()
    )
    val items = snapshot.accepted(state)
    val stateLabel = memoryTemporalStateLabel(state)
    showFeaturePage(stateLabel)
    featureContent.addView(featureHeroCard(
        stateLabel,
        getString(R.string.cc_memory_temporal_page_subtitle, stateLabel),
        R.drawable.ic_agent_history,
        "#2F80ED",
        items.size.toString()
    ))
    addSectionTitle(getString(R.string.cc_memory_temporal_items))
    if (items.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.cc_memory_temporal_empty, stateLabel),
            getString(R.string.cc_memory_temporal_empty_subtitle),
            R.drawable.ic_agent_memory,
            ""
        ))
        return
    }
    items.take(200).forEach { item ->
        val itemState = memoryTemporalStateLabel(GlobalMemoryTemporalPolicy.classify(item))
        val itemSubtitle = if (item.supersededByItemId.isNotBlank()) {
            getString(
                R.string.cc_memory_temporal_item_replaced_subtitle,
                itemState,
                memoryNamespaceLabel(item),
                item.evidenceCount
            )
        } else {
            getString(
                R.string.cc_memory_temporal_item_subtitle,
                itemState,
                memoryNamespaceLabel(item),
                item.evidenceCount
            )
        }
        featureContent.addView(featureRow(
            item.topic.ifBlank { item.kind.name.lowercase(Locale.ROOT).replace('_', ' ') },
            itemSubtitle,
            R.drawable.ic_agent_memory,
            securityTime(item.lastSeenAtMillis)
        ))
    }
}

internal fun MainActivity.showGlobalMemoryGraphPage() {
    val graph = GlobalSuperAgentRuntime.get(this).entityMemoryGraphSnapshot()
    val nodesById = graph.nodes.associateBy(GlobalEntityNode::id)
    showFeaturePage(getString(R.string.cc_memory_graph_title))
    featureContent.addView(featureHeroCard(
        getString(R.string.cc_memory_graph_hero_title),
        getString(R.string.cc_memory_graph_hero_subtitle),
        R.drawable.ic_protocol_link,
        "#2F80ED",
        getString(R.string.cc_memory_graph_status, graph.nodes.size, graph.relations.size)
    ))
    addSectionTitle(getString(R.string.cc_memory_graph_current_entities))
    if (graph.nodes.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.cc_memory_graph_empty),
            getString(R.string.cc_memory_graph_empty_subtitle),
            R.drawable.ic_protocol_link,
            ""
        ))
    } else {
        graph.nodes.sortedByDescending(GlobalEntityNode::lastSeenAtMillis).take(40).forEach { node ->
            featureContent.addView(featureRow(
                node.label,
                getString(
                    R.string.cc_memory_graph_node_subtitle,
                    node.kind.name.lowercase(Locale.ROOT).replace('_', ' '),
                    memoryTemporalStateLabel(node.temporalState)
                ),
                R.drawable.ic_agent_node,
                ""
            ))
        }
    }
    if (graph.relations.isNotEmpty()) {
        addSectionTitle(getString(R.string.cc_memory_graph_relations))
        graph.relations.sortedByDescending(GlobalEntityRelation::lastSeenAtMillis).take(40).forEach { relation ->
            val from = nodesById[relation.fromNodeId]?.label ?: return@forEach
            val to = nodesById[relation.toNodeId]?.label ?: return@forEach
            featureContent.addView(featureRow(
                getString(R.string.cc_memory_graph_relation_title, from, to),
                relation.kind.name.lowercase(Locale.ROOT).replace('_', ' '),
                R.drawable.ic_protocol_link,
                memoryTemporalStateLabel(relation.temporalState)
            ))
        }
    }
}

internal fun MainActivity.showGlobalMemoryEvolutionHistoryPage() {
    val records = GlobalSuperAgentRuntime.get(this).memoryEvolutionRecordsSnapshot()
        .sortedByDescending(GlobalMemoryEvolutionRecord::createdAtMillis)
    showFeaturePage(getString(R.string.cc_memory_evolution_history_title))
    featureContent.addView(featureHeroCard(
        getString(R.string.cc_memory_evolution_history_hero_title),
        getString(R.string.cc_memory_evolution_history_hero_subtitle),
        R.drawable.ic_agent_history,
        "#6C5CE7",
        records.size.toString()
    ))
    addSectionTitle(getString(R.string.cc_memory_evolution_history_recent))
    if (records.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.cc_memory_evolution_history_empty),
            getString(R.string.cc_memory_evolution_history_empty_subtitle),
            R.drawable.ic_agent_history,
            ""
        ))
        return
    }
    records.take(100).forEach { record ->
        featureContent.addView(featureRow(
            record.subject,
            getString(
                R.string.cc_memory_evolution_history_item_subtitle,
                memoryEvolutionActionLabel(record.action),
                memoryEvolutionOutcomeLabel(record.outcome),
                record.evidenceCount
            ),
            R.drawable.ic_agent_history,
            securityTime(record.createdAtMillis)
        ))
    }
}

internal fun MainActivity.showGlobalMemoryAuditPage(runNow: Boolean = false) {
    val runtime = GlobalSuperAgentRuntime.get(this)
    val report = if (runNow) runtime.runMemoryAudit() else runtime.memoryAuditSnapshot()
    showFeaturePage(getString(R.string.cc_memory_audit_title))
    featureContent.addView(featureHeroCard(
        getString(R.string.cc_memory_audit_hero_title),
        getString(R.string.cc_memory_audit_hero_subtitle),
        R.drawable.ic_security_shield,
        "#16A085",
        report.findings.size.toString()
    ).apply { setOnClickListener { showGlobalMemoryAuditPage(runNow = true) } })
    addSectionTitle(getString(R.string.cc_memory_audit_findings))
    if (report.findings.isEmpty()) {
        featureContent.addView(featureRow(
            getString(R.string.cc_memory_audit_clean),
            getString(R.string.cc_memory_audit_clean_subtitle),
            R.drawable.ic_security_shield,
            getString(R.string.cc_status_ready)
        ))
    } else {
        report.findings.forEach { finding ->
            featureContent.addView(featureRow(
                memoryAuditFindingLabel(finding.kind),
                getString(R.string.cc_memory_audit_evidence_count, finding.evidenceCount),
                R.drawable.ic_security_shield,
                ""
            ))
        }
    }
    if (report.themes.isNotEmpty()) {
        addSectionTitle(getString(R.string.cc_memory_audit_themes))
        report.themes.forEach { theme ->
            featureContent.addView(featureRow(
                theme.title,
                getString(
                    R.string.cc_memory_theme_subtitle,
                    theme.itemCount,
                    theme.conversationCount,
                    theme.evidenceCount
                ),
                R.drawable.ic_agent_knowledge,
                ""
            ))
        }
    }
}

internal fun MainActivity.memoryCandidateKindLabel(kind: GlobalMemoryCandidateKind): String = getString(
    when (kind) {
        GlobalMemoryCandidateKind.IDENTITY -> R.string.agent_memory_kind_identity
        GlobalMemoryCandidateKind.PREFERENCE -> R.string.agent_memory_kind_preference
        GlobalMemoryCandidateKind.GOAL, GlobalMemoryCandidateKind.PROJECT_STATE -> R.string.agent_memory_kind_task
        GlobalMemoryCandidateKind.DECISION, GlobalMemoryCandidateKind.SKILL_OPPORTUNITY -> R.string.agent_memory_kind_workflow
        GlobalMemoryCandidateKind.RELATION -> R.string.agent_memory_kind_contact
        GlobalMemoryCandidateKind.FACT -> R.string.agent_memory_kind_knowledge
    }
)

internal fun MainActivity.memoryCandidateRiskLabel(risk: GlobalMemoryCandidateRisk): String = getString(
    when (risk) {
        GlobalMemoryCandidateRisk.LOW -> R.string.cc_memory_risk_low
        GlobalMemoryCandidateRisk.REVIEW_REQUIRED -> R.string.cc_memory_risk_review
        GlobalMemoryCandidateRisk.PRIVATE_BLOCKED -> R.string.cc_memory_risk_private
    }
)

internal fun MainActivity.memoryTemporalStateLabel(state: GlobalMemoryTemporalState): String = getString(
    when (state) {
        GlobalMemoryTemporalState.HISTORICAL -> R.string.cc_memory_state_historical
        GlobalMemoryTemporalState.CURRENT -> R.string.cc_memory_state_current
        GlobalMemoryTemporalState.PLANNED -> R.string.cc_memory_state_planned
        GlobalMemoryTemporalState.DEPRECATED -> R.string.cc_memory_state_deprecated
        GlobalMemoryTemporalState.PENDING -> R.string.cc_memory_state_pending
        GlobalMemoryTemporalState.CONFLICTED -> R.string.cc_memory_state_conflicted
    }
)

internal fun MainActivity.memoryNamespaceLabel(item: GlobalWorldItem): String {
    val label = getString(
        when (item.namespace) {
            GlobalMemoryNamespace.GENERAL -> R.string.cc_memory_namespace_general
            GlobalMemoryNamespace.USER -> R.string.cc_memory_namespace_user
            GlobalMemoryNamespace.PROJECT -> R.string.cc_memory_namespace_project
            GlobalMemoryNamespace.DEVICE -> R.string.cc_memory_namespace_device
            GlobalMemoryNamespace.SECURITY -> R.string.cc_memory_namespace_security
        }
    )
    val genericIds = setOf("", "default", "self", "local", "policy")
    return if (item.namespaceId in genericIds) label else "$label · ${item.namespaceId.take(32)}"
}

internal fun MainActivity.memoryEvolutionActionLabel(action: GlobalMemoryEvolutionAction): String = getString(
    when (action) {
        GlobalMemoryEvolutionAction.CREATE -> R.string.cc_memory_action_create
        GlobalMemoryEvolutionAction.STRENGTHEN -> R.string.cc_memory_action_strengthen
        GlobalMemoryEvolutionAction.SUPERSEDE -> R.string.cc_memory_action_supersede
        GlobalMemoryEvolutionAction.LINK -> R.string.cc_memory_action_link
        GlobalMemoryEvolutionAction.CONSOLIDATE -> R.string.cc_memory_action_consolidate
        GlobalMemoryEvolutionAction.REVIEW_CONFLICT -> R.string.cc_memory_action_review_conflict
        GlobalMemoryEvolutionAction.BLOCK_PRIVATE -> R.string.cc_memory_action_block_private
    }
)

internal fun MainActivity.memoryAuditFindingLabel(kind: GlobalMemoryAuditFindingKind): String = getString(
    when (kind) {
        GlobalMemoryAuditFindingKind.EXPIRED -> R.string.cc_memory_audit_expired
        GlobalMemoryAuditFindingKind.DUPLICATE -> R.string.cc_memory_audit_duplicate
        GlobalMemoryAuditFindingKind.LOW_CONFIDENCE_REUSED -> R.string.cc_memory_audit_low_confidence
        GlobalMemoryAuditFindingKind.STALE_CANDIDATE -> R.string.cc_memory_audit_stale_candidate
        GlobalMemoryAuditFindingKind.UNRESOLVED_CONFLICT -> R.string.cc_memory_audit_conflict
        GlobalMemoryAuditFindingKind.SKILL_CANDIDATE -> R.string.cc_memory_audit_skill_candidate
        GlobalMemoryAuditFindingKind.COMPLETED_GOAL -> R.string.cc_memory_audit_completed_goal
    }
)

internal fun MainActivity.memoryEvolutionOutcomeLabel(outcome: GlobalMemoryEvolutionOutcome): String = getString(
    when (outcome) {
        GlobalMemoryEvolutionOutcome.APPLIED -> R.string.cc_memory_evolution_outcome_applied
        GlobalMemoryEvolutionOutcome.WAITING_REVIEW -> R.string.cc_memory_evolution_outcome_waiting
        GlobalMemoryEvolutionOutcome.CONFLICTED -> R.string.cc_memory_evolution_outcome_conflicted
        GlobalMemoryEvolutionOutcome.PRIVATE_BLOCKED -> R.string.cc_memory_evolution_outcome_private_blocked
        GlobalMemoryEvolutionOutcome.APPROVED -> R.string.cc_memory_evolution_outcome_approved
        GlobalMemoryEvolutionOutcome.REJECTED -> R.string.cc_memory_evolution_outcome_rejected
    }
)

internal fun MainActivity.renderControlCenterLearningPage() {
    val pending = agentLearningEngine.proposals(AgentLearningProposalStatus.PENDING)
    val approved = agentLearningEngine.proposals(AgentLearningProposalStatus.APPROVED)
    val rejected = agentLearningEngine.proposals(AgentLearningProposalStatus.REJECTED)
    val captureEnabled = mobileNativeAgent.safetySettings().memoryCapture
    val proposalRows = pending.map { proposal ->
        ControlCenterRowSpec(
            actionId = "learning.proposal:${proposal.id}",
            title = proposal.title,
            subtitle = getString(R.string.cc_learning_evidence_subtitle, proposal.evidenceRunIds.size),
            iconRes = R.drawable.ic_agent_skill,
            status = getString(R.string.cc_learning_review),
            tone = ControlCenterTone.VIOLET
        )
    }.ifEmpty {
        listOf(
            ControlCenterRowSpec(
                actionId = "",
                title = getString(R.string.cc_learning_no_proposals_title),
                subtitle = getString(R.string.cc_learning_no_proposals_subtitle),
                iconRes = R.drawable.ic_agent_skill,
                status = getString(R.string.cc_status_ready),
                tone = ControlCenterTone.GREEN,
                showChevron = false
            )
        )
    }
    showControlCenterFeature(
        getString(R.string.cc_learning_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(R.string.cc_learning_banner_title),
                subtitle = getString(R.string.cc_learning_banner_subtitle),
                iconRes = R.drawable.ic_agent_skill,
                tone = if (pending.isEmpty()) ControlCenterTone.GREEN else ControlCenterTone.VIOLET
            ),
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_learning_overview_title),
                subtitle = getString(R.string.cc_learning_overview_subtitle),
                iconRes = R.drawable.ic_agent_skill,
                metrics = listOf(
                    ControlCenterMetricSpec(pending.size.toString(), getString(R.string.cc_learning_metric_pending)),
                    ControlCenterMetricSpec(approved.size.toString(), getString(R.string.cc_learning_metric_approved)),
                    ControlCenterMetricSpec(rejected.size.toString(), getString(R.string.cc_learning_metric_rejected))
                )
            ),
            sections = listOf(
                ControlCenterSectionSpec(getString(R.string.cc_learning_section_proposals), proposalRows),
                ControlCenterSectionSpec(
                    getString(R.string.cc_learning_section_policy),
                    listOf(
                        ControlCenterRowSpec(
                            actionId = "learning.toggle_capture",
                            title = getString(R.string.cc_learning_memory_title),
                            subtitle = getString(R.string.cc_learning_memory_subtitle),
                            iconRes = R.drawable.ic_agent_memory,
                            switchValue = captureEnabled,
                            showChevron = false
                        ),
                        ControlCenterRowSpec(
                            actionId = "",
                            title = getString(R.string.cc_learning_review_policy_title),
                            subtitle = getString(R.string.cc_learning_review_policy_subtitle),
                            iconRes = R.drawable.ic_security_shield,
                            status = getString(R.string.cc_learning_review),
                            tone = ControlCenterTone.BLUE,
                            showChevron = false
                        )
                    )
                )
            )
        )
    )
}

internal fun MainActivity.showLearningProposalDialog(proposalId: String) {
    val proposal = agentLearningEngine.proposals().firstOrNull { it.id == proposalId } ?: return
    AlertDialog.Builder(this)
        .setTitle(proposal.title)
        .setMessage(
            getString(
                R.string.cc_learning_dialog_message,
                proposal.summary,
                proposal.evidenceRunIds.size
            )
        )
        .setPositiveButton(R.string.cc_learning_approve) { _, _ ->
            val installed = agentLearningEngine.approve(proposal.id)
            Toast.makeText(
                this,
                getString(if (installed != null) R.string.cc_learning_approved else R.string.cc_learning_action_failed),
                Toast.LENGTH_SHORT
            ).show()
            renderControlCenterLearningPage()
        }
        .setNegativeButton(R.string.cc_learning_reject) { _, _ ->
            agentLearningEngine.reject(proposal.id)
            renderControlCenterLearningPage()
        }
        .setNeutralButton(R.string.common_cancel, null)
        .show()
}

internal fun MainActivity.renderControlCenterRuntimePage() {
    val status = AgentOnDeviceRuntimeManager(this).status()
    val catalogManager = agentRuntimePackCatalogManager
    val catalog = catalogManager.cachedVerified()
    val catalogEntries = catalogManager.cachedCompatible()
    val catalogById = catalogEntries.associateBy(AgentRuntimePackCatalogEntry::packId)
    val receipts = AgentRuntimeExecutionReceiptStore(this).list(limit = 5)
    val readyPacks = status.packs.count { it.state == AgentRuntimePackState.READY }
    val environmentPackIds = setOf("linux-base", "python-uv")
    val environmentPacks = status.packs.filter { it.id in environmentPackIds }
    val softwarePacks = status.packs.filterNot { it.id in environmentPackIds }
    val softwareReady = softwarePacks.count { it.state == AgentRuntimePackState.READY }
    val environmentRows = environmentPacks.map { pack ->
        val catalogEntry = catalogById[pack.id]
        val preparing = runtimeCatalogRefreshInProgress && pendingRuntimeCatalogPackId == pack.id
        val stateText = when {
            preparing -> getString(R.string.cc_runtime_install_preparing)
            pack.state == AgentRuntimePackState.READY -> getString(R.string.cc_status_ready)
            pack.state == AgentRuntimePackState.NOT_INSTALLED -> getString(R.string.cc_runtime_catalog_install)
            else -> getString(R.string.cc_runtime_catalog_repair)
        }
        ControlCenterRowSpec(
            actionId = if (preparing) {
                ""
            } else if (pack.state == AgentRuntimePackState.READY) {
                "runtime.pack:${pack.id}"
            } else {
                "runtime.auto_install:${pack.id}"
            },
            title = RuntimePackDisplayPolicy.installedTitle(
                runtimePackTitle(pack.id),
                pack.manifest?.version.takeIf { pack.state == AgentRuntimePackState.READY }
            ),
            subtitle = catalogEntry?.let { entry ->
                getString(
                    R.string.cc_runtime_catalog_pack_subtitle,
                    entry.version,
                    formatBytes(entry.archiveSizeBytes),
                    entry.license
                )
            } ?: pack.reason.ifBlank {
                pack.manifest?.capabilities?.joinToString().orEmpty().ifBlank {
                    getString(R.string.cc_runtime_pack_subtitle)
                }
            },
            iconRes = R.drawable.ic_settings_diagnostics,
            status = stateText,
            tone = when (pack.state) {
                AgentRuntimePackState.READY -> ControlCenterTone.GREEN
                AgentRuntimePackState.NOT_INSTALLED -> ControlCenterTone.BLUE
                AgentRuntimePackState.INVALID, AgentRuntimePackState.INCOMPATIBLE -> ControlCenterTone.AMBER
            },
            showChevron = true
        )
    }
    val receiptRows = if (receipts.isEmpty()) {
        listOf(
            ControlCenterRowSpec(
                actionId = "",
                title = getString(R.string.cc_runtime_receipt_empty_title),
                subtitle = getString(R.string.cc_runtime_receipt_empty_subtitle),
                iconRes = R.drawable.ic_agent_history,
                status = "",
                tone = ControlCenterTone.NEUTRAL,
                showChevron = false
            )
        )
    } else {
        receipts.map { receipt ->
            ControlCenterRowSpec(
                actionId = "runtime.receipt:${receipt.requestId}",
                title = getString(
                    R.string.cc_runtime_receipt_title,
                    runtimeLanguageTitle(receipt.language)
                ),
                subtitle = getString(
                    R.string.cc_runtime_receipt_subtitle,
                    listTime(receipt.createdAtMillis),
                    receipt.requestId.take(8)
                ),
                iconRes = R.drawable.ic_agent_history,
                status = runtimeReceiptStatus(receipt.status),
                tone = if (receipt.status == AgentRuntimeReceiptStatus.COMPLETED) {
                    ControlCenterTone.GREEN
                } else if (receipt.status == AgentRuntimeReceiptStatus.RUNNING) {
                    ControlCenterTone.BLUE
                } else {
                    ControlCenterTone.AMBER
                },
                showChevron = true
            )
        }
    }
    showControlCenterFeature(
        getString(R.string.cc_runtime_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(if (status.backendReady) R.string.cc_runtime_ready_title else R.string.cc_runtime_setup_title),
                subtitle = status.reason,
                iconRes = R.drawable.ic_settings_diagnostics,
                tone = if (status.backendReady) ControlCenterTone.GREEN else ControlCenterTone.AMBER
            ),
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_runtime_overview_title),
                subtitle = getString(R.string.cc_runtime_overview_subtitle),
                iconRes = R.drawable.ic_settings_diagnostics,
                badges = listOf(
                    ControlCenterBadgeSpec(status.architecture.ifBlank { "unknown" }, ControlCenterTone.BLUE),
                    ControlCenterBadgeSpec(status.backend.wireValue, if (status.backendReady) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL)
                ),
                metrics = listOf(
                    ControlCenterMetricSpec(readyPacks.toString(), getString(R.string.cc_runtime_metric_ready)),
                    ControlCenterMetricSpec(status.packs.size.toString(), getString(R.string.cc_runtime_metric_total)),
                    ControlCenterMetricSpec(AgentRuntimeLanguage.entries.count(status::languageReady).toString(), getString(R.string.cc_runtime_metric_languages))
                )
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_runtime_section_management),
                    listOf(
                        ControlCenterRowSpec(
                            actionId = if (status.lifecyclePhase in setOf(
                                    AgentRuntimeLifecyclePhase.STARTING,
                                    AgentRuntimeLifecyclePhase.STOPPING
                                )) "" else "runtime.lifecycle",
                            title = getString(R.string.cc_runtime_lifecycle_title),
                            subtitle = status.lifecycleReason.ifBlank {
                                getString(R.string.cc_runtime_lifecycle_subtitle)
                            },
                            iconRes = R.drawable.ic_protocol_link,
                            status = runtimeLifecycleLabel(status.lifecyclePhase),
                            tone = when (status.lifecyclePhase) {
                                AgentRuntimeLifecyclePhase.READY -> ControlCenterTone.GREEN
                                AgentRuntimeLifecyclePhase.STARTING -> ControlCenterTone.BLUE
                                AgentRuntimeLifecyclePhase.BLOCKED,
                                AgentRuntimeLifecyclePhase.DEGRADED,
                                AgentRuntimeLifecyclePhase.BACKING_OFF -> ControlCenterTone.AMBER
                                AgentRuntimeLifecyclePhase.STOPPED,
                                AgentRuntimeLifecyclePhase.STOPPING -> ControlCenterTone.NEUTRAL
                            },
                            showChevron = status.lifecyclePhase !in setOf(
                                AgentRuntimeLifecyclePhase.STARTING,
                                AgentRuntimeLifecyclePhase.STOPPING
                            )
                        ),
                        ControlCenterRowSpec(
                            actionId = routeAction(ControlCenterRoute.SOFTWARE_CENTER),
                            title = getString(R.string.cc_runtime_software_center_title),
                            subtitle = getString(R.string.cc_runtime_software_center_subtitle),
                            iconRes = R.drawable.ic_local_model,
                            status = getString(
                                R.string.cc_runtime_software_center_status,
                                softwareReady,
                                softwarePacks.size
                            ),
                            tone = if (softwareReady == softwarePacks.size) ControlCenterTone.GREEN else ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            actionId = if (runtimeCatalogRefreshInProgress) "" else "runtime.catalog_refresh",
                            title = getString(R.string.cc_runtime_catalog_refresh_title),
                            subtitle = if (catalog == null) {
                                getString(R.string.cc_runtime_catalog_refresh_subtitle)
                            } else {
                                getString(
                                    R.string.cc_runtime_catalog_loaded_subtitle,
                                    catalog.catalogVersion,
                                    catalogEntries.size
                                )
                            },
                            iconRes = R.drawable.ic_settings_diagnostics,
                            status = if (runtimeCatalogRefreshInProgress) {
                                getString(R.string.cc_runtime_catalog_refreshing)
                            } else {
                                catalog?.catalogVersion.orEmpty()
                            },
                            tone = if (catalog == null) ControlCenterTone.NEUTRAL else ControlCenterTone.GREEN,
                            showChevron = !runtimeCatalogRefreshInProgress
                        )
                    )
                ),
                ControlCenterSectionSpec(getString(R.string.cc_runtime_section_environment), environmentRows),
                ControlCenterSectionSpec(getString(R.string.cc_runtime_section_receipts), receiptRows),
                ControlCenterSectionSpec(
                    getString(R.string.cc_runtime_section_security),
                    listOf(
                        ControlCenterRowSpec("", getString(R.string.cc_runtime_isolation_title), getString(R.string.cc_runtime_isolation_subtitle), R.drawable.ic_security_shield, getString(R.string.cc_status_ready), ControlCenterTone.GREEN, showChevron = false),
                        ControlCenterRowSpec("", getString(R.string.cc_runtime_network_title), getString(R.string.cc_runtime_network_subtitle), R.drawable.ic_protocol_link, getString(R.string.common_off), ControlCenterTone.NEUTRAL, showChevron = false)
                    )
                )
            )
        )
    )
}

internal fun MainActivity.renderControlCenterSoftwareCenterPage(query: String = "") {
    val runtimeManager = AgentOnDeviceRuntimeManager(this)
    val packStatuses = runtimeManager.packStatuses()
    val catalogManager = agentRuntimePackCatalogManager
    val catalog = catalogManager.cachedVerified()
    val catalogById = catalogManager.cachedCompatible().associateBy(AgentRuntimePackCatalogEntry::packId)
    val installedById = packStatuses.associateBy(AgentRuntimePackStatus::id)
    val softwareIds = AgentOnDeviceRuntimeManager.REQUIRED_PACKS.filterNot {
        it == "linux-base" || it == "python-uv"
    }
    val normalizedQuery = query.trim().lowercase(Locale.ROOT)
    val visibleIds = softwareIds.filter { packId ->
        normalizedQuery.isBlank() ||
            packId.lowercase(Locale.ROOT).contains(normalizedQuery) ||
            runtimePackTitle(packId).lowercase(Locale.ROOT).contains(normalizedQuery)
    }
    val softwareRows = if (visibleIds.isEmpty()) {
        listOf(
            ControlCenterRowSpec(
                actionId = "runtime.software_clear_search",
                title = getString(R.string.cc_runtime_software_no_results_title),
                subtitle = getString(R.string.cc_runtime_software_no_results_subtitle, query),
                iconRes = R.drawable.ic_settings_model,
                status = getString(R.string.cc_runtime_software_clear_search),
                tone = ControlCenterTone.NEUTRAL
            )
        )
    } else {
        visibleIds.map { packId ->
            val installed = installedById[packId]
            val entry = catalogById[packId]
            val ready = installed?.state == AgentRuntimePackState.READY
            val sameVersion = ready && entry != null && installed?.manifest?.version == entry.version
            val update = ready && entry != null && !sameVersion
            val preparing = !ready && (
                runtimePackInstallInProgressId == packId ||
                    (runtimeCatalogRefreshInProgress && pendingRuntimeCatalogPackId == packId)
                )
            val actionId = if (preparing) {
                ""
            } else if (ready && !update) {
                "runtime.pack:$packId"
            } else {
                "runtime.auto_install:$packId"
            }
            val subtitle = entry?.let {
                getString(
                    R.string.cc_runtime_catalog_pack_subtitle,
                    it.version,
                    formatBytes(it.archiveSizeBytes),
                    it.license
                )
            } ?: installed?.manifest?.let {
                getString(
                    R.string.cc_runtime_software_installed_subtitle,
                    it.version,
                    formatBytes(it.installedSizeBytes)
                )
            } ?: getString(R.string.cc_runtime_software_lookup_subtitle)
            val statusText = getString(
                when {
                    preparing -> R.string.cc_runtime_install_preparing
                    update -> R.string.cc_runtime_catalog_update
                    ready -> R.string.cc_runtime_catalog_installed
                    installed?.state == AgentRuntimePackState.INVALID ||
                        installed?.state == AgentRuntimePackState.INCOMPATIBLE -> R.string.cc_runtime_catalog_repair
                    else -> R.string.cc_runtime_catalog_install
                }
            )
            ControlCenterRowSpec(
                actionId = actionId,
                title = runtimePackTitle(packId),
                subtitle = subtitle,
                iconRes = if (packId == "ffmpeg") R.drawable.ic_tab_discover else R.drawable.ic_settings_diagnostics,
                status = statusText,
                tone = when {
                    ready && !update -> ControlCenterTone.GREEN
                    installed?.state == AgentRuntimePackState.INVALID ||
                        installed?.state == AgentRuntimePackState.INCOMPATIBLE -> ControlCenterTone.AMBER
                    else -> ControlCenterTone.BLUE
                }
            )
        }
    }
    val readyCount = packStatuses.count {
        it.id in softwareIds && it.state == AgentRuntimePackState.READY
    }
    showControlCenterFeature(
        getString(R.string.cc_runtime_software_center_title),
        ControlCenterPageSpec(
            banner = ControlCenterBannerSpec(
                title = getString(R.string.cc_runtime_software_banner_title),
                subtitle = getString(R.string.cc_runtime_software_banner_subtitle),
                iconRes = R.drawable.ic_local_model,
                tone = ControlCenterTone.BLUE
            ),
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_runtime_software_overview_title),
                subtitle = getString(R.string.cc_runtime_software_overview_subtitle),
                iconRes = R.drawable.ic_local_model,
                badges = listOf(
                    ControlCenterBadgeSpec(
                        getString(R.string.cc_runtime_software_verified_badge),
                        ControlCenterTone.GREEN
                    ),
                    ControlCenterBadgeSpec(runtimeManager.architecture().ifBlank { "unknown" }, ControlCenterTone.BLUE)
                ),
                metrics = listOf(
                    ControlCenterMetricSpec(readyCount.toString(), getString(R.string.cc_runtime_software_metric_installed)),
                    ControlCenterMetricSpec(softwareIds.size.toString(), getString(R.string.cc_runtime_software_metric_available)),
                    ControlCenterMetricSpec(catalog?.catalogVersion.orEmpty().ifBlank { "-" }, getString(R.string.cc_runtime_software_metric_catalog))
                )
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_runtime_software_section_find),
                    listOf(
                        ControlCenterRowSpec(
                            actionId = "runtime.software_search",
                            title = getString(R.string.cc_runtime_software_search_title),
                            subtitle = if (query.isBlank()) {
                                getString(R.string.cc_runtime_software_search_subtitle)
                            } else {
                                getString(R.string.cc_runtime_software_search_active, query)
                            },
                            iconRes = R.drawable.ic_settings_model,
                            status = if (query.isBlank()) "" else getString(R.string.cc_runtime_software_clear_search),
                            tone = ControlCenterTone.NEUTRAL
                        ),
                        ControlCenterRowSpec(
                            actionId = if (runtimeCatalogRefreshInProgress) "" else "runtime.catalog_refresh",
                            title = getString(R.string.cc_runtime_catalog_refresh_title),
                            subtitle = if (catalog == null) {
                                getString(R.string.cc_runtime_catalog_refresh_subtitle)
                            } else {
                                getString(
                                    R.string.cc_runtime_catalog_loaded_subtitle,
                                    catalog.catalogVersion,
                                    catalogById.size
                                )
                            },
                            iconRes = R.drawable.ic_settings_diagnostics,
                            status = if (runtimeCatalogRefreshInProgress) {
                                getString(R.string.cc_runtime_catalog_refreshing)
                            } else {
                                catalog?.catalogVersion.orEmpty()
                            },
                            tone = if (catalog == null) ControlCenterTone.NEUTRAL else ControlCenterTone.GREEN,
                            showChevron = !runtimeCatalogRefreshInProgress
                        )
                    )
                ),
                ControlCenterSectionSpec(getString(R.string.cc_runtime_software_section_catalog), softwareRows),
                ControlCenterSectionSpec(
                    getString(R.string.cc_runtime_software_section_advanced),
                    listOf(
                        ControlCenterRowSpec(
                            actionId = "runtime.import",
                            title = getString(R.string.cc_runtime_import_title),
                            subtitle = getString(R.string.cc_runtime_import_subtitle),
                            iconRes = R.drawable.ic_import,
                            status = "",
                            tone = ControlCenterTone.NEUTRAL
                        )
                    )
                )
            ),
            footer = getString(R.string.cc_runtime_software_footer)
        )
    )
}

internal fun MainActivity.showRuntimeSoftwareSearchDialog() {
    val currentQuery = controlCenterDestination
        ?.takeIf { it.route == ControlCenterRoute.SOFTWARE_CENTER }
        ?.payload
        .orEmpty()
    val input = EditText(this).apply {
        setText(currentQuery)
        hint = getString(R.string.cc_runtime_software_search_hint)
        inputType = InputType.TYPE_CLASS_TEXT
        setSingleLine(true)
        setSelection(text.length)
        setPadding(dp(20), dp(8), dp(20), dp(8))
    }
    val dialog = AlertDialog.Builder(this)
        .setTitle(R.string.cc_runtime_software_search_title)
        .setView(input)
        .setPositiveButton(R.string.cc_runtime_software_search_action, null)
        .setNegativeButton(R.string.common_cancel, null)
        .setNeutralButton(R.string.cc_runtime_software_clear_search, null)
        .create()
    dialog.setOnShowListener {
        dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
            controlCenterDestination = ControlCenterDestination(
                ControlCenterRoute.SOFTWARE_CENTER,
                input.text?.toString().orEmpty().trim()
            )
            dialog.dismiss()
            renderCurrentControlCenterDestination()
        }
        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
            controlCenterDestination = ControlCenterDestination(ControlCenterRoute.SOFTWARE_CENTER)
            dialog.dismiss()
            renderCurrentControlCenterDestination()
        }
    }
    dialog.show()
}

internal fun MainActivity.runtimePackTitle(id: String): String = when (id) {
    "linux-base" -> getString(R.string.cc_runtime_pack_linux)
    "python-uv" -> getString(R.string.cc_runtime_pack_python)
    "node-js" -> getString(R.string.cc_runtime_pack_node)
    "go" -> "Go"
    "rust" -> "Rust"
    "cpp" -> "C / C++"
    "java" -> "Java"
    "gradle" -> "Gradle"
    "android-sdk" -> getString(R.string.cc_runtime_pack_android_sdk)
    "browser-automation" -> getString(R.string.cc_runtime_pack_browser)
    "ffmpeg" -> "FFmpeg"
    else -> id
}

internal fun MainActivity.runtimeLanguageTitle(language: AgentRuntimeLanguage): String = when (language) {
    AgentRuntimeLanguage.SHELL -> "Shell"
    AgentRuntimeLanguage.PYTHON -> "Python"
    AgentRuntimeLanguage.UV -> "uv"
    AgentRuntimeLanguage.JAVASCRIPT -> "JavaScript"
    AgentRuntimeLanguage.TYPESCRIPT -> "TypeScript"
    AgentRuntimeLanguage.GO -> "Go"
    AgentRuntimeLanguage.RUST -> "Rust"
    AgentRuntimeLanguage.C -> "C"
    AgentRuntimeLanguage.CPP -> "C++"
    AgentRuntimeLanguage.JAVA -> "Java"
    AgentRuntimeLanguage.BROWSER -> getString(R.string.cc_runtime_pack_browser)
    AgentRuntimeLanguage.FFMPEG -> "FFmpeg"
    AgentRuntimeLanguage.FFPROBE -> "ffprobe"
}

internal fun MainActivity.runtimeReceiptStatus(status: AgentRuntimeReceiptStatus): String = getString(
    when (status) {
        AgentRuntimeReceiptStatus.RUNNING -> R.string.cc_runtime_receipt_running
        AgentRuntimeReceiptStatus.COMPLETED -> R.string.cc_runtime_receipt_completed
        AgentRuntimeReceiptStatus.FAILED -> R.string.cc_runtime_receipt_failed
        AgentRuntimeReceiptStatus.CANCELLED -> R.string.cc_runtime_receipt_cancelled
        AgentRuntimeReceiptStatus.TIMED_OUT -> R.string.cc_runtime_receipt_timed_out
    }
)

internal fun MainActivity.runtimeLifecycleLabel(phase: AgentRuntimeLifecyclePhase): String = getString(
    when (phase) {
        AgentRuntimeLifecyclePhase.BLOCKED -> R.string.cc_runtime_lifecycle_blocked
        AgentRuntimeLifecyclePhase.STOPPED -> R.string.cc_runtime_lifecycle_stopped
        AgentRuntimeLifecyclePhase.STARTING -> R.string.cc_runtime_lifecycle_starting
        AgentRuntimeLifecyclePhase.READY -> R.string.cc_runtime_lifecycle_ready
        AgentRuntimeLifecyclePhase.DEGRADED -> R.string.cc_runtime_lifecycle_degraded
        AgentRuntimeLifecyclePhase.BACKING_OFF -> R.string.cc_runtime_lifecycle_backing_off
        AgentRuntimeLifecyclePhase.STOPPING -> R.string.cc_runtime_lifecycle_stopping
    }
)

internal fun MainActivity.showRuntimeLifecycleDialog() {
    val snapshot = AgentOnDeviceRuntimeLifecycle.inspect(this)
    val nextAttempt = snapshot.nextAttemptAtMillis.takeIf { it > 0L }?.let(::listTime)
        ?: getString(R.string.cc_runtime_lifecycle_not_scheduled)
    val builder = AlertDialog.Builder(this)
        .setTitle(R.string.cc_runtime_lifecycle_title)
        .setMessage(
            getString(
                R.string.cc_runtime_lifecycle_details,
                runtimeLifecycleLabel(snapshot.phase),
                snapshot.reason.ifBlank { getString(R.string.status_unknown) },
                snapshot.controllerId.ifBlank { getString(R.string.cc_runtime_lifecycle_no_controller) },
                snapshot.consecutiveFailures,
                nextAttempt
            )
        )
        .setNegativeButton(R.string.common_cancel, null)
    when (snapshot.phase) {
        AgentRuntimeLifecyclePhase.READY,
        AgentRuntimeLifecyclePhase.DEGRADED -> {
            builder.setPositiveButton(R.string.cc_runtime_lifecycle_restart) { _, _ ->
                runRuntimeLifecycleOperation(restart = true, stop = false)
            }
            builder.setNeutralButton(R.string.cc_runtime_lifecycle_stop) { _, _ ->
                runRuntimeLifecycleOperation(restart = false, stop = true)
            }
        }
        AgentRuntimeLifecyclePhase.STOPPED,
        AgentRuntimeLifecyclePhase.BACKING_OFF -> builder.setPositiveButton(
            R.string.cc_runtime_lifecycle_start
        ) { _, _ -> runRuntimeLifecycleOperation(restart = false, stop = false) }
        AgentRuntimeLifecyclePhase.BLOCKED,
        AgentRuntimeLifecyclePhase.STARTING,
        AgentRuntimeLifecyclePhase.STOPPING -> Unit
    }
    builder.show()
}

internal fun MainActivity.runRuntimeLifecycleOperation(restart: Boolean, stop: Boolean) {
    Toast.makeText(this, R.string.cc_runtime_lifecycle_working, Toast.LENGTH_SHORT).show()
    thread(name = "galaxyssi-runtime-lifecycle") {
        val outcome = runCatching {
            when {
                stop -> AgentOnDeviceRuntimeLifecycle.stop(this)
                restart -> AgentOnDeviceRuntimeLifecycle.restart(this)
                else -> AgentOnDeviceRuntimeLifecycle.start(this, force = true)
            }
        }
        runOnUiThread {
            Toast.makeText(
                this,
                outcome.fold(
                    onSuccess = { result ->
                        getString(
                            R.string.cc_runtime_lifecycle_result,
                            runtimeLifecycleLabel(result.phase),
                            result.reason
                        )
                    },
                    onFailure = { error ->
                        getString(
                            R.string.cc_runtime_lifecycle_failed,
                            error.message ?: getString(R.string.status_unknown)
                        )
                    }
                ),
                Toast.LENGTH_LONG
            ).show()
            renderRuntimeControlCenterIfVisible()
        }
    }
}

internal fun MainActivity.scheduleRuntimeLifecycleStartup() {
    thread(name = "galaxyssi-runtime-autostart") {
        runCatching { AgentEmbeddedRuntimeBootstrap.ensureInstalled(this) }
        runCatching { AgentOnDeviceRuntimeLifecycle.ensureRunning(this) }
        runOnUiThread {
            renderRuntimeControlCenterIfVisible()
        }
    }
}

internal fun MainActivity.showRuntimeReceiptDialog(requestId: String) {
    val receipt = AgentRuntimeExecutionReceiptStore(this).find(requestId) ?: return
    AlertDialog.Builder(this)
        .setTitle(getString(R.string.cc_runtime_receipt_title, runtimeLanguageTitle(receipt.language)))
        .setMessage(
            getString(
                R.string.cc_runtime_receipt_details,
                receipt.requestId,
                runtimeReceiptStatus(receipt.status),
                receipt.sourceSha256,
                receipt.packVersions.entries.joinToString { "${it.key} ${it.value}" }.ifBlank { "-" },
                receipt.exitCode?.toString() ?: "-",
                receipt.artifacts.size,
                receipt.error.ifBlank { "-" }
            )
        )
        .setPositiveButton(android.R.string.ok, null)
        .show()
}

internal fun MainActivity.refreshRuntimePackCatalog() {
    if (runtimeCatalogRefreshInProgress) return
    runtimeCatalogRefreshInProgress = true
    renderRuntimeControlCenterIfVisible()
    thread(name = "galaxyssi-runtime-catalog-refresh") {
        val outcome = runCatching { agentRuntimePackCatalogManager.refresh() }
        runOnUiThread {
            runtimeCatalogRefreshInProgress = false
            val requestedPackId = pendingRuntimeCatalogPackId
            pendingRuntimeCatalogPackId = null
            outcome.fold(
                onSuccess = { catalog ->
                    val requestedEntry = requestedPackId?.let { packId ->
                        agentRuntimePackCatalogManager.cachedCompatible()
                            .firstOrNull { it.packId == packId }
                    }
                    when {
                        requestedEntry != null -> installRuntimeCatalogPack(requestedEntry)
                        requestedPackId != null -> Toast.makeText(
                            this,
                            getString(
                                R.string.cc_runtime_catalog_pack_unavailable,
                                runtimePackTitle(requestedPackId)
                            ),
                            Toast.LENGTH_LONG
                        ).show()
                        else -> Toast.makeText(
                            this,
                            getString(R.string.cc_runtime_catalog_refresh_success, catalog.catalogVersion),
                            Toast.LENGTH_LONG
                        ).show()
                    }
                },
                onFailure = { error ->
                    Toast.makeText(
                        this,
                        getString(
                            R.string.cc_runtime_catalog_refresh_failed,
                            error.message ?: getString(R.string.status_unknown)
                        ),
                        Toast.LENGTH_LONG
                    ).show()
                }
            )
            renderRuntimeControlCenterIfVisible()
        }
    }
}

internal fun MainActivity.autoInstallRuntimePack(packId: String) {
    if (packId !in AgentOnDeviceRuntimeManager.REQUIRED_PACKS) {
        Toast.makeText(
            this,
            getString(R.string.cc_runtime_catalog_pack_unavailable, runtimePackTitle(packId)),
            Toast.LENGTH_LONG
        ).show()
        return
    }
    val entry = agentRuntimePackCatalogManager.cachedCompatible()
        .firstOrNull { it.packId == packId }
    if (entry != null) {
        installRuntimeCatalogPack(entry)
        return
    }
    pendingRuntimeCatalogPackId = packId
    Toast.makeText(
        this,
        getString(R.string.cc_runtime_install_loading_catalog, runtimePackTitle(packId)),
        Toast.LENGTH_SHORT
    ).show()
    refreshRuntimePackCatalog()
}

internal fun MainActivity.renderRuntimeControlCenterIfVisible() {
    when (controlCenterDestination?.route) {
        ControlCenterRoute.ON_DEVICE_RUNTIME -> renderControlCenterRuntimePage()
        ControlCenterRoute.SOFTWARE_CENTER -> renderControlCenterSoftwareCenterPage(
            controlCenterDestination?.payload.orEmpty()
        )
        else -> Unit
    }
}

internal fun MainActivity.showRuntimeCatalogPackDialog(packId: String) {
    val entry = agentRuntimePackCatalogManager.cachedCompatible()
        .firstOrNull { it.packId == packId } ?: return
    val installed = AgentOnDeviceRuntimeManager(this).status().packs.firstOrNull { it.id == packId }
    val sameVersion = installed?.state == AgentRuntimePackState.READY &&
        installed.manifest?.version == entry.version
    val dependencies = entry.dependencies.joinToString { runtimePackTitle(it) }
        .ifBlank { getString(R.string.cc_runtime_catalog_no_dependencies) }
    val message = getString(
        R.string.cc_runtime_catalog_details,
        entry.version,
        entry.architecture,
        formatBytes(entry.archiveSizeBytes),
        formatBytes(entry.installedSizeBytes),
        entry.license,
        dependencies,
        entry.releaseNotes.ifBlank { getString(R.string.cc_runtime_catalog_no_release_notes) }
    )
    AlertDialog.Builder(this)
        .setTitle(runtimePackTitle(packId))
        .setMessage(message)
        .setPositiveButton(
            if (sameVersion) R.string.cc_runtime_catalog_reinstall else R.string.cc_runtime_catalog_install
        ) { _, _ -> installRuntimeCatalogPack(entry) }
        .setNegativeButton(R.string.common_cancel, null)
        .show()
}

internal fun MainActivity.installRuntimeCatalogPack(entry: AgentRuntimePackCatalogEntry) {
    if (runtimePackInstallInProgressId != null) return
    val manager = agentRuntimePackCatalogManager
    val plan = runCatching { manager.installationPlan(entry) }.getOrElse { error ->
        Toast.makeText(
            this,
            getString(R.string.cc_runtime_install_failed, error.message ?: getString(R.string.status_unknown)),
            Toast.LENGTH_LONG
        ).show()
        return
    }
    runtimeCatalogRefreshInProgress = false
    pendingRuntimeCatalogPackId = null
    runtimePackInstallInProgressId = entry.packId
    val installedById = AgentOnDeviceRuntimeManager(this).packStatuses().associateBy(AgentRuntimePackStatus::id)
    val pending = plan.filter { item ->
        item.packId == entry.packId || installedById[item.packId]?.let { installed ->
            installed.state != AgentRuntimePackState.READY || installed.manifest?.version != item.version
        } != false
    }
    val cancellation = AgentNativeToolCancellationSource()
    val progressText = TextView(this).apply {
        setPadding(dp(24), dp(8), dp(24), dp(8))
        setTextColor(Color.rgb(43, 48, 58))
        textSize = 15f
        text = getString(R.string.cc_runtime_install_progress_preparing)
    }
    val progressDialog = AlertDialog.Builder(this)
        .setTitle(getString(R.string.cc_runtime_install_progress_title))
        .setView(progressText)
        .setNegativeButton(R.string.common_cancel) { _, _ -> cancellation.cancel() }
        .create()
    progressDialog.setCanceledOnTouchOutside(false)
    progressDialog.setOnCancelListener { cancellation.cancel() }
    progressDialog.show()

    var lastProgressKey = ""
    fun updateProgress(pack: AgentRuntimePackCatalogEntry, index: Int, stage: String, percent: Int) {
        val boundedPercent = percent.coerceIn(0, 100)
        val progressKey = "${pack.packId}:$index:$stage:$boundedPercent"
        if (progressKey == lastProgressKey) return
        lastProgressKey = progressKey
        runOnUiThread {
            if (progressDialog.isShowing) {
                progressText.text = getString(
                    R.string.cc_runtime_install_progress,
                    runtimePackTitle(pack.packId),
                    index + 1,
                    pending.size,
                    stage,
                    boundedPercent
                )
            }
        }
    }

    thread(name = "galaxyssi-runtime-catalog-install") {
        val outcome = runCatching {
            pending.forEachIndexed { index, pack ->
                if (cancellation.token.isCancellationRequested) throw AgentNativeToolCancelledException()
                val result = manager.downloadAndInstall(
                    pack,
                    cancellation.token,
                    onDownloadProgress = { progress ->
                        val percent = if (progress.totalBytes > 0L) {
                            ((progress.downloadedBytes * 80L) / progress.totalBytes).toInt()
                        } else 0
                        updateProgress(
                            pack,
                            index,
                            getString(R.string.cc_runtime_install_stage_downloading),
                            percent
                        )
                    },
                    onInstallProgress = { progress ->
                        val percent = when (progress.stage) {
                            AgentRuntimePackInstallStage.PREPARING -> 81
                            AgentRuntimePackInstallStage.COPYING -> 83
                            AgentRuntimePackInstallStage.EXTRACTING -> 88
                            AgentRuntimePackInstallStage.VERIFYING -> 94
                            AgentRuntimePackInstallStage.ACTIVATING -> 98
                            AgentRuntimePackInstallStage.COMPLETED -> 100
                        }
                        updateProgress(
                            pack,
                            index,
                            getString(runtimeInstallStageLabel(progress.stage)),
                            percent
                        )
                    }
                )
                check(result.state == AgentRuntimePackState.READY) {
                    result.reason.ifBlank { "Runtime pack did not become ready" }
                }
            }
        }
        runOnUiThread {
            if (progressDialog.isShowing) progressDialog.dismiss()
            runtimePackInstallInProgressId = null
            runtimeCatalogRefreshInProgress = false
            pendingRuntimeCatalogPackId = null
            val installedSuccessfully = outcome.isSuccess
            val message = outcome.fold(
                onSuccess = {
                    getString(R.string.cc_runtime_install_success, runtimePackTitle(entry.packId), entry.version)
                },
                onFailure = { error ->
                    if (error is AgentNativeToolCancelledException) {
                        getString(R.string.cc_runtime_install_cancelled)
                    } else {
                        getString(
                            R.string.cc_runtime_install_failed,
                            error.message ?: getString(R.string.status_unknown)
                        )
                    }
                }
            )
            Toast.makeText(this, message, Toast.LENGTH_LONG).show()
            renderRuntimeControlCenterIfVisible()
            if (installedSuccessfully) scheduleRuntimeLifecycleStartup()
        }
    }
}

internal fun MainActivity.runtimeInstallStageLabel(stage: AgentRuntimePackInstallStage): Int = when (stage) {
    AgentRuntimePackInstallStage.PREPARING -> R.string.cc_runtime_install_stage_preparing
    AgentRuntimePackInstallStage.COPYING -> R.string.cc_runtime_install_stage_copying
    AgentRuntimePackInstallStage.EXTRACTING -> R.string.cc_runtime_install_stage_extracting
    AgentRuntimePackInstallStage.VERIFYING -> R.string.cc_runtime_install_stage_verifying
    AgentRuntimePackInstallStage.ACTIVATING -> R.string.cc_runtime_install_stage_activating
    AgentRuntimePackInstallStage.COMPLETED -> R.string.cc_runtime_install_stage_completed
}

internal fun MainActivity.openRuntimePackPicker() {
    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
        addCategory(Intent.CATEGORY_OPENABLE)
        type = AgentRuntimePackInstaller.PACKAGE_MIME_TYPE
        putExtra(
            Intent.EXTRA_MIME_TYPES,
            arrayOf(AgentRuntimePackInstaller.PACKAGE_MIME_TYPE, "application/zip", "application/octet-stream")
        )
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
    }, REQUEST_IMPORT_RUNTIME_PACK)
}

internal fun MainActivity.importRuntimePackFromUri(uri: Uri) {
    runCatching {
        contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    Toast.makeText(this, getString(R.string.cc_runtime_installing), Toast.LENGTH_SHORT).show()
    thread(name = "galaxyssi-runtime-pack-install") {
        val outcome = runCatching { AgentRuntimePackInstaller(this).install(uri) }
        runOnUiThread {
            outcome.fold(
                onSuccess = { result ->
                    scheduleRuntimeLifecycleStartup()
                    val message = if (result.state == AgentRuntimePackState.READY) {
                        getString(R.string.cc_runtime_install_success, runtimePackTitle(result.packId), result.version)
                    } else {
                        getString(
                            R.string.cc_runtime_install_incomplete,
                            runtimePackTitle(result.packId),
                            result.reason.ifBlank { getString(R.string.status_needs_setup) }
                        )
                    }
                    Toast.makeText(this, message, Toast.LENGTH_LONG).show()
                },
                onFailure = { error ->
                    Toast.makeText(
                        this,
                        getString(R.string.cc_runtime_install_failed, error.message ?: getString(R.string.status_unknown)),
                        Toast.LENGTH_LONG
                    ).show()
                }
            )
            renderRuntimeControlCenterIfVisible()
        }
    }
}

internal fun MainActivity.showRuntimePackDialog(packId: String) {
    val pack = AgentOnDeviceRuntimeManager(this).status().packs.firstOrNull { it.id == packId } ?: return
    val manifest = pack.manifest
    val message = getString(
        R.string.cc_runtime_pack_details_message,
        manifest?.version.orEmpty().ifBlank { getString(R.string.status_unknown) },
        manifest?.architecture.orEmpty().ifBlank { getString(R.string.status_unknown) },
        formatBytes(manifest?.installedSizeBytes ?: 0L),
        manifest?.license.orEmpty().ifBlank { getString(R.string.status_unknown) }
    )
    AlertDialog.Builder(this)
        .setTitle(runtimePackTitle(packId))
        .setMessage(message)
        .setPositiveButton(R.string.cc_runtime_uninstall) { _, _ -> confirmRuntimePackUninstall(packId) }
        .setNegativeButton(R.string.common_cancel, null)
        .show()
}

internal fun MainActivity.confirmRuntimePackUninstall(packId: String) {
    AlertDialog.Builder(this)
        .setTitle(getString(R.string.cc_runtime_uninstall_title, runtimePackTitle(packId)))
        .setMessage(R.string.cc_runtime_uninstall_message)
        .setPositiveButton(R.string.cc_runtime_uninstall) { _, _ ->
            thread(name = "galaxyssi-runtime-pack-uninstall") {
                val outcome = runCatching { AgentRuntimePackInstaller(this).uninstall(packId) }
                runOnUiThread {
                    Toast.makeText(
                        this,
                        outcome.fold(
                            onSuccess = {
                                if (packId != "linux-base") scheduleRuntimeLifecycleStartup()
                                getString(R.string.cc_runtime_uninstall_success, runtimePackTitle(packId))
                            },
                            onFailure = { getString(R.string.cc_runtime_uninstall_failed, it.message ?: getString(R.string.status_unknown)) }
                        ),
                        Toast.LENGTH_LONG
                    ).show()
                    renderRuntimeControlCenterIfVisible()
                }
            }
        }
        .setNegativeButton(R.string.common_cancel, null)
        .show()
}
