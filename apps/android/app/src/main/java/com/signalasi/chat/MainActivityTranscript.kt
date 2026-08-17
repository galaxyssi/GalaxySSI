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

internal fun MainActivity.renderAgentState(
    state: AgentUiState,
    conversationId: String = agentTranscriptStore.activeConversation().id,
    turnId: String = "",
    syncTranscript: Boolean = true,
    activeConversationId: String? = null
) {
    if (turnId.isNotBlank()) recordRunControlProgress(state, turnId)
    val currentConversationId = activeConversationId ?: agentTranscriptStore.activeConversation().id
    val transcriptTurnId = AgentFinalResponseIdentity.resolveTurnId(
        explicitTurnId = turnId,
        taskId = state.sessionId,
        turnIdForTask = agentTranscriptStore::turnIdForTask
    )
    val replyIndicatorRemoved = transcriptTurnId.isNotBlank() &&
        AgentReplyWaitingIndicatorPolicy.stopsFor(state.phase) &&
        pendingAgentReplyIndicators.remove(transcriptTurnId) != null
    if (conversationId != currentConversationId) {
        if (syncTranscript) syncAgentTranscript(state, conversationId, turnId)
        return
    }
    agentRenderedConversationId = conversationId
    if (state == lastRenderedAgentState) {
        if (syncTranscript) renderAgentOutput(state, conversationId, turnId)
        updateAgentSubmitButtonAppearance(
            agentGoalInput.text?.toString()?.isNotBlank() == true || agentInputAttachments.isNotEmpty()
        )
        if (replyIndicatorRemoved) refreshAgentTranscriptWindow(conversationId)
        return
    }
    lastRenderedAgentState = state
    val pendingAction = state.pendingAction
    if (syncTranscript) renderAgentOutput(state, conversationId, turnId)
    val safetySettings = mobileNativeAgent.safetySettings()
    agentMemoryCaptureButton.text = getString(
        R.string.agent_safety_memory_capture_value,
        onOffLabel(safetySettings.memoryCapture)
    )
    agentMemoryCaptureButton.setTextColor(
        if (safetySettings.memoryCapture) getColorCompat(R.color.wechat_green) else getColorCompat(R.color.text_secondary)
    )
    agentRecordingInstruction.text = if (agentVoiceListening) {
        getString(R.string.agent_voice_listening)
    } else {
        getString(R.string.agent_voice_recording_hint)
    }
    agentSubmitButton.isEnabled = true
    agentSubmitButton.alpha = 1f
    latestAgentScreenContext = state.currentScreen
    updateAgentSubmitButtonAppearance(
        agentGoalInput.text?.toString()?.isNotBlank() == true || agentInputAttachments.isNotEmpty()
    )
}

internal fun MainActivity.recordRunControlProgress(state: AgentUiState, turnId: String) {
    val runId = agentRunIdsByTurn[turnId] ?: return
    val run = agentRunRecorder.run(runId) ?: return
    val action = state.pendingAction ?: state.plan?.actions?.lastOrNull { candidate ->
        candidate.status == AgentActionStatus.RUNNING ||
            candidate.status == AgentActionStatus.WAITING_RESPONSE
    }
    if (state.phase == AgentPhase.WAITING_RESPONSE && action?.kind == AgentActionKind.CALL_CONNECTOR) {
        recordStructuredAgentHandoff(state, turnId, run, action)
    }
    val eventType = when (state.phase) {
        AgentPhase.OBSERVING -> AgentRunControlEventType.STEP_STARTED
        AgentPhase.PLANNING -> AgentRunControlEventType.PLANNING
        AgentPhase.WAITING_CONFIRMATION -> AgentRunControlEventType.WAITING_FOR_USER
        AgentPhase.EXECUTING -> if (action?.isSupervisedProjectConnector() == true) {
            AgentRunControlEventType.PLANNING
        } else if (action != null) {
            AgentRunControlEventType.TOOL_STARTED
        } else {
            AgentRunControlEventType.STEP_STARTED
        }
        AgentPhase.VERIFYING -> AgentRunControlEventType.TOOL_PROGRESS
        AgentPhase.WAITING_RESPONSE -> AgentRunControlEventType.WAITING_FOR_DEVICE
        AgentPhase.PAUSED -> AgentRunControlEventType.PAUSED
        AgentPhase.CANCELLED,
        AgentPhase.BLOCKED,
        AgentPhase.FAILED,
        AgentPhase.COMPLETED -> return
    }
    val stepId = action?.id.orEmpty().ifBlank { state.steps.firstOrNull { it.status == AgentStepStatus.CURRENT }?.kind?.name.orEmpty() }
    val toolCallId = action?.takeIf {
        it.kind == AgentActionKind.CALL_NATIVE_TOOL || it.kind == AgentActionKind.CALL_CONNECTOR
    }?.id.orEmpty()
    val latest = agentRunEventStore.latestEvent(runId)
    if (latest?.type == eventType && latest.stepId == stepId && latest.toolCallId == toolCallId) return
    val agentId = state.plan?.route?.targetId.orEmpty()
        .ifBlank { state.plan?.selectedAgentOrModel.orEmpty() }
        .ifBlank { "signalasi-mobile" }
    val execution = AgentExecutionPresentationPolicy.location(state.plan?.route, action)
    appendRunControlEvent(
        run = run,
        messageId = turnId,
        taskId = turnId,
        agentId = agentId,
        type = eventType,
        payload = mapOf(
            "phase" to state.phase.name.lowercase(Locale.ROOT),
            "action_kind" to action?.kind?.name.orEmpty().lowercase(Locale.ROOT),
            "delivery_mode" to state.plan?.route?.deliveryMode.orEmpty(),
            "execution_contract" to execution.contract,
            "execution_location_kind" to execution.locationKind.name.lowercase(Locale.ROOT),
            "execution_runtime_kind" to execution.runtimeKind.name.lowercase(Locale.ROOT),
            "execution_location_id" to execution.locationId,
            "execution_location_name" to execution.locationName,
            "execution_runtime_id" to execution.runtimeId,
            "planning_only" to (action?.isSupervisedProjectConnector() == true).toString()
        ),
        stepId = stepId,
        toolCallId = toolCallId
    )
}

