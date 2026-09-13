package com.galaxyssi.chat

import android.content.Context
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject

/** Persistent run projection shared by page-owned and background connector execution. */
internal class AgentExecutionRunRecorder(
    private val context: Context,
    private val runtime: MobileNativeAgent,
    private val recordedRunId: String = ""
) {
    private val agentRunRecorder = AgentRunRecorder.get(context)
    private val agentRunEventStore = AgentRunEventStore(context)
    private val agentTranscriptStore by lazy { AgentTranscriptStore(context) }
    private val agentLearningEngine by lazy {
        val skills = AgentSkillRuntime(EncryptedAgentSkillStore(context),
            runtime.nativeToolIds() + AGENT_ORCHESTRATION_TOOL_ID)
        AgentLearningEngine(context, EncryptedAgentMemoryStore(context), skills,
            AgentConversationSkillCompiler(skills) { runtime.nativeToolCatalog() })
    }

    fun recordAgentRunFromState(turnId: String, state: AgentUiState) {
        if (state.phase !in setOf(AgentPhase.COMPLETED, AgentPhase.FAILED, AgentPhase.CANCELLED, AgentPhase.BLOCKED)) return
        val persistedRunId = runCatching {
            EncryptedAgentWorkspaceStore(context).find(turnId)?.parentRunId.orEmpty()
        }.getOrDefault("")
        val runId = recordedRunId.ifBlank { persistedRunId }
        val run = agentRunRecorder.run(runId)
            ?.takeIf { it.status == AgentRecordedRunStatus.RUNNING }
            ?: return
        val result = state.lastActionResult
        val nativeActions = (state.plan?.actionHistory.orEmpty() + state.plan?.actions.orEmpty())
            .distinctBy { it.id }
            .filter { it.kind == AgentActionKind.CALL_NATIVE_TOOL }
        val calls = nativeActions.map { action ->
            val isLast = result?.actionId == action.id
            val succeeded = action.status == AgentActionStatus.COMPLETED || (isLast && result?.success == true)
            AgentToolCallRecord(
                id = if (isLast) result?.metadata?.get("invocation_id").orEmpty().ifBlank { action.id } else action.id,
                toolName = action.parameters["tool_id"].orEmpty(),
                status = if (succeeded) AgentToolCallStatus.SUCCEEDED else AgentToolCallStatus.FAILED,
                argumentsJson = action.parameters["input_json"].orEmpty().ifBlank { "{}" },
                resultJson = if (isLast) result?.metadata?.get("native_tool_output").orEmpty().ifBlank {
                    JSONObject().put("message", action.result).toString()
                } else JSONObject().put("message", action.result).toString(),
                errorMessage = if (succeeded) "" else action.result,
                startedAtMillis = if (isLast) result?.metadata?.get("started_at_millis")?.toLongOrNull() ?: 0L else 0L,
                completedAtMillis = if (isLast) result?.metadata?.get("completed_at_millis")?.toLongOrNull() ?: 0L else 0L
            )
        }
        val routeTarget = state.plan?.route?.targetId.orEmpty()
            .ifBlank { state.plan?.selectedAgentOrModel.orEmpty() }
        val handoffAlreadyRecorded = agentRunEventStore.events(run.runId)
            .any { it.type == AgentRunControlEventType.HANDOFF }
        if (routeTarget.isNotBlank() && routeTarget != "galaxyssi-mobile" && !handoffAlreadyRecorded) {
            appendRunControlEvent(
                run = run,
                messageId = turnId,
                taskId = turnId,
                agentId = routeTarget,
                type = AgentRunControlEventType.HANDOFF,
                payload = mapOf(
                    "from_agent_id" to "galaxyssi-mobile",
                    "to_agent_id" to routeTarget,
                    "reason" to state.plan?.routeRationale.orEmpty(),
                    "return_to_agent_id" to "galaxyssi-mobile"
                )
            )
        }
        val planJson = JSONArray().apply {
            state.plan?.actions.orEmpty().forEach { item ->
                put(JSONObject().put("id", item.id).put("kind", item.kind.name).put("target", item.target))
            }
        }.toString()
        agentRunRecorder.complete(
            runId = runId,
            planJson = planJson,
            toolCalls = calls,
            sourcesJson = "[]",
            finalOutputJson = JSONObject().put("text", result?.message.orEmpty()).toString(),
            renderSpecJson = "{}",
            artifacts = runtimeArtifactsFromResult(result?.metadata?.get("native_tool_output").orEmpty()),
            success = state.phase == AgentPhase.COMPLETED,
            finalStatus = when (state.phase) {
                AgentPhase.COMPLETED -> AgentRecordedRunStatus.COMPLETED
                AgentPhase.CANCELLED -> AgentRecordedRunStatus.CANCELLED
                else -> AgentRecordedRunStatus.FAILED
            },
            executionResourceId = routeTarget.ifBlank { "galaxyssi-mobile" }
        )?.let(::observeCompletedAgentRun)
    }

    fun observeCompletedAgentRun(run: AgentRecordedRun) {
        val existing = agentRunEventStore.events(run.runId).lastOrNull()
        ensureRecordedRunTimeline(
            run = run,
            messageId = existing?.messageId.orEmpty().ifBlank { run.runId },
            taskId = existing?.taskId.orEmpty().ifBlank { run.taskThreadId },
            agentId = existing?.agentId.orEmpty().ifBlank { "galaxyssi-mobile" }
        )
        appendRunControlEvent(
            run = run,
            messageId = existing?.messageId.orEmpty().ifBlank { run.runId },
            taskId = existing?.taskId.orEmpty().ifBlank { run.taskThreadId },
            agentId = existing?.agentId.orEmpty().ifBlank { "galaxyssi-mobile" },
            type = when (run.status) {
                AgentRecordedRunStatus.COMPLETED -> AgentRunControlEventType.RUN_COMPLETED
                AgentRecordedRunStatus.CANCELLED -> AgentRunControlEventType.RUN_CANCELLED
                AgentRecordedRunStatus.RUNNING, AgentRecordedRunStatus.FAILED -> AgentRunControlEventType.RUN_FAILED
            },
            payload = mapOf(
                "timeline_contract" to AgentRunTimelineContract.VERSION,
                "timeline_kind" to if (run.status == AgentRecordedRunStatus.COMPLETED) "result" else "failure",
                "run_status" to run.status.name.lowercase(Locale.ROOT),
                "tool_call_count" to run.toolCalls.size,
                "artifact_count" to run.artifacts.size,
                "execution_resource_id" to run.executionResourceId
            )
        )
        val privateMode = agentTranscriptStore.context(run.conversationId).privateMode
        agentLearningEngine.observeCompletedRun(
            run = run,
            recentRuns = agentRunRecorder.recentRuns(),
            privateMode = privateMode,
            memoryCaptureEnabled = runtime.safetySettings().memoryCapture
        )
    }

    fun ensureRecordedRunTimeline(
        run: AgentRecordedRun,
        messageId: String,
        taskId: String,
        agentId: String
    ) {
        var events = agentRunEventStore.events(run.runId)
        if (!AgentRunTimelineContract.coverage(events).hasPlan) {
            val planStepCount = runCatching { JSONArray(run.agentPlanJson).length() }.getOrDefault(0)
            appendRunControlEvent(
                run = run,
                messageId = messageId,
                taskId = taskId,
                agentId = agentId,
                type = AgentRunControlEventType.PLANNING,
                payload = mapOf(
                    "timeline_contract" to AgentRunTimelineContract.VERSION,
                    "timeline_kind" to "plan",
                    "plan_step_count" to planStepCount,
                    "synthetic_from_recorded_run" to true
                ),
                stepId = "plan",
                timestampMillis = run.createdAtMillis
            )
            events = agentRunEventStore.events(run.runId)
        }
        run.toolCalls.forEach { call ->
            val hasStart = events.any {
                it.toolCallId == call.id && it.type == AgentRunControlEventType.TOOL_STARTED
            }
            if (!hasStart) {
                appendRunControlEvent(
                    run = run,
                    messageId = messageId,
                    taskId = taskId,
                    agentId = agentId,
                    type = AgentRunControlEventType.TOOL_STARTED,
                    payload = mapOf(
                        "timeline_contract" to AgentRunTimelineContract.VERSION,
                        "timeline_kind" to "tool",
                        "tool_id" to call.toolName,
                        "status" to "running",
                        "synthetic_from_recorded_run" to true
                    ),
                    stepId = call.id,
                    toolCallId = call.id,
                    timestampMillis = call.startedAtMillis.takeIf { it > 0L } ?: run.createdAtMillis
                )
                events = agentRunEventStore.events(run.runId)
            }
            val hasCompletion = events.any {
                it.toolCallId == call.id && it.type == AgentRunControlEventType.TOOL_COMPLETED
            }
            if (!hasCompletion) {
                appendRunControlEvent(
                    run = run,
                    messageId = messageId,
                    taskId = taskId,
                    agentId = agentId,
                    type = AgentRunControlEventType.TOOL_COMPLETED,
                    payload = mapOf(
                        "timeline_contract" to AgentRunTimelineContract.VERSION,
                        "timeline_kind" to "tool",
                        "tool_id" to call.toolName,
                        "status" to call.status.name.lowercase(Locale.ROOT),
                        "synthetic_from_recorded_run" to true
                    ),
                    stepId = call.id,
                    toolCallId = call.id,
                    timestampMillis = call.completedAtMillis.takeIf { it > 0L }
                        ?: run.completedAtMillis.takeIf { it > 0L }
                        ?: System.currentTimeMillis()
                )
                events = agentRunEventStore.events(run.runId)
            }
        }
    }

    fun appendRunControlEvent(
        run: AgentRecordedRun,
        messageId: String,
        taskId: String,
        agentId: String,
        type: AgentRunControlEventType,
        payload: AgentNativeJsonObject = emptyMap(),
        stepId: String = "",
        toolCallId: String = "",
        timestampMillis: Long = System.currentTimeMillis()
    ) {
        val profile = AppStore.profile(context)
        agentRunEventStore.appendNext(
            AgentRunControlEvent(
                conversationId = run.conversationId,
                messageId = messageId,
                taskId = taskId,
                runId = run.runId,
                stepId = stepId,
                toolCallId = toolCallId,
                agentId = agentId,
                deviceId = profile.optString("device_id").ifBlank { profile.optString("galaxyssi_id") },
                type = type,
                sequence = 0L,
                timestampMillis = timestampMillis,
                payload = payload
            )
        )
    }
}
