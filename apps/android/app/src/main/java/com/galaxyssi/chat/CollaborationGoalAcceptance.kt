package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Host-only checkpoint metadata. Model response JSON is never decoded into this type. */
data class CollaborationAcceptanceReceipt internal constructor(
    val assessmentHash: String,
    val criteriaHash: String,
    val goalHash: String,
    val runId: String,
    val turnId: String,
    val nodeId: String,
    val accepted: Boolean,
    val feedback: String,
    val checkedAt: Long
) {
    internal fun matches(raw: String, criteria: String, goal: String, run: String, turn: String, node: String) =
        assessmentHash == AgentNativeJsonCodec.sha256(raw) && criteriaHash == AgentNativeJsonCodec.sha256(criteria) &&
            goalHash == AgentNativeJsonCodec.sha256(goal) && runId == run && turnId == turn && nodeId == node

    internal fun encode() = JSONObject().put("assessment_hash", assessmentHash).put("criteria_hash", criteriaHash)
        .put("goal_hash", goalHash).put("run_id", runId).put("turn_id", turnId).put("node_id", nodeId)
        .put("accepted", accepted).put("feedback", feedback).put("checked_at", checkedAt)

    internal companion object {
        fun decode(json: JSONObject?): CollaborationAcceptanceReceipt? = json?.let { runCatching {
            CollaborationAcceptanceReceipt(it.getString("assessment_hash"), it.getString("criteria_hash"),
                it.getString("goal_hash"), it.getString("run_id"), it.getString("turn_id"), it.getString("node_id"),
                it.getBoolean("accepted"), it.getString("feedback"), it.getLong("checked_at"))
        }.getOrNull() }
    }
}

/** Validates documentary deliveries; computational/physical completion needs a qualified adapter. */
internal class CollaborationGoalAcceptance(
    private val workspace: CollaborationResearchWorkspace,
    private val ledger: CollaborationEvidenceLedger
) {
    constructor(context: Context) : this(CollaborationResearchWorkspace(context), CollaborationEvidenceLedger(context))

    fun evaluate(access: CollaborationWorkspaceAccess, raw: String, criteria: String, goal: String,
                 now: Long = System.currentTimeMillis()): CollaborationAcceptanceReceipt {
        val failure = runCatching {
            val assessment = requireNotNull(CollaborationGoalLoop.decode(raw)) { "Invalid goal assessment" }
            val prior = JSONArray(criteria)
            require(prior.length() > 0) { "Establish the original acceptance criteria before submitting completion" }
            val current = assessment.getJSONArray("criteria")
            val byId = (0 until current.length()).associate { current.getJSONObject(it).let { item -> item.getString("id") to item } }
            repeat(prior.length()) { index ->
                val before = prior.getJSONObject(index)
                val after = requireNotNull(byId[before.getString("id")]) { "An original criterion was dropped" }
                require(before.getString("requirement") == after.getString("requirement") &&
                    before.optString("verification") == after.optString("verification")) { "An original criterion was weakened" }
            }
            require(assessment.getString("decision") == "achieved" && assessment.getJSONArray("work").length() == 0 &&
                assessment.getJSONArray("blockers").length() == 0 && (assessment.optJSONArray("recruit")?.length() ?: 0) == 0) {
                "Unfinished assignments or blockers remain"
            }
            repeat(current.length()) { validateCriterion(access, current.getJSONObject(it)) }
        }.exceptionOrNull()
        return CollaborationAcceptanceReceipt(AgentNativeJsonCodec.sha256(raw), AgentNativeJsonCodec.sha256(criteria),
            AgentNativeJsonCodec.sha256(goal), access.runId, access.turnId, access.nodeId, failure == null,
            failure?.message?.take(1200) ?: "Exact documentary deliveries and independent reviews checked; not empirical validation", now)
    }

    private fun validateCriterion(access: CollaborationWorkspaceAccess, criterion: JSONObject) {
        val id = criterion.getString("id")
        require(criterion.getString("status") == "met") { "$id: criterion remains open" }
        require(criterion.optString("verification") == "documentary") {
            "$id: ${criterion.optString("verification")} requires a qualified execution/experimental validator; text and simulations cannot certify it"
        }
        require(criterion.optString("evidence_kind") == "observed") { "$id: a proposed or simulated delivery is not an observed document" }
        val deliveryRef = criterion.getJSONObject("delivery")
        val reviewRef = criterion.getJSONObject("review")
        val delivery = currentRevision(access, deliveryRef)
        val review = currentRevision(access, reviewRef)
        require(delivery.getString("kind") in setOf("artifact", "proposal", "decision") &&
            delivery.getJSONObject("body").optString("content").isNotBlank()) { "$id: no substantive saved delivery" }
        require(review.getString("kind") == "decision" && review.getString("person_id") != delivery.getString("person_id")) {
            "$id: the author cannot independently review their own delivery"
        }
        repeat(delivery.getInt("revision")) { index ->
            val previous = requireNotNull(workspace.read(access, delivery.getString("object_id"), index + 1)) {
                "$id: delivery authorship history is incomplete"
            }
            require(previous.getString("person_id") != review.getString("person_id")) {
                "$id: a previous contributor cannot independently review the same delivery"
            }
        }
        val check = review.getJSONObject("body").getJSONObject("acceptance_review")
        require(check.getString("criterion_id") == id && check.getString("requirement") == criterion.getString("requirement")) {
            "$id: review addresses a different requirement"
        }
        val target = check.getJSONObject("target")
        require(listOf("object_id", "revision", "sha256").all { target.get(it) == deliveryRef.get(it) }) {
            "$id: review addresses a different delivery version"
        }
        require(review.getJSONArray("parents").let { parents -> (0 until parents.length()).any {
            parents.getJSONObject(it).let { parent -> parent.getString("object_id") == deliveryRef.getString("object_id") &&
                parent.getInt("revision") == deliveryRef.getInt("revision") }
        } }) { "$id: review has no preserved delivery reference" }
        require(check.getString("verdict") == "supported" && check.getString("rationale").isNotBlank() &&
            check.getJSONArray("unresolved").length() == 0) { "$id: review is negative, incomplete or has unresolved objections" }
        listOf(delivery, review).forEach { revision ->
            val refs = revision.getJSONArray("host_observations")
            repeat(refs.length()) { index ->
                val ref = refs.getJSONObject(index)
                val observation = requireNotNull(ledger.read(access, ref.getString("evidence_id"), ref.getString("sha256"))) {
                    "$id: a cited observation is missing, corrupt or inaccessible"
                }
                require(observation.getString("status") == "returned" && observation.getString("observation_kind") == "tool_output_recorded") {
                    "$id: failed tools and member assessments are not supporting observations"
                }
            }
        }
    }

    private fun currentRevision(access: CollaborationWorkspaceAccess, ref: JSONObject): JSONObject {
        val id = ref.getString("object_id")
        val revision = ref.getInt("revision")
        val saved = requireNotNull(workspace.read(access, id, revision)) { "Delivery/review is missing or isolated" }
        require(saved.getString("sha256") == ref.getString("sha256")) { "Delivery/review digest does not match" }
        require(saved.getString("run_id") == access.runId && saved.getString("turn_id") == access.turnId) {
            "Historical material must be re-evaluated for this goal, not reused as current acceptance"
        }
        require(workspace.isCurrent(access, id, revision)) { "Delivery/review has a newer revision; review the current work" }
        return saved
    }
}
