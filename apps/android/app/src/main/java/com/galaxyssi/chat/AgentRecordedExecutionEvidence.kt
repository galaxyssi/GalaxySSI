package com.galaxyssi.chat

import org.json.JSONObject
import java.util.Locale

/** Final run records retain execution facts, not the first plan snapshot or a completion paraphrase. */
internal object AgentRecordedExecutionEvidence {
    fun actions(plan: AgentPlan?, scope: AgentPlanContinuationScope): List<AgentAction> =
        AgentWorkspaceToolCallProjection.actions(plan).filter(scope::owns)

    fun calls(actions: List<AgentAction>, result: AgentActionResult?): List<AgentToolCallRecord> {
        val native = actions.filter { it.kind == AgentActionKind.CALL_NATIVE_TOOL }
        return native.zip(AgentWorkspaceToolCallProjection.records(native, result)).map { (action, call) ->
            val observed = result?.takeIf { it.actionId == action.id }
            val latest = observed?.let { AgentNativeActionObservation.evidence(it, Int.MAX_VALUE) }.orEmpty()
            val evidence = if (action.evidence.isNotBlank() && latest.startsWith(action.evidence)) latest
                else action.evidence
            val encoded = objectJson(evidence.ifBlank { call.resultJson }, "evidence", action.result)
            val status = if (call.status == AgentToolCallStatus.FAILED &&
                JSONObject(encoded).optString("status") == "cancelled") AgentToolCallStatus.CANCELLED else call.status
            call.copy(status = status, argumentsJson = objectJson(call.argumentsJson, "raw_input", ""),
                resultJson = encoded)
        }
    }

    fun lifecycle(call: AgentToolCallRecord): List<AgentRunControlEventType> = when (call.status) {
        AgentToolCallStatus.PENDING -> emptyList()
        AgentToolCallStatus.RUNNING -> listOf(AgentRunControlEventType.TOOL_STARTED)
        AgentToolCallStatus.SUCCEEDED, AgentToolCallStatus.FAILED, AgentToolCallStatus.CANCELLED -> buildList {
            val undispatched = runCatching { JSONObject(call.resultJson).opt("execution_started") == false }
                .getOrDefault(false)
            if (!undispatched) add(AgentRunControlEventType.TOOL_STARTED)
            add(AgentRunControlEventType.TOOL_COMPLETED)
        }
    }

    fun matches(call: AgentToolCallRecord, event: AgentRunControlEvent, type: AgentRunControlEventType): Boolean =
        event.type == type && (event.toolCallId == call.id ||
            event.stepId == call.id && event.payload["tool_id"] == call.toolName) &&
            (call.startedAtMillis <= 0L || event.timestampMillis >= call.startedAtMillis) &&
            (type != AgentRunControlEventType.TOOL_COMPLETED || completionMatches(call.status,
                event.payload["status"]?.toString().orEmpty().lowercase(Locale.ROOT)))

    private fun completionMatches(status: AgentToolCallStatus, value: String): Boolean = when (status) {
        AgentToolCallStatus.SUCCEEDED -> value in setOf("succeeded", "success", "completed")
        AgentToolCallStatus.FAILED -> value in setOf("failed", "verification_failed", "rejected", "unavailable", "timed_out")
        AgentToolCallStatus.CANCELLED -> value == "cancelled"
        AgentToolCallStatus.PENDING, AgentToolCallStatus.RUNNING -> false
    }

    private fun objectJson(value: String, rawKey: String, message: String): String = runCatching {
        JSONObject(value.ifBlank { "{}" }).toString()
    }.getOrElse { JSONObject().put("message", message).put(rawKey, value).toString() }
}
