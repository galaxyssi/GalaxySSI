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

internal fun MainActivity.scheduleAgentInitialHydration() {
    if (initialAgentHydrationScheduled) return
    initialAgentHydrationScheduled = true
    agentPage.postDelayed({
        thread(name = "signalasi-agent-initial-hydration") {
            val hydrationStartedAt = SystemClock.elapsedRealtime()
            var hydrationCheckpointAt = hydrationStartedAt
            fun traceHydration(stage: String) {
                val now = SystemClock.elapsedRealtime()
                Log.i(
                    "SignalASIStartup",
                    "agent_hydration_stage stage=$stage step=${now - hydrationCheckpointAt}ms " +
                        "total=${now - hydrationStartedAt}ms"
                )
                hydrationCheckpointAt = now
            }
            val outcome = runCatching {
                val initialConversation = agentTranscriptStore.activeConversation()
                traceHydration("active_conversation")
                var initialPage = agentTranscriptStore.page(
                    conversationId = initialConversation.id,
                    pageSize = INITIAL_VISIBLE_AGENT_TRANSCRIPT_ITEMS
                )
                traceHydration("initial_page")
                val supersededKeys = AgentTranscriptLifecyclePolicy
                    .supersededFailureDedupeKeys(initialPage.entries)
                supersededKeys.forEach { dedupeKey ->
                    agentTranscriptStore.deleteByDedupeKey(initialConversation.id, dedupeKey)
                }
                if (supersededKeys.isNotEmpty()) {
                    initialPage = agentTranscriptStore.page(
                        conversationId = initialConversation.id,
                        pageSize = INITIAL_VISIBLE_AGENT_TRANSCRIPT_ITEMS
                    )
                }
                val initialEntries = initialPage.entries
                traceHydration("lifecycle_cleanup")
                val previewPage = initialPage
                runOnUiThread {
                    if (!isFinishing && !isDestroyed && initialAgentHydrationPending) {
                        resetAgentTranscriptRendering(initialConversation.id)
                        agentTranscriptWindow.replace(initialConversation.id, previewPage)
                        agentTranscriptAllLoaded = !previewPage.hasMore
                        renderAgentTranscript(previewPage.entries)
                        refreshAgentConversationHeader(initialConversation)
                    }
                }
                val pendingTaskIds = initialEntries.asSequence()
                    .map(AgentTranscriptEntry::taskId)
                    .filter(String::isNotBlank)
                    .distinct()
                    .filterNot { taskId ->
                        AgentTaskTerminalReplyPolicy.hasTerminalReply(initialEntries, taskId)
                    }
                    .toSet()
                val recoveryRequired = pendingTaskIds.isNotEmpty()
                val state = if (recoveryRequired) {
                    restoreRecoverableAgentRuntime(
                        conversationId = initialConversation.id,
                        transcriptEntries = initialEntries
                    )
                } else {
                    null
                } ?: mobileNativeAgent.snapshot()
                traceHydration("runtime_restore")
                val conversation = agentTranscriptStore.activeConversation()
                val hydratedEntries = if (conversation.id == initialConversation.id) {
                    initialEntries
                } else {
                    agentTranscriptStore.list(conversation.id)
                }
                val tasks = if (recoveryRequired) {
                    SQLiteAgentTaskStore(applicationContext).forSession(conversation.id)
                } else {
                    emptyList()
                }
                traceHydration("task_restore")
                val recoveries = if (tasks.isEmpty()) {
                    emptyList()
                } else {
                    AgentTranscriptLifecyclePolicy.staleConnectorRecoveries(
                        entries = hydratedEntries,
                        tasks = tasks,
                        activeTaskIds = AgentTaskRuntime.supervisor(applicationContext).activeTaskIds(),
                        nowMillis = System.currentTimeMillis()
                    )
                }
                recoveries.forEach { recovery ->
                    val result = recovery.result.ifBlank {
                        applicationContext.getString(R.string.agent_stale_connector_no_result)
                    }
                    agentTranscriptStore.append(
                        role = AgentTranscriptRole.ASSISTANT,
                        text = CodexStyleResponsePolicy.sanitizeAssistantText(result),
                        dedupeKey = "stale-connector:${recovery.taskId}",
                        conversationId = recovery.conversationId,
                        turnId = recovery.turnId,
                        taskId = recovery.taskId
                    )
                }
                traceHydration("stale_recovery")
                val transcriptPage = if (
                    conversation.id == initialConversation.id && recoveries.isEmpty()
                ) {
                    initialPage
                } else {
                    agentTranscriptStore.page(
                        conversationId = conversation.id,
                        pageSize = INITIAL_VISIBLE_AGENT_TRANSCRIPT_ITEMS
                    )
                }
                traceHydration("final_page")
                val insightCount = globalSuperAgentRuntime.newProactiveInsightCount()
                traceHydration("insight_count")
                AgentInitialHydration(state, conversation, transcriptPage, insightCount, tasks)
            }
            runOnUiThread {
                if (isFinishing || isDestroyed) {
                    initialAgentHydrationPending = false
                    initialAgentHydrationReady.countDown()
                    return@runOnUiThread
                }
                outcome.onSuccess { hydration ->
                    hydration.tasks.forEach { task ->
                        rememberAgentExecutionPresentation(
                            task.taskId,
                            AgentExecutionPresentationPolicy.local(
                                routeKind = task.routeKind,
                                targetTitle = task.targetTitle,
                                selectedAgentOrModel = task.targetTitle,
                                phase = task.phase,
                                currentStep = task.executionLog.lastOrNull().orEmpty(),
                                startedAtMillis = task.createdAtMillis,
                                completedAtMillis = task.updatedAtMillis.takeIf {
                                    task.phase in setOf(
                                        AgentPhase.COMPLETED,
                                        AgentPhase.FAILED,
                                        AgentPhase.CANCELLED,
                                        AgentPhase.BLOCKED
                                    )
                                } ?: 0L,
                                resolvedLocation =
                                    AgentExecutionPresentationPolicy.location(task)
                            )
                        )
                    }
                    if (agentTranscriptWindow.conversationId != hydration.conversation.id) {
                        resetAgentTranscriptRendering(hydration.conversation.id)
                    }
                    agentTranscriptWindow.replace(
                        hydration.conversation.id,
                        hydration.transcriptPage
                    )
                    agentTranscriptAllLoaded = !hydration.transcriptPage.hasMore
                    renderAgentTranscript(hydration.transcriptPage.entries)
                    val restoredTurnId = hydration.transcriptPage.entries.asReversed().firstOrNull { entry ->
                        entry.taskId == hydration.state.sessionId && entry.turnId.isNotBlank()
                    }?.turnId.orEmpty()
                    renderAgentState(
                        hydration.state,
                        conversationId = hydration.conversation.id,
                        turnId = restoredTurnId,
                        syncTranscript = false,
                        activeConversationId = hydration.conversation.id
                    )
                    refreshAgentConversationHeader(hydration.conversation)
                    refreshGlobalInsightIndicator(hydration.insightCount)
                    Log.i(
                        "SignalASIStartup",
                        "agent_hydration total=${SystemClock.elapsedRealtime() - hydrationStartedAt}ms entries=${hydration.transcriptPage.entries.size} visible=${renderedAgentTranscriptIds.size}"
                    )
                }.onFailure { error ->
                    Log.w("SignalASIStartup", "Initial Agent hydration failed", error)
                }
                initialAgentHydrationPending = false
                initialAgentHydrationReady.countDown()
                consumePendingAgentConnectorResponsesAsync()
                scheduleAgentSkillBootstrap()
            }
        }
    }, 100L)
}

