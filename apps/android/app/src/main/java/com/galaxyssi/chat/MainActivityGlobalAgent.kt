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
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) {
        globalSuperAgentRuntime
    } else GlobalSuperAgentRuntime.get(this)
    val settings = runtime.settings()
    val modelBudget = runtime.modelCallBudgetSnapshot()
    val dashboard = runtime.dashboard()
    val continuity = runtime.continuitySnapshot()
    val cognition = runtime.cognitionTasks()
    val research = runtime.researchTasks()
    val runs = runtime.autonomousRuns()
    val discovery = runtime.proactiveDiscoveryState()
    val reasoningResources = GlobalAgentResourceResolver(this).route(
        "Perform background reasoning and research for the user's authorized personal goals.",
        settings.allowPairedAgentCognition,
        settings.allowCloudCognition
    )
    val activeResearch = research.count {
        it.status in setOf(
            GlobalResearchTaskStatus.QUEUED,
            GlobalResearchTaskStatus.RUNNING,
            GlobalResearchTaskStatus.SCHEDULED,
            GlobalResearchTaskStatus.WAITING_FOR_RESOURCE
        )
    }
    val activeCognition = dashboard.queuedCognitionCount
    val activeRuns = dashboard.activeAutonomousRunCount
    val runningResearch = research.count { it.status == GlobalResearchTaskStatus.RUNNING }
    val waitingResearch = research.count { it.status == GlobalResearchTaskStatus.WAITING_FOR_RESOURCE }
    val verifiedResearch = research.count {
        it.status == GlobalResearchTaskStatus.COMPLETED && it.evidenceLedger.verified
    }
    val completedRuns = runs.count {
        it.status in setOf(GlobalAutonomousRunStatus.COMPLETED, GlobalAutonomousRunStatus.PARTIAL)
    }
    val obsidianSettings = ObsidianAndroidBridge.settings(this)
    val obsidianCandidateCount = ObsidianAndroidBridge.pendingCandidates(this).size
    showControlCenterFeature(
        getString(R.string.cc_global_agent_title),
        ControlCenterPageSpec(
            banner = when {
                dashboard.unresolvedConflictCount > 0 -> ControlCenterBannerSpec(
                    title = getString(R.string.cc_global_conflicts_banner, dashboard.unresolvedConflictCount),
                    subtitle = getString(R.string.cc_global_conflicts_banner_subtitle),
                    iconRes = R.drawable.ic_info_outline,
                    tone = ControlCenterTone.AMBER,
                    actionId = "global.world.conflicts"
                )
                reasoningResources.isEmpty() && (activeCognition > 0 || activeResearch > 0) ->
                    ControlCenterBannerSpec(
                        title = getString(R.string.cc_global_resource_needed_title),
                        subtitle = getString(R.string.cc_global_resource_needed_subtitle),
                        iconRes = R.drawable.ic_settings_model,
                        tone = ControlCenterTone.AMBER
                    )
                else -> null
            },
            hero = ControlCenterHeroSpec(
                title = getString(R.string.cc_global_agent_title),
                subtitle = getString(R.string.cc_global_agent_subtitle),
                iconRes = R.drawable.galaxyssi_mark_large,
                preserveIconColor = true,
                badges = listOf(
                    ControlCenterBadgeSpec(
                        getString(if (settings.enabled) R.string.cc_global_understanding_active else R.string.on_device_agent_status_paused),
                        if (settings.enabled) ControlCenterTone.GREEN else ControlCenterTone.AMBER
                    ),
                    ControlCenterBadgeSpec(
                        getString(if (settings.autonomousResearchEnabled) R.string.cc_global_research_active else R.string.common_off),
                        if (settings.autonomousResearchEnabled) ControlCenterTone.BLUE else ControlCenterTone.NEUTRAL
                    )
                ),
                metrics = listOf(
                    ControlCenterMetricSpec(dashboard.topicCount.toString(), getString(R.string.cc_global_metric_topics)),
                    ControlCenterMetricSpec(dashboard.crossConversationLinkCount.toString(), getString(R.string.cc_global_metric_links)),
                    ControlCenterMetricSpec(dashboard.pendingInsightCount.toString(), getString(R.string.cc_global_metric_insights))
                )
            ),
            sections = listOf(
                ControlCenterSectionSpec(
                    getString(R.string.cc_global_section_loop),
                    listOf(
                        ControlCenterRowSpec(
                            "global.world.links",
                            getString(R.string.cc_global_loop_observe_title),
                            getString(R.string.cc_global_loop_observe_subtitle),
                            R.drawable.ic_agent_memory,
                            getString(if (dashboard.pendingEventCount > 0) R.string.cc_global_status_running else R.string.cc_global_status_completed),
                            if (dashboard.pendingEventCount > 0) ControlCenterTone.BLUE else ControlCenterTone.GREEN
                        ),
                        ControlCenterRowSpec(
                            "global.cognition",
                            getString(R.string.cc_global_loop_curiosity_title),
                            getString(R.string.cc_global_loop_curiosity_subtitle),
                            R.drawable.ic_tab_discover,
                            getString(
                                if (discovery.scanLeaseExpiresAtMillis > System.currentTimeMillis()) {
                                    R.string.cc_global_status_running
                                } else if (discovery.lastCompletedAtMillis > 0L) {
                                    R.string.cc_global_status_completed
                                } else R.string.cc_global_status_queued
                            ),
                            if (discovery.lastCompletedAtMillis > 0L) ControlCenterTone.GREEN else ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            "global.research",
                            getString(R.string.cc_global_loop_research_title),
                            getString(R.string.cc_global_loop_research_subtitle),
                            R.drawable.ic_agent_knowledge,
                            getString(
                                when {
                                    runningResearch > 0 -> R.string.cc_global_status_running
                                    waitingResearch > 0 && reasoningResources.isEmpty() -> R.string.cc_global_status_waiting
                                    activeResearch > 0 -> R.string.cc_global_status_queued
                                    else -> R.string.cc_global_status_completed
                                }
                            ),
                            when {
                                runningResearch > 0 -> ControlCenterTone.BLUE
                                waitingResearch > 0 && reasoningResources.isEmpty() -> ControlCenterTone.AMBER
                                else -> ControlCenterTone.GREEN
                            }
                        ),
                        ControlCenterRowSpec(
                            "global.research",
                            getString(R.string.cc_global_loop_verify_title),
                            getString(R.string.cc_global_loop_verify_subtitle),
                            R.drawable.ic_security_shield,
                            verifiedResearch.toString(),
                            if (verifiedResearch > 0) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL
                        ),
                        ControlCenterRowSpec(
                            "global.runs",
                            getString(R.string.cc_global_loop_plan_title),
                            getString(R.string.cc_global_loop_plan_subtitle),
                            R.drawable.ic_agent_history,
                            getString(
                                when {
                                    activeRuns > 0 -> R.string.cc_global_status_running
                                    completedRuns > 0 -> R.string.cc_global_status_completed
                                    else -> R.string.cc_global_status_queued
                                }
                            ),
                            if (activeRuns > 0) ControlCenterTone.VIOLET else ControlCenterTone.NEUTRAL
                        ),
                        ControlCenterRowSpec(
                            "global.insights",
                            getString(R.string.cc_global_loop_notify_title),
                            getString(R.string.cc_global_loop_notify_subtitle),
                            R.drawable.ic_settings_notification,
                            dashboard.pendingInsightCount.toString(),
                            if (dashboard.pendingInsightCount > 0) ControlCenterTone.VIOLET else ControlCenterTone.NEUTRAL
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_global_section_autonomy),
                    listOf(
                        ControlCenterRowSpec("global.toggle_enabled", getString(R.string.cc_global_master_title), getString(R.string.cc_global_master_subtitle), R.drawable.ic_agent_node, switchValue = settings.enabled, showChevron = false),
                        ControlCenterRowSpec("global.toggle_model_understanding", getString(R.string.cc_global_model_understanding_title), getString(R.string.cc_global_model_understanding_subtitle), R.drawable.ic_settings_model, switchValue = settings.modelUnderstandingEnabled, showChevron = false, enabled = settings.enabled),
                        ControlCenterRowSpec("global.toggle_autonomous_preparation", getString(R.string.cc_global_autonomous_preparation_title), getString(R.string.cc_global_autonomous_preparation_subtitle), R.drawable.ic_agent_control, switchValue = settings.autonomousPreparationEnabled, showChevron = false, enabled = settings.enabled),
                        ControlCenterRowSpec("global.toggle_autonomous_tools", getString(R.string.cc_global_autonomous_tools_title), getString(R.string.cc_global_autonomous_tools_subtitle), R.drawable.ic_agent_control, switchValue = settings.autonomousToolExecutionEnabled, showChevron = false, enabled = settings.enabled && settings.autonomousPreparationEnabled),
                        ControlCenterRowSpec("global.toggle_dynamic_replanning", getString(R.string.cc_global_dynamic_replanning_title), getString(R.string.cc_global_dynamic_replanning_subtitle), R.drawable.ic_reset_data, switchValue = settings.dynamicAutonomousReplanningEnabled, showChevron = false, enabled = settings.enabled && settings.autonomousPreparationEnabled),
                        ControlCenterRowSpec("global.toggle_long_horizon", getString(R.string.cc_global_long_horizon_toggle_title), getString(R.string.cc_global_long_horizon_toggle_subtitle), R.drawable.ic_agent_history, switchValue = settings.longHorizonPlanningEnabled, showChevron = false, enabled = settings.enabled),
                        ControlCenterRowSpec("global.toggle_discovery", getString(R.string.cc_global_discovery_title), getString(R.string.cc_global_discovery_subtitle), R.drawable.ic_tab_discover, switchValue = settings.proactiveDiscoveryEnabled, showChevron = false, enabled = settings.enabled && settings.modelUnderstandingEnabled),
                        ControlCenterRowSpec("global.toggle_proactive", getString(R.string.cc_global_proactive_title), getString(R.string.cc_global_proactive_subtitle), R.drawable.ic_agent_memory, switchValue = settings.proactiveInsightsEnabled, showChevron = false, enabled = settings.enabled),
                        ControlCenterRowSpec("global.toggle_learning", getString(R.string.cc_global_learning_toggle_title), getString(R.string.cc_global_learning_toggle_subtitle), R.drawable.ic_agent_skill, switchValue = settings.adaptiveLearningEnabled, showChevron = false, enabled = settings.enabled),
                        ControlCenterRowSpec("global.toggle_research", getString(R.string.cc_global_research_title), getString(R.string.cc_global_research_subtitle), R.drawable.ic_agent_knowledge, switchValue = settings.autonomousResearchEnabled, showChevron = false, enabled = settings.enabled),
                        ControlCenterRowSpec("global.toggle_auto_conversations", getString(R.string.cc_global_topics_title), getString(R.string.cc_global_topics_subtitle), R.drawable.ic_agent_history, switchValue = settings.autoCreateConversationsEnabled, showChevron = false, enabled = settings.enabled),
                        ControlCenterRowSpec("global.toggle_notifications", getString(R.string.cc_global_notifications_title), getString(R.string.cc_global_notifications_subtitle), R.drawable.ic_settings_notification, switchValue = settings.notificationsEnabled, showChevron = false, enabled = settings.enabled)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_global_section_world),
                    listOf(
                        ControlCenterRowSpec("global.world.goals", getString(R.string.cc_global_goals_title), getString(R.string.cc_global_goals_subtitle), R.drawable.ic_agent_node, dashboard.activeGoalCount.toString(), ControlCenterTone.VIOLET),
                        ControlCenterRowSpec("global.world.tasks", getString(R.string.cc_global_tasks_title), getString(R.string.cc_global_tasks_subtitle), R.drawable.ic_agent_history, dashboard.activeTaskCount.toString(), ControlCenterTone.BLUE),
                        ControlCenterRowSpec("global.world.conflicts", getString(R.string.cc_global_conflicts_title), getString(R.string.cc_global_conflicts_subtitle), R.drawable.ic_info_outline, dashboard.unresolvedConflictCount.toString(), if (dashboard.unresolvedConflictCount > 0) ControlCenterTone.AMBER else ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("global.world.links", getString(R.string.cc_global_links_title), getString(R.string.cc_global_links_subtitle), R.drawable.ic_protocol_link, dashboard.crossConversationLinkCount.toString(), ControlCenterTone.GREEN)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_global_section_intelligence),
                    listOf(
                        ControlCenterRowSpec("global.cognition", getString(R.string.cc_global_cognition_queue_title), getString(R.string.cc_global_cognition_queue_subtitle), R.drawable.ic_settings_model, activeCognition.toString(), if (activeCognition > 0) ControlCenterTone.VIOLET else ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("global.runs", getString(R.string.cc_global_runs_title), getString(R.string.cc_global_runs_subtitle), R.drawable.ic_agent_control, (activeRuns + dashboard.waitingConfirmationCount).toString(), if (activeRuns > 0) ControlCenterTone.GREEN else if (dashboard.waitingConfirmationCount > 0) ControlCenterTone.AMBER else ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("global.long_horizon", getString(R.string.cc_global_long_horizon_title), getString(R.string.cc_global_long_horizon_subtitle), R.drawable.ic_agent_history, dashboard.longHorizonGoalCount.toString(), if (dashboard.blockedLongHorizonGoalCount > 0) ControlCenterTone.AMBER else if (dashboard.longHorizonGoalCount > 0) ControlCenterTone.VIOLET else ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("global.research", getString(R.string.cc_global_research_queue_title), getString(R.string.cc_global_research_queue_subtitle), R.drawable.ic_agent_knowledge, activeResearch.toString(), if (activeResearch > 0) ControlCenterTone.BLUE else ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("global.insights", getString(R.string.cc_global_pending_insights_title), getString(R.string.cc_global_pending_insights_subtitle), R.drawable.ic_agent_memory, dashboard.pendingInsightCount.toString(), if (dashboard.pendingInsightCount > 0) ControlCenterTone.VIOLET else ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec("global.learning", getString(R.string.cc_global_learning_title), getString(R.string.cc_global_learning_subtitle), R.drawable.ic_agent_skill, getString(R.string.cc_global_learning_status, dashboard.feedbackCount, dashboard.learnedTopicCount), if (dashboard.feedbackCount > 0) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL),
                        ControlCenterRowSpec(
                            "global.continuity",
                            getString(R.string.cc_global_continuity_title),
                            getString(
                                R.string.cc_global_continuity_subtitle,
                                continuity.pendingEventCount,
                                continuity.retryingEvents.size,
                                continuity.quarantinedEvents.size
                            ),
                            R.drawable.ic_security_shield,
                            getString(
                                when {
                                    continuity.quarantinedEvents.isNotEmpty() -> R.string.cc_global_continuity_attention
                                    continuity.retryingEvents.isNotEmpty() || continuity.pendingEventCount > 0 -> R.string.cc_global_continuity_recovering
                                    else -> R.string.cc_global_continuity_healthy
                                }
                            ),
                            when {
                                continuity.quarantinedEvents.isNotEmpty() -> ControlCenterTone.AMBER
                                continuity.retryingEvents.isNotEmpty() || continuity.pendingEventCount > 0 -> ControlCenterTone.BLUE
                                else -> ControlCenterTone.GREEN
                            }
                        ),
                        ControlCenterRowSpec("global.process_now", getString(R.string.cc_global_process_now_title), getString(R.string.cc_global_process_now_subtitle), R.drawable.ic_reset_data, getString(R.string.cc_global_process_now_action), ControlCenterTone.GREEN, showChevron = false, enabled = settings.enabled)
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_global_section_resources),
                    listOf(
                        ControlCenterRowSpec(
                            "global.daily_model_calls",
                            getString(R.string.cc_global_daily_model_calls_title),
                            getString(R.string.cc_global_daily_model_calls_subtitle),
                            R.drawable.ic_settings_model,
                            getString(
                                R.string.cc_global_daily_model_calls_status,
                                modelBudget.dispatchesInWindow,
                                modelBudget.dailyLimit
                            ),
                            if (modelBudget.dispatchesInWindow >= modelBudget.dailyLimit) ControlCenterTone.AMBER else ControlCenterTone.BLUE
                        ),
                        ControlCenterRowSpec(
                            "global.concurrent_model_calls",
                            getString(R.string.cc_global_concurrent_model_calls_title),
                            getString(R.string.cc_global_concurrent_model_calls_subtitle),
                            R.drawable.ic_agent_history,
                            getString(
                                R.string.cc_global_concurrent_model_calls_status,
                                modelBudget.activeCalls,
                                modelBudget.concurrencyLimit
                            ),
                            if (modelBudget.activeCalls >= modelBudget.concurrencyLimit) ControlCenterTone.AMBER else ControlCenterTone.GREEN
                        ),
                        ControlCenterRowSpec(
                            "global.daily_model_tokens",
                            getString(R.string.cc_global_daily_model_tokens_title),
                            getString(R.string.cc_global_daily_model_tokens_subtitle),
                            R.drawable.ic_protocol_link,
                            getString(
                                R.string.cc_global_daily_model_tokens_status,
                                formatCompactCount(modelBudget.totalTokensInWindow),
                                formatCompactCount(modelBudget.dailyTokenLimit)
                            ),
                            if (modelBudget.totalTokensInWindow >= modelBudget.dailyTokenLimit) ControlCenterTone.AMBER else ControlCenterTone.VIOLET
                        ),
                        ControlCenterRowSpec(
                            "global.daily_reported_cost",
                            getString(R.string.cc_global_daily_reported_cost_title),
                            getString(
                                R.string.cc_global_daily_reported_cost_subtitle,
                                modelBudget.unpricedDispatches
                            ),
                            R.drawable.ic_security_shield,
                            getString(
                                R.string.cc_global_daily_reported_cost_status,
                                formatUsdMicros(modelBudget.reportedCostMicrosInWindow),
                                formatUsdMicros(modelBudget.dailyReportedCostLimitMicros)
                            ),
                            if (modelBudget.dailyReportedCostLimitMicros > 0L &&
                                modelBudget.reportedCostMicrosInWindow >= modelBudget.dailyReportedCostLimitMicros
                            ) ControlCenterTone.AMBER else ControlCenterTone.BLUE
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_obsidian_section),
                    listOf(
                        ControlCenterRowSpec(
                            "obsidian.configure",
                            getString(R.string.cc_obsidian_vault_title),
                            getString(R.string.cc_obsidian_vault_subtitle),
                            R.drawable.ic_agent_knowledge,
                            obsidianSettings.vaultName.ifBlank { getString(R.string.cc_obsidian_not_configured) },
                            if (obsidianSettings.enabled) ControlCenterTone.GREEN else ControlCenterTone.NEUTRAL
                        ),
                        ControlCenterRowSpec(
                            "obsidian.sync",
                            getString(R.string.cc_obsidian_sync_title),
                            getString(R.string.cc_obsidian_sync_subtitle),
                            R.drawable.ic_reset_data,
                            getString(R.string.cc_obsidian_sync_action),
                            ControlCenterTone.BLUE,
                            showChevron = false,
                            enabled = obsidianSettings.enabled
                        ),
                        ControlCenterRowSpec(
                            "obsidian.candidates",
                            getString(R.string.cc_obsidian_candidates_title),
                            getString(R.string.cc_obsidian_candidates_subtitle),
                            R.drawable.ic_info_outline,
                            obsidianCandidateCount.toString(),
                            if (obsidianCandidateCount > 0) ControlCenterTone.AMBER else ControlCenterTone.NEUTRAL,
                            enabled = obsidianSettings.enabled
                        ),
                        ControlCenterRowSpec(
                            "obsidian.disconnect",
                            getString(R.string.cc_obsidian_disconnect_title),
                            getString(R.string.cc_obsidian_disconnect_subtitle),
                            R.drawable.ic_delete,
                            getString(R.string.cc_obsidian_disconnect_action),
                            ControlCenterTone.NEUTRAL,
                            showChevron = false,
                            enabled = obsidianSettings.enabled
                        )
                    )
                ),
                ControlCenterSectionSpec(
                    getString(R.string.cc_global_section_privacy),
                    listOf(
                        ControlCenterRowSpec("global.toggle_paired_cognition", getString(R.string.cc_global_paired_cognition_title), getString(R.string.cc_global_paired_cognition_subtitle), R.drawable.ic_device_node, switchValue = settings.allowPairedAgentCognition, showChevron = false, enabled = settings.enabled && settings.modelUnderstandingEnabled),
                        ControlCenterRowSpec("global.toggle_cloud_cognition", getString(R.string.cc_global_cloud_cognition_title), getString(R.string.cc_global_cloud_cognition_subtitle), R.drawable.ic_security_shield, switchValue = settings.allowCloudCognition, showChevron = false, enabled = settings.enabled && settings.modelUnderstandingEnabled),
                        ControlCenterRowSpec("apps.chat_history", getString(R.string.cc_global_sessions_title), getString(R.string.cc_global_sessions_subtitle), R.drawable.ic_agent_history, "", ControlCenterTone.NEUTRAL)
                    )
                )
            ),
            footer = getString(R.string.cc_global_footer)
        )
    )
}

internal fun MainActivity.updateGlobalAgentSettings(transform: (GlobalAgentSettings) -> GlobalAgentSettings) {
    val runtime = if (isGlobalSuperAgentRuntimeInitialized()) globalSuperAgentRuntime else GlobalSuperAgentRuntime.get(this)
    runtime.updateSettings(transform)
    renderControlCenterGlobalAgentPage()
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
            if (controlCenterDestination?.route == ControlCenterRoute.GLOBAL_AGENT) {
                renderControlCenterGlobalAgentPage()
            }
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
            renderControlCenterGlobalAgentPage()
        }
        .setNegativeButton(R.string.cc_obsidian_reject) { _, _ ->
            if (ObsidianAndroidBridge.rejectCandidate(this, candidate.id)) {
                Toast.makeText(this, R.string.cc_obsidian_candidate_rejected, Toast.LENGTH_SHORT).show()
            }
            renderControlCenterGlobalAgentPage()
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
    val destination = agentTranscriptStore.resolveMergedConversationId(conversationId) ?: return
    agentTranscriptStore.conversation(destination)?.takeIf {
        it.status == AgentConversationStatus.ARCHIVED
    }?.let { agentTranscriptStore.restoreConversation(destination) }
    if (!agentTranscriptStore.switchConversation(destination)) return
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
        agentRoutingExecutor.execute {
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
