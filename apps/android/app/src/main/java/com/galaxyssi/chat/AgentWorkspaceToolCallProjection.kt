package com.galaxyssi.chat

import java.util.Locale
import org.json.JSONObject

/** A workspace indexes logical actions; native invocation receipts keep their own identity. */
internal object AgentWorkspaceToolCallProjection {
    fun actions(plan: AgentPlan?): List<AgentAction> =
        (plan?.actionHistory.orEmpty() + plan?.actions.orEmpty()).associateBy { it.id }.values.toList()

    fun records(actions: List<AgentAction>, result: AgentActionResult?): List<AgentToolCallRecord> =
        actions.filter { it.kind in setOf(AgentActionKind.CALL_NATIVE_TOOL, AgentActionKind.CALL_CONNECTOR) }
            .map { action ->
                val observed = result?.takeIf { it.actionId == action.id }
                val status = when (action.status) {
                    AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION -> AgentToolCallStatus.PENDING
                    AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE -> AgentToolCallStatus.RUNNING
                    AgentActionStatus.COMPLETED -> AgentToolCallStatus.SUCCEEDED
                    AgentActionStatus.FAILED, AgentActionStatus.BLOCKED, AgentActionStatus.ROLLED_BACK -> AgentToolCallStatus.FAILED
                }
                AgentToolCallRecord(
                    id = action.id,
                    toolName = action.parameters["tool_id"].orEmpty()
                        .ifBlank { action.parameters["connector_id"].orEmpty() }
                        .ifBlank { action.kind.name.lowercase(Locale.ROOT) },
                    status = status,
                    argumentsJson = action.parameters["input_json"].orEmpty()
                        .ifBlank { JSONObject(action.parameters).toString() },
                    resultJson = if (observed != null) observed.metadata["native_tool_output"].orEmpty()
                        .ifBlank { JSONObject(observed.metadata).put("message", observed.message).toString() }
                        else JSONObject().put("message", action.result).toString(),
                    errorMessage = if (status == AgentToolCallStatus.FAILED) action.result else "",
                    startedAtMillis = observed?.metadata?.get("started_at_millis")?.toLongOrNull() ?: 0L,
                    completedAtMillis = observed?.metadata?.get("completed_at_millis")?.toLongOrNull() ?: 0L
                )
            }

    fun merge(previous: List<AgentToolCallRecord>, incoming: List<AgentToolCallRecord>): List<AgentToolCallRecord> {
        val calls = previous.associateByTo(linkedMapOf()) { it.id }
        incoming.forEach { next ->
            val old = calls.remove(next.id)
            val sameAttempt = old != null && old.toolName == next.toolName &&
                (next.startedAtMillis == 0L || old.startedAtMillis == 0L || next.startedAtMillis == old.startedAtMillis)
            val sameState = sameAttempt && old?.status == next.status
            calls[next.id] = if (old == null) next else next.copy(
                argumentsJson = next.argumentsJson.ifBlank { old.argumentsJson },
                // Later history snapshots contain a summary, not a replacement observation.
                resultJson = if (sameState && isSummary(next.resultJson) && !isSummary(old.resultJson)) {
                    old.resultJson
                } else next.resultJson.ifBlank { if (sameState) old.resultJson else "" },
                startedAtMillis = next.startedAtMillis.takeIf { it > 0L }
                    ?: old.startedAtMillis.takeIf { old.toolName == next.toolName } ?: 0L,
                completedAtMillis = next.completedAtMillis.takeIf { it > 0L }
                    ?: old.completedAtMillis.takeIf { sameState } ?: 0L
            )
        }
        return calls.values.toList()
    }

    private fun isSummary(value: String): Boolean = value.isBlank() || runCatching {
        val json = JSONObject(value)
        json.keys().asSequence().all { it == "message" }
    }.getOrDefault(false)
}
