package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject

/** User-chosen journal review, never a prescribed test interval. Check-ins do not invalidate it. */
internal data class HealthCareVisitReviewRef(val journal: String, val encounter: String, val revision: Int,
    val encounterRevision: Int, val goalDigest: String, val invalidated: Boolean = false) {
    init { require(listOf(journal, encounter).all(HealthProfilePolicy::uuid) && revision > 0 && encounterRevision > 0)
        require(goalDigest.matches(Regex("[0-9a-f]{64}"))) }
    fun json() = JSONObject().put("journal", journal).put("encounter", encounter).put("revision", revision)
        .put("encounter_revision", encounterRevision).put("goal_digest", goalDigest).put("invalidated", invalidated)
    fun matches(value: HealthCareVisitFollowUp, visit: HealthCareEncounter) = !invalidated && journal == value.id &&
        encounter == value.encounterId && encounter == visit.id && encounterRevision == visit.revision &&
        value.encounterRevision == visit.revision && goalDigest == AgentNativeJsonCodec.sha256(value.goal) &&
        value.state in setOf(HealthCareVisitFollowUpState.ACTIVE, HealthCareVisitFollowUpState.REVIEW) &&
        visit.details.state == HealthCareEncounterState.ATTENDED
    companion object {
        fun of(value: HealthCareVisitFollowUp, visit: HealthCareEncounter) = HealthCareVisitReviewRef(value.id, visit.id,
            value.revision, visit.revision, AgentNativeJsonCodec.sha256(value.goal))
        fun from(j: JSONObject) = HealthCareVisitReviewRef(j.getString("journal"), j.getString("encounter"),
            j.getInt("revision"), j.getInt("encounter_revision"), j.getString("goal_digest"), j.getBoolean("invalidated"))
    }
}

internal object HealthCareVisitReviewPolicy {
    fun actionId(journal: String) = UUID.nameUUIDFromBytes("visit-review:$journal".toByteArray(Charsets.UTF_8)).toString()
    fun confirm(issue: HealthCareConcern, value: HealthCareVisitFollowUp, visit: HealthCareEncounter,
        title: String, rationale: String, now: Long): HealthCareAction {
        val ref = HealthCareVisitReviewRef.of(value, visit)
        if (value.concernId != issue.id || visit.concernId != issue.id || !ref.matches(value, visit) ||
            issue.stage in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED)) throw HealthCareConflict()
        return HealthCareAction(actionId(value.id), HealthCareActionKind.VISIT_REVIEW, title, rationale,
            "user_confirmed_visit_review", HealthCareActionState.CONFIRMED, confirmedAt = now,
            basis = HealthCareFollowUpPolicy.basis(issue), visitReview = ref)
    }
    fun invalidate(issue: HealthCareConcern, predicate: (HealthCareVisitReviewRef) -> Boolean) =
        issue.copy(actions = issue.actions.map { action -> action.visitReview?.let { ref ->
            if (!ref.invalidated && predicate(ref)) action.copy(visitReview = ref.copy(invalidated = true)) else action
        } ?: action })
}
