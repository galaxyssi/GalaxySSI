package com.galaxyssi.chat

import org.json.JSONObject

internal enum class HealthCareAnswerState { PENDING, ACCEPTED, DISMISSED }

/** A model extraction is not a saved health fact until a local user review accepts it. */
internal data class HealthCareAnswerDraft(val id: String, val grant: HealthCareDiscussionGrant,
    val questionId: String, val questionRevision: Int, val basis: String, val scope: String,
    val sourceId: String, val quote: String, val answer: String, val createdAt: Long,
    val state: HealthCareAnswerState = HealthCareAnswerState.PENDING, val reviewedAt: Long = 0,
    val reviewedAnswer: String = "") {
    init {
        require(listOf(id, questionId).all(HealthProfilePolicy::uuid) && sourceId.isNotBlank())
        require(questionRevision > 0 && createdAt > 0 && reviewedAt >= 0)
        require(listOf(basis, scope).all { it.matches(Regex("[0-9a-f]{64}")) })
        require(quote.isNotBlank() && quote.length <= 2000 && answer.isNotBlank() && answer.length <= 2000)
        require(reviewedAnswer.length <= 2000 && (state == HealthCareAnswerState.ACCEPTED) == reviewedAnswer.isNotBlank())
        require((state == HealthCareAnswerState.PENDING) == (reviewedAt == 0L))
        require(grant.questionsShared && grant.researchAuthorizationId.isEmpty() && grant.userInputDigest.isNotEmpty())
    }
    fun json() = JSONObject().put("id", id).put("grant", grant.json()).put("question", questionId)
        .put("question_revision", questionRevision).put("basis", basis).put("scope", scope)
        .put("source", sourceId).put("quote", quote).put("answer", answer).put("created_at", createdAt)
        .put("state", state.name).put("reviewed_at", reviewedAt).put("reviewed_answer", reviewedAnswer)
    companion object {
        fun from(j: JSONObject) = HealthCareAnswerDraft(j.getString("id"), HealthCareDiscussionGrant.from(j.getJSONObject("grant")),
            j.getString("question"), j.getInt("question_revision"), j.getString("basis"), j.getString("scope"),
            j.getString("source"), j.getString("quote"), j.getString("answer"), j.getLong("created_at"),
            HealthCareAnswerState.valueOf(j.getString("state")), j.getLong("reviewed_at"), j.getString("reviewed_answer"))
    }
}

internal data class HealthCareAnswerPage(val items: List<HealthCareAnswerDraft>, val next: String?)

internal object HealthCareAnswerPolicy {
    fun userSource(grant: HealthCareDiscussionGrant, entry: AgentTranscriptEntry?, quote: String): Boolean =
        grant.questionsShared && grant.researchAuthorizationId.isEmpty() && grant.userInputDigest.isNotEmpty() &&
            entry != null && entry.role == AgentTranscriptRole.USER && entry.conversationId == grant.conversationId &&
            entry.turnId == grant.turnId && AgentNativeJsonCodec.sha256(entry.text.trim()) == grant.userInputDigest &&
            quote.isNotBlank() && quote.length <= 2000 && entry.text.contains(quote)

    fun current(draft: HealthCareAnswerDraft, issue: HealthCareConcern, question: HealthCareQuestion,
        settings: HealthCareSettings, privacy: HealthPrivacyPolicy): Boolean =
        settings.enabled && privacy.metrics && privacy.profile && draft.grant.settingsVersion == settings.version &&
            draft.grant.privacyVersion == privacy.version && draft.grant.concernId == issue.id &&
            draft.questionId == question.id && question.concernId == issue.id && draft.questionRevision == question.revision &&
            draft.scope == HealthCareQuestionPolicy.scope(issue) && question.scope == draft.scope &&
            draft.basis == HealthCareQuestionPolicy.basis(issue) && draft.grant.profileLink == issue.profileLink &&
            HealthCareSignal.SOURCE_REMOVED !in issue.assessment.signals
}