internal fun MainActivity.restoreRecoverableAgentRuntime(
    conversationId: String,
    transcriptEntries: List<AgentTranscriptEntry>
): AgentUiState? {
    val resolvedConversationId = agentTranscriptStore.resolveMergedConversationId(conversationId)
        ?: conversationId
    val workspaceStore = EncryptedAgentWorkspaceStore(this)
    val allWorkspaces = workspaceStore.recoverable(AgentWorkspaceLimits.MAX_RECOVERY_CANDIDATES)
    val activeSupervisorTaskIds = AgentTaskRuntime.supervisor(this).activeTaskIds()
    val hasActiveSupervisorTaskInConversation = allWorkspaces.any { workspace ->
        workspace.workspaceId in activeSupervisorTaskIds &&
            (agentTranscriptStore.resolveMergedConversationId(workspace.conversationId)
                ?: workspace.conversationId) == resolvedConversationId
    }
    val liveRuntimes = buildSet {
        addAll(provisionalAgentTasks)
        addAll(activeAgentTasks.values)
        if (isMobileNativeAgentInitialized()) add(mobileNativeAgent)
    }
    val hasLiveRuntimeInConversation = liveRuntimes.any { runtime ->
        val runtimeConversationId = agentRuntimeConversationIds[runtime]
            ?.let { agentTranscriptStore.resolveMergedConversationId(it) ?: it }
            .orEmpty()
        runtimeConversationId == resolvedConversationId && runtime.snapshot().runningTaskCount > 0
    }
    if (!AgentWorkspaceRestoreArbitrationPolicy.shouldScanPersistedWorkspaces(
            hasLiveRuntimeInConversation = hasLiveRuntimeInConversation,
            hasActiveSupervisorTaskInConversation = hasActiveSupervisorTaskInConversation
        )
    ) {
        Log.i(
            "SignalASIAgentLifecycle",
            "skipping persisted workspace restore for active conversation=" +
                "${resolvedConversationId.take(8)} live_runtime=$hasLiveRuntimeInConversation " +
                "supervisor_task=$hasActiveSupervisorTaskInConversation"
        )
        return null
    }
    val latestConversationTurnId = transcriptEntries.asReversed().firstOrNull { entry ->
        entry.role == AgentTranscriptRole.USER && entry.turnId.isNotBlank()
    }?.turnId.orEmpty()
    val workspaces = AgentWorkspaceRestoreCandidatePolicy.ordered(allWorkspaces.filter { candidate ->
        val candidateConversationId = agentTranscriptStore
            .resolveMergedConversationId(candidate.conversationId)
            ?: candidate.conversationId
        AgentWorkspaceRestoreArbitrationPolicy.belongsToActiveConversation(
            candidateConversationId,
            resolvedConversationId
        ) &&
            candidate.status in setOf(
                AgentWorkspaceStatus.RUNNING,
                AgentWorkspaceStatus.WAITING_CONFIRMATION,
                AgentWorkspaceStatus.WAITING_RESPONSE,
                AgentWorkspaceStatus.PAUSED,
                AgentWorkspaceStatus.BLOCKED,
                AgentWorkspaceStatus.FAILED
            )
    }, preferredWorkspaceId = latestConversationTurnId)
    fun recoveryStillOwnsForeground(candidateWorkspaceId: String): Boolean {
        val currentConversationId = runCatching { agentTranscriptStore.activeConversation().id }
            .getOrDefault("")
            .let { agentTranscriptStore.resolveMergedConversationId(it) ?: it }
        val liveRuntimeWorkspaceIds = buildSet {
            provisionalAgentTasks.forEach { runtime ->
                if (runtime.snapshot().runningTaskCount > 0) {
                    agentRuntimeTurnIds[runtime]?.takeIf(String::isNotBlank)?.let(::add)
                }
            }
            activeAgentTasks.values.forEach { runtime ->
                if (runtime.snapshot().runningTaskCount > 0) {
                    agentRuntimeTurnIds[runtime]?.takeIf(String::isNotBlank)?.let(::add)
                }
            }
        }
        return AgentWorkspaceRestoreArbitrationPolicy.stillOwnsRecovery(
            candidateWorkspaceId = candidateWorkspaceId,
            startedConversationId = resolvedConversationId,
            currentConversationId = currentConversationId,
            activeSupervisorWorkspaceIds = AgentTaskRuntime.supervisor(this).activeTaskIds(),
            liveRuntimeWorkspaceIds = liveRuntimeWorkspaceIds
        )
    }
    workspaces.forEach { workspace ->
        if (!recoveryStillOwnsForeground(workspace.workspaceId)) {
            Log.i(
                "SignalASIAgentLifecycle",
                "abandoning stale workspace restore=${workspace.workspaceId.take(8)} before hydration"
            )
            return null
        }
        val candidateConversationId = agentTranscriptStore
            .resolveMergedConversationId(workspace.conversationId)
            ?: workspace.conversationId
        val candidateEntries = if (candidateConversationId == resolvedConversationId) {
            transcriptEntries
        } else {
            agentTranscriptStore.list(candidateConversationId)
        }
        if (AgentTaskTerminalReplyPolicy.hasTerminalReply(candidateEntries, workspace.taskId)) {
            return@forEach
        }
        val candidateStartedAt = SystemClock.elapsedRealtime()
        val runtime = MobileNativeAgent(
            this,
            actionExecutor = directAgentActionExecutor,
            sessionStore = SharedPreferencesAgentSessionStore(this, "task:${workspace.workspaceId}"),
            nativeToolEventSink = AgentNativeToolEventSink(::recordNativeToolLifecycleEvent)
        )
        var state = runtime.snapshot()
        Log.i(
            "SignalASIAgentLifecycle",
            "hydrated workspace=${workspace.workspaceId.take(8)} status=${workspace.status.name} " +
                "elapsed_ms=${SystemClock.elapsedRealtime() - candidateStartedAt}"
        )
        val interruptedRecovery = AgentInterruptedWorkspaceRecoveryPolicy.shouldResume(
            workspace.status,
            state.phase,
            state.plan,
            state.lastActionResult
        )
        val interruptedHandoffRecovery =
            AgentPendingHandoffRecoveryPolicy.interruptedRecoveryAction(state.phase, state.plan) != null
        val failedDeliveryRecovery = AgentConnectorDeliveryRecoveryPolicy.shouldResume(
            workspaceStatus = workspace.status,
            phase = state.phase,
            lastActionResult = state.lastActionResult,
            plan = state.plan
        )
        val belongsToCurrentConversation = candidateConversationId == resolvedConversationId
        val recoverable = AgentWorkspaceRestorePolicy.shouldRestore(
            workspaceStatus = workspace.status,
            phase = state.phase,
            belongsToCurrentConversation = belongsToCurrentConversation,
            hasPendingAction = state.pendingAction != null,
            interruptedRecovery = interruptedRecovery,
            interruptedHandoffRecovery = interruptedHandoffRecovery,
            failedDeliveryRecovery = failedDeliveryRecovery
        )
        if (!recoverable) return@forEach
        if (!recoveryStillOwnsForeground(workspace.workspaceId)) {
            Log.i(
                "SignalASIAgentLifecycle",
                "abandoning stale workspace restore=${workspace.workspaceId.take(8)} before recovery"
            )
            return null
        }
        val failedWaitingWorkspaceRecovery = workspace.status == AgentWorkspaceStatus.FAILED &&
            state.phase == AgentPhase.WAITING_RESPONSE
        if (failedWaitingWorkspaceRecovery) {
            runCatching {
                AgentTaskRuntime.supervisor(this).reopenInterruptedWorkspace(
                    workspace.workspaceId,
                    "A durable connector handoff is still waiting and must be reconciled"
                )
            }.onFailure { error ->
                Log.w(
                    "SignalASIAgentLifecycle",
                    "failed to reopen waiting workspace=${workspace.workspaceId.take(8)}",
                    error
                )
                return@forEach
            }
        }
        if (interruptedRecovery) {
            if (!recoveryStillOwnsForeground(workspace.workspaceId)) return null
            if (workspace.status == AgentWorkspaceStatus.FAILED && !failedWaitingWorkspaceRecovery) {
                runCatching {
                    AgentTaskRuntime.supervisor(this).reopenInterruptedWorkspace(
                        workspace.workspaceId
                    )
                }.onFailure { error ->
                    Log.w(
                        "SignalASIAgentLifecycle",
                        "failed to reopen interrupted workspace=${workspace.workspaceId.take(8)}",
                        error
                    )
                    return@forEach
                }
            }
            Log.i(
                "SignalASIAgentLifecycle",
                "resuming interrupted workspace=${workspace.workspaceId.take(8)} from durable evidence"
            )
            state = runCatching(runtime::resumeCurrentTask).getOrElse { error ->
                Log.w(
                    "SignalASIAgentLifecycle",
                    "failed to resume interrupted workspace=${workspace.workspaceId.take(8)}",
                    error
                )
                runtime.snapshot()
            }
        }
        if (interruptedHandoffRecovery) {
            if (!recoveryStillOwnsForeground(workspace.workspaceId)) return null
            Log.w(
                "SignalASIAgentLifecycle",
                "resuming interrupted connector recovery workspace=${workspace.workspaceId.take(8)}"
            )
            state = runCatching(runtime::resumeInterruptedConnectorHandoffRecovery).getOrElse { error ->
                Log.w(
                    "SignalASIAgentLifecycle",
                    "failed to resume connector recovery workspace=${workspace.workspaceId.take(8)}",
                    error
                )
                null
            } ?: runtime.snapshot()
            persistAgentWorkspaceSnapshot(
                workspace.workspaceId,
                state,
                runtime,
                interruptedRecoveryReason = "Interrupted connector recovery resumed from durable state"
            )
        }
        if (failedDeliveryRecovery) {
            if (!recoveryStillOwnsForeground(workspace.workspaceId)) return null
            runCatching {
                AgentTaskRuntime.supervisor(this).reopenInterruptedWorkspace(
                    workspace.workspaceId,
                    "A connector delivery failure is being observed and replanned"
                )
            }.onFailure { error ->
                Log.w(
                    "SignalASIAgentLifecycle",
                    "failed to reopen delivery failure workspace=${workspace.workspaceId.take(8)}",
                    error
                )
                return@forEach
            }
            Log.w(
                "SignalASIAgentLifecycle",
                "resuming connector delivery recovery workspace=${workspace.workspaceId.take(8)}"
            )
            state = runCatching(runtime::resumeFailedConnectorDeliveryRecovery).getOrElse { error ->
                Log.w(
                    "SignalASIAgentLifecycle",
                    "failed to replan delivery failure workspace=${workspace.workspaceId.take(8)}",
                    error
                )
                null
            } ?: runtime.snapshot()
            persistAgentWorkspaceSnapshot(
                workspace.workspaceId,
                state,
                runtime,
                interruptedRecoveryReason = "Connector delivery recovery resumed from durable state"
            )
        }
        val waitingSourceMessageId = state.lastActionResult?.metadata
            ?.get("source_message_id")
            ?.toLongOrNull()
            ?.takeIf { it > 0L }
        if (waitingSourceMessageId != null && state.phase == AgentPhase.WAITING_RESPONSE) {
            if (!recoveryStillOwnsForeground(workspace.workspaceId)) return null
            val waitingMetadata = state.lastActionResult?.metadata.orEmpty()
            val remainsInReliableOutbox = SignalASILinkDeliveryStore.hasPendingClientSourceMessageId(
                this,
                waitingSourceMessageId
            )
            val durableResponseAlreadyArrived = AgentConnectorResponseStore.pending(this).any { response ->
                response.conversationId == candidateConversationId &&
                    response.turnId == workspace.workspaceId
            }
            val recoveryDeadline = AgentConnectorTimingPolicy
                .deadlines(waitingMetadata["has_attachments"] == "true")
                .runningMs
            Log.i(
                "SignalASIAgentLifecycle",
                "handoff recovery audit source=$waitingSourceMessageId " +
                    "outbox=$remainsInReliableOutbox " +
                    "remote_status=${waitingMetadata["remote_task_status"].orEmpty().ifBlank { "none" }} " +
                    "attempt=${AgentPendingHandoffRecoveryPolicy.recoveryAttempt(waitingMetadata)}"
            )
            if (!durableResponseAlreadyArrived && AgentPendingHandoffRecoveryPolicy.shouldRecover(
                    phase = state.phase,
                    sourceMessageId = waitingSourceMessageId,
                    remainsInReliableOutbox = remainsInReliableOutbox,
                    metadata = waitingMetadata,
                    staleAfterMillis = recoveryDeadline
                )
            ) {
                Log.w(
                    "SignalASIAgentLifecycle",
                    "recovering stranded connector source=$waitingSourceMessageId " +
                        "workspace=${workspace.workspaceId.take(8)}"
                )
                state = runtime.recoverStrandedConnectorHandoff(
                    waitingSourceMessageId,
                    "The previous connector handoff was not accepted; dispatching it again"
                ) ?: runtime.snapshot()
                state.lastActionResult?.metadata
                    ?.get("source_message_id")
                    ?.toLongOrNull()
                    ?.takeIf { it > 0L && it != waitingSourceMessageId }
                    ?.let { replacementSourceMessageId ->
                        AgentPendingDeliveryStore.markRecoveryPredecessor(
                            this,
                            waitingSourceMessageId,
                            replacementSourceMessageId
                        )
                    }
                persistAgentWorkspaceSnapshot(
                    workspace.workspaceId,
                    state,
                    runtime,
                    interruptedRecoveryReason = "Stranded connector handoff was recovered from durable state"
                )
            } else if (AgentPendingHandoffRecoveryPolicy.isExhausted(
                    phase = state.phase,
                    sourceMessageId = waitingSourceMessageId,
                    remainsInReliableOutbox = remainsInReliableOutbox,
                    metadata = waitingMetadata,
                    staleAfterMillis = recoveryDeadline
                )
            ) {
                Log.e(
                    "SignalASIAgentLifecycle",
                    "connector recovery exhausted source=$waitingSourceMessageId " +
                        "workspace=${workspace.workspaceId.take(8)}"
                )
                state = runtime.handleConnectorDeliveryFailure(
                    waitingSourceMessageId,
                    "The task could not reach the selected model after automatic recovery"
                ) ?: runtime.snapshot()
                AgentPendingDeliveryStore.remove(this, waitingSourceMessageId)
                persistAgentWorkspaceSnapshot(
                    workspace.workspaceId,
                    state,
                    runtime,
                    interruptedRecoveryReason = "Connector recovery exhaustion was reconciled from durable state"
                )
            }
        }
        if (!recoveryStillOwnsForeground(workspace.workspaceId)) {
            Log.i(
                "SignalASIAgentLifecycle",
                "abandoning stale workspace restore=${workspace.workspaceId.take(8)} before binding"
            )
            return null
        }
        mobileNativeAgent = runtime
        agentRuntimeConversationIds[runtime] = candidateConversationId
        agentRuntimeTurnIds[runtime] = workspace.workspaceId
        if (interruptedRecovery) {
            // resumeCurrentTask() may create a replacement connector handoff. Persist the
            // new source and WAITING_RESPONSE state before a reply or watchdog event arrives.
            persistAgentWorkspaceSnapshot(
                workspace.workspaceId,
                state,
                runtime,
                interruptedRecoveryReason = "Interrupted execution resumed from durable state"
            )
        }
        state.lastActionResult?.metadata
            ?.get("source_message_id")
            ?.toLongOrNull()
            ?.takeIf { it > 0L }
            ?.let { sourceMessageId ->
                activeAgentTasks[sourceMessageId] = runtime
                if (state.phase == AgentPhase.WAITING_RESPONSE) {
                    AgentPendingDeliveryStore.put(
                        this,
                        AgentPendingDelivery(
                            sourceMessageId = sourceMessageId,
                            conversationId = candidateConversationId,
                            turnId = workspace.workspaceId,
                            taskId = state.lastActionResult?.metadata?.get("remote_task_id").orEmpty()
                                .ifBlank { workspace.workspaceId },
                            contactId = state.lastActionResult?.metadata?.get("contact_id").orEmpty()
                        )
                    )
                    scheduleConnectorTimeouts(
                        runtime = runtime,
                        sourceMessageId = sourceMessageId,
                        conversationId = candidateConversationId,
                        turnId = workspace.workspaceId
                    )
                    consumePendingAgentConnectorResponsesAsync()
                }
            }
        Log.i(
            "SignalASIAgentLifecycle",
            "restored active workspace=${workspace.workspaceId.take(8)} phase=${state.phase.name}"
        )
        return state
    }
    return null
}

