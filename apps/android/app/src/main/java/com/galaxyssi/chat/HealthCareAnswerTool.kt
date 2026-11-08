package com.galaxyssi.chat

import org.json.JSONObject

internal object HealthCareAnswerTool {
    const val ID = "galaxyssi.health.answers.propose"
    fun definitions(execute: (String, AgentNativeToolInvocationContext, AgentNativeJsonObject) -> JSONObject) = listOf(
        AgentNativeToolDefinition(AgentNativeToolDescriptor(ID, "1.0.0", "Stage a health answer for user review",
            "Extract only from the current human message, with an exact quote and question ID/revision from the authorized ledger. " +
                "Creates a pending draft only. The user must review it in the existing health entry before it becomes a saved self-report. " +
                "No confirmation, clinical fact, profile/measurement edit or reminder is created. Same question and turn reuse the first draft, including a dismissal.",
            AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "question_id" to AgentNativeJsonSchema.string(minLength = 36, maxLength = 36),
                "question_revision" to AgentNativeJsonSchema.integer(minimum = 1),
                "quote" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 2000),
                "answer" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 2000)
            ), required = setOf("question_id", "question_revision", "quote", "answer"), additionalProperties = false),
            AgentNativeJsonSchema.objectSchema(additionalProperties = true), AgentNativeToolRisk.MEDIUM,
            capabilities = setOf("health.answers.propose"), effect = AgentNativeToolEffect.MUTATION,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT), AgentNativeToolExecutor { call ->
            try { AgentNativeToolExecutionResult.success(execute(ID, call.context, call.input).toNativeObject()) }
            catch (_: HealthCareConflict) { AgentNativeToolExecutionResult.failure("health_answer_review_required",
                "The authorized source or question is unavailable or changed. Do not invent a quote or save a fact. The user can review the question in Personal Health.") }
            catch (_: IllegalArgumentException) { AgentNativeToolExecutionResult.failure("invalid_health_answer_draft",
                "Use only question_id, question_revision, an exact quote from this human message and a proposed answer. Confirmation is a user-only action.") }
        }))

    fun stage(care: HealthCareStore, grant: HealthCareDiscussionGrant, input: AgentNativeJsonObject,
        source: AgentTranscriptEntry?, now: Long): JSONObject {
        require(input.keys == setOf("question_id", "question_revision", "quote", "answer"))
        val id = input["question_id"] as? String ?: ""
        val revision = input["question_revision"] as? Number ?: throw IllegalArgumentException()
        require(HealthProfilePolicy.uuid(id) && revision.toDouble() == revision.toInt().toDouble() && revision.toInt() > 0)
        val draft = care.proposeAnswer(grant, id, revision.toInt(), source ?: throw HealthCareConflict(),
            input["quote"] as? String ?: "", input["answer"] as? String ?: "", now)
        return JSONObject().put("draft_id", draft.id).put("review_state", draft.state.name)
            .put("user_confirmation_required", draft.state == HealthCareAnswerState.PENDING)
            .put("answer_saved_by_tool", false).put("writes_modify_measurements_or_profile", false)
    }
}
