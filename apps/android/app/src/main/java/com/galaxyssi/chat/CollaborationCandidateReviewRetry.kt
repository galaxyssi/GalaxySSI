package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Reassign a completed but unpublished documentary review, never an uncertain remote execution. */
internal object CollaborationCandidateReviewRetry {
    const val REQUEST = "retry_review"
    const val ELIGIBLE = "retryable_review"
    const val PHASE = "settled_phase"

    fun relevant(existing: JSONObject?, request: JSONObject): Boolean {
        if (existing == null) return true
        if ((request.optJSONObject("target")?.optLong("revision") ?: 0) > existing.getJSONObject("target").getLong("revision")) return true
        if (!request.has(REQUEST)) return false
        val node = request.optJSONObject(REQUEST)?.optString("node_id").orEmpty()
        val history = existing.optJSONArray("prior_settlements") ?: JSONArray()
        return node.isBlank() || (0 until history.length()).none { history.getJSONObject(it).optString("node_id") == node }
    }

    fun validate(workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess,
                 previous: JSONObject, request: JSONObject, target: JSONObject): JSONObject {
        val retry = request.getJSONObject(REQUEST)
        require(retry.keys().asSequence().toSet() == setOf("node_id", "reason") &&
            retry.opt("node_id") is String && retry.opt("reason") is String && retry.getString("reason").isNotBlank()) {
            "Review reassignment requires the exact completed node_id and a concrete correction reason"
        }
        require(previous.getString("phase") == "done" && previous.optBoolean(ELIGIBLE) &&
            previous.optString(PHASE) in setOf("validate", "recheck") &&
            previous.getString("node_id") == retry.getString("node_id") &&
            CollaborationResearchCandidates.same(previous.getJSONObject("target"), target)) {
            "Only a host-completed review without a committed publication may be reassigned; reconcile offline or failed work first"
        }
        require(workspace.publicationRevisions(access, retry.getString("node_id")).isEmpty()) {
            "The old review now has a committed publication; reconcile it instead of repeating completed work"
        }
        return JSONObject(retry.toString())
    }

    fun settlement(previous: JSONObject) = JSONObject().apply {
        listOf("target", "result", "node_id", "settled_phase", "editor", "reviewer", "work_key", ELIGIBLE)
            .forEach { key -> if (previous.has(key)) put(key, previous.get(key)) }
    }

    fun key(target: JSONObject, retry: JSONObject): String = AgentNativeJsonCodec.sha256(
        JSONArray().put("candidate-review-reassignment").put(target).put(retry.getString("node_id")).toString())
}
