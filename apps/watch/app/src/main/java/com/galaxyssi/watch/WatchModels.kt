package com.galaxyssi.watch

import org.json.JSONObject
import java.util.UUID

enum class TaskState {
    QUEUED, SENT, ACCEPTED, RUNNING, WAITING_APPROVAL, STOP_REQUESTED, COMPLETED, FAILED, CANCELLED;
    val terminal: Boolean get() = this in setOf(COMPLETED, FAILED, CANCELLED)
}

data class WatchTask(
    val id: String,
    val desktopId: String,
    val routeId: String,
    val agentId: String,
    val conversationId: String,
    val turnId: String,
    val messageId: String,
    val sourceId: Long,
    val prompt: String,
    val reply: String = "",
    val state: TaskState = TaskState.QUEUED,
    val sequence: Long = -1,
    val progress: String = "",
    val localOperation: String = "",
    val location: String = "",
    val remoteTaskId: String = "",
    val executionGeneration: Long = 1
) {
    val contactId: String get() = "$desktopId:$agentId"
    fun json(): JSONObject = JSONObject().put("id", id).put("desktop", desktopId)
        .put("route", routeId).put("agent", agentId).put("conversation", conversationId)
        .put("turn", turnId).put("message", messageId).put("source", sourceId)
        .put("prompt", prompt).put("reply", reply).put("state", state.name)
        .put("sequence", sequence).put("progress", progress).put("local_operation", localOperation).put("location", location)
        .put("remote_task_id", remoteTaskId)
        .put("execution_generation", executionGeneration)

    fun request(language: String): JSONObject = JSONObject().put("type", "text")
        .put("message_id", messageId).put("content", prompt).put("contact_id", contactId)
        .put("desktop_id", desktopId).put("agent_id", agentId).put("client_route_id", routeId)
        .put("task_id", id).put("conversation_id", conversationId).put("turn_id", turnId)
        .put("client_message_id", sourceId).put("source_message_id", sourceId)
        .put("response_language", language).put("time", sourceId)

    /** A desktop may allocate its task ID; source/turn/route remain the client's identity. */
    fun matches(endpoint: String, payload: JSONObject): Boolean {
        if (endpoint != desktopId || payload.optString("client_route_id") != routeId ||
            payload.optString("conversation_id") != conversationId || payload.optString("turn_id") != turnId) return false
        if (payload.optString("agent_id").let { it.isNotBlank() && it != agentId }) return false
        if (payload.optString("contact_id").let { it.isNotBlank() && it != contactId }) return false
        val remote = payload.optString("task_id")
        if (remote.isBlank() || (remoteTaskId.isNotEmpty() && remote != remoteTaskId)) return false
        if (payload.has("source_message_id") && payload.optString("source_message_id") != sourceId.toString()) return false
        return remote == id || payload.optString("source_message_id") == sourceId.toString()
    }

    /** Authenticated routing is checked before any state or content is accepted. */
    fun reduce(endpoint: String, payload: JSONObject): WatchTask {
        if (!matches(endpoint, payload)) return this
        val version = com.galaxyssi.chat.AgentRemoteOutcomeCodec.version(payload) ?: return this
        if (!com.galaxyssi.chat.AgentRemoteExecutionVersion(executionGeneration, sequence).accepts(version)) return this
        val type = payload.optString("type")
        val content = if (payload.optString("exact_content_encoding") == "base64-utf8" &&
            payload.optString("exact_content_b64").length in 1..256 * 1024) runCatching {
                String(java.util.Base64.getDecoder().decode(payload.getString("exact_content_b64")), Charsets.UTF_8)
            }.getOrDefault(payload.optString("content")) else payload.optString("content")
        if (type == "text" && content.isNotBlank()) {
            val outcome = when (payload.optString("task_status")) {
                "failed", "timed_out" -> TaskState.FAILED
                "cancelled", "canceled" -> TaskState.CANCELLED
                else -> TaskState.COMPLETED
            }
            return copy(reply = content.take(32_000), state = outcome, remoteTaskId = payload.getString("task_id"),
                executionGeneration = version.generation, sequence = maxOf(sequence, version.sequence))
        }
        if ((state.terminal && version.generation <= executionGeneration) || type != "agent_task_event") return this
        val seq = payload.optLong("status_seq", -1)
        if (version.generation == executionGeneration && seq >= 0 && seq <= sequence) return this
        val next = when (payload.optString("task_status")) {
            "completed", "succeeded", "done" -> TaskState.COMPLETED
            "failed", "error", "timed_out" -> TaskState.FAILED
            "cancelled", "canceled" -> TaskState.CANCELLED
            "waiting_approval", "awaiting_approval", "approval_required" -> TaskState.WAITING_APPROVAL
            else -> if (state == TaskState.STOP_REQUESTED) state else TaskState.RUNNING
        }
        return copy(state = next, sequence = if (version.generation > executionGeneration) seq else maxOf(sequence, seq),
            remoteTaskId = payload.getString("task_id"), executionGeneration = version.generation,
            progress = payload.optString("current_step").ifBlank { payload.optString("error") }.take(2000),
            reply = payload.optString("result").ifBlank { reply }.take(32_000))
    }

    companion object {
        fun create(desktop: String, route: String, agent: String, prompt: String,
            conversation: String = UUID.randomUUID().toString()): WatchTask {
            require(prompt.isNotBlank() && prompt.length <= 4000)
            require(desktop.isNotBlank() && route.isNotBlank() && agent.isNotBlank())
            return WatchTask(UUID.randomUUID().toString(), desktop, route, agent, conversation,
                UUID.randomUUID().toString(), UUID.randomUUID().toString(), System.currentTimeMillis(), prompt.trim())
        }
        fun fromJson(j: JSONObject) = WatchTask(j.getString("id"), j.getString("desktop"),
            j.getString("route"), j.getString("agent"), j.getString("conversation"),
            j.getString("turn"), j.getString("message"), j.getLong("source"), j.getString("prompt"),
            j.optString("reply"), TaskState.valueOf(j.getString("state")), j.optLong("sequence", -1), j.optString("progress"), j.optString("local_operation"), j.optString("location"), j.optString("remote_task_id"), j.optLong("execution_generation", 1))
    }
}

data class WatchAgent(val desktopId: String, val id: String, val name: String, val available: Boolean)

enum class ConnectionState { DISCONNECTED, CONNECTING, BROKER_CONNECTED, ERROR }
