package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Content release is distinct from satisfying the complete criterion or acknowledging receipt. */
internal object CollaborationInterimDelivery {
    const val FIELD = "interim_delivery"
    const val RECEIPT = "interim_delivery_receipt"
    const val READINESS = "content_readiness"
    const val TOOL = "galaxyssi.collaboration.conversation_delivery"

    fun reference(assessment: JSONObject): JSONObject? {
        if (!assessment.has(FIELD)) return null
        require(assessment.optString("decision") == "continue" && !assessment.has(CollaborationFinalDelivery.FIELD)) {
            "interim_delivery belongs to a continuing goal, not completion or final_delivery"
        }
        val request = requireNotNull(assessment.optJSONObject(FIELD)) { "interim_delivery must be an object" }
        require(request.keys().asSequence().toSet() == setOf("criterion_id", "target") &&
            request.opt("criterion_id") is String && request.getString("criterion_id").isNotBlank()) {
            "interim_delivery requires only criterion_id and exact target"
        }
        CollaborationReviewContract.validateReference(requireNotNull(request.optJSONObject("target")))
        return request
    }

    fun criterion(assessment: JSONObject, prior: JSONArray): JSONObject {
        val request = requireNotNull(reference(assessment))
        val current = assessment.getJSONArray("criteria")
        CollaborationEvidenceRequirements.validateAdmission(prior, current)
        val byId = (0 until current.length()).associate { current.getJSONObject(it).let { row -> row.getString("id") to row } }
        repeat(prior.length()) { index ->
            val before = prior.getJSONObject(index)
            val after = requireNotNull(byId[before.getString("id")]) { "Interim delivery cannot drop a preserved criterion" }
            require(before.getString("requirement") == after.getString("requirement") &&
                before.optString("verification") == after.optString("verification") &&
                CollaborationEvidenceRequirements.preserved(before, after) && CollaborationQualifiedValidation.preserved(before, after)) {
                "Interim delivery cannot change an established acceptance contract"
            }
        }
        val id = request.getString("criterion_id")
        require((0 until prior.length()).any { prior.getJSONObject(it).getString("id") == id }) {
            "Establish a criterion before requesting interim delivery"
        }
        val criterion = requireNotNull(byId[id]) { "Interim criterion is missing" }
        require(CollaborationResearchCandidates.same(criterion.getJSONObject("delivery"), request.getJSONObject("target"))) {
            "Interim target must be the exact criterion delivery"
        }
        return criterion
    }

    fun readiness(review: JSONObject): JSONObject = review.optJSONObject(READINESS) ?: review.also {
        require(it.getString("verdict") == "supported") {
            "An incomplete overall review needs a separate content_readiness verdict before interim release"
        }
    }

    const val REVIEW_INSTRUCTIONS = "A review may separately add content_readiness:{verdict,rationale,unresolved:[]} for interim release. " +
        "This judges content only; preserve the overall verdict and unresolved postconditions. "
    const val INSTRUCTIONS = "On continue, interim_delivery:{criterion_id,target:{object_id,revision,sha256}} releases an established criterion's " +
        "exact delivery after independent content_readiness support; keep delivery/review refs and unmet conditions. " +
        "Read the host interim_delivery_receipt next; android_native_tool/galaxyssi.collaboration.conversation_delivery proves " +
        "local persistence, not user reading, remote acknowledgement or completion. "
}
