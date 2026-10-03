package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal class CollaborationEvidenceAccessRevoked : IllegalStateException("Group access was removed")

internal enum class CollaborationEvidenceOrigin(val wireValue: String) {
    ANDROID_CLOUD_TOOL("android_cloud_tool"), ANDROID_NATIVE_TOOL("android_native_tool"),
    DESKTOP_CODEX_TOOL("desktop_codex_tool")
}

/** Host observations establish what ran and what it returned, never the truth of a model's conclusion. */
internal class CollaborationEvidenceLedger(
    private val rows: CollaborationWorkspaceRows,
    private val authorized: (String) -> Boolean = { true }
) {
    constructor(context: Context) : this(object : CollaborationWorkspaceRows {
        private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)
        override fun read(key: String) = database.readString(key, "").takeIf(String::isNotBlank)
        override fun commit(values: Map<String, String>) = database.mutateStrings(values)
        override fun page(prefix: String, after: String, limit: Int) = database.keysAfter(prefix, after, limit)
    }, { group -> CollaborationGroupStore(context.applicationContext).load(group) != null })

    fun bind(source: Long, access: CollaborationWorkspaceAccess) = synchronized(LOCK) {
        require(source > 0 && access.nodeId.isNotBlank() && access.personId.isNotBlank() &&
            access.runId.isNotBlank() && access.turnId.isNotBlank())
        if (!authorized(access.groupId)) throw CollaborationEvidenceAccessRevoked()
        val key = prefix(access.groupId) + "binding:$source"
        val value = identity(access).put("dependencies", JSONArray(access.dependencyNodes.sorted())).toString()
        val existing = rows.read(key)
        check(existing == null || existing == value) { "Research dispatch identity changed" }
        val accessKey = prefix(access.groupId) + "access:" + digest(value)
        val indexedSource = rows.read(accessKey)
        if (indexedSource != null) {
            check(indexedSource.toLongOrNull()?.let { rows.read(prefix(access.groupId) + "binding:$it") } == value) {
                "Research dispatch access index is corrupt"
            }
        }
        val writes = linkedMapOf<String, String>()
        if (existing == null) writes[key] = value
        if (indexedSource == null) writes[accessKey] = source.toString()
        if (writes.isNotEmpty()) rows.commit(writes)
    }

    fun authorizes(access: CollaborationWorkspaceAccess): Boolean = synchronized(LOCK) {
        if (!authorized(access.groupId)) return@synchronized false
        val value = identity(access).put("dependencies", JSONArray(access.dependencyNodes.sorted())).toString()
        val source = rows.read(prefix(access.groupId) + "access:" + digest(value))?.toLongOrNull()
            ?.takeIf { it > 0 } ?: return@synchronized false
        rows.read(prefix(access.groupId) + "binding:$source") == value
    }

    fun binding(source: Long, group: String, turn: String): CollaborationWorkspaceAccess? = synchronized(LOCK) {
        if (source <= 0 || !authorized(group)) return@synchronized null
        val json = rows.read(prefix(group) + "binding:$source")?.let(::JSONObject) ?: return@synchronized null
        if (json.getString("group_id") != group || json.getString("turn_id") != turn) return@synchronized null
        val dependencies = json.getJSONArray("dependencies")
        CollaborationWorkspaceAccess(group, json.getString("run_id"), turn, json.getLong("round"),
            json.getString("node_id"), json.getString("person_id"),
            (0 until dependencies.length()).mapTo(linkedSetOf()) { dependencies.getString(it) })
    }

    fun record(access: CollaborationWorkspaceAccess, invocationId: String, tool: String, input: String,
               output: String, started: Long, finished: Long,
               origin: CollaborationEvidenceOrigin = CollaborationEvidenceOrigin.ANDROID_CLOUD_TOOL): JSONObject = synchronized(LOCK) {
        if (!authorized(access.groupId)) throw CollaborationEvidenceAccessRevoked()
        require(access.runId.isNotBlank() && access.turnId.isNotBlank() && access.nodeId.isNotBlank() &&
            access.personId.isNotBlank() && invocationId.isNotBlank() && tool.isNotBlank())
        require(finished >= started && started >= 0)
        val parsed = runCatching { JSONObject(output) }.getOrNull()
        val status = when {
            parsed == null -> "unstructured"
            parsed.optString("status") in setOf("failed", "error", "cancelled", "timed_out", "unavailable", "rejected", "verification_failed") ||
                parsed.opt("error")?.let { it != JSONObject.NULL && it.toString().isNotBlank() } == true -> "failed"
            else -> "returned"
        }
        val id = digest(JSONArray(listOf(access.runId, access.nodeId, invocationId)).toString())
        val payload = identity(access).put("evidence_id", id).put("invocation_id", invocationId)
            .put("tool", tool).put("status", status).put("origin", origin.wireValue)
            .put("observation_kind", if (tool == ResearchEvidenceAudit.TOOL) "member_assessment_recorded" else "tool_output_recorded")
            .put("input_json", input).put("output_json", output)
            .put("input_sha256", digest(input)).put("output_sha256", digest(output))
            .put("started_at", started).put("finished_at", finished)
            .put("trust", "execution_observed_not_claim_verified").toString()
        val hash = digest(payload)
        val key = prefix(access.groupId) + "observation:$id"
        val envelope = JSONObject().put("payload", payload).put("sha256", hash).toString()
        val previous = rows.read(key)
        check(previous == null || previous == envelope) { "An evidence invocation cannot change its recorded outcome" }
        if (previous == null) rows.commit(mapOf(key to envelope))
        reference(JSONObject(payload), hash)
    }

    fun read(access: CollaborationWorkspaceAccess, id: String, expectedHash: String = ""): JSONObject? = synchronized(LOCK) {
        if (!authorized(access.groupId) || !id.matches(ID)) return@synchronized null
        val envelope = rows.read(prefix(access.groupId) + "observation:$id")?.let(::JSONObject) ?: return@synchronized null
        val raw = envelope.getString("payload")
        val hash = envelope.getString("sha256")
        check(digest(raw) == hash) { "Research evidence integrity check failed" }
        if (expectedHash.isNotBlank() && expectedHash != hash) return@synchronized null
        val payload = JSONObject(raw)
        check(payload.getString("evidence_id") == id && digest(payload.getString("input_json")) == payload.getString("input_sha256") &&
            digest(payload.getString("output_json")) == payload.getString("output_sha256")) { "Research evidence identity or content changed" }
        payload.takeIf(access::canRead)?.put("sha256", hash)
    }

    data class EvidencePage(val source: JSONObject, val content: String, val total: Int, val next: Int?, val coverage: JSONObject)

    fun readPage(access: CollaborationWorkspaceAccess, id: String, expectedHash: String = "", offset: Int = 0,
                 recordCoverage: Boolean = true): EvidencePage? = synchronized(LOCK) {
        val saved = read(access, id, expectedHash) ?: return@synchronized null
        val content = saved.toString()
        require(offset in 0..content.length) { "Evidence offset must be within the original document" }
        require(offset == 0 || offset == content.length || !Character.isLowSurrogate(content[offset]) ||
            !Character.isHighSurrogate(content[offset - 1])) { "Evidence offset splits a Unicode character" }
        var end = offset + minOf(8_000, content.length - offset)
        if (end < content.length && Character.isHighSurrogate(content[end - 1]) && Character.isLowSurrogate(content[end])) end--
        val coverage = if (recordCoverage)
            CollaborationEvidenceReadCoverage.record(rows, prefix(access.groupId), access, saved, content, offset, end)
        else CollaborationEvidenceReadCoverage.snapshot(rows, prefix(access.groupId), access, saved)
        EvidencePage(reference(saved, saved.getString("sha256")), content.substring(offset, end), content.length,
            end.takeIf { it < content.length }, coverage)
    }

    fun confirmPage(access: CollaborationWorkspaceAccess, id: String, expectedHash: String,
                    offset: Int, pageHash: String): JSONObject? = synchronized(LOCK) {
        val page = readPage(access, id, expectedHash, offset, recordCoverage = false) ?: return@synchronized null
        require(MqttImmutableContent.sha256(page.content) == pageHash) { "Confirmed evidence page differs from the served page" }
        readPage(access, id, expectedHash, offset)?.coverage
    }

    fun references(access: CollaborationWorkspaceAccess, requested: JSONArray): JSONArray = synchronized(LOCK) { JSONArray().apply {
        repeat(requested.length()) { index ->
            val item = requested.getJSONObject(index)
            val hash = item.getString("sha256")
            require(hash.matches(ID)) { "An exact evidence digest is required" }
            val saved = requireNotNull(read(access, item.getString("evidence_id"), hash)) {
                "Evidence is missing, changed or isolated from this assignment"
            }
            put(reference(saved, hash).put(CollaborationEvidenceReadCoverage.FIELD,
                CollaborationEvidenceReadCoverage.snapshot(rows, prefix(access.groupId), access, saved)))
        }
    } }

    /** Recheck the frozen publication snapshot, never refresh it from later reads. */
    fun requireReadCoverage(access: CollaborationWorkspaceAccess, review: JSONObject) = synchronized(LOCK) {
        val refs = review.getJSONArray("host_observations")
        require(refs.length() > 0) { "Independent candidate review requires original evidence" }
        repeat(refs.length()) { index ->
            val ref = refs.getJSONObject(index)
            val original = requireNotNull(read(access, ref.getString("evidence_id"), ref.getString("sha256"))) {
                "Candidate review original evidence is missing, changed or isolated"
            }
            CollaborationEvidenceReadCoverage.requireComplete(ref, review, original)
        }
    }

    fun browse(access: CollaborationWorkspaceAccess, cursor: String = ""): Pair<List<JSONObject>, String?> = synchronized(LOCK) {
        if (!authorized(access.groupId)) return@synchronized emptyList<JSONObject>() to null
        val prefix = prefix(access.groupId) + "observation:"
        require(cursor.isBlank() || cursor.startsWith(prefix) && cursor.removePrefix(prefix).matches(ID))
        val keys = rows.page(prefix, cursor, 21)
        val selected = keys.take(20)
        selected.mapNotNull { key -> read(access, key.removePrefix(prefix))?.let { reference(it, it.getString("sha256")) } } to
            selected.lastOrNull()?.takeIf { keys.size > selected.size }
    }

    companion object {
        private val LOCK = Any()
        private const val DATABASE = "galaxyssi_collaboration_evidence_v1"
        private val ID = Regex("[a-f0-9]{64}")
        private fun digest(value: String) = AgentNativeJsonCodec.sha256(value)
        private fun prefix(group: String) = "group:${digest(group)}:"
        private fun identity(access: CollaborationWorkspaceAccess) = JSONObject().put("group_id", access.groupId)
            .put("run_id", access.runId).put("turn_id", access.turnId).put("round", access.round)
            .put("node_id", access.nodeId).put("person_id", access.personId)
        private fun reference(value: JSONObject, hash: String) = JSONObject().put("sha256", hash).apply {
            listOf("evidence_id", "tool", "status", "origin", "observation_kind", "person_id", "node_id", "finished_at", "trust")
                .forEach { put(it, value.get(it)) }
        }
        fun remove(context: Context, group: String) = synchronized(LOCK) {
            val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)
            database.mutateStrings(emptyMap(), database.keys(prefix(group)))
        }
    }
}

