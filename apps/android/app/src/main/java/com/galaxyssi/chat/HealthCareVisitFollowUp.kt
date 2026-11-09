package com.galaxyssi.chat

import org.json.JSONObject

internal enum class HealthCareVisitFollowUpState { ACTIVE, REVIEW, PAUSED, ARCHIVED }
internal enum class HealthCareVisitFollowUpKind { START, CHECK_IN, REVIEW, PAUSE, RESUME, ARCHIVE, REOPEN }
internal enum class HealthCareVisitReviewDecision { CONTINUE, DISCUSS_CHANGE, DISCUSS_MAINTENANCE }

/** Self-reported follow-up, not clinical assessment or a replacement prescription. */
internal data class HealthCareVisitFollowUpInput(
    val kind: HealthCareVisitFollowUpKind, val goal: String = "", val feelings: String = "",
    val function: String = "", val sleep: String = "", val barriers: String = "", val note: String = "",
    val needsReview: Boolean = false, val decision: HealthCareVisitReviewDecision? = null
) {
    init {
        require(goal == goal.trim() && goal.length <= 1000)
        require(listOf(feelings, function, sleep, barriers, note).all { it == it.trim() && it.length <= 2000 })
        require((kind == HealthCareVisitFollowUpKind.REVIEW) == (decision != null))
        require(kind in setOf(HealthCareVisitFollowUpKind.START, HealthCareVisitFollowUpKind.REVIEW) || goal.isEmpty())
        require(kind == HealthCareVisitFollowUpKind.CHECK_IN || !needsReview && listOf(feelings, function, sleep, barriers).all { it.isEmpty() })
        when (kind) {
            HealthCareVisitFollowUpKind.START -> require(goal.isNotBlank())
            HealthCareVisitFollowUpKind.CHECK_IN -> require(listOf(feelings, function, sleep, barriers, note).any { it.isNotBlank() })
            else -> require(note.isNotBlank())
        }
    }
    fun json() = JSONObject().put("kind", kind.name).put("goal", goal).put("feelings", feelings)
        .put("function", function).put("sleep", sleep).put("barriers", barriers).put("note", note)
        .put("needs_review", needsReview).put("decision", decision?.name ?: JSONObject.NULL)
    companion object { fun from(j: JSONObject) = HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.valueOf(j.getString("kind")),
        j.getString("goal"), j.getString("feelings"), j.getString("function"), j.getString("sleep"), j.getString("barriers"),
        j.getString("note"), j.getBoolean("needs_review"), j.takeUnless { it.isNull("decision") }?.getString("decision")?.let(HealthCareVisitReviewDecision::valueOf)) }
}

internal data class HealthCareVisitFollowUp(val id: String, val concernId: String, val encounterId: String,
    val revision: Int, val encounterRevision: Int, val goal: String, val state: HealthCareVisitFollowUpState,
    val createdAt: Long, val updatedAt: Long) {
    init {
        require(listOf(id, concernId, encounterId).all(HealthProfilePolicy::uuid))
        require(revision > 0 && encounterRevision > 0 && goal.isNotBlank() && goal == goal.trim() && goal.length <= 1000)
        require(createdAt > 0 && updatedAt >= createdAt)
    }
    fun json() = JSONObject().put("id", id).put("concern", concernId).put("encounter", encounterId).put("revision", revision)
        .put("encounter_revision", encounterRevision).put("goal", goal).put("state", state.name).put("created", createdAt).put("updated", updatedAt)
    companion object { fun from(j: JSONObject) = HealthCareVisitFollowUp(j.getString("id"), j.getString("concern"), j.getString("encounter"),
        j.getInt("revision"), j.getInt("encounter_revision"), j.getString("goal"), HealthCareVisitFollowUpState.valueOf(j.getString("state")),
        j.getLong("created"), j.getLong("updated")) }
}

