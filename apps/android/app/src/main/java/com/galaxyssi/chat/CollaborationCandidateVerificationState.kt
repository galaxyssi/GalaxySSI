package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Validates host scheduling checkpoints, not candidate truth or goal acceptance. */
internal object CollaborationCandidateVerificationState {
    private val HASH = Regex("[a-f0-9]{64}")
    private val PHASES = setOf("validate", "repair", "recheck", "done")
    private const val FORMAT = "candidate-checkpoint.v2"
    data class Checkpoint(val cycles: JSONArray, val pendingRequests: JSONArray)

    fun checkpoint(raw: String): Checkpoint {
        val checkpoint = if (raw.trimStart().startsWith("[")) Checkpoint(JSONArray(raw), JSONArray()) else {
            val value = JSONObject(raw)
            require(value.getString("format") == FORMAT) { "Unknown candidate checkpoint format" }
            Checkpoint(value.getJSONArray("cycles"), value.getJSONArray("pending_requests"))
        }
        validate(checkpoint.cycles)
        repeat(checkpoint.pendingRequests.length()) { checkpoint.pendingRequests.getJSONObject(it) }
        return checkpoint
    }

    fun read(raw: String): JSONArray = checkpoint(raw).cycles

    fun encode(cycles: JSONArray, pendingRequests: List<JSONObject>): String = if (pendingRequests.isEmpty()) cycles.toString() else
        JSONObject().put("format", FORMAT).put("cycles", cycles).put("pending_requests", JSONArray(pendingRequests)).toString()

    fun requests(saved: JSONArray, incoming: JSONArray): List<JSONObject> {
        val pending = linkedMapOf<String, JSONObject>()
        listOf(saved, incoming).forEach { source -> repeat(source.length()) { index ->
            val request = JSONObject(source.getJSONObject(index).toString())
            val target = request.optJSONObject("target")
            val key = target?.optString("object_id")?.takeIf(String::isNotBlank)
                ?.let { "object:$it:${target.opt("revision")}:${target.opt("sha256")}" } ?: "request:$request"
            pending[key] = request
        } }
        return pending.values.toList()
    }

    private fun validate(cycles: JSONArray) {
        val objects = hashSetOf<String>()
        val ids = hashSetOf<String>()
        val nodes = hashSetOf<String>()
        repeat(cycles.length()) { index ->
            val cycle = cycles.getJSONObject(index)
            val id = text(cycle, "id")
            val objectId = text(cycle, "object_id")
            require(id.matches(HASH) && ids.add(id) && objectId.matches(HASH) && objects.add(objectId)) {
                "Invalid or duplicate saved candidate cycle identity"
            }
            val target = cycle.getJSONObject("target")
            exactReference(target)
            require(target.getString("object_id") == objectId) { "Candidate checkpoint target identity changed" }
            val phase = text(cycle, "phase")
            require(phase in PHASES) { "Invalid saved candidate phase" }
            if (cycle.has("work_key")) require(text(cycle, "work_key").matches(HASH)) { "Invalid candidate work version key" }
            require(text(cycle, "editor") != text(cycle, "reviewer")) { "Candidate editor cannot independently review the repair" }
            val criterion = cycle.getJSONObject("criterion")
            text(criterion, "id")
            text(criterion, "requirement")
            require(criterion.getString("verification") == "documentary" &&
                CollaborationEvidenceRequirements.required(criterion).isNotEmpty()) { "Candidate checkpoint lacks a documentary source contract" }
            if (cycle.has("node_id")) require(nodes.add(text(cycle, "node_id"))) { "Candidate dispatch identity is duplicated" }
            if (cycle.has("review")) exactReference(cycle.getJSONObject("review"))
            if (phase in setOf("repair", "recheck")) require(cycle.has("review")) { "Candidate repair/recheck is missing its exact review basis" }
            if (phase == "done") text(cycle, "result") else {
                require(cycle.has("node_id") && !cycle.has("result")) { "Active candidate checkpoint lacks a dispatch or contains a terminal result" }
            }
        }
    }

    fun pending(raw: String): Boolean = runCatching {
        checkpoint(raw).let { saved -> saved.pendingRequests.length() > 0 ||
            (0 until saved.cycles.length()).any { saved.cycles.getJSONObject(it).getString("phase") != "done" } }
    }.getOrDefault(true)

    private fun exactReference(ref: JSONObject) {
        val version = CollaborationRemoteEvidenceProtocol.integer(ref, "revision")
        require(text(ref, "object_id").matches(HASH) && text(ref, "sha256").matches(HASH) &&
            version != null && version in 1..Int.MAX_VALUE.toLong()) { "Candidate checkpoint requires an exact revision reference" }
    }

    private fun text(value: JSONObject, key: String): String = value.getString(key).also {
        require(it.isNotBlank()) { "Candidate checkpoint $key is blank" }
    }
}