internal class CollaborationCloudEvidence(
    private val ledger: CollaborationEvidenceLedger,
    val access: CollaborationWorkspaceAccess,
    private val clock: () -> Long = System::currentTimeMillis,
    private val newId: () -> String = { UUID.randomUUID().toString() }
) {
    fun execute(tool: String, input: JSONObject, operation: () -> String): String {
        val started = clock()
        val invocation = newId()
        val output = try { operation() } catch (error: Exception) {
            runCatching {
                ledger.record(access, invocation, tool, input.toString(), JSONObject().put("status", "failed")
                    .put("error", error::class.java.simpleName).toString(), started, maxOf(started, clock()))
            }
            throw error
        }
        val result = runCatching { JSONObject(output) }.getOrElse {
            JSONObject().put("status", "unstructured").put("output_text", output)
        }
        result.remove("galaxyssi_evidence_receipt")
        result.remove("galaxyssi_evidence_recording")
        try {
            val receipt = ledger.record(access, invocation, tool, input.toString(), output, started, maxOf(started, clock()))
            result.put("galaxyssi_evidence_receipt", receipt)
        } catch (revoked: CollaborationEvidenceAccessRevoked) {
            throw revoked
        } catch (_: Exception) {
            // Do not turn a completed operation into a retry merely because its evidence write failed.
            result.put("galaxyssi_evidence_recording", JSONObject().put("status", "not_durable")
                .put("tool_output_preserved", true).put("do_not_reexecute", true)
                .put("message", "No durable host receipt is available. Do not repeat the operation solely to obtain a receipt."))
        }
        return result.toString()
    }
}