internal data class HealthCareVisitFollowUpReceipt(val operationId: String, val expectedConcern: Int, val expectedFollowUp: Int?,
    val value: HealthCareVisitFollowUp, val input: HealthCareVisitFollowUpInput, val recordedAt: Long,
    val sourceRecord: HealthCareRecordRef?, val encounterRevision: Int) {
    init {
        require(HealthProfilePolicy.uuid(operationId) && expectedConcern in 1 until Int.MAX_VALUE)
        require(value.revision == expectedConcern + 1 && recordedAt > 0 && encounterRevision > 0)
        require(expectedFollowUp == null || expectedFollowUp in 1..expectedConcern)
        require((input.kind == HealthCareVisitFollowUpKind.START) == (expectedFollowUp == null))
    }
    fun json() = JSONObject().put("operation", operationId).put("expected_concern", expectedConcern)
        .put("expected_followup", expectedFollowUp ?: JSONObject.NULL).put("value", value.json()).put("input", input.json())
        .put("recorded", recordedAt).put("source_record", sourceRecord?.json() ?: JSONObject.NULL)
        .put("encounter_revision", encounterRevision).put("provenance", "user_reported")
    companion object { fun from(j: JSONObject): HealthCareVisitFollowUpReceipt {
        require(j.getString("provenance") == "user_reported")
        return HealthCareVisitFollowUpReceipt(j.getString("operation"), j.getInt("expected_concern"),
            j.takeUnless { it.isNull("expected_followup") }?.getInt("expected_followup"), HealthCareVisitFollowUp.from(j.getJSONObject("value")),
            HealthCareVisitFollowUpInput.from(j.getJSONObject("input")), j.getLong("recorded"), j.optJSONObject("source_record")?.let(HealthCareRecordRef::from),
            j.getInt("encounter_revision"))
    } }
}

internal data class HealthCareVisitFollowUpPage(val items: List<HealthCareVisitFollowUpReceipt>, val next: Int?)

internal object HealthCareVisitFollowUpPolicy {
    fun apply(issue: HealthCareConcern, visit: HealthCareEncounter, before: HealthCareVisitFollowUp?,
        input: HealthCareVisitFollowUpInput, operation: String, now: Long): HealthCareVisitFollowUpReceipt {
        require(now > 0 && issue.revision in 1 until Int.MAX_VALUE && HealthProfilePolicy.uuid(operation))
        if (visit.concernId != issue.id || before != null && (before.concernId != issue.id || before.encounterId != visit.id)) throw HealthCareConflict()
        if (visit.details.state != HealthCareEncounterState.ATTENDED && input.kind !in setOf(HealthCareVisitFollowUpKind.PAUSE, HealthCareVisitFollowUpKind.ARCHIVE))
            throw HealthCareConflict()
        val state = when (input.kind) {
            HealthCareVisitFollowUpKind.START -> { if (before != null) throw HealthCareConflict(); HealthCareVisitFollowUpState.ACTIVE }
            HealthCareVisitFollowUpKind.CHECK_IN -> {
                if (before?.state !in setOf(HealthCareVisitFollowUpState.ACTIVE, HealthCareVisitFollowUpState.REVIEW)) throw HealthCareConflict()
                if (input.needsReview) HealthCareVisitFollowUpState.REVIEW else before!!.state
            }
            HealthCareVisitFollowUpKind.REVIEW -> {
                if (before?.state !in setOf(HealthCareVisitFollowUpState.ACTIVE, HealthCareVisitFollowUpState.REVIEW)) throw HealthCareConflict()
                if (input.decision == HealthCareVisitReviewDecision.CONTINUE) HealthCareVisitFollowUpState.ACTIVE else HealthCareVisitFollowUpState.REVIEW
            }
            HealthCareVisitFollowUpKind.PAUSE -> {
                if (before?.state !in setOf(HealthCareVisitFollowUpState.ACTIVE, HealthCareVisitFollowUpState.REVIEW)) throw HealthCareConflict()
                HealthCareVisitFollowUpState.PAUSED
            }
            HealthCareVisitFollowUpKind.RESUME -> {
                if (before?.state != HealthCareVisitFollowUpState.PAUSED) throw HealthCareConflict()
                HealthCareVisitFollowUpState.REVIEW
            }
            HealthCareVisitFollowUpKind.ARCHIVE -> {
                if (before == null || before.state == HealthCareVisitFollowUpState.ARCHIVED) throw HealthCareConflict()
                HealthCareVisitFollowUpState.ARCHIVED
            }
            HealthCareVisitFollowUpKind.REOPEN -> {
                if (before?.state != HealthCareVisitFollowUpState.ARCHIVED) throw HealthCareConflict()
                HealthCareVisitFollowUpState.REVIEW
            }
        }
        val time = maxOf(now, issue.updatedAt, before?.updatedAt ?: now)
        val anchor = if (before == null || input.kind == HealthCareVisitFollowUpKind.REVIEW) visit.revision else before.encounterRevision
        val value = HealthCareVisitFollowUp(before?.id ?: operation, issue.id, visit.id, issue.revision + 1, anchor,
            input.goal.ifBlank { before!!.goal }, state, before?.createdAt ?: time, time)
        return HealthCareVisitFollowUpReceipt(operation, issue.revision, before?.revision, value, input, now, issue.assessment.record, visit.revision)
    }
}