internal fun MainActivity.scheduleAgentSkillBootstrap() {
    val runtime = agentSkillRuntime
    thread(name = "signalasi-skill-bootstrap") {
        runCatching { AgentBuiltInSkills.synchronizeIfNeeded(applicationContext, runtime) }
    }
}

internal fun MainActivity.scheduleAgentStartupMaintenance() {
    handler.removeCallbacks(agentStartupMaintenanceRunnable)
    handler.postDelayed(
        agentStartupMaintenanceRunnable,
        AGENT_STARTUP_MAINTENANCE_DELAY_MILLIS
    )
}

internal fun MainActivity.scheduleNavigationContentPrewarm() {
    handler.postDelayed({
        navigationContentExecutor.execute {
            val page = runCatching(::buildControlCenterHomePage).getOrNull() ?: return@execute
            handler.post {
                if (!isFinishing && !isDestroyed && activeMainTab != PAGE_SETTINGS) {
                    renderControlCenterHomePage(page)
                }
            }
        }
    }, NAVIGATION_CONTENT_PREWARM_DELAY_MILLIS)
}

internal fun MainActivity.startMessageService() {
    val intent = Intent(this, MessageService::class.java)
    runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }.onFailure { error ->
        Log.w("SignalASIStartup", "Message service start was deferred", error)
    }
}