internal fun MainActivity.recordStructuredAgentHandoff(
    state: AgentUiState,
    turnId: String,
    run: AgentRecordedRun,
    action: AgentAction
) {
    if (!isAgentHandoffStoreInitialized()) return
    val route = state.plan?.route
    val fromAgentId = "signalasi-mobile"
    val toAgentId = route?.targetId.orEmpty()
        .ifBlank { action.parameters["connector_id"].orEmpty() }
        .ifBlank { action.target }
    if (toAgentId.isBlank() || toAgentId == fromAgentId) return
    val sourceMessageId = state.lastActionResult?.metadata
        ?.get("source_message_id")?.toLongOrNull()?.coerceAtLeast(0L) ?: 0L
    val execution = AgentExecutionPresentationPolicy.location(route, action)
    val handoffId = AgentHandoffLifecycle.stableId(run.runId, action.id, fromAgentId, toAgentId)
    val mutation = agentHandoffStore.beginActive(
        AgentHandoffRequest(
            handoffId = handoffId,
            conversationId = run.conversationId,
            taskId = turnId,
            runId = run.runId,
            fromAgentId = fromAgentId,
            toAgentId = toAgentId,
            returnToAgentId = fromAgentId,
            reason = state.plan?.routeRationale.orEmpty().ifBlank { action.description },
            deliveryMode = when (route?.deliveryMode.orEmpty().lowercase(Locale.ROOT)) {
                "observe", "inject", "context" -> AgentDeliveryMode.OBSERVE
                "ignore", "none", "skip" -> AgentDeliveryMode.IGNORE
                else -> AgentDeliveryMode.RESPOND
            },
            requiredCapabilities = route?.capabilities.orEmpty().toSet(),
            artifactIds = action.outputSourceIds(),
            checkpoint = mapOf(
                "source_message_id" to sourceMessageId,
                "last_event_sequence" to (agentRunEventStore.latestEvent(run.runId)?.sequence ?: 0L)
            ),
            context = mapOf(
                "turn_id" to turnId,
                "step_id" to action.id,
                "route_kind" to route?.kind?.name.orEmpty(),
                "delivery_mode" to route?.deliveryMode.orEmpty(),
                "execution_contract" to execution.contract,
                "execution_location_kind" to execution.locationKind.name.lowercase(Locale.ROOT),
                "execution_runtime_kind" to execution.runtimeKind.name.lowercase(Locale.ROOT),
                "execution_location_id" to execution.locationId,
                "execution_location_name" to execution.locationName
            )
        ),
        sourceMessageId = sourceMessageId
    )
    if (!mutation.created) return
    appendRunControlEvent(
        run = run,
        messageId = turnId,
        taskId = turnId,
        agentId = toAgentId,
        type = AgentRunControlEventType.HANDOFF,
        payload = mapOf(
            "handoff_id" to handoffId,
            "from_agent_id" to fromAgentId,
            "to_agent_id" to toAgentId,
            "return_to_agent_id" to fromAgentId,
            "reason" to mutation.record.request.reason,
            "delivery_mode" to mutation.record.request.deliveryMode.name.lowercase(Locale.ROOT),
            "source_message_id" to sourceMessageId,
            "artifact_ids" to mutation.record.request.artifactIds,
            "execution_contract" to execution.contract,
            "execution_location_kind" to execution.locationKind.name.lowercase(Locale.ROOT),
            "execution_runtime_kind" to execution.runtimeKind.name.lowercase(Locale.ROOT),
            "execution_location_id" to execution.locationId,
            "execution_location_name" to execution.locationName
        ),
        stepId = action.id,
        toolCallId = action.id
    )
}

internal fun MainActivity.finishStructuredAgentHandoff(turnId: String, response: AgentConnectorResponse) {
    if (!isAgentHandoffStoreInitialized()) return
    val runId = agentRunIdsByTurn[turnId] ?: return
    val run = agentRunRecorder.run(runId) ?: return
    val state = if (response.success) AgentHandoffState.RETURNED else AgentHandoffState.FAILED
    val record = agentHandoffStore.finish(
        runId = runId,
        sourceMessageId = response.sourceMessageId,
        state = state,
        resultSummary = response.content
    ) ?: return
    appendRunControlEvent(
        run = run,
        messageId = turnId,
        taskId = turnId,
        agentId = record.request.toAgentId,
        type = AgentRunControlEventType.STEP_COMPLETED,
        payload = mapOf(
            "handoff_id" to record.request.handoffId,
            "handoff_state" to record.state.name.lowercase(Locale.ROOT),
            "from_agent_id" to record.request.toAgentId,
            "to_agent_id" to record.request.returnToAgentId,
            "source_message_id" to response.sourceMessageId,
            "success" to response.success
        ),
        stepId = record.request.context["step_id"]?.toString().orEmpty(),
        toolCallId = record.request.context["step_id"]?.toString().orEmpty()
    )
}

internal fun MainActivity.renderAgentOutput(state: AgentUiState, conversationId: String, turnId: String) {
    syncAgentTranscript(state, conversationId, turnId)
    if (conversationId == agentTranscriptStore.activeConversation().id) {
        refreshAgentConversationHeader()
        refreshAgentTranscriptWindow(conversationId)
    }
}

