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

/** Checks mapped coverage/review integrity and explicitly qualified computation, not scientific truth. */
internal class CollaborationGoalAcceptance(
    private val workspace: CollaborationResearchWorkspace,
    private val ledger: CollaborationEvidenceLedger
) {
    constructor(context: Context) : this(CollaborationResearchWorkspace(context), CollaborationEvidenceLedger(context))

    fun evaluate(access: CollaborationWorkspaceAccess, raw: String, criteria: String, goal: String,
                 now: Long = System.currentTimeMillis()): CollaborationAcceptanceReceipt {
        val scope = access.copy(dependencyNodes = access.dependencyNodes.toSet())
        val assessmentHash = AgentNativeJsonCodec.sha256(raw)
        val criteriaHash = AgentNativeJsonCodec.sha256(criteria)
        val goalHash = AgentNativeJsonCodec.sha256(goal)
        fun receipt(failure: Throwable?) = CollaborationAcceptanceReceipt(assessmentHash, criteriaHash, goalHash,
            scope.runId, scope.turnId, scope.nodeId, failure == null,
            if (failure != null) failure.message?.take(1200) ?: "Acceptance validation failed" else
                "Host source-ID coverage and independent review integrity checked; " +
                    "computational qualification covers only the selected validator's preserved inputs and operations. " +
                    "semantic support is a reviewer judgment, not objective scientific truth and not empirical validation; " +
                    "source classification is not a compliance audit or a user/device delivery receipt", now)
        return runCatching {
            val assessment = requireNotNull(CollaborationGoalLoop.decode(raw)) { "Invalid goal assessment" }
            require(!CollaborationCandidateEvolution.requested(assessment)) { "Candidate cycle work remains requested" }
            val prior = JSONArray(criteria)
            require(prior.length() > 0) { "Establish the original acceptance criteria before submitting completion" }
            val current = assessment.getJSONArray("criteria")
            val byId = (0 until current.length()).associate { current.getJSONObject(it).let { item -> item.getString("id") to item } }
            val priorIds = hashSetOf<String>()
            repeat(prior.length()) { index ->
                val before = prior.getJSONObject(index)
                require(priorIds.add(before.getString("id"))) { "Duplicate preserved criterion" }
                val after = requireNotNull(byId[before.getString("id")]) { "An original criterion was dropped" }
                require(before.getString("requirement") == after.getString("requirement") &&
                    before.optString("verification") == after.optString("verification") &&
                    CollaborationEvidenceRequirements.preserved(before, after) &&
                    CollaborationQualifiedValidation.preserved(before, after)) { "An original criterion was weakened" }
            }
            require(assessment.getString("decision") == "achieved" && assessment.getJSONArray("work").length() == 0 &&
                assessment.getJSONArray("blockers").length() == 0 && (assessment.optJSONArray("recruit")?.length() ?: 0) == 0) {
                "Unfinished assignments or blockers remain"
            }
            val coverage = CollaborationGoalCoverageManifest.resolve(requireNotNull(assessment.optJSONObject(CollaborationSemanticGoalCoverage.FIELD)) {
                "Publish an explicit original-goal requirement mapping and a separate independent semantic coverage review; supply goal_coverage references"
            }, current, goal) { ref -> currentRevision(scope, ref) }
            val targets = coverage.parts.mapTo(linkedSetOf()) { part ->
                CollaborationAcceptanceReviewSnapshot.Binding.of(part.mapping, CollaborationSemanticGoalCoverage.REVIEW)
            }
            repeat(current.length()) { index ->
                val criterion = current.getJSONObject(index)
                targets.add(CollaborationAcceptanceReviewSnapshot.Binding.of(criterion.getJSONObject("delivery"),
                    CollaborationReviewContract.KIND, criterion.getString("id"), criterion.getString("requirement")))
            }
            val snapshot = workspace.acceptanceReviewSnapshot(scope, targets)
            CollaborationFinalDelivery.content(assessment) { ref -> currentRevision(scope, ref) }?.let { text ->
                require(assessment.getString("summary") == text) {
                    "final_delivery must project the complete saved content unchanged before acceptance"
                }
            }
            // Resolution precedes the review snapshot; recheck directories inside its mutation fence.
            coverage.manifests.forEach { currentRevision(scope, it) }
            validateCoverage(scope, coverage.parts, current, goal, snapshot)
            repeat(current.length()) {
                val criterion = current.getJSONObject(it)
                require(criterion.optString("verification") != "computational" || criterion.getString("id") in priorIds) {
                    "Establish computational inputs in preserved criteria before requesting completion"
                }
                validateCriterion(scope, criterion, snapshot)
            }
            workspace.withAcceptanceFence(snapshot) { receipt(null) }
        }.getOrElse { receipt(it) }
    }

    private fun validateCoverage(access: CollaborationWorkspaceAccess, parts: List<CollaborationSemanticGoalCoverage.ReferencePair>, criteria: JSONArray, goal: String,
                                 snapshot: CollaborationAcceptanceReviewSnapshot) {
        val validation = CollaborationSemanticGoalCoverage.Validation(criteria, goal)
        val covered = parts.map { part ->
            val mapping = currentRevision(access, part.mapping)
            val review = currentRevision(access, part.review)
            require(mapping.getString("kind") == "artifact" && review.getString("kind") == CollaborationReviewContract.KIND) {
                "Coverage needs a saved mapping artifact and a typed independent review"
            }
            require(access.personId.isNotBlank() && review.getString("person_id") != access.personId) {
                "The evaluating coordinator cannot independently certify coverage of its own criteria"
            }
            CollaborationReviewContract.validate(review.getString("kind"), review.getJSONObject("body"))
            val check = review.getJSONObject("body").getJSONObject(CollaborationSemanticGoalCoverage.REVIEW)
            validateIndependentReview(access, part.mapping, mapping, review, check, "Original-goal coverage")
            val body = mapping.getJSONObject("body").getJSONObject(CollaborationSemanticGoalCoverage.MAPPING)
            validateCurrentReviews(snapshot, part.mapping, CollaborationSemanticGoalCoverage.REVIEW, "Original-goal coverage") { settled ->
                validation.part(body, settled)
            }
            validation.part(body, check)
        }
        validation.complete(covered)
    }

    private fun validateCriterion(access: CollaborationWorkspaceAccess, criterion: JSONObject, snapshot: CollaborationAcceptanceReviewSnapshot) {
        val id = criterion.getString("id")
        require(criterion.getString("status") == "met") { "$id: criterion remains open" }
        val deliveryRef = criterion.getJSONObject("delivery")
        val reviewRef = criterion.getJSONObject("review")
        val delivery = currentRevision(access, deliveryRef)
        val review = currentRevision(access, reviewRef)
        require(delivery.getString("kind") in setOf("artifact", "proposal", "decision") &&
            delivery.getJSONObject("body").opt("content") is String &&
            delivery.getJSONObject("body").optString("content").isNotBlank()) { "$id: no substantive saved delivery" }
        CollaborationQualifiedValidation.validate(criterion, delivery.getJSONObject("body"), CollaborationValidationEvidence(
            delivery, review, exact = { ref, kind ->
                CollaborationReviewContract.validateReference(ref)
                val saved = requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))) {
                    "Executable verification record is missing or isolated"
                }
                require(saved.getString("kind") == kind && CollaborationResearchCandidates.same(saved, ref) &&
                    workspace.isCurrent(access, ref.getString("object_id"), ref.getInt("revision"))) {
                    "Executable verification record kind, version or digest changed"
                }
                saved
            }, original = { ref -> ledger.read(access, ref.getString("evidence_id"), ref.getString("sha256")) },
            requireReadCoverage = { ledger.requireReadCoverage(access, it) },
            contributors = { workspace.contributorIds(access, it) }))
        CollaborationReviewContract.validate(CollaborationReviewContract.KIND, review.getJSONObject("body"))
        val check = review.getJSONObject("body").getJSONObject("acceptance_review")
        validateIndependentReview(access, deliveryRef, delivery, review, check, id)
        require(check.getString("criterion_id") == id && check.getString("requirement") == criterion.getString("requirement")) {
            "$id: review addresses a different requirement"
        }
        require(check.getString("verdict") == "supported" && check.getJSONArray("unresolved").length() == 0) {
            "$id: review is negative, incomplete or has unresolved objections"
        }
        validateCurrentReviews(snapshot, deliveryRef, CollaborationReviewContract.KIND, id, criterion.getString("requirement"))
        val reviewedObservations = mutableListOf<JSONObject>()
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
                if (revision === review) {
                    CollaborationEvidenceReadCoverage.requireComplete(ref, review, observation)
                    reviewedObservations += observation
                }
            }
        }
        CollaborationEvidenceRequirements.validate(criterion, reviewedObservations)
    }

    private fun validateIndependentReview(access: CollaborationWorkspaceAccess, deliveryRef: JSONObject, delivery: JSONObject,
                                          review: JSONObject, check: JSONObject, id: String) {
        require(review.getString("kind") in setOf("decision", CollaborationReviewContract.KIND) &&
            review.getString("person_id") != delivery.getString("person_id")) {
            "$id: the author cannot independently review their own delivery"
        }
        require(review.getString("person_id") !in workspace.contributorIds(access, deliveryRef)) {
            "$id: a previous contributor or declared ancestor author cannot independently review the same delivery"
        }
        val target = check.getJSONObject("target")
        require(listOf("object_id", "revision", "sha256").all { target.get(it) == deliveryRef.get(it) }) {
            "$id: review addresses a different delivery version"
        }
        require(review.getJSONArray("parents").let { parents -> (0 until parents.length()).any {
            parents.getJSONObject(it).let { parent -> parent.getString("object_id") == deliveryRef.getString("object_id") &&
                parent.getInt("revision") == deliveryRef.getInt("revision") }
        } }) { "$id: review has no preserved delivery reference" }
    }

    private fun validateCurrentReviews(snapshot: CollaborationAcceptanceReviewSnapshot, target: JSONObject,
                                       field: String, id: String, requirement: String = "", validateSupported: (JSONObject) -> Unit = {}) {
        val reviews = snapshot.reviews(CollaborationAcceptanceReviewSnapshot.Binding.of(target, field, id, requirement))
        reviews.forEach { revision ->
            val check = revision.getJSONObject("body").getJSONObject(field)
            require(check.getString("verdict") == "supported" && check.getJSONArray("unresolved").length() == 0) {
                "$id: a current typed review retains dissent or untested requirements; its author must resolve it in a new revision of that review"
            }
            validateSupported(check)
        }
    }

    private fun currentRevision(access: CollaborationWorkspaceAccess, ref: JSONObject): JSONObject {
        CollaborationReviewContract.validateReference(ref)
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
