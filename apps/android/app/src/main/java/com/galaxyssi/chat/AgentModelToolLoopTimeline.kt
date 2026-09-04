package com.galaxyssi.chat

import java.util.Locale

internal enum class AgentModelToolTimelineText {
    MODEL_REASONING,
    MODEL_SELECTED_TOOLS,
    MODEL_PREPARED_STEP,
    TOOL_RUNNING,
    TOOL_PROGRESS,
    TOOL_SUCCEEDED,
    TOOL_FAILED,
    TOOL_RETRYING,
    TOOL_WAITING,
    MODEL_LOOP_STOPPED
}

internal data class AgentModelToolTimelineProjection(
    val controlEventType: AgentRunControlEventType,
    val timelineKind: AgentRunTimelineKind,
    val stepId: String,
    val toolCallId: String,
    val toolId: String,
    val dedupeSuffix: String,
    val text: AgentModelToolTimelineText?,
    val detail: String,
    val count: Int,
    val payload: AgentNativeJsonObject
)

/**
 * Projects the model-owned tool loop into the same durable timeline used by
 * native and remote execution. Model prompts and hidden reasoning never enter
 * the projection; only lifecycle state and locally verified tool outcomes do.
 */
internal object AgentModelToolLoopTimelinePolicy {
    fun project(event: AgentModelToolLoopEvent): AgentModelToolTimelineProjection {
        val toolId = event.details["tool_id"]?.toString().orEmpty()
        val status = event.details["status"]?.toString().orEmpty()
        val primaryDetail = listOf("message", "error_code", "code", "stage")
            .asSequence()
            .mapNotNull { key -> event.details[key]?.toString()?.trim() }
            .firstOrNull(String::isNotBlank)
            .orEmpty()
        val percent = (event.details["percent"] as? Number)?.toInt()?.coerceIn(0, 100)
        val detail = listOfNotNull(
            primaryDetail.takeIf(String::isNotBlank),
            percent?.let { "$it%" }
        ).joinToString(" · ").take(MAX_DETAIL_CHARACTERS)
        val toolCount = event.details["tool_call_count"].asInt()
        val controlType = when (event.type) {
            AgentModelToolLoopEventType.LOOP_STARTED,
            AgentModelToolLoopEventType.MODEL_REQUESTED -> AgentRunControlEventType.THINKING
            AgentModelToolLoopEventType.MODEL_RESPONDED,
            AgentModelToolLoopEventType.TOOL_CALL_REJECTED,
            AgentModelToolLoopEventType.APPROVAL_DECIDED,
            AgentModelToolLoopEventType.BUDGET_EXCEEDED,
            AgentModelToolLoopEventType.LOOP_DETECTED,
            AgentModelToolLoopEventType.LOOP_CANCELLED,
            AgentModelToolLoopEventType.LOOP_FAILED,
            AgentModelToolLoopEventType.LOOP_COMPLETED -> AgentRunControlEventType.STEP_COMPLETED
            AgentModelToolLoopEventType.TOOL_CALL_PROPOSED -> AgentRunControlEventType.STEP_STARTED
            AgentModelToolLoopEventType.APPROVAL_REQUIRED ->
                AgentRunControlEventType.TOOL_PERMISSION_REQUIRED
            AgentModelToolLoopEventType.LOOP_RESUMED,
            AgentModelToolLoopEventType.TOOL_RETRY_SCHEDULED -> AgentRunControlEventType.RETRYING
            AgentModelToolLoopEventType.TOOL_STARTED -> AgentRunControlEventType.TOOL_STARTED
            AgentModelToolLoopEventType.TOOL_PROGRESS -> AgentRunControlEventType.TOOL_STARTED
            AgentModelToolLoopEventType.TOOL_FINISHED -> AgentRunControlEventType.TOOL_COMPLETED
        }
        val timelineKind = when (event.type) {
            AgentModelToolLoopEventType.LOOP_STARTED,
            AgentModelToolLoopEventType.MODEL_REQUESTED -> AgentRunTimelineKind.PLAN
            AgentModelToolLoopEventType.MODEL_RESPONDED,
            AgentModelToolLoopEventType.TOOL_CALL_REJECTED,
            AgentModelToolLoopEventType.APPROVAL_DECIDED,
            AgentModelToolLoopEventType.BUDGET_EXCEEDED,
            AgentModelToolLoopEventType.LOOP_DETECTED,
            AgentModelToolLoopEventType.LOOP_CANCELLED,
            AgentModelToolLoopEventType.LOOP_FAILED,
            AgentModelToolLoopEventType.LOOP_COMPLETED -> AgentRunTimelineKind.OBSERVE
            AgentModelToolLoopEventType.TOOL_CALL_PROPOSED -> AgentRunTimelineKind.ACT
            AgentModelToolLoopEventType.APPROVAL_REQUIRED -> AgentRunTimelineKind.OTHER
            AgentModelToolLoopEventType.LOOP_RESUMED,
            AgentModelToolLoopEventType.TOOL_RETRY_SCHEDULED -> AgentRunTimelineKind.RETRY
            AgentModelToolLoopEventType.TOOL_STARTED,
            AgentModelToolLoopEventType.TOOL_PROGRESS,
            AgentModelToolLoopEventType.TOOL_FINISHED -> AgentRunTimelineKind.TOOL
        }
        val text = when (event.type) {
            AgentModelToolLoopEventType.MODEL_REQUESTED -> AgentModelToolTimelineText.MODEL_REASONING
            AgentModelToolLoopEventType.MODEL_RESPONDED -> if (toolCount > 0) {
                AgentModelToolTimelineText.MODEL_SELECTED_TOOLS
            } else {
                AgentModelToolTimelineText.MODEL_PREPARED_STEP
            }
            AgentModelToolLoopEventType.TOOL_STARTED -> AgentModelToolTimelineText.TOOL_RUNNING
            AgentModelToolLoopEventType.TOOL_PROGRESS -> AgentModelToolTimelineText.TOOL_PROGRESS
            AgentModelToolLoopEventType.TOOL_FINISHED -> if (status == SUCCESS_STATUS) {
                AgentModelToolTimelineText.TOOL_SUCCEEDED
            } else {
                AgentModelToolTimelineText.TOOL_FAILED
            }
            AgentModelToolLoopEventType.TOOL_RETRY_SCHEDULED ->
                AgentModelToolTimelineText.TOOL_RETRYING
            AgentModelToolLoopEventType.APPROVAL_REQUIRED -> AgentModelToolTimelineText.TOOL_WAITING
            AgentModelToolLoopEventType.TOOL_CALL_REJECTED -> AgentModelToolTimelineText.TOOL_FAILED
            AgentModelToolLoopEventType.BUDGET_EXCEEDED,
            AgentModelToolLoopEventType.LOOP_DETECTED,
            AgentModelToolLoopEventType.LOOP_CANCELLED,
            AgentModelToolLoopEventType.LOOP_FAILED -> AgentModelToolTimelineText.MODEL_LOOP_STOPPED
            AgentModelToolLoopEventType.LOOP_STARTED,
            AgentModelToolLoopEventType.TOOL_CALL_PROPOSED,
            AgentModelToolLoopEventType.APPROVAL_DECIDED,
            AgentModelToolLoopEventType.LOOP_RESUMED,
            AgentModelToolLoopEventType.LOOP_COMPLETED -> null
        }
        val stableToolCallId = event.toolCallId.orEmpty().ifBlank { event.invocationId.orEmpty() }
        val dedupeSuffix = when {
            stableToolCallId.isNotBlank() -> "tool:$stableToolCallId"
            event.type == AgentModelToolLoopEventType.MODEL_REQUESTED ||
                event.type == AgentModelToolLoopEventType.MODEL_RESPONDED -> "round:${event.round}"
            event.type in TERMINAL_MODEL_EVENTS -> "terminal"
            else -> "event:${event.sequence}"
        }
        return AgentModelToolTimelineProjection(
            controlEventType = controlType,
            timelineKind = timelineKind,
            stepId = stableToolCallId.ifBlank { "model-round-${event.round}" },
            toolCallId = stableToolCallId,
            toolId = toolId,
            dedupeSuffix = dedupeSuffix,
            text = text,
            detail = detail,
            count = toolCount,
            payload = buildMap {
                put("timeline_contract", AgentRunTimelineContract.VERSION)
                put("timeline_kind", timelineKind.name.lowercase(Locale.ROOT))
                put("model_tool_loop", true)
                put("model_event_type", event.type.name.lowercase(Locale.ROOT))
                put("model_round", event.round)
                put("model_sequence", event.sequence)
                put("model_turn_id", event.turnId)
                put("model_task_id", event.taskId)
                put("tool_manifest_sha256", event.toolManifestSha256)
                if (toolId.isNotBlank()) put("tool_id", toolId)
                if (event.toolCallId != null) put("model_tool_call_id", event.toolCallId)
                if (event.invocationId != null) put("invocation_id", event.invocationId)
                event.details.forEach { (key, value) ->
                    if (key !in SENSITIVE_DETAIL_KEYS && value != null) put(key, value)
                }
            }
        )
    }

    private fun Any?.asInt(): Int = when (this) {
        is Number -> toInt()
        else -> toString().toIntOrNull() ?: 0
    }

    private val TERMINAL_MODEL_EVENTS = setOf(
        AgentModelToolLoopEventType.BUDGET_EXCEEDED,
        AgentModelToolLoopEventType.LOOP_DETECTED,
        AgentModelToolLoopEventType.LOOP_CANCELLED,
        AgentModelToolLoopEventType.LOOP_FAILED
    )
    private val SENSITIVE_DETAIL_KEYS = setOf("arguments", "input", "prompt", "assistant_text")
    private const val SUCCESS_STATUS = "succeeded"
    private const val MAX_DETAIL_CHARACTERS = 240
}