internal fun MainActivity.syncAgentTranscript(state: AgentUiState, conversationId: String, turnId: String) {
    val transcriptTurnId = AgentFinalResponseIdentity.resolveTurnId(
        explicitTurnId = turnId,
        taskId = state.sessionId,
        turnIdForTask = agentTranscriptStore::turnIdForTask
    )
    state.plan?.selectedAgentOrModel?.takeIf { it.isNotBlank() }?.let {
        agentTranscriptStore.setSelectedModelOrAgent(conversationId, agentTraceTargetLabel(it))
    }
    val planId = state.plan?.planId.orEmpty().ifBlank {
        "${state.sessionId}:${state.currentGoal.hashCode()}"
    }
    state.auditTrail.forEach { entry ->
        val line = agentExecutionLine(state, entry) ?: return@forEach
        agentTranscriptStore.append(
            AgentTranscriptRole.PROCESS,
            line,
            dedupeKey = "audit:${entry.timestampMillis}:${entry.event.name}:${entry.detail.hashCode()}",
            timestampMillis = entry.timestampMillis,
            conversationId = conversationId,
            turnId = transcriptTurnId,
            taskId = state.sessionId
        )
    }
    state.pendingAction?.let { pending ->
        val description = pending.description.trim()
        val processDescription = localizedAgentProcessText(description)
        if (state.phase == AgentPhase.WAITING_CONFIRMATION &&
            description.isNotBlank()
        ) {
            val richOutput = AgentRichContentCodec.encode(listOf(
                AgentRichBlock(
                    id = "approval:${state.sessionId}:${pending.id}",
                    type = AgentRichBlockType.APPROVAL,
                    title = agentApprovalTitle(pending),
                    text = getString(
                        R.string.agent_inline_approval_detail,
                        agentRiskLabel(pending.risk)
                    ),
                    fallbackText = getString(R.string.agent_inline_approval_waiting),
                    actions = agentPermissionChoices(
                        AgentConfirmationPolicy.tier(pending)
                    ).map { choice ->
                        AgentRichAction(
                            id = "${choice.wireValue}:${pending.id}",
                            label = agentPermissionChoiceLabel(choice),
                            verb = "decide_task_permission",
                            value = choice.wireValue
                        )
                    }
                )
            ))
            agentTranscriptStore.append(
                AgentTranscriptRole.ASSISTANT,
                description,
                dedupeKey = "approval:$planId:${pending.id}",
                conversationId = conversationId,
                turnId = transcriptTurnId,
                taskId = state.sessionId,
                richOutputJson = richOutput
            )
        } else if (description.isNotBlank() &&
            description != "Create a safe local task plan" &&
            !description.contains(':') &&
            !pending.isPhoneDevelopmentRuntimeHandoff()
        ) {
            agentTranscriptStore.append(
                AgentTranscriptRole.PROCESS,
                processDescription,
                dedupeKey = "pending:$planId:${pending.id}:${description.hashCode()}",
                conversationId = conversationId,
                turnId = transcriptTurnId,
                taskId = state.sessionId
            )
        }
    }
    val connectorMetadata = state.lastActionResult?.metadata.orEmpty()
    val connectorPublished = state.phase == AgentPhase.WAITING_RESPONSE &&
        connectorMetadata["awaiting_response"] == "true" &&
        connectorMetadata["source_message_id"].orEmpty().isNotBlank()
    val remoteTaskCreated = connectorMetadata["remote_task_id"].orEmpty().isNotBlank()
    if (connectorPublished && !remoteTaskCreated && transcriptTurnId.isNotBlank()) {
        val target = connectorMetadata["target"].orEmpty()
            .ifBlank { state.plan?.route?.targetTitle.orEmpty() }
            .ifBlank { state.plan?.selectedAgentOrModel.orEmpty() }
            .ifBlank { getString(R.string.tab_agent) }
        agentTranscriptStore.upsert(
            AgentTranscriptRole.PROCESS,
            "$target · ${getString(R.string.agent_task_status_starting)}",
            dedupeKey = "connector-turn:$transcriptTurnId",
            conversationId = conversationId,
            turnId = transcriptTurnId,
            taskId = state.sessionId
        )
    }
    val terminal = state.phase == AgentPhase.COMPLETED ||
        state.phase == AgentPhase.FAILED ||
        state.phase == AgentPhase.CANCELLED ||
        state.phase == AgentPhase.BLOCKED
    val rawResult = state.lastActionResult?.message.orEmpty()
    val route = state.plan?.route
    val terminalNoReply = if (state.phase == AgentPhase.FAILED && rawResult.isNotBlank()) {
        agentNoReplyDisplay(
            taskStatus = "failed",
            error = rawResult,
            currentStep = state.pendingAction?.description.orEmpty(),
            agentId = route?.targetId.orEmpty()
                .ifBlank { state.plan?.selectedAgentOrModel.orEmpty() },
            targetName = route?.targetTitle.orEmpty()
                .ifBlank { state.plan?.selectedAgentOrModel.orEmpty() },
            routeKind = route?.kind ?: AgentRouteKind.UNKNOWN,
            routeStatus = route?.status
        )
    } else {
        null
    }
    val result = CodexStyleResponsePolicy.sanitizeAssistantText(
        terminalNoReply?.message ?: rawResult
    )
    val settledConnectorResult = state.lastActionResult?.metadata?.get("awaiting_response") == "false"
    if (result.isNotBlank() && transcriptTurnId.isNotBlank() &&
        !AgentSupervisedProjectControlPayload.isControlPayloadFragment(result) &&
        (settledConnectorResult || terminal) && !isTransientAgentResult(result)
    ) {
        val actionId = state.lastActionResult?.actionId.orEmpty()
        agentTranscriptStore.upsert(
            AgentTranscriptRole.ASSISTANT,
            result,
            dedupeKey = AgentFinalResponseIdentity.dedupeKey(
                turnId = transcriptTurnId,
                sourceMessageId = connectorMetadata["source_message_id"]?.toLongOrNull() ?: 0L,
                taskId = connectorMetadata["remote_task_id"].orEmpty()
                    .ifBlank { state.sessionId }
            ),
            conversationId = conversationId,
            turnId = transcriptTurnId,
            taskId = state.sessionId,
            richOutputJson = CodexStyleResponsePolicy.filterAssistantRichOutput(
                AgentRuntimeArtifactUi.mergeWithArtifactOutputs(
                    state.lastActionResult?.metadata?.get("rich_output").orEmpty(),
                    state.plan?.artifactRichOutputJson.orEmpty()
                )
            )
        )
    }
}

internal fun MainActivity.agentApprovalTitle(action: AgentAction): String {
    val timerSeconds = action.parameters["timer_seconds"]?.toIntOrNull()
    return when {
        timerSeconds != null && timerSeconds % 60 == 0 -> getString(
            R.string.agent_inline_approval_timer_minutes,
            timerSeconds / 60
        )
        timerSeconds != null -> getString(R.string.agent_inline_approval_timer_seconds, timerSeconds)
        else -> action.description
    }
}

internal fun MainActivity.agentRiskLabel(risk: AgentRisk): String = getString(
    when (risk) {
        AgentRisk.LOW -> R.string.agent_risk_low
        AgentRisk.MEDIUM -> R.string.agent_risk_medium
        AgentRisk.HIGH -> R.string.agent_risk_high
        AgentRisk.BLOCKED -> R.string.agent_risk_blocked
    }
)