internal fun MainActivity.requestAgentNotificationPermissionIfNeeded() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
        checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
    ) {
        requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_AGENT_NOTIFICATIONS
        )
    }
}

internal fun MainActivity.configureSystemBars() {
    window.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
    window.statusBarColor = getColorCompat(R.color.bar_bg)
    window.navigationBarColor = getColorCompat(R.color.bar_bg)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        val isNight = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        var flags = if (isNight) 0 else View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        if (!isNight && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            flags = flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
        window.decorView.systemUiVisibility = flags
    }
}

internal fun MainActivity.applyDeviceProfileWindowPolicy() {
    requestedOrientation = when (deviceProfile.kind) {
        AgentDeviceProfileKind.TABLET,
        AgentDeviceProfileKind.AUTOMOTIVE,
        AgentDeviceProfileKind.LEGACY_SAMSUNG_TABLET ->
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        AgentDeviceProfileKind.PHONE,
        AgentDeviceProfileKind.LEGACY_SAMSUNG_PHONE ->
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }
    if (deviceProfile.reduceMotion) {
        val attributes = window.attributes
        attributes.windowAnimations = 0
        window.attributes = attributes
    }
    Log.i(
        "SignalASIDeviceProfile",
        "profile=${deviceProfile.id} read=${deviceProfile.maxReadReasoningTasks} " +
            "team=${deviceProfile.maxTeamConcurrency} qemuCpu=${deviceProfile.maxQemuCpuCount}"
    )
}

