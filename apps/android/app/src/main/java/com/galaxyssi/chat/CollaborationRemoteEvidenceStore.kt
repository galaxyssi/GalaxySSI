package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal interface CollaborationRemoteEvidenceRows {
    fun read(key: String): String?
    fun mutate(values: Map<String, String>, remove: List<String> = emptyList())
    fun keys(prefix: String, after: String = "", limit: Int = 100): List<String>
}

/** Intent, one active descriptor and verified pages survive process death independently of the model. */
internal class CollaborationRemoteEvidenceStore(private val rows: CollaborationRemoteEvidenceRows) {
    constructor(context: Context) : this(object : CollaborationRemoteEvidenceRows {
        private val db = AgentEncryptedDatabase(context.applicationContext, DATABASE)
        override fun read(key: String) = db.readString(key, "").takeIf(String::isNotBlank)
        override fun mutate(values: Map<String, String>, remove: List<String>) = db.mutateStrings(values, remove)
        override fun keys(prefix: String, after: String, limit: Int) = db.keysAfter(prefix, after, limit)
    })

    fun create(desktop: String, fields: JSONObject, access: CollaborationWorkspaceAccess): String =
        createIntent(desktop, fields, access).first

    fun createIntent(desktop: String, fields: JSONObject, access: CollaborationWorkspaceAccess,
        terminal: Boolean = true): Pair<String, Boolean> = synchronized(LOCK) {
        require(CollaborationRemoteEvidenceProtocol.validScope(fields) && desktop.isNotBlank() &&
            access.groupId == fields.getString("conversation_id") && access.turnId == fields.getString("turn_id"))
        val scope = CollaborationRemoteEvidenceProtocol.scope(fields)
        val key = sourcePrefix(access.groupId, fields.getString("source_message_id")) +
            AgentNativeJsonCodec.sha256(JSONArray(listOf(desktop) + AgentResultRecoveryClient.identity(scope) +
                scope.getLong("execution_generation")).toString())
        val existing = rows.read(key)?.let(::JSONObject)
        var wake = existing == null
        if (existing == null) {
            val job = JSONObject().put("desktop", desktop).put("fields", scope).put("run_id", access.runId)
                .put("node_id", access.nodeId).put("status", "pending").put("cursor", 0).put("imported", 0)
                .put("skipped_large", 0).put("provider_history_complete", false).put("terminal_requested", terminal)
            rows.mutate(mapOf(key to job.toString(), pendingKey(key) to key))
        } else {
            require(existing.getString("run_id") == access.runId && existing.getString("node_id") == access.nodeId)
            val upgrade = terminal && !existing.optBoolean("terminal_requested", true)
            if (upgrade) existing.put("terminal_requested", true)
            if (existing.optString("status") in SNAPSHOT_STATUSES) {
                existing.put("status", "pending").remove("index_complete")
                wake = true
            }
            if (upgrade || wake) writeJob(key, existing)
        }
        key to wake
    }

    fun read(key: String): JSONObject? = synchronized(LOCK) { rows.read(key)?.let(::JSONObject) }
    fun save(key: String, value: JSONObject) = synchronized(LOCK) {
        if (rows.read(key) != null) writeJob(key, value)
    }

    /** A terminal notification can arrive while a live snapshot is importing. Never lose that demand. */
    fun completeSnapshot(key: String, value: JSONObject): Boolean = synchronized(LOCK) {
        val latest = rows.read(key)?.let(::JSONObject) ?: return true
        if (latest.optString("status") != "pending") return true
        val sealed = value.optBoolean("archive_final")
        val terminal = latest.optBoolean("terminal_requested", true)
        val status = when {
            terminal && !sealed -> "pending"
            sealed && value.getLong("skipped_large") == 0L -> "imported"
            sealed -> "partial_large_objects"
            value.getLong("skipped_large") == 0L -> "snapshot_imported"
            else -> "snapshot_partial_large_objects"
        }
        value.put("status", status).put("snapshot_at", System.currentTimeMillis())
        if (status == "pending") value.remove("index_complete")
        writeJob(key, value)
        status != "pending"
    }