internal fun MainActivity.isTransientAgentResult(value: String): Boolean {
    val normalized = value.trim().lowercase(Locale.US)
    return normalized.startsWith("waiting for ") ||
        normalized.startsWith("sent the request") ||
        normalized.startsWith("received a response") ||
        normalized.startsWith("\u5df2\u5c06\u8bf7\u6c42\u53d1\u9001") ||
        normalized.startsWith("\u5df2\u6536\u5230")
}

internal fun MainActivity.captureAgentTranscriptScrollAnchor(): AgentTranscriptScrollAnchor? {
    if (!isAgentOutputLayoutInitialized() || !isAgentTranscriptAdapterInitialized()) return null
    val position = agentOutputLayout.findFirstVisibleItemPosition()
    if (position == RecyclerView.NO_POSITION) return null
    val entryId = agentTranscriptAdapter.entryIdAt(position) ?: return null
    val topOffset = agentOutputLayout.findViewByPosition(position)?.top
        ?: agentOutputList.paddingTop
    return AgentTranscriptScrollAnchor(entryId, topOffset)
}

internal fun MainActivity.restoreAgentTranscriptScrollAnchor(anchor: AgentTranscriptScrollAnchor?) {
    if (anchor == null) return
    val position = agentTranscriptAdapter.indexOfEntry(anchor.entryId)
    if (position >= 0) {
        agentOutputLayout.scrollToPositionWithOffset(position, anchor.topOffset)
    }
}

internal fun MainActivity.scrollAgentTranscriptToBottom() {
    val lastPosition = agentTranscriptAdapter.itemCount - 1
    if (lastPosition < 0) return
    agentOutputList.scrollToPosition(lastPosition)
    agentOutputList.post {
        agentOutputList.scrollBy(0, agentOutputList.computeVerticalScrollRange())
    }
}

internal fun MainActivity.renderAgentTranscript(entries: List<AgentTranscriptEntry>) {
    val renderStartedAt = SystemClock.elapsedRealtime()
    val activeConversationId = agentTranscriptStore.activeConversation().id
    val liveEntries = liveAgentConnectorStreams.values
        .filter { it.conversationId == activeConversationId }
    val hydratedEntries = (entries + liveEntries)
        .distinctBy(AgentTranscriptEntry::id)
        .sortedBy(AgentTranscriptEntry::timestampMillis)
        .map(::expandedAgentTranscriptEntry)
    val filteredEntries = hydratedEntries.filterNot { entry ->
        val leakedControlPayload = AgentSupervisedProjectControlPayload
            .isTranscriptControlPayload(entry.text, entry.richOutputJson)
        if (leakedControlPayload && agentTranscriptStore.deleteEntry(entry.id)) {
            agentTranscriptWindow.remove(entry.id)
        }
        val staleApproval = isLocalAgentApprovalEntry(entry) &&
            (isDirectActionApprovalEntry(entry) || !isAgentApprovalStillWaiting(entry.taskId))
        if (staleApproval && agentTranscriptStore.deleteEntry(entry.id)) {
            agentTranscriptWindow.remove(entry.id)
        }
        leakedControlPayload || staleApproval
    }
    renderedAgentTranscriptSourceEntries = filteredEntries
    val collapsedEntries = AgentTranscriptPresentationPolicy.collapseProcessGroups(
        filteredEntries
    )
    val waitingResult = AgentReplyWaitingIndicatorPolicy.apply(
        entries = collapsedEntries,
        pending = pendingAgentReplyIndicators.values,
        conversationId = activeConversationId
    )
    waitingResult.resolvedTurnIds.forEach(pendingAgentReplyIndicators::remove)
    val visibleEntries = waitingResult.entries
    val incomingIds = visibleEntries.map(AgentTranscriptRenderPolicy::identity)
    val renderedIds = renderedAgentTranscriptIds.toList()
    val diff = AgentTranscriptRenderPolicy.diff(
        renderedIds,
        renderedAgentTranscriptSignatures,
        visibleEntries
    )
    val reset = diff.reset || agentTranscriptAdapter.itemCount != renderedIds.size
    val shouldFollow = agentTranscriptAutoFollow
    val scrollAnchor = captureAgentTranscriptScrollAnchor()
    var changed = false
    if (reset) {
        agentTranscriptAdapter.replaceAll(visibleEntries)
        renderedAgentTranscriptIds.clear()
        renderedAgentTranscriptSignatures.clear()
        visibleEntries.forEach { entry ->
            val identity = AgentTranscriptRenderPolicy.identity(entry)
            renderedAgentTranscriptIds += identity
            renderedAgentTranscriptSignatures[identity] =
                AgentTranscriptRenderPolicy.signature(entry)
        }
        changed = visibleEntries.isNotEmpty() || renderedIds.isNotEmpty()
    } else {
        diff.replacementIndices.forEach { index ->
            val entry = visibleEntries[index]
            agentTranscriptAdapter.replaceAt(index, entry)
            renderedAgentTranscriptSignatures[AgentTranscriptRenderPolicy.identity(entry)] =
                AgentTranscriptRenderPolicy.signature(entry)
            changed = true
        }
        val appended = visibleEntries.drop(diff.appendFromIndex)
        agentTranscriptAdapter.append(appended)
        appended.forEach { entry ->
            val identity = AgentTranscriptRenderPolicy.identity(entry)
            renderedAgentTranscriptIds += identity
            renderedAgentTranscriptSignatures[identity] =
                AgentTranscriptRenderPolicy.signature(entry)
            changed = true
        }
    }
    renderedAgentTranscriptSignatures.keys.retainAll(incomingIds.toSet())
    if (!changed) return
    val elapsed = SystemClock.elapsedRealtime() - renderStartedAt
    if (elapsed >= AGENT_TRANSCRIPT_PERF_LOG_THRESHOLD_MS || reset) {
        Log.d(
            "SignalASIPerf",
            "transcript_render source=${entries.size} visible=${visibleEntries.size} " +
                "reset=$reset replacements=${diff.replacementIndices.size} " +
                "appended=${visibleEntries.size - diff.appendFromIndex} elapsed_ms=$elapsed"
        )
    }
    agentOutputList.post {
        if (shouldFollow) {
            scrollAgentTranscriptToBottom()
        } else {
            restoreAgentTranscriptScrollAnchor(scrollAnchor)
        }
    }
}

