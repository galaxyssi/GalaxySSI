package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Checks publication shape, not the truth of a review or completion of a goal. */
internal object CollaborationReviewContract {
    const val KIND = "acceptance_review"
    private val digest = Regex("[a-f0-9]{64}")

    fun validate(kind: String, body: JSONObject) {
        if (kind != KIND) return
        val review = requireNotNull(body.optJSONObject(KIND)) {
            "Publish body.acceptance_review as a JSON object, not prose inside body.content"
        }
        listOf("criterion_id", "requirement", "rationale").forEach { key ->
            require(review.opt(key) is String && review.getString(key).isNotBlank()) { "acceptance_review.$key is required" }
        }
        val target = requireNotNull(review.optJSONObject("target")) { "An exact reviewed target is required" }
        listOf("object_id", "sha256").forEach { key ->
            require(target.opt(key) is String && target.getString(key).matches(digest)) { "Copy the target's exact $key" }
        }
        require(CollaborationRemoteEvidenceProtocol.integer(target, "revision")?.let { it in 1L..Int.MAX_VALUE.toLong() } == true) {
            "Copy the target's exact integer revision"
        }
        require(review.optString("verdict") in setOf("supported", "refuted", "not_tested")) { "Invalid review verdict" }
        val unresolved = requireNotNull(review.optJSONArray("unresolved")) { "unresolved must be an array of blocking issues" }
        repeat(unresolved.length()) { index ->
            require(unresolved.opt(index) is String && unresolved.getString(index).isNotBlank()) { "State each unresolved blocker explicitly" }
        }
        require(review.getString("verdict") != "supported" || unresolved.length() == 0) {
            "A supported review cannot retain unresolved blockers; use refuted/not_tested or resolve them in new work"
        }
    }

    fun instructions(): String = "For an assigned documentary acceptance review, use workspace kind=acceptance_review. " +
        "body.acceptance_review MUST be a JSON object, not a serialized string or text inside body.content. Example shape: " +
        JSONObject().put("body", JSONObject().put(KIND, JSONObject()
            .put("criterion_id", "exact criterion ID").put("requirement", "exact preserved requirement")
            .put("target", JSONObject().put("object_id", "exact host object ID").put("revision", 1).put("sha256", "exact digest"))
            .put("verdict", "supported|refuted|not_tested").put("rationale", "specific evidence-based assessment")
            .put("unresolved", JSONArray()))).toString() + ". " +
        "unresolved lists unmet acceptance requirements, not optional improvements; keep nonblocking suggestions separately in body.recommendations. " +
        "If a requirement is unmet or untested, preserve that blocker and use refuted or not_tested, never supported. " +
        "Cite the exact reviewed delivery in parents and the actually read host evidence in observations. " +
        "When a criterion has required_observations, read and cite those original origin/tool receipts from mode=evidence; " +
        "a receipt for reading the peer's workspace document cannot substitute for its original tool output. "
}
