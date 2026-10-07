package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Interim publications are immutable data, not child completion or accepted scientific claims. */
internal class CollaborationMilestoneJournal(
    private val rows: CollaborationWorkspaceRows,
    private val access: CollaborationWorkspaceAccess
) {
    private val scope = AgentNativeJsonCodec.sha256(JSONArray(listOf(access.groupId, access.runId, access.turnId,
        access.round, access.nodeId, access.personId)).toString())
    private val groupPrefix = "group:${AgentNativeJsonCodec.sha256(access.groupId)}:"
    private val prefix = "${groupPrefix}milestone:$scope:"

    fun publicationKey(id: String) = "${groupPrefix}milestone-publication:$scope:${AgentNativeJsonCodec.sha256(id)}"

    fun outcomeWrites(id: String, raw: String, receipt: JSONObject, now: Long): Map<String, String> {
        val record = JSONObject().put("milestone_id", id).put("producer_node", access.nodeId)
            .put("person_id", access.personId).put("scope_sha256", scope)
            .put("raw", raw).put("raw_sha256", AgentNativeJsonCodec.sha256(raw)).put("recorded_at", now)
            .put("receipt", receipt)
        record.put("record_sha256", AgentNativeJsonCodec.sha256(record.toString()))
        return buildMap {
            // Preserve failed drafts as well, without rewriting a successful milestone.
            val attemptKey = "${groupPrefix}milestone-attempt:$scope:${AgentNativeJsonCodec.sha256(id)}:" +
                AgentNativeJsonCodec.sha256(JSONArray().put(raw).put(receipt).toString())
            if (rows.read(attemptKey) == null) put(attemptKey, record.toString())
            if (receipt.optString("status") == "recorded") put(prefix + AgentNativeJsonCodec.sha256(id), record.toString())
        }
    }

    fun resolve(artifact: JSONObject, read: (JSONObject) -> JSONObject): List<JSONObject> {
        if (!artifact.has("milestones")) return emptyList()
        val ids = requireNotNull(artifact.optJSONArray("milestones")) { "milestones must contain this assignment's published milestone IDs" }
        val seen = hashSetOf<String>()
        val revisions = linkedMapOf<String, JSONObject>()
        repeat(ids.length()) { index ->
            val id = ids.opt(index) as? String ?: throw IllegalArgumentException("milestones[$index] must be a string")
            validateId(id)
            require(seen.add(id)) { "Duplicate milestone ID: $id" }
            val record = requireNotNull(rows.read(prefix + AgentNativeJsonCodec.sha256(id))) { "Unknown milestone: $id" }.let(::JSONObject)
            checkRecord(record)
            require(record.getString("milestone_id") == id) { "Milestone identity changed" }
            val refs = record.getJSONObject("receipt").getJSONArray("revisions")
            repeat(refs.length()) { at ->
                val original = read(refs.getJSONObject(at))
                revisions["${original.getString("object_id")}:${original.getInt("revision")}"] = original
            }
        }
        return revisions.values.toList()
    }

    fun page(cursor: String): JSONObject {
        require(cursor.isEmpty() || cursor.startsWith(prefix) && cursor.removePrefix(prefix).matches(HASH)) { "Cursor belongs to another assignment" }
        val keys = rows.page(prefix, cursor, 33)
        val records = keys.take(32).map { key ->
            val value = requireNotNull(rows.read(key)).let(::JSONObject)
            checkRecord(value)
            JSONObject().put("milestone_id", value.getString("milestone_id"))
                .put("raw_sha256", value.getString("raw_sha256")).put("recorded_at", value.getLong("recorded_at"))
                .put("revision_count", value.getJSONObject("receipt").getJSONArray("revisions").length())
        }
        return JSONObject().put("status", "returned").put("milestones", JSONArray(records))
            .put("next_cursor", if (keys.size > 32) keys[31] else JSONObject.NULL)
            .put("trust", "host_recorded_interim_versions_not_task_completion_or_verification")
    }

    private fun checkRecord(record: JSONObject) {
        val unsigned = JSONObject(record.toString()).apply { remove("record_sha256") }
        require(AgentNativeJsonCodec.sha256(unsigned.toString()) == record.getString("record_sha256") &&
            record.getString("scope_sha256") == scope && record.getString("producer_node") == access.nodeId &&
            record.getString("person_id") == access.personId &&
            AgentNativeJsonCodec.sha256(record.getString("raw")) == record.getString("raw_sha256") &&
            record.getJSONObject("receipt").getString("status") == "recorded") { "Milestone integrity check failed" }
    }

    companion object {
        private val HASH = Regex("[a-f0-9]{64}")
        fun validateId(id: String) { require(id.isNotBlank() && id == id.trim() && id.length <= 160 && id.none(Char::isISOControl)) {
            "Use a stable nonblank milestone_id of at most 160 characters"
        } }
    }
}