internal fun MainActivity.agentChunkedAssistantContent(entry: AgentTranscriptEntry): View {
    val cached = expandedAgentTranscriptText[entry.id]
        ?.takeIf { it.sha256 == entry.textSha256 }
        ?: run {
            expandedAgentTranscriptText.remove(entry.id)
            null
        }
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        val chunkContainer = LinearLayout(this@agentChunkedAssistantContent).apply {
            orientation = LinearLayout.VERTICAL
            tag = "agent-transcript-chunks:${entry.id}"
        }
        if (cached?.chunks.isNullOrEmpty()) {
            chunkContainer.addView(agentAssistantRichContent(entry, entry))
        } else {
            cached?.chunks?.forEach { chunk ->
                chunkContainer.addView(agentAssistantTextChunk(entry, chunk))
            }
        }
        addView(chunkContainer)
        if (cached?.done != true) {
            addView(TextView(this@agentChunkedAssistantContent).apply {
                tag = "agent-transcript-expand:${entry.id}"
                val loading = entry.id in agentTranscriptExpansionInFlight
                text = if (loading) "\u2026" else getString(R.string.rich_output_show_more)
                isEnabled = !loading
                textSize = 13f
                includeFontPadding = false
                setTextColor(Color.parseColor("#087F69"))
                setPadding(0, dp(8), dp(8), dp(8))
                setOnClickListener {
                    loadAllAgentTranscriptTextChunks(entry, chunkContainer, this)
                }
            })
        }
    }
}

internal fun MainActivity.agentAssistantTextChunk(
    entry: AgentTranscriptEntry,
    chunk: String
): View = agentAssistantRichContent(
    entry.copy(
        text = chunk,
        richOutputJson = "",
        textChunkCount = 0,
        textLength = chunk.length,
        textSha256 = AgentLargeOutputPolicy.digest(chunk)
    ),
    entry
)

internal fun MainActivity.loadAllAgentTranscriptTextChunks(
    entry: AgentTranscriptEntry,
    chunkContainer: LinearLayout,
    button: TextView
) {
    if (!agentTranscriptExpansionInFlight.add(entry.id)) return
    button.isEnabled = false
    button.text = "\u2026"
    val existing = expandedAgentTranscriptText[entry.id]
        ?.takeIf { it.sha256 == entry.textSha256 }
        ?.chunks
        ?.toList()
        .orEmpty()
    agentTranscriptContentExecutor.execute {
        val loaded = existing.toMutableList()
        val result = runCatching {
            var offset = loaded.size
            var done = false
            while (!done) {
                val page = checkNotNull(
                    agentTranscriptStore.textChunkPage(
                        entryId = entry.id,
                        offset = offset,
                        pageSize = 2
                    )
                ) { "Agent transcript output is unavailable" }
                check(page.sha256 == entry.textSha256) {
                    "Agent transcript output digest changed"
                }
                check(page.chunks.isNotEmpty() || page.done) {
                    "Agent transcript output stream stopped"
                }
                loaded += page.chunks
                offset = page.nextOffset
                done = page.done
                runOnUiThread {
                    if (entry.conversationId != agentRenderedConversationId) {
                        return@runOnUiThread
                    }
                    val cache = expandedAgentTranscriptText.getOrPut(entry.id) {
                        AgentExpandedTextOutput(entry.textSha256)
                    }
                    if (cache.sha256 != entry.textSha256) return@runOnUiThread
                    if (cache.chunks.size == page.offset) {
                        val visibleContainer =
                            agentOutputList.findViewWithTag<LinearLayout>(
                                "agent-transcript-chunks:${entry.id}"
                            ) ?: chunkContainer.takeIf { it.isAttachedToWindow }
                        if (page.offset == 0) visibleContainer?.removeAllViews()
                        page.chunks.forEach { chunk ->
                            cache.chunks += chunk
                            visibleContainer?.let { target ->
                                target.addView(
                                    agentAssistantTextChunk(entry, chunk)
                                )
                            }
                        }
                    }
                }
            }
            val complete = loaded.joinToString("")
            check(complete.length == entry.textLength) {
                "Agent transcript output length mismatch"
            }
            check(AgentLargeOutputPolicy.digest(complete) == entry.textSha256) {
                "Agent transcript output digest mismatch"
            }
        }
        runOnUiThread {
            agentTranscriptExpansionInFlight.remove(entry.id)
            if (isFinishing || isDestroyed) return@runOnUiThread
            val error = result.exceptionOrNull()
            if (error != null) {
                val visibleButton = agentOutputList.findViewWithTag<TextView>(
                    "agent-transcript-expand:${entry.id}"
                ) ?: button
                visibleButton.isEnabled = true
                visibleButton.text = getString(R.string.rich_output_show_more)
                Toast.makeText(
                    this,
                    error.message ?: getString(R.string.rich_output_load_failed),
                    Toast.LENGTH_SHORT
                ).show()
                return@runOnUiThread
            }
            if (entry.conversationId != agentRenderedConversationId) {
                return@runOnUiThread
            }
            val cache = expandedAgentTranscriptText.getOrPut(entry.id) {
                AgentExpandedTextOutput(entry.textSha256)
            }
            cache.done = true
            (
                agentOutputList.findViewWithTag<TextView>(
                    "agent-transcript-expand:${entry.id}"
                ) ?: button
                ).visibility = View.GONE
            trimExpandedAgentTranscriptCaches()
        }
    }
}

internal fun MainActivity.trimExpandedAgentTranscriptCaches() {
    while (
        expandedAgentTranscriptText.size >
        MAX_EXPANDED_AGENT_TRANSCRIPT_ENTRIES
    ) {
        expandedAgentTranscriptText.remove(expandedAgentTranscriptText.keys.first())
    }
    while (
        expandedAgentTranscriptEntries.size >
        MAX_EXPANDED_AGENT_TRANSCRIPT_ENTRIES
    ) {
        expandedAgentTranscriptEntries.remove(expandedAgentTranscriptEntries.keys.first())
    }
}

internal fun MainActivity.expandedAgentTranscriptEntry(
    preview: AgentTranscriptEntry
): AgentTranscriptEntry {
    val expanded = expandedAgentTranscriptEntries[preview.id] ?: return preview
    val matches = expanded.conversationId == preview.conversationId &&
        expanded.textSha256 == preview.textSha256 &&
        expanded.richOutputSha256 == preview.richOutputSha256
    if (matches) return expanded
    expandedAgentTranscriptEntries.remove(preview.id)
    return preview
}

