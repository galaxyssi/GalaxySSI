package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthCareReviewDecision { OBSERVE, CLARIFY, RESEARCH, PROPOSE_PLAN, CLINICIAN_REVIEW }
internal enum class HealthCareReviewEvent { SOURCE_CHANGE, USER_FEEDBACK, CONFIRMED_ACTION_DUE }

internal data class HealthCareQuestionRef(val id: String, val revision: Int) {
    init { require(HealthProfilePolicy.uuid(id) && revision > 0) }
    fun json() = JSONObject().put("id", id).put("revision", revision)
    companion object {
        fun from(value: JSONObject) = HealthCareQuestionRef(value.getString("id"), value.getInt("revision"))
    }
}

/** Model reasoning is an assessment, never a confirmed clinical action or a diagnosis. */
internal data class HealthCareModelReviewInput(
    val summary: String, val rationale: String, val uncertainty: String, val nextStep: String,
    val decision: HealthCareReviewDecision, val events: List<HealthCareReviewEvent>,
    val records: List<HealthCareRecordRef>, val evidenceIds: List<String>, val planId: String,
    val attentionRequested: Boolean, val attentionReason: String,
    val questions: List<HealthCareQuestionRef> = emptyList()
) {
    init {
        require(summary.isNotBlank() && summary.length <= 1000)
        require(listOf(rationale, uncertainty, nextStep, attentionReason).all { it.isNotBlank() && it.length <= 2000 })
        require(events.isNotEmpty() && events.size <= 3 && events.distinct() == events)
        require(records.isNotEmpty() && records.size <= 30 && records.distinct() == records)
        require(evidenceIds.size <= 8 && evidenceIds.distinct() == evidenceIds && evidenceIds.all(HealthProfilePolicy::uuid))
        require(planId.isEmpty() || HealthProfilePolicy.uuid(planId))
        require(decision != HealthCareReviewDecision.PROPOSE_PLAN || planId.isNotEmpty())
        require(questions.size <= 30 && questions.map { it.id }.distinct().size == questions.size)
    }
    fun requireSubmission() {
        require(decision != HealthCareReviewDecision.CLARIFY || questions.isNotEmpty()) {
            "A clarification must reference retained questions"
        }
    }
    fun json() = JSONObject().put("summary", summary).put("rationale", rationale).put("uncertainty", uncertainty)
        .put("next_step", nextStep).put("decision", decision.name).put("review_events", JSONArray(events.map { it.name }))
        .put("records", JSONArray(records.map { it.json() })).put("evidence_ids", JSONArray(evidenceIds))
        .put("plan_id", planId).put("attention_requested", attentionRequested).put("attention_reason", attentionReason)
        .put("questions", JSONArray(questions.map { it.json() }))
    companion object {
        private val keys = setOf("summary", "rationale", "uncertainty", "next_step", "decision", "review_events",
            "records", "evidence_ids", "plan_id", "attention_requested", "attention_reason", "questions")
        fun parse(input: AgentNativeJsonObject): HealthCareModelReviewInput {
            require(input.keys == keys)
            require(input["attention_requested"] is Boolean)
            require(listOf("summary", "rationale", "uncertainty", "next_step", "decision", "plan_id", "attention_reason")
                .all { input[it] is String })
            listOf("records", "questions").forEach { key ->
                val rows = input[key] as? List<*> ?: throw IllegalArgumentException()
                rows.forEach {
                    val row = it as? Map<*, *> ?: throw IllegalArgumentException()
                    require(row.keys == setOf("id", "revision") && row["id"] is String)
                    val revision = row["revision"] as? Number ?: throw IllegalArgumentException()
                    require(revision.toDouble() == revision.toInt().toDouble())
                }
            }
            listOf("review_events", "evidence_ids").forEach { key ->
                require((input[key] as? List<*>)?.all { it is String } == true)
            }
            return from(JSONObject(input)).also { it.requireSubmission() }
        }
        fun from(j: JSONObject): HealthCareModelReviewInput {
            val events = j.getJSONArray("review_events")
            val records = j.getJSONArray("records")
            val evidence = j.getJSONArray("evidence_ids")
            return HealthCareModelReviewInput(j.getString("summary"), j.getString("rationale"), j.getString("uncertainty"),
                j.getString("next_step"), HealthCareReviewDecision.valueOf(j.getString("decision")),
                List(events.length()) { HealthCareReviewEvent.valueOf(events.getString(it)) },
                List(records.length()) { HealthCareRecordRef.from(records.getJSONObject(it)) },
                List(evidence.length()) { evidence.getString(it) }, j.getString("plan_id"),
                j.getBoolean("attention_requested"), j.getString("attention_reason"),
                j.optJSONArray("questions")?.let { rows -> List(rows.length()) { HealthCareQuestionRef.from(rows.getJSONObject(it)) } }.orEmpty())
        }
    }
}

internal data class HealthCareModelReview(val grant: HealthCareDiscussionGrant, val trigger: String,
    val inputVersion: String, val createdAt: Long, val input: HealthCareModelReviewInput) {
    init {
        require(grant.researchAuthorizationId.isNotEmpty() && trigger.matches(Regex("[0-9a-f]{64}")))
        require(inputVersion.isNotBlank() && createdAt >= grant.approvedAt)
    }
    fun json() = JSONObject().put("grant", grant.json()).put("trigger", trigger).put("input_version", inputVersion)
        .put("created_at", createdAt).put("assessment", input.json())
    fun reusable(next: HealthCareDiscussionGrant): Boolean = grant.turnId != next.turnId &&
        grant.concernId == next.concernId && grant.conversationId == next.conversationId && grant.destination == next.destination &&
        grant.privacyVersion == next.privacyVersion && grant.settingsVersion == next.settingsVersion &&
        grant.targetId == next.targetId && grant.modelId == next.modelId && grant.effort == next.effort &&
        grant.profileLink == next.profileLink && (!grant.questionsShared || next.questionsShared) &&
        (!grant.feedbackHistoryShared || next.feedbackHistoryShared) && next.related.keys.containsAll(grant.related.keys) && createdAt <= next.approvedAt
    companion object {
        fun from(j: JSONObject) = HealthCareModelReview(HealthCareDiscussionGrant.from(j.getJSONObject("grant")),
            j.getString("trigger"), j.getString("input_version"), j.getLong("created_at"),
            HealthCareModelReviewInput.from(j.getJSONObject("assessment")))
    }
}
