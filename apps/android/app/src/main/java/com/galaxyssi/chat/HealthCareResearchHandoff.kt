package com.galaxyssi.chat

import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject

/** Describe why this run exists without turning elapsed time into new clinical evidence. */
internal object HealthCareResearchHandoff {
    fun reusable(value: HealthCareEvidence, grant: HealthCareDiscussionGrant): Boolean =
        value.grant.concernId == grant.concernId && value.grant.conversationId == grant.conversationId &&
            value.grant.turnId != grant.turnId && value.grant.destination == grant.destination &&
            value.grant.privacyVersion == grant.privacyVersion && value.grant.settingsVersion == grant.settingsVersion &&
            value.grant.profileLink == grant.profileLink &&
            value.observedAt <= grant.approvedAt

    fun snapshot(issue: HealthCareConcern, job: HealthCareResearchJob,
        previous: HealthCareResearchJob?, before: HealthCareConcern?, sources: List<HealthCareEvidence> = emptyList(),
        recordedPlanExists: Boolean = false, modelReview: HealthCareModelReview? = null): JSONObject {
        require(job.concernId == issue.id && job.conversationId == issue.conversationId && job.revision == issue.revision)
        val prior = previous?.takeIf { it.state == HealthCareResearchState.COMPLETED && it.turnId != job.turnId &&
            it.concernId == issue.id && it.conversationId == job.conversationId && it.createdAt <= job.createdAt }
        val baseline = before?.takeIf { prior != null && it.id == issue.id && it.revision == prior.revision &&
            it.conversationId == issue.conversationId }
        fun due(value: HealthCareConcern, at: Long) = value.actions.filter {
            it.state == HealthCareActionState.CONFIRMED && it.dueFrom?.let { from -> from <= at } == true
        }
        fun changed(values: List<HealthCareAction>, priorValues: List<HealthCareAction>) = values.filter { value ->
            priorValues.none { it.copy(feedback = null) == value.copy(feedback = null) }
        }.map { it.id }
        val elapsed = due(issue, job.createdAt)
        val newlyDue = changed(elapsed, if (baseline != null) due(baseline, prior!!.createdAt) else emptyList())
        val outcomes = changed(issue.actions.filter { it.state == HealthCareActionState.DONE },
            baseline?.actions?.filter { it.state == HealthCareActionState.DONE }.orEmpty())
        val feedback = issue.actions.filter { action -> action.feedback != null &&
            baseline?.actions?.firstOrNull { it.id == action.id }?.feedback?.id != action.feedback.id }.map { it.id }
        val reasons = buildList {
            if (baseline == null) add(if (prior == null) "initial_review" else "prior_context_unavailable")
            else {
                if (issue.assessment.record != baseline.assessment.record) add(
                    if (issue.assessment.record?.id != baseline.assessment.record?.id) "new_measurement" else "record_corrected")
                else if (issue.inputVersion != baseline.inputVersion) add("measurement_history_changed")
                if (issue.context != baseline.context) add("measurement_context_changed")
                if (issue.questionVersion != baseline.questionVersion) add("question_response_changed")
                if (issue.profileLink != baseline.profileLink) add("selected_profile_changed")
                if (issue.target != baseline.target || issue.targetRevision != baseline.targetRevision) add("reviewed_target_changed")
                if (outcomes.isNotEmpty() || feedback.isNotEmpty()) add("action_feedback")
                if (newlyDue.isNotEmpty()) add("review_due")
                if (isEmpty()) add("authorization_review")
            }
        }
        return JSONObject().put("observed_at", Instant.ofEpochMilli(job.createdAt).toString())
            .put("structured_review_required", job.reviewRequired)
            .put("prior_model_assessment", modelReview?.takeIf { it.grant.turnId == prior?.turnId &&
                it.grant.concernId == issue.id && it.grant.conversationId == job.conversationId }?.let {
                JSONObject().put("assessment", it.input.json()).put("input_version", it.inputVersion)
                    .put("created_at", Instant.ofEpochMilli(it.createdAt).toString())
                    .put("clinical_verification", false).put("actions_executed", false)
            } ?: JSONObject.NULL)
            .put("reasons", JSONArray(reasons)).put("comparison_available", baseline != null)
            .put("elapsed_time_only", baseline != null && reasons == listOf("review_due"))
            .put("newly_due_action_ids", if (baseline == null) JSONObject.NULL else JSONArray(newlyDue))
            .put("due_action_ids", JSONArray(elapsed.map { it.id }))
            .put("new_outcome_action_ids", if (baseline == null) JSONObject.NULL else JSONArray(outcomes))
            .put("new_feedback_action_ids", if (baseline == null) JSONObject.NULL else JSONArray(feedback))
            .put("research_progress", JSONObject().put("prior_response_completed", prior != null)
                .put("source_context_available", sources.isNotEmpty()).put("recorded_plan_exists", recordedPlanExists)
                .put("recorded_action_count", issue.actions.size)
                .put("initial_source_review_pending", sources.isEmpty() && !recordedPlanExists && issue.actions.isEmpty()))
            .put("prior_automatic_source_reads", JSONArray(sources.take(8).map { source ->
                JSONObject().put("url", source.url).put("title", source.title)
                    .put("retrieved_at", Instant.ofEpochMilli(source.retrievedAt).toString())
                    .put("content_sha256", source.contentHash).put("excerpt", source.excerpt.take(1000))
                    .put("excerpt_truncated", source.excerpt.length > 1000)
                    .put("medical_applicability_verified", false).put("usable_for_new_plan", false)
            }))
            .put("previous_review", prior?.let { JSONObject().put("turn_id", it.turnId).put("revision", it.revision)
                .put("started_at", Instant.ofEpochMilli(it.createdAt).toString()) } ?: JSONObject.NULL)
    }
}
