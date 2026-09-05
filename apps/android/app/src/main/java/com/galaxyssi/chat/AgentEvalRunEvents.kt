package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import java.util.UUID

internal object AgentEvalRunEvents {
    const val OBSERVER = "galaxyssi-eval-observer"

    fun append(context: Context, run: AgentRecordedRun, type: AgentRunControlEventType,
        payload: AgentNativeJsonObject): Boolean = runCatching {
        val store = AgentRunEventStore(context)
        store.appendNext(create(run, store.latestEvent(run.runId), type, payload)) != null
    }.onFailure {
        // Do not log private requests, raw Run ids or exception messages.
        Log.w("AgentEvalRecovery", "event_append_failed:${it.javaClass.simpleName}")
    }.getOrDefault(false)

    fun create(run: AgentRecordedRun, previous: AgentRunControlEvent?, type: AgentRunControlEventType,
        payload: AgentNativeJsonObject): AgentRunControlEvent {
        require(run.runId.isNotBlank()) { "Evaluation Run identity is missing" }
        val id = UUID.randomUUID().toString()
        val observation = payload + mapOf("observation_only" to true,
            "execution_resource_unassigned" to run.executionResourceId.isBlank())
        if (previous != null) {
            require(previous.runId == run.runId) { "Evaluation Run identity mismatch" }
            return previous.copy(eventId = id, idempotencyKey = id, actionId = "eval:$id",
                stepId = "", toolCallId = "", type = type, sequence = 0L,
                timestampMillis = System.currentTimeMillis(), payload = observation)
        }
        return AgentRunKernelContract.canonical(AgentRunControlEvent(
            eventId = id, conversationId = run.conversationId, messageId = run.runId,
            taskId = run.taskThreadId.ifBlank { "eval-task:${run.runId}" }, runId = run.runId,
            agentId = run.executionResourceId.trim().ifBlank { OBSERVER }, deviceId = "local",
            type = type, sequence = 0L, payload = observation))
    }
}
