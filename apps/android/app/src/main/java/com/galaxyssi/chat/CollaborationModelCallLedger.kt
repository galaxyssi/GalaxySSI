package com.galaxyssi.chat

import android.content.Context
import com.galaxyssi.chat.voice.modelstream.ModelCallAuditSink
import org.json.JSONObject

/** Host-only accounting, deliberately separate from model-authored evidence and prompt context. */
internal class CollaborationModelCallLedger(
    private val rows: CollaborationWorkspaceRows,
    private val authorized: (CollaborationWorkspaceAccess) -> Boolean = { true }
) {
    constructor(context: Context) : this(object : CollaborationWorkspaceRows {
        private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)
        override fun read(key: String) = database.readString(key, "").takeIf(String::isNotBlank)
        override fun commit(values: Map<String, String>) = database.mutateStrings(values)
        override fun page(prefix: String, after: String, limit: Int) = database.keysAfter(prefix, after, limit)
    }, { access -> CollaborationEvidenceLedger(context.applicationContext).authorizes(access) })

    fun sink(access: CollaborationWorkspaceAccess): ModelCallAuditSink {
        require(listOf(access.groupId, access.runId, access.turnId, access.nodeId, access.personId).all(String::isNotBlank))
        return ModelCallAuditSink { receipt -> synchronized(LOCK) {
            check(authorized(access)) { "Model accounting access revoked" }
            val id = receipt.getString("call_id")
            require(ID.matches(id) && receipt.getString("format") == "galaxyssi.model-call.v1")
            val key = prefix(access.groupId, access.runId) + id
            val initialKey = "$key:admission"
            val old = rows.read(key)?.let(::JSONObject)
            val payload = JSONObject(receipt.toString()).put("group_id", access.groupId).put("run_id", access.runId)
                .put("turn_id", access.turnId).put("round", access.round).put("node_id", access.nodeId).put("person_id", access.personId)
            val initial = rows.read(initialKey)?.let(::JSONObject)
            if (initial == null) {
                check(old == null && payload.getString("status") == "started") { "Model admission receipt is missing" }
                rows.commit(mapOf(key to payload.toString(), initialKey to payload.toString()))
            } else {
                listOf("call_id", "request_id", "provider", "transport", "requested_model", "request_sha256", "started_at",
                    "group_id", "run_id", "turn_id", "round", "node_id", "person_id").forEach {
                    val same = if (it == "round" || it == "started_at") initial.getLong(it) == payload.getLong(it)
                        else initial.get(it) == payload.get(it)
                    check(same) { "Model call identity changed: $it" }
                }
                check(old != null) { "Model receipt index is incomplete" }
                if (old.toString() != payload.toString()) {
                    check(old.getString("status") == "started" && payload.getString("status") in TERMINAL) {
                        "A settled model receipt is immutable"
                    }
                    rows.commit(mapOf(key to payload.toString()))
                }
            }
        } }
    }

    /** Local export only. Entries left at started remain unknown after process death. */
    fun page(group: String, run: String, after: String = ""): Pair<List<JSONObject>, String?> = synchronized(LOCK) {
        require(group.isNotBlank() && run.isNotBlank())
        val prefix = prefix(group, run)
        require(after.isEmpty() || after.startsWith(prefix) && ID.matches(after.removePrefix(prefix)))
        // Admission records sort directly after their call. Read two rows per call, plus lookahead.
        val keys = rows.page(prefix, after, 202).filterNot { it.endsWith(":admission") }
        val selected = keys.take(100)
        selected.map { key -> JSONObject(requireNotNull(rows.read(key))) } to
            selected.lastOrNull()?.takeIf { keys.size > selected.size }
    }

    companion object {
        private const val DATABASE = "galaxyssi_collaboration_model_calls_v1"
        private val LOCK = Any()
        private val ID = Regex("[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}")
        private val TERMINAL = setOf("completed", "failed", "cancelled", "interrupted")
        private fun groupPrefix(group: String) = "group:${AgentNativeJsonCodec.sha256(group)}:"
        private fun prefix(group: String, run: String) = groupPrefix(group) + "run:${AgentNativeJsonCodec.sha256(run)}:"
        fun remove(context: Context, group: String) = synchronized(LOCK) {
            val db = AgentEncryptedDatabase(context.applicationContext, DATABASE)
            db.mutateStrings(emptyMap(), db.keys(groupPrefix(group)))
        }
    }
}