    private fun writeJob(key: String, value: JSONObject, remove: List<String> = emptyList()) {
        val latest = rows.read(key)?.let(::JSONObject) ?: return
        if (value.optString("status") == "pending" && latest.optString("status") != "pending" &&
            latest.optString("status") !in SNAPSHOT_STATUSES) return
        val copy = JSONObject(value.toString()).put("terminal_requested",
            latest.optBoolean("terminal_requested", true) || value.optBoolean("terminal_requested", true))
        val values = mutableMapOf(key to copy.toString())
        if (copy.optString("status") == "pending") values[pendingKey(key)] = key
        rows.mutate(values, remove + if (copy.optString("status") != "pending") listOf(pendingKey(key)) else emptyList())
    }
    fun pending(after: String = ""): List<Pair<String, String>> = synchronized(LOCK) {
        rows.keys("pending:", after, 20).mapNotNull { index -> rows.read(index)?.let { index to it } }
    }
    fun schedulerCursor(): String = synchronized(LOCK) { rows.read("scheduler:cursor").orEmpty() }
    fun schedulerCursor(value: String) = synchronized(LOCK) { rows.mutate(mapOf("scheduler:cursor" to value)) }
    fun states(group: String, source: Long): List<JSONObject> = synchronized(LOCK) {
        val prefix = sourcePrefix(group, source.toString())
        buildList {
            var cursor = ""
            do {
                val keys = rows.keys(prefix, cursor)
                keys.filter { ":page:" !in it }.mapNotNull { rows.read(it)?.let(::JSONObject) }.forEach(::add)
                cursor = keys.lastOrNull().orEmpty()
            } while (keys.size == 100)
        }
    }
    fun page(key: String, descriptor: JSONObject, index: Int): JSONObject? = synchronized(LOCK) {
        rows.read(pageKey(key, descriptor, index))?.let(::JSONObject)
    }
    fun savePage(key: String, descriptor: JSONObject, index: Int, page: JSONObject) = synchronized(LOCK) {
        if (rows.read(key) != null) {
            // Persist only fields validated by the page codec; transport nonces are not evidence.
            val copy = JSONObject()
            listOf("status", "page_index", "sha256", "page_count", "total_bytes", "data_b64", "page_sha256")
                .forEach { copy.put(it, page.get(it)) }
            rows.mutate(mapOf(pageKey(key, descriptor, index) to copy.toString()))
        }
    }
    fun advance(key: String, value: JSONObject, descriptor: JSONObject, imported: Boolean) = synchronized(LOCK) {
        value.put("cursor", descriptor.getLong("sequence")).remove("active")
        val counter = if (imported) "imported" else "skipped_large"
        value.put(counter, value.getLong(counter) + 1)
        if (rows.read(key) != null) writeJob(key, value, pageKeys(key, descriptor))
    }
    private fun pageKeys(key: String, descriptor: JSONObject): List<String> = buildList {
        val prefix = pagePrefix(key, descriptor)
        var cursor = ""
        do {
            val batch = rows.keys(prefix, cursor)
            addAll(batch); cursor = batch.lastOrNull().orEmpty()
        } while (batch.size == 100)
    }
    fun remove(group: String) = synchronized(LOCK) {
        val prefix = groupPrefix(group)
        while (true) {
            val keys = rows.keys(prefix)
            if (keys.isEmpty()) break
            rows.mutate(emptyMap(), keys + keys.filter { ":page:" !in it }.map(::pendingKey))
        }
    }

    companion object {
        private val LOCK = Any()
        private val SNAPSHOT_STATUSES = setOf("snapshot_imported", "snapshot_partial_large_objects")
        private const val DATABASE = "collaboration_remote_evidence_v1"
        private fun groupPrefix(group: String) = "group:${AgentNativeJsonCodec.sha256(group)}:"
        private fun sourcePrefix(group: String, source: String) = groupPrefix(group) + "source:$source:"
        private fun pendingKey(key: String) = "pending:${AgentNativeJsonCodec.sha256(key)}"
        private fun pagePrefix(key: String, descriptor: JSONObject) = key.substringBefore(":source:") +
            ":page:${AgentNativeJsonCodec.sha256(key)}:${descriptor.getString("sha256")}:"
        private fun pageKey(key: String, descriptor: JSONObject, index: Int) =
            pagePrefix(key, descriptor) + index.toString().padStart(8, '0')
    }
}
