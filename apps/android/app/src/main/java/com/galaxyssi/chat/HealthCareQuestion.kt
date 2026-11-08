package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthCareQuestionState { OPEN, ANSWERED, DEFERRED, DECLINED, CONFLICT }

/** User answers are reviewed self-reports, not edits to a measurement or a prescription. */
internal data class HealthCareQuestion(val id: String, val concernId: String, val key: String,
    val question: String, val purpose: String, val basis: String, val scope: String,
    val record: HealthCareRecordRef?, val measuredAt: Long, val turnId: String,
    val revision: Int, val createdAt: Long, val updatedAt: Long,
    val state: HealthCareQuestionState = HealthCareQuestionState.OPEN, val answer: String = "") {
    init {
        require(listOf(id, concernId, turnId).all(HealthProfilePolicy::uuid))
        require(key.matches(Regex("[a-z][a-z0-9_.]{0,79}")))
        require(question.isNotBlank() && question.length <= 500 && purpose.isNotBlank() && purpose.length <= 1000)
        require(listOf(basis, scope).all { it.matches(Regex("[0-9a-f]{64}")) })
        require(revision > 0 && createdAt > 0 && updatedAt >= createdAt && measuredAt > 0 && answer.length <= 2000)
        require(if (state in setOf(HealthCareQuestionState.ANSWERED, HealthCareQuestionState.CONFLICT)) answer.isNotBlank() else answer.isEmpty())
    }
    fun json() = JSONObject().put("id", id).put("concern", concernId).put("key", key).put("question", question)
        .put("purpose", purpose).put("basis", basis).put("scope", scope).put("record", record?.json() ?: JSONObject.NULL)
        .put("measured_at", measuredAt).put("turn", turnId).put("revision", revision).put("created_at", createdAt)
        .put("updated_at", updatedAt).put("state", state.name).put("answer", answer)
    companion object {
        fun from(j: JSONObject) = HealthCareQuestion(j.getString("id"), j.getString("concern"), j.getString("key"),
            j.getString("question"), j.getString("purpose"), j.getString("basis"), j.getString("scope"),
            j.optJSONObject("record")?.let(HealthCareRecordRef::from), j.getLong("measured_at"), j.getString("turn"),
            j.getInt("revision"), j.getLong("created_at"), j.getLong("updated_at"),
            HealthCareQuestionState.valueOf(j.getString("state")), j.getString("answer"))
    }
}

internal data class HealthCareQuestionPage(val items: List<HealthCareQuestion>, val next: String?)

internal object HealthCareQuestionPolicy {
    fun scope(issue: HealthCareConcern) = AgentNativeJsonCodec.sha256(mapOf("profile" to issue.profileId,
        "selection" to issue.profileLink?.scope?.json()?.toString()))
    // Permission clocks and other answers are not new clinical facts.
    fun basis(issue: HealthCareConcern) = AgentNativeJsonCodec.sha256(mapOf(
        "record" to issue.assessment.record?.json()?.toString(), "measured_at" to issue.assessment.measuredAt,
        "context" to issue.context?.json()?.toString(),
        "profile" to issue.profileLink?.json()?.toString()))
    fun known(issue: HealthCareConcern, profile: HealthProfileContext?): Map<String, String> {
        val saved = HealthCareClarificationContext.snapshot(issue).getJSONObject("known_answers")
        val result = saved.keys().asSequence().associate { "context.$it" to saved.get(it).toString() }.toMutableMap()
        if (profile != null) HealthCareProfilePolicy.snapshot(requireNotNull(issue.profileLink), profile, issue.assessment.measuredAt)
            .getJSONObject("fields").let { fields -> fields.keys().forEach { key ->
                val value = fields.getJSONObject(key)
                if (value.getString("state") == "KNOWN") result["profile.${key.lowercase(java.util.Locale.ROOT)}"] = value.toString()
            } }
        return result
    }
    fun view(value: HealthCareQuestion, issue: HealthCareConcern, known: Map<String, String>): JSONObject {
        require(value.concernId == issue.id && value.scope == scope(issue))
        val stale = value.basis != basis(issue)
        val fact = known[value.key]
        val answered = !stale && value.state == HealthCareQuestionState.ANSWERED
        val conflict = fact != null && answered && value.answer != fact
        val state = when {
            conflict -> "CONFLICT"
            fact != null && value.state != HealthCareQuestionState.CONFLICT -> "ANSWERED"
            stale -> "STALE"
            else -> value.state.name
        }
        return JSONObject().put("id", value.id).put("revision", value.revision).put("key", value.key)
            .put("question", value.question).put("purpose", value.purpose).put("state", state)
            .put("stored_state", value.state.name).put("asked_record", value.record?.json() ?: JSONObject.NULL)
            .put("measured_at", value.measuredAt).put("updated_at", value.updatedAt)
            .put("saved_fact", fact ?: JSONObject.NULL)
            .put("reviewed_answer", if (!stale && value.answer.isNotEmpty()) value.answer else JSONObject.NULL)
            .put("source", if (fact != null) "saved_authorized_health_data" else "user_reviewed_question_ledger")
            .put("recheck_reason", if (stale) "Source revision or selected context changed; previous answers are not current." else "")
            .put("ask_again", state == "OPEN")
            .put("user_reopen_required", value.state in setOf(HealthCareQuestionState.DEFERRED, HealthCareQuestionState.DECLINED))
    }
    fun snapshot(page: HealthCareQuestionPage, issue: HealthCareConcern, profile: HealthProfileContext?): JSONObject {
        val facts = known(issue, profile)
        return JSONObject().put("items", JSONArray(page.items.map { view(it, issue, facts) }))
            .put("next", page.next ?: JSONObject.NULL).put("done", page.next == null)
            .put("question_version", issue.questionVersion).put("answers_are_self_reports", true)
            .put("writes_modify_measurements_or_profile", false)
    }
}
