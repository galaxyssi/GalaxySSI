package com.galaxyssi.chat

import android.content.Context

internal object HealthCarePlanTool {
    const val ID = "galaxyssi.health.plan.propose"
    private fun text(max: Int, description: String = "") = AgentNativeJsonSchema.string(minLength = 1, maxLength = max, description = description)
    private val source = AgentNativeJsonSchema.objectSchema(properties = mapOf(
        "title" to text(300), "url" to text(1000, "HTTPS source URL actually read. The same URL may support distinct quoted passages; do not duplicate the same receipt and quote."),
        "version" to text(80, "Source version/publication date, or explicitly unknown."),
        "applicability" to text(2000, "Population, limitations and why the source applies to this concern. This remains a model assessment."),
        "evidence_id" to text(36, "Exact native health_evidence evidence_id returned by galaxyssi.web.intelligence.fetch in this approved turn."),
        "supporting_quote" to AgentNativeJsonSchema.string(minLength = 12, maxLength = 600,
            description = "Short exact original-language passage from that receipt's excerpt supporting the proposed action. Do not translate or combine nonadjacent sentences.")
    ), required = setOf("title", "url", "version", "applicability", "evidence_id", "supporting_quote"), additionalProperties = false)
    private val action = AgentNativeJsonSchema.objectSchema(properties = mapOf(
        "kind" to AgentNativeJsonSchema.string(enumValues = HealthCareActionKind.entries.map { it.name }),
        "description" to text(1000), "rationale" to text(2000, "Reason for this action and any suggested time window."),
        "source_index" to AgentNativeJsonSchema.integer(minimum = 0, maximum = 7),
        "applicability" to HealthCareApplicabilitySchema.schema,
        "due_from" to AgentNativeJsonSchema.string(maxLength = 40, description = "ISO-8601 date/time with offset, or empty when no justified window exists."),
        "due_until" to AgentNativeJsonSchema.string(maxLength = 40, description = "End of the justified review window, with offset; empty with due_from. Not a reminder authorization.")
    ), required = setOf("kind", "description", "rationale", "source_index", "due_from", "due_until", "applicability"), additionalProperties = false)

    private val target = AgentNativeJsonSchema.objectSchema(properties = mapOf(
        "field" to text(80, "One required measurement component from the concern, never a composite value."),
        "low" to AgentNativeJsonSchema.string(maxLength = 20, description = "Exact decimal lower bound or empty for no lower bound. Not a reference-range midpoint."),
        "high" to AgentNativeJsonSchema.string(maxLength = 20, description = "Exact decimal upper bound or empty for no upper bound. At least one bound is required."),
        "unit" to text(32, "Must match the current measurement unit; do not silently convert."),
        "low_inclusive" to AgentNativeJsonSchema.boolean(), "high_inclusive" to AgentNativeJsonSchema.boolean(),
        "rationale" to text(2000, "Why this target applies to this person, limitations, and why it is not just a diagnostic/reference threshold. No medication instructions."),
        "source_index" to AgentNativeJsonSchema.integer(minimum = 0, maximum = 7),
        "applicability" to HealthCareApplicabilitySchema.schema
    ), required = setOf("field", "low", "high", "unit", "low_inclusive", "high_inclusive", "rationale", "source_index", "applicability"), additionalProperties = false)

    fun definition(submit: (AgentNativeToolInvocationContext, AgentNativeJsonObject) -> HealthCarePlan) = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(ID, "1.3.0", "Propose a health follow-up plan",
            "Submit one final draft per approved health-discussion turn for user review in the Agent page. " +
                "No action is confirmed or scheduled. Include per-action applicability checks, missing factors, source conflicts and justified review windows. " +
                "Read the actual population/limitations passages; when applicability is unresolved, propose context clarification or clinician discussion, not an assumed eligible plan. " +
                "Do not prescribe medication changes, manufacture an optimal numerical target, or delay urgent care. " +
                "Optionally include target_proposal only when source-backed individual applicability is justified. It remains unconfirmed; updating an existing target needs a new review. " +
                "Use clinician discussion items when professional assessment is required. Do not claim citations are independently verified.",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "uncertainty" to text(2000, "Missing context, contraindications and remaining uncertainty; explicitly say when none is known."),
                "sources" to AgentNativeJsonSchema.array(source, minItems = 1, maxItems = 8),
                "actions" to AgentNativeJsonSchema.array(action, minItems = 0, maxItems = 8), "target_proposal" to target
            ), required = setOf("uncertainty", "sources", "actions"), additionalProperties = false),
            AgentNativeJsonSchema.objectSchema(additionalProperties = true), AgentNativeToolRisk.MEDIUM,
            capabilities = setOf("health.plan.propose"), effect = AgentNativeToolEffect.MUTATION,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT),
        executor = AgentNativeToolExecutor { call ->
            try {
                val plan = submit(call.context, call.input)
                AgentNativeToolExecutionResult.success(mapOf("proposal_id" to plan.id, "state" to plan.state.name.lowercase(),
                    "action_count" to plan.actions.size, "scheduled" to false, "evidence_verified" to false,
                    "target_proposed" to (plan.target != null), "target_confirmed" to false,
                    "retrieval_receipts" to plan.sources.count { it.evidence != null }, "applicability_review_count" to plan.applicability.size,
                    "message" to "Draft retained for explicit user review. Native receipts verify retrieval and exact quotes, not medical applicability. No care action or reminder was performed."))
            } catch (_: HealthCareEvidenceMissing) {
                AgentNativeToolExecutionResult.failure("health_evidence_missing",
                    "Read each source with galaxyssi.web.intelligence.fetch in this approved turn. Use its health_evidence evidence_id, exact URL and a supporting original-language excerpt. Search snippets, another turn's receipts and invented quotes cannot ground a care plan. If retrieval fails, explain the evidence gap instead of inventing a plan.")
            } catch (_: HealthCareConflict) {
                AgentNativeToolExecutionResult.failure("health_scope_changed", "Concern, approval or draft changed. Ask the user to review the current concern; do not retry stale data.")
            } catch (_: IllegalArgumentException) {
                AgentNativeToolExecutionResult.failure("invalid_health_plan", "Use source-backed actions and/or a target_proposal, applicability (mode/checks/missing_information/conflicts), valid source indices and paired ISO timestamps with offsets. DISCUSSION_ONLY is only for CONTEXT/CLINICIAN_DISCUSSION. Targets require INDIVIDUALIZED applicability, bounded decimal strings and explicit inclusive/exclusive bounds. Do not supply confirmation, patient context or verification flags. No extra fields or past review windows.")
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