internal fun MainActivity.loadFullAgentTranscriptEntry(
    preview: AgentTranscriptEntry,
    button: TextView
) {
    if (!agentTranscriptExpansionInFlight.add(preview.id)) return
    button.isEnabled = false
    button.text = "\u2026"
    agentTranscriptContentExecutor.execute {
        val result = runCatching { agentTranscriptStore.fullEntry(preview.id) }
        runOnUiThread {
            agentTranscriptExpansionInFlight.remove(preview.id)
            if (isFinishing || isDestroyed) return@runOnUiThread
            val expanded = result.getOrNull()
            if (
                expanded == null ||
                expanded.conversationId != agentRenderedConversationId ||
                AgentLargeOutputPolicy.hasDeferredContent(expanded)
            ) {
                button.isEnabled = true
                button.text = getString(R.string.rich_output_show_more)
                Toast.makeText(
                    this,
                    result.exceptionOrNull()?.message
                        ?: getString(R.string.rich_output_load_failed),
                    Toast.LENGTH_SHORT
                ).show()
                return@runOnUiThread
            }
            expandedAgentTranscriptEntries.remove(expanded.id)
            expandedAgentTranscriptEntries[expanded.id] = expanded
            trimExpandedAgentTranscriptCaches()
            renderAgentTranscript(agentTranscriptWindow.entries)
        }
    }
}

internal fun MainActivity.isAgentApprovalEntry(entry: AgentTranscriptEntry): Boolean =
    entry.taskId.isNotBlank() && AgentRichContentCodec.decode(entry.richOutputJson).any { block ->
        block.type == AgentRichBlockType.APPROVAL && block.actions.any { action ->
            action.verb in setOf(
                "decide_task_permission",
                "decide_remote_task_permission"
            )
        }
    }

internal fun MainActivity.isLocalAgentApprovalEntry(entry: AgentTranscriptEntry): Boolean =
    entry.taskId.isNotBlank() && AgentRichContentCodec.decode(entry.richOutputJson).any { block ->
        block.type == AgentRichBlockType.APPROVAL && block.actions.any { action ->
            action.verb == "decide_task_permission"
        }
    }

internal fun MainActivity.isRemoteAgentApprovalEntry(entry: AgentTranscriptEntry): Boolean =
    entry.taskId.isNotBlank() && AgentRichContentCodec.decode(entry.richOutputJson).any { block ->
        block.type == AgentRichBlockType.APPROVAL && block.actions.any { action ->
            action.verb == "decide_remote_task_permission"
        }
    }

internal fun MainActivity.isDirectActionApprovalEntry(entry: AgentTranscriptEntry): Boolean =
    AgentRichContentCodec.decode(entry.richOutputJson).any { block ->
        if (block.type != AgentRichBlockType.APPROVAL) return@any false
        val value = listOf(block.title, block.text, block.fallbackText, entry.text)
            .joinToString(" ")
            .lowercase(Locale.US)
        listOf(
            "timer", "alarm", "camera", "flashlight", "torch", "volume", "battery status",
            "device status", "open app", "launch app", "\u8ba1\u65f6\u5668", "\u95f9\u949f", "\u62cd\u7167",
            "\u624b\u7535\u7b52", "\u97f3\u91cf", "\u7535\u91cf", "\u8bbe\u5907\u72b6\u6001", "\u6253\u5f00 app"
        ).any(value::contains)
    }

internal fun MainActivity.isAgentApprovalStillWaiting(taskId: String): Boolean {
    if (taskId.isBlank()) return false
    return buildList {
        add(mobileNativeAgent)
        addAll(activeAgentTasks.values)
        addAll(provisionalAgentTasks)
    }.distinct().any { runtime ->
        val state = runtime.snapshot()
        state.sessionId == taskId &&
            state.phase == AgentPhase.WAITING_CONFIRMATION &&
            state.pendingAction?.let(AgentConfirmationPolicy::tier) != AgentConfirmationTier.DIRECT
    }
}

internal fun MainActivity.agentTranscriptRow(entry: AgentTranscriptEntry): View {
    if (AgentReplyWaitingIndicatorPolicy.isIndicator(entry)) {
        return agentReplyWaitingTranscriptRow()
    }
    val content = when (entry.role) {
        AgentTranscriptRole.USER -> agentUserTranscriptRow(entry)
        AgentTranscriptRole.ASSISTANT -> agentAssistantTranscriptRow(entry)
        AgentTranscriptRole.PROCESS -> agentProcessTranscriptRow(entry)
    }
    if (entry.sourceConversationId.isBlank() || entry.role == AgentTranscriptRole.PROCESS) return content
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = if (entry.role == AgentTranscriptRole.USER) Gravity.END else Gravity.START
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        addView(TextView(this@agentTranscriptRow).apply {
            text = getString(
                R.string.agent_session_merged_from,
                entry.sourceConversationTitle.ifBlank { entry.sourceConversationId.take(12) }
            )
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 11f
            includeFontPadding = false
            setPadding(dp(2), dp(8), dp(2), 0)
        })
        addView(content)
    }
}

internal fun MainActivity.agentReplyWaitingTranscriptRow(): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    gravity = Gravity.START
    layoutParams = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(10) }
    addView(
        AgentVoiceTranscriptionPendingView(
            context = this@agentReplyWaitingTranscriptRow,
            bubbleBackground = false,
            accessibilityText = getString(R.string.agent_status_waiting_response),
            dotColorRes = R.color.text_primary
        ),
        LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
    )
}

internal fun MainActivity.agentAssistantTranscriptRow(entry: AgentTranscriptEntry): View {
    val progressiveText = entry.textChunkCount > 0 && entry.richOutputChunkCount == 0
    val richContent = if (progressiveText) {
        agentChunkedAssistantContent(entry)
    } else {
        agentAssistantRichContent(entry, entry)
    }
    val content = if (
        !progressiveText &&
        AgentLargeOutputPolicy.hasDeferredContent(entry)
    ) {
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            addView(richContent)
            addView(TextView(this@agentAssistantTranscriptRow).apply {
                text = getString(R.string.rich_output_show_more)
                textSize = 13f
                includeFontPadding = false
                setTextColor(Color.parseColor("#087F69"))
                setPadding(0, dp(8), dp(8), dp(8))
                setOnClickListener {
                    loadFullAgentTranscriptEntry(entry, this)
                }
            })
        }
    } else {
        richContent
    }
    val execution = agentExecutionPresentations[entry.taskId]
        ?.takeUnless { isAgentApprovalEntry(entry) || entry.dedupeKey.startsWith("agent-recovery:") }
        ?: return content
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        addView(content)
        addView(TextView(this@agentAssistantTranscriptRow).apply {
            text = buildString {
                append(execution.executorLabel)
                append(" \u00b7 ")
                append(agentExecutionHostText(execution.locationKind))
                append(" \u00b7 ")
                append(agentExecutionRuntimeText(execution))
                execution.locationLabelHint.takeIf(String::isNotBlank)?.let {
                    append(" \u00b7 ")
                    append(it)
                }
            }
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 10f
            includeFontPadding = false
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(dp(2), dp(5), dp(2), 0)
        })
    }
}

