package com.galaxyssi.chat

import org.json.JSONObject

/** Selects an existing reviewed deliverable; selection itself never certifies acceptance or receipt. */
internal object CollaborationFinalDelivery {
    const val FIELD = "final_delivery"

    fun reference(assessment: JSONObject): JSONObject? {
        if (!assessment.has(FIELD)) return null
        require(assessment.optString("decision") == "achieved") {
            "final_delivery is for a completion proposal, not an unfinished plan"
        }
        val ref = requireNotNull(assessment.optJSONObject(FIELD)) { "final_delivery must be an exact workspace reference" }
        CollaborationReviewContract.validateReference(ref)
        return ref
    }

    fun content(assessment: JSONObject, resolve: (JSONObject) -> JSONObject): String? {
        val ref = reference(assessment) ?: return null
        val criteria = assessment.getJSONArray("criteria")
        require((0 until criteria.length()).any { index ->
            val criterion = criteria.getJSONObject(index)
            criterion.optString("status") == "met" && criterion.optJSONObject("delivery")?.let { target ->
                listOf("object_id", "revision", "sha256").all { target.opt(it) == ref.get(it) }
            } == true
        }) { "final_delivery must be the exact delivery of a met criterion; an unreviewed extra summary cannot be substituted" }
        val saved = resolve(ref)
        require(saved.getString("kind") in setOf("artifact", "proposal", "decision")) { "final_delivery must be a substantive deliverable" }
        val body = saved.getJSONObject("body")
        require(body.opt("content") is String && body.getString("content").isNotBlank()) { "final_delivery has no complete text" }
        return body.getString("content")
    }

    fun prepare(workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess, raw: String): String {
        val assessment = CollaborationGoalLoop.decode(raw) ?: return raw
        val text = content(assessment) { ref ->
            val id = ref.getString("object_id")
            val revision = ref.getInt("revision")
            val saved = requireNotNull(workspace.read(access, id, revision)) { "final_delivery is missing or isolated" }
            require(saved.getString("sha256") == ref.getString("sha256") &&
                saved.getString("run_id") == access.runId && saved.getString("turn_id") == access.turnId &&
                workspace.isCurrent(access, id, revision)) { "final_delivery digest, scope or current version does not match" }
            saved
        } ?: return raw
        return assessment.put("summary", text).toString()
    }

    fun instructions() = "Save final text before independent review. On achieved, select final_delivery:{object_id,revision,sha256} " +
        "from a met criterion: the host copies its complete body.content unchanged, subject to all acceptance checks. " +
        "Do not paraphrase it again or preclaim review success; review references belong in assessment metadata. " +
        "Selection is not evidence of transport receipt or user reading. Do not wait for review of this future assessment before submitting it. "
}
