package com.galaxyssi.chat

import android.content.Context

internal object HealthCarePlanTool {
    const val ID = "galaxyssi.health.plan.propose"
    private fun text(max: Int, description: String = "") = AgentNativeJsonSchema.string(minLength = 1, maxLength = max, description = description)
    private val source = AgentNativeJsonSchema.objectSchema(properties = mapOf(
        "title" to text(300), "url" to text(1000, "HTTPS source URL actually read, not an invented citation."),
        "version" to text(80, "Source version/publication date, or explicitly unknown."),
        "applicability" to text(2000, "Population, limitations and why the source applies to this concern.")
    ), required = setOf("title", "url", "version", "applicability"), additionalProperties = false)
    private val action = AgentNativeJsonSchema.objectSchema(properties = mapOf(
        "kind" to AgentNativeJsonSchema.string(enumValues = HealthCareActionKind.entries.map { it.name }),
        "description" to text(1000), "rationale" to text(2000, "Reason for this action and any suggested time window."),
        "source_index" to AgentNativeJsonSchema.integer(minimum = 0, maximum = 7),
        "due_from" to AgentNativeJsonSchema.string(maxLength = 40, description = "ISO-8601 date/time with offset, or empty when no justified window exists."),
        "due_until" to AgentNativeJsonSchema.string(maxLength = 40, description = "End of the justified review window, with offset; empty with due_from. Not a reminder authorization.")
    ), required = setOf("kind", "description", "rationale", "source_index", "due_from", "due_until"), additionalProperties = false)

    fun definition(submit: (AgentNativeToolInvocationContext, AgentNativeJsonObject) -> HealthCarePlan) = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(ID, "1.0.0", "Propose a health follow-up plan",
            "Submit one final draft per approved health-discussion turn for user review in the Agent page. " +
                "No action is confirmed or scheduled. Include uncertainties, evidence applicability and justified review windows. " +
                "Do not prescribe medication changes, manufacture an optimal numerical target, or delay urgent care. " +
                "Use clinician discussion items when professional assessment is required. Do not claim citations are independently verified.",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "uncertainty" to text(2000, "Missing context, contraindications and remaining uncertainty; explicitly say when none is known."),
                "sources" to AgentNativeJsonSchema.array(source, minItems = 1, maxItems = 8),
                "actions" to AgentNativeJsonSchema.array(action, minItems = 1, maxItems = 8)
            ), required = setOf("uncertainty", "sources", "actions"), additionalProperties = false),
            AgentNativeJsonSchema.objectSchema(additionalProperties = true), AgentNativeToolRisk.MEDIUM,
            capabilities = setOf("health.plan.propose"), effect = AgentNativeToolEffect.MUTATION,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT),
        executor = AgentNativeToolExecutor { call ->
            try {
                val plan = submit(call.context, call.input)
                AgentNativeToolExecutionResult.success(mapOf("proposal_id" to plan.id, "state" to plan.state.name.lowercase(),
                    "action_count" to plan.actions.size, "scheduled" to false, "evidence_verified" to false,
                    "message" to "Draft retained for explicit user review. No care action or reminder was performed."))
            } catch (_: HealthCareConflict) {
                AgentNativeToolExecutionResult.failure("health_scope_changed", "Concern, approval or draft changed. Ask the user to review the current concern; do not retry stale data.")
            } catch (_: IllegalArgumentException) {
                AgentNativeToolExecutionResult.failure("invalid_health_plan", "Use complete source-backed actions, valid source indices and paired ISO timestamps with offsets. No extra fields or past review windows.")
            }
        })

    fun definitions(context: Context) = listOf(definition { invocation, input ->
        if (!HealthCareDiscussion.bound(context, invocation.conversationId) ||
            HealthCareDiscussion.rejection(context, invocation.conversationId, invocation.turnId) != null) throw HealthCareConflict()
        HealthCareStore(context).use { store ->
            val grant = store.discussionGrant(invocation.turnId) ?: throw HealthCareConflict()
            val concern = store.concern(grant.concernId) ?: throw HealthCareConflict()
            store.proposePlan(HealthCarePlanPolicy.parse(input, grant, concern, System.currentTimeMillis()))
        }
    })
}
