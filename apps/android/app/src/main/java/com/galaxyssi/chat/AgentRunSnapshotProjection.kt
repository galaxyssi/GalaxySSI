package com.galaxyssi.chat

import org.json.JSONObject
import java.security.MessageDigest
import java.nio.ByteBuffer

internal data class AgentRunSnapshotProjection(
    val kind: String,
    val taskId: String,
    val messageId: String,
    val requestId: String
)

internal enum class AgentRunSnapshotLookup(val column: String) {
    TASK("task_hash"), MESSAGE("message_hash"), REQUEST("request_hash")
}

internal data class AgentRunSnapshotPage(
    val events: List<AgentRunControlEvent>,
    val nextBeforeOrdinal: Long?
)

/** Projection pointers reuse the authenticated event body; no second plaintext/body store. */
internal object AgentRunSnapshotContract {
    const val VOICE = "voice_agent_run"
    const val VOICE_PAYLOAD = "voice_agent_run_snapshot"

    fun describe(event: AgentRunControlEvent): AgentRunSnapshotProjection? {
        val raw = event.payload[VOICE_PAYLOAD] ?: return null
        require(raw is String) { "Invalid voice Run snapshot payload" }
        val snapshot = JSONObject(raw)
        require(snapshot.getString("run_id") == event.runId &&
            snapshot.getString("task_id") == event.taskId &&
            snapshot.getString("conversation_id") == event.conversationId &&
            snapshot.getLong("source_message_id").toString() == event.messageId) {
            "Run snapshot identity does not match its event"
        }
        require(snapshot.getString("turn_id").isNotBlank()) { "Run snapshot turn is missing" }
        val request = snapshot.getString("idempotency_key")
        require(request.isNotBlank()) { "Run snapshot request identity is missing" }
        return AgentRunSnapshotProjection(VOICE, event.taskId, event.messageId, request)
    }

    fun matches(event: AgentRunControlEvent, kind: String, lookup: AgentRunSnapshotLookup?, value: String): Boolean {
        val projection = describe(event) ?: return false
        if (projection.kind != kind) return false
        return when (lookup) {
            null -> event.runId == value
            AgentRunSnapshotLookup.TASK -> projection.taskId == value
            AgentRunSnapshotLookup.MESSAGE -> projection.messageId == value
            AgentRunSnapshotLookup.REQUEST -> projection.requestId == value
        }
    }

    fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))
        .joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }

    fun lookupHash(kind: String, lookup: AgentRunSnapshotLookup, value: String): String {
        val hash = MessageDigest.getInstance("SHA-256")
        listOf(kind, lookup.name, value).forEach { part ->
            val bytes = part.toByteArray(Charsets.UTF_8)
            hash.update(ByteBuffer.allocate(4).putInt(bytes.size).array())
            hash.update(bytes)
        }
        return hash.digest().joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
    }
}