internal fun MainActivity.applyDeviceProfileInputTargets() {
    val targetPx = dp(deviceProfile.minimumTouchTargetDp)
    listOf(
        agentGoalInput,
        agentAttachButton,
        agentSubmitButton,
        imageButton,
        sendButton
    ).forEach { view ->
        view.minimumWidth = targetPx
        view.minimumHeight = targetPx
        val params = view.layoutParams
        if (params.width in 1 until targetPx) params.width = targetPx
        if (params.height in 1 until targetPx) params.height = targetPx
        view.layoutParams = params
    }
}

internal fun MainActivity.maintainMcpCredentials() {
    if (!isAgentMcpRegistryInitialized()) return
    val due = agentMcpRegistry.list().filter {
        it.enabled && it.authProfile.refreshExchange != null &&
            it.effectiveAuthState(System.currentTimeMillis()) == AgentMcpAuthState.REFRESHING
    }
    if (due.isEmpty()) return
    thread(name = "signalasi-mcp-maintenance") {
        val coordinator = AgentMcpAuthenticationCoordinator(agentMcpRegistry)
        due.forEach { connection -> runCatching { runBlocking { coordinator.refreshIfNeeded(connection.id) } } }
        runOnUiThread {
            if (controlCenterDestination?.route == ControlCenterRoute.MCP) {
                renderCurrentControlCenterDestination()
            }
        }
    }
}
