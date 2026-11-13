package com.galaxyssi.chat

import android.content.Context

internal object HealthCareModelReviewTool {
    const val ID = "galaxyssi.health.review.record"
    private fun text(max: Int) = AgentNativeJsonSchema.string(minLength = 1, maxLength = max)
    fun definition(record: (AgentNativeToolInvocationContext, HealthCareModelReviewInput) -> HealthCareModelReview) = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(ID, "1.0.0", "Record this automatic health assessment",
            "Finish an authorized automatic review with one durable structured assessment before the final answer. " +
                "Use exact record IDs/revisions from the primary snapshot and explicitly selected related measurements; " +
                "include at least one primary record. Use only current-turn evidence receipts. " +
                "Separate facts, reasoning and uncertainty; do not invent evidence. An empty evidence list means no retrieved support. " +
                "A PROPOSE_PLAN decision requires plan_id from health.plan.propose in this turn. " +
                "Review events are conditions, not scheduled checks. Attention is a recommendation, not a sent notification. " +
                "No diagnosis, medication change, target confirmation, reminder or concern closure is performed. " +
                "Submit the final assessment only once; identical retries return the same receipt.",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "summary" to text(1000), "rationale" to text(2000), "uncertainty" to text(2000), "next_step" to text(2000),
                "decision" to AgentNativeJsonSchema.string(enumValues = HealthCareReviewDecision.entries.map { it.name }),
                "review_events" to AgentNativeJsonSchema.array(AgentNativeJsonSchema.string(enumValues = HealthCareReviewEvent.entries.map { it.name }), minItems = 1, maxItems = 3),
                "records" to AgentNativeJsonSchema.array(AgentNativeJsonSchema.objectSchema(properties = mapOf(
                    "id" to text(36), "revision" to AgentNativeJsonSchema.integer(minimum = 1)),
                    required = setOf("id", "revision"), additionalProperties = false), minItems = 1, maxItems = 30),
                "evidence_ids" to AgentNativeJsonSchema.array(text(36), minItems = 0, maxItems = 8),
                "plan_id" to AgentNativeJsonSchema.string(maxLength = 36),
                "attention_requested" to AgentNativeJsonSchema.boolean(), "attention_reason" to text(2000)
            ), required = setOf("summary", "rationale", "uncertainty", "next_step", "decision", "review_events", "records",
                "evidence_ids", "plan_id", "attention_requested", "attention_reason"), additionalProperties = false),
            AgentNativeJsonSchema.objectSchema(additionalProperties = true), AgentNativeToolRisk.MEDIUM,
            capabilities = setOf("health.review.record"), effect = AgentNativeToolEffect.MUTATION,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT),
        executor = AgentNativeToolExecutor { call ->
            try {
                val value = record(call.context, HealthCareModelReviewInput.parse(call.input))
                AgentNativeToolExecutionResult.success(mapOf("review_id" to value.grant.turnId, "stored" to true,
                    "clinical_verification" to false, "scheduled" to false, "notification_sent" to false, "concern_closed" to false))
            } catch (_: HealthCareConflict) {
                AgentNativeToolExecutionResult.failure("health_review_scope_changed",
                    "The approved concern, evidence, plan or authorization changed. Do not reuse another turn's data or overwrite a recorded assessment.")
            } catch (_: IllegalArgumentException) {
                AgentNativeToolExecutionResult.failure("invalid_health_review",
                    "Supply all structured fields, exact current snapshot record references, unique review_events and evidence_ids. Do not supply approval or execution flags.")
            }
        })
    fun definitions(context: Context) = listOf(definition { invocation, input ->
        if (!HealthCareDiscussion.bound(context, invocation.conversationId) ||
            HealthCareDiscussion.rejection(context, invocation.conversationId, invocation.turnId) != null) throw HealthCareConflict()
        HealthCareStore(context).use { store ->
            val grant = store.discussionGrant(invocation.turnId) ?: throw HealthCareConflict()
            store.recordModelReview(grant, input, System.currentTimeMillis())
        }
    })
}