internal fun MainActivity.agentAssistantRichContent(
    displayEntry: AgentTranscriptEntry,
    actionEntry: AgentTranscriptEntry
): View = AgentRichContentView(
    activity = this,
    onTextViewReady = { textView -> attachAgentTranscriptActions(textView, actionEntry) },
    onAction = { action -> handleAgentRichAction(actionEntry, action) },
    onFormSubmit = { block, values -> handleAgentRichForm(actionEntry, block, values) },
    enableResponseSections = displayEntry.textChunkCount == 0,
    isSectionExpanded = { entryId, kind, expandedByDefault ->
        agentResponseSectionExpansion["$entryId:${kind.name}"] ?: (
            expandedByDefault ||
                AgentPreferenceModePolicy.profile(
                    mobileNativeAgent.preferenceMode()
                ).expandStructuredDetails
            )
    },
    onSectionExpansionChanged = { entryId, kind, expanded ->
        val key = "$entryId:${kind.name}"
        agentResponseSectionExpansion.remove(key)
        agentResponseSectionExpansion[key] = expanded
        while (agentResponseSectionExpansion.size > MAX_AGENT_RESPONSE_SECTION_STATES) {
            agentResponseSectionExpansion.remove(agentResponseSectionExpansion.keys.first())
        }
    }
).create(displayEntry.copy(
    text = CodexStyleResponsePolicy.sanitizeAssistantText(
        localizedAgentAssistantText(displayEntry.text)
    ),
    richOutputJson = CodexStyleResponsePolicy.filterAssistantRichOutput(
        displayEntry.richOutputJson
    )
))

