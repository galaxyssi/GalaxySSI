package com.galaxyssi.chat

import org.json.JSONObject

internal enum class HealthCareFeedbackKind { COMPLETED, PARTIAL, BARRIER }

internal data class HealthCareFeedback(val id: String, val kind: HealthCareFeedbackKind, val note: String,
    val recordedAt: Long, val basis: String, val scope: String) {
    init {
        require(HealthProfilePolicy.uuid(id) && note.isNotBlank() && note.length <= 2000 && recordedAt > 0)
        require(basis.isEmpty() || basis.matches(Regex("[0-9a-f]{64}")))
        require(scope.matches(Regex("[0-9a-f]{64}")))
    }
    fun json() = JSONObject().put("id", id).put("kind", kind.name).put("note", note).put("recorded_at", recordedAt)
        .put("basis", basis).put("scope", scope)
    companion object {
        fun from(j: JSONObject) = HealthCareFeedback(j.getString("id"), HealthCareFeedbackKind.valueOf(j.getString("kind")),
            j.getString("note"), j.getLong("recorded_at"), j.getString("basis"), j.getString("scope"))
    }
}

internal data class HealthCareFeedbackReceipt(val concernId: String, val actionId: String, val revision: Int,
    val actionTitle: String, val feedback: HealthCareFeedback) {
    init {
        require(HealthProfilePolicy.uuid(concernId) && HealthProfilePolicy.uuid(actionId) && revision > 1)
        require(actionTitle.isNotBlank() && actionTitle.length <= 1000)
    }
    fun json() = JSONObject().put("concern", concernId).put("action", actionId).put("revision", revision)
        .put("action_title", actionTitle).put("feedback", feedback.json())
    companion object {
        fun from(j: JSONObject) = HealthCareFeedbackReceipt(j.getString("concern"), j.getString("action"),
            j.getInt("revision"), j.getString("action_title"), HealthCareFeedback.from(j.getJSONObject("feedback")))
    }
}

internal data class HealthCareFeedbackPage(val items: List<HealthCareFeedbackReceipt>, val next: Int?)

internal object HealthCareFeedbackPolicy {
    fun apply(issue: HealthCareConcern, actionId: String, feedback: HealthCareFeedback): HealthCareConcern {
        val action = issue.actions.firstOrNull { it.id == actionId } ?: throw HealthCareConflict()
        if (action.state != HealthCareActionState.CONFIRMED || !issue.open || feedback.basis != action.basis ||
            feedback.scope != HealthCareQuestionPolicy.scope(issue)) throw HealthCareConflict()
        val done = feedback.kind == HealthCareFeedbackKind.COMPLETED
        return issue.copy(actions = issue.actions.map { if (it.id == actionId) it.copy(feedback = feedback,
            state = if (done) HealthCareActionState.DONE else it.state, outcome = if (done) feedback.note else it.outcome) else it },
            stage = if (issue.stage == HealthCareStage.PAUSED) issue.stage else HealthCareStage.REASSESS,
            updatedAt = maxOf(issue.updatedAt, feedback.recordedAt))
    }
    fun modelAction(issue: HealthCareConcern, action: HealthCareAction): JSONObject = action.json().apply {
        action.feedback?.let { value ->
            if (value.scope != HealthCareQuestionPolicy.scope(issue)) {
                remove("feedback"); remove("outcome"); put("feedback_outside_current_scope", true)
            } else put("feedback", value.json().put("self_reported", true).put("health_improvement_verified", false)
                .put("plan_basis_current", value.basis.isNotEmpty() && value.basis == HealthCareFollowUpPolicy.basis(issue))
                .put("history_included", false))
        }
    }
}
