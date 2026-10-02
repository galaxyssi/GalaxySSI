package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Used under the workspace transaction lock; attempts and revisions commit together. */
internal class CollaborationPublicationJournal(
    private val rows: CollaborationWorkspaceRows,
    private val access: CollaborationWorkspaceAccess
) {
    private val prefix = "group:${hash(access.groupId)}:submission:${hash("${access.runId}:${access.nodeId}")}:"
    private val identity = JSONObject().put("group", access.groupId).put("run", access.runId)
        .put("turn", access.turnId).put("round", access.round).put("node", access.nodeId)
        .put("person", access.personId).put("dependencies", JSONArray(access.dependencyNodes.sorted())).toString()

    fun enroll(stage: CollaborationResearchStage, task: JSONObject?) {
        require(stage != CollaborationResearchStage.DELIVER) { "Delivery uses the goal acceptance contract" }
        val contract = JSONObject().put("identity", identity).put("stage", stage.name).put("candidate_task", task)
        val key = prefix + "contract"
        val existing = read(key)
        require(existing == null || existing.toString() == contract.toString()) { "Publication contract changed" }
        if (existing == null) rows.commit(mapOf(key to envelope(contract)))
    }

    fun contract(): JSONObject? = read(prefix + "contract")?.also {
        require(it.getString("identity") == identity) { "Publication identity changed" }
    }

    fun checkpoint(): JSONObject? {
        val contract = contract() ?: return null
        return read(prefix + "latest")?.also {
            require(it.getString("contract_sha256") == hash(contract.toString()) &&
                it.getString("raw_sha256") == hash(it.getString("raw"))) { "Publication checkpoint binding changed" }
            val sequence = it.getLong("sequence")
            require(sequence > 0 && read(attemptKey(sequence))?.toString() == it.toString()) {
                "Publication attempt history changed"
            }
        }
    }

    fun outcomeWrites(raw: String, receipt: JSONObject, now: Long): Map<String, String> {
        val contract = requireNotNull(contract()) { "Publication repair was not enrolled by the host" }
        val previous = checkpoint()
        require(previous?.getJSONObject("receipt")?.optString("status") != "recorded") {
            "A successful publication is immutable"
        }
        val sequence = Math.addExact(previous?.getLong("sequence") ?: 0L, 1L)
        val value = JSONObject().put("contract_sha256", hash(contract.toString()))
            .put("sequence", sequence).put("raw", raw).put("raw_sha256", hash(raw))
            .put("receipt", receipt).put("recorded_at", now)
            .put("previous_sha256", previous?.toString()?.let(::hash).orEmpty())
        val key = attemptKey(sequence)
        check(rows.read(key) == null) { "Publication attempt cannot be overwritten" }
        val encoded = envelope(value)
        return mapOf(key to encoded, prefix + "latest" to encoded)
    }

    private fun attemptKey(sequence: Long) = prefix + "attempt:" + sequence.toString().padStart(20, '0')
    private fun read(key: String): JSONObject? = rows.read(key)?.let { encoded ->
        val envelope = JSONObject(encoded)
        val raw = envelope.getString("payload")
        check(hash(raw) == envelope.getString("sha256")) { "Publication journal integrity check failed" }
        JSONObject(raw)
    }

    private fun envelope(value: JSONObject): String = value.toString().let {
        JSONObject().put("payload", it).put("sha256", hash(it)).toString()
    }
    private fun hash(value: String) = AgentNativeJsonCodec.sha256(value)
}