internal fun MainActivity.agentProcessTranscriptRow(entry: AgentTranscriptEntry): View {
    val groupKey = AgentTranscriptPresentationPolicy.processGroupKey(entry)
    val turnEntries = when {
        entry.turnId.isNotBlank() -> renderedAgentTranscriptSourceEntries.filter { candidate ->
            candidate.turnId == entry.turnId ||
                (candidate.turnId.isBlank() && candidate.taskId == entry.taskId)
        }
        entry.taskId.isNotBlank() -> renderedAgentTranscriptSourceEntries.filter { candidate ->
            candidate.taskId == entry.taskId
        }
        else -> listOf(entry)
    }.ifEmpty { listOf(entry) }
    val processEntries = AgentExecutionLoopTimelinePolicy.suppressSupersededPlaceholders(turnEntries)
        .filter { candidate ->
            candidate.role == AgentTranscriptRole.PROCESS &&
                !AgentTranscriptPresentationPolicy.isRedundantConnectorCompletion(candidate) &&
                !AgentTranscriptPresentationPolicy.isInternalRuntimeHandoff(candidate) &&
                when {
                    entry.turnId.isNotBlank() -> candidate.turnId == entry.turnId ||
                        candidate.id == entry.id ||
                        (candidate.turnId.isBlank() && candidate.taskId == entry.taskId)
                    entry.taskId.isNotBlank() -> candidate.taskId == entry.taskId
                    else -> candidate.id == entry.id
                }
        }
        .sortedBy(AgentTranscriptEntry::timestampMillis)
        .distinctBy { it.text.trim() }
    val processSegments = AgentTranscriptPresentationPolicy.narrationSegments(
        processEntries.ifEmpty { listOf(entry) }
    )
    val hasProcessDetails = processSegments.isNotEmpty()
    val startedAt = processEntries.firstOrNull()?.timestampMillis ?: entry.timestampMillis
    val completedAt = agentProcessCompletionTimestamp(entry, turnEntries)
    val completed = completedAt != null
    val expanded = hasProcessDetails &&
        AgentTranscriptPresentationPolicy.processExpanded(
            completed = completed,
            manuallyExpanded = groupKey in expandedAgentProcessGroups,
            manuallyCollapsedWhileActive = groupKey in collapsedActiveAgentProcessGroups
        )
    val timelineActions = if (completed) {
        emptyList()
    } else {
        agentTimelineRuntime(entry)
            ?.phaseSnapshot()
            ?.let(AgentExecutionLoopTimelinePolicy::actionsForPhase)
            .orEmpty()
    }
    val voiceAgentRun = if (isVoiceAgentRunBridgeInitialized() && entry.taskId.isNotBlank()) {
        voiceAgentRunBridge.findByTaskId(entry.taskId)
    } else {
        null
    }
    val execution = agentExecutionPresentation(
        entry = entry,
        processEntries = processEntries,
        startedAtMillis = startedAt,
        completedAtMillis = completedAt
    )
    val canCancel = execution.cancellable && (
        AgentExecutionLoopTimelineAction.CANCEL in timelineActions ||
            voiceAgentRun?.cancellable == true
        )
    val secondaryTimelineActions = timelineActions.filterNot {
        it == AgentExecutionLoopTimelineAction.CANCEL
    }
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            topMargin = dp(10)
        }
        addView(LinearLayout(this@agentProcessTranscriptRow).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            isClickable = true
            isFocusable = true
            minimumHeight = dp(34)
            setPadding(0, dp(5), 0, dp(5))
            addView(View(this@agentProcessTranscriptRow).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(
                        Color.parseColor(if (completed) "#22A06B" else "#2F7CF6")
                    )
                }
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LinearLayout.LayoutParams(dp(7), dp(7)).apply {
                marginEnd = dp(9)
            })
            addView(LinearLayout(this@agentProcessTranscriptRow).apply {
                orientation = LinearLayout.VERTICAL
                addView(LinearLayout(this@agentProcessTranscriptRow).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    addView(TextView(this@agentProcessTranscriptRow).apply {
                        text = execution.executorLabel
                        setTextColor(getColorCompat(R.color.text_primary))
                        textSize = 14f
                        setTypeface(typeface, android.graphics.Typeface.BOLD)
                        includeFontPadding = false
                        maxLines = 1
                        ellipsize = android.text.TextUtils.TruncateAt.END
                    }, LinearLayout.LayoutParams(
                        0,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        1f
                    ))
                    addView(TextView(this@agentProcessTranscriptRow).apply {
                        text = agentExecutionHostText(execution.locationKind)
                        setTextColor(agentExecutionHostTextColor(execution.locationKind))
                        textSize = 10f
                        setTypeface(typeface, android.graphics.Typeface.BOLD)
                        includeFontPadding = false
                        gravity = Gravity.CENTER
                        minHeight = dp(22)
                        setPadding(dp(7), 0, dp(7), 0)
                        background = GradientDrawable().apply {
                            cornerRadius = dp(5).toFloat()
                            setColor(agentExecutionHostBackgroundColor(execution.locationKind))
                        }
                    }, LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        dp(22)
                    ).apply {
                        marginStart = dp(8)
                    })
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ))
                addView(TextView(this@agentProcessTranscriptRow).apply {
                    setTextColor(getColorCompat(R.color.text_secondary))
                    textSize = 11f
                    includeFontPadding = false
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    setPadding(0, dp(3), 0, 0)
                    val statusView = this
                    val ticker = object : Runnable {
                        override fun run() {
                            val elapsedMillis = (
                                (completedAt ?: System.currentTimeMillis()) - startedAt
                            ).coerceAtLeast(0L)
                            statusView.text = buildString {
                                append(agentExecutionRuntimeText(execution))
                                execution.locationLabelHint
                                    .takeIf(String::isNotBlank)
                                    ?.let {
                                        append(" \u00b7 ")
                                        append(it)
                                    }
                                append(" \u00b7 ")
                                append(
                                    execution.currentStep.ifBlank {
                                        agentExecutionPhaseText(execution.phase)
                                    }
                                )
                                append(" \u00b7 ")
                                append(agentTraceDuration(elapsedMillis))
                            }
                            if (completedAt == null && statusView.isAttachedToWindow) {
                                statusView.postDelayed(this, AGENT_PROCESS_TIMER_TICK_MS)
                            }
                        }
                    }
                    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                        override fun onViewAttachedToWindow(view: View) {
                            statusView.removeCallbacks(ticker)
                            ticker.run()
                        }

                        override fun onViewDetachedFromWindow(view: View) {
                            statusView.removeCallbacks(ticker)
                        }
                    })
                })
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            if (canCancel) {
                addView(TextView(this@agentProcessTranscriptRow).apply {
                    text = getString(R.string.agent_execution_cancel)
                    setTextColor(Color.parseColor("#59636D"))
                    textSize = 12f
                    gravity = Gravity.CENTER
                    includeFontPadding = false
                    minHeight = dp(32)
                    setPadding(dp(9), 0, dp(9), 0)
                    background = GradientDrawable().apply {
                        cornerRadius = dp(6).toFloat()
                        setColor(Color.parseColor("#F4F6F8"))
                        setStroke(dp(1), Color.parseColor("#DDE2E7"))
                    }
                    contentDescription =
                        getString(R.string.agent_execution_cancel_description)
                    setOnClickListener {
                        if (voiceAgentRun?.cancellable == true) {
                            cancelVoiceAgentRun(voiceAgentRun)
                        } else agentTimelineRuntime(entry)?.let { runtime ->
                            runAgentTimelineAction(
                                entry,
                                runtime,
                                AgentExecutionLoopTimelineAction.CANCEL
                            )
                        }
                    }
                }, LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    dp(32)
                ).apply {
                    marginStart = dp(8)
                })
            }
            if (hasProcessDetails) {
                addView(ImageView(this@agentProcessTranscriptRow).apply {
                    setImageResource(R.drawable.ic_chevron_down)
                    imageTintList = android.content.res.ColorStateList.valueOf(
                        getColorCompat(R.color.text_secondary)
                    )
                    rotation = if (expanded) 180f else 0f
                    contentDescription = getString(R.string.agent_trace_processed_details)
                }, LinearLayout.LayoutParams(dp(17), dp(17)).apply {
                    marginStart = dp(8)
                })
            }
            if (secondaryTimelineActions.isNotEmpty()) {
                addView(ImageView(this@agentProcessTranscriptRow).apply {
                    setImageResource(R.drawable.ic_more_horizontal)
                    imageTintList = android.content.res.ColorStateList.valueOf(
                        getColorCompat(R.color.text_secondary)
                    )
                    scaleType = ImageView.ScaleType.CENTER_INSIDE
                    setPadding(dp(6), dp(6), dp(6), dp(6))
                    contentDescription = getString(R.string.agent_more_actions)
                    isClickable = true
                    isFocusable = true
                    setOnClickListener { anchor ->
                        showAgentTimelineMenu(entry, anchor, includeCancel = false)
                    }
                }, LinearLayout.LayoutParams(dp(32), dp(32)).apply {
                    marginStart = dp(4)
                })
            }
            if (hasProcessDetails) {
                setOnClickListener {
                    if (completed) {
                        if (expanded) expandedAgentProcessGroups.remove(groupKey)
                        else expandedAgentProcessGroups.add(groupKey)
                    } else {
                        if (expanded) collapsedActiveAgentProcessGroups.add(groupKey)
                        else collapsedActiveAgentProcessGroups.remove(groupKey)
                    }
                    clearAgentTranscriptRows()
                    refreshAgentTranscriptWindow(entry.conversationId)
                }
            } else {
                if (voiceAgentRun != null) {
                    setOnClickListener { showVoiceAgentRunDetails(voiceAgentRun) }
                } else {
                    isClickable = false
                    isFocusable = false
                }
            }
        })
        if (expanded) {
            processSegments.forEach { segment ->
                segment.entries.forEach { narration ->
                    addView(agentProcessNarrationRow(narration))
                }
            }
        }
        addView(View(this@agentProcessTranscriptRow).apply {
            setBackgroundColor(Color.parseColor("#E8EAED"))
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)).apply {
            topMargin = if (expanded) dp(5) else dp(2)
        })
    }
}
