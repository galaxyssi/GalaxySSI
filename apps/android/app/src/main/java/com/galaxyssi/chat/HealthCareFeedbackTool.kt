package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal object HealthCareFeedbackTool {
    const val ID = "galaxyssi.health.feedback.read"

    fun cursor(input: AgentNativeJsonObject): Int? {
        require(input.keys.all { it in setOf("input_version", "revision", "before_revision") })
        require(input["input_version"] is String)
        integer(input["revision"])
        return if (input.containsKey("before_revision")) integer(input["before_revision"]) else null
    }
    private fun integer(value: Any?): Int {
        require(value is Number && value.toDouble().isFinite() && value.toDouble() == value.toInt().toDouble() && value.toInt() > 0)
        return value.toInt()
    }

    fun definition(read: (AgentNativeToolInvocationContext, AgentNativeJsonObject) -> JSONObject) = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(ID, "1.0.0", "Read this health concern's action feedback",
            "Read at most 30 saved feedback entries in descending revision order, only after this turn's explicit health-sharing approval. " +
                "Use the approved snapshot input_version and revision. Follow next as before_revision; omit it for the first page. " +
                "Redacted entries are outside the current sharing scope. Execution feedback is self-reported, not verified improvement. " +
                "No arbitrary patient, concern or action selector; no writes, new reminders, treatment changes or original medical files.",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "input_version" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 256),
                "revision" to AgentNativeJsonSchema.integer(minimum = 1),
                "before_revision" to AgentNativeJsonSchema.integer(minimum = 1)
            ), required = setOf("input_version", "revision"), additionalProperties = false),
            AgentNativeJsonSchema.objectSchema(additionalProperties = true), AgentNativeToolRisk.LOW,
            capabilities = setOf("health.feedback.read"), effect = AgentNativeToolEffect.READ_ONLY,
            concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY, idempotency = AgentNativeToolIdempotency.IDEMPOTENT),
        executor = AgentNativeToolExecutor { call ->
            try { AgentNativeToolExecutionResult.success(read(call.context, call.input).toNativeObject()) }
            catch (_: HealthCareConflict) { AgentNativeToolExecutionResult.failure("health_scope_changed",
                "The approved feedback scope, concern or sources changed or expired. Obtain a current user review; do not combine stale pages.") }
            catch (_: IllegalArgumentException) { AgentNativeToolExecutionResult.failure("invalid_health_feedback_cursor",
                "Supply the approved input_version and revision and, for older entries, the exact next before_revision.") }
        })

    fun definitions(context: Context) = listOf(definition { invocation, input ->
        if (!HealthCareDiscussion.bound(context, invocation.conversationId) ||
            HealthCareDiscussion.rejection(context, invocation.conversationId, invocation.turnId) != null) throw HealthCareConflict()
        val result = read(context, HealthOverviewDatabases(), invocation, input)
        if (HealthCareDiscussion.rejection(context, invocation.conversationId, invocation.turnId) != null) throw HealthCareConflict()
        result
    })

    internal fun read(context: Context, names: HealthOverviewDatabases, invocation: AgentNativeToolInvocationContext,
        input: AgentNativeJsonObject, now: Long = System.currentTimeMillis()): JSONObject {
        val before = cursor(input)
        return HealthCareStore(context, names.care).use { care ->
            val grant = care.discussionGrant(invocation.turnId) ?: throw HealthCareConflict()
            val issue = care.concern(grant.concernId) ?: throw HealthCareConflict()
            val settings = care.settings()
            HealthPrivacyStore(context, names.privacy).use { privacy ->
                val permission = privacy.policy()
                HealthRecordStore(context, names.records).use { records ->
                    fun current() = grant.feedbackHistoryShared &&
                        (grant.targetId == "local-llm" || permission.online) &&
                        HealthCareDiscussionPolicy.permitted(grant, invocation.conversationId, invocation.turnId, issue,
                            settings, permission, grant.destination, now) && care.discussion(invocation.conversationId) == issue.id &&
                        input["input_version"] == issue.inputVersion && integer(input["revision"]) == issue.revision &&
                        care.discussionGrant(invocation.turnId) == grant && care.researchGrantCurrent(grant) &&
                        care.concern(issue.id)?.revision == issue.revision && care.settings() == settings && privacy.policy() == permission &&
                        HealthCareProfileAccess.current(context, grant.profileLink, names) &&
                        issue.inputVersion == HealthCareEngine.inputVersion(settings.version, permission.version, records.metricVersion(issue.metric))
                    if (!current()) throw HealthCareConflict()
                    require(before == null || before <= issue.revision)
                    val page = privacy.track(HealthAccessScope(HealthAccessPurpose.PROACTIVE_CARE, setOf(issue.metric))) {
                        care.feedback(issue.id, beforeRevision = before ?: Int.MAX_VALUE)
                    }
                    val result = JSONObject().put("protocol", HealthCareFeedbackObservation.PROTOCOL)
                        .put("input_version", issue.inputVersion).put("revision", issue.revision)
                        .put("page_start", before ?: JSONObject.NULL).put("next", page.next ?: JSONObject.NULL)
                        .put("done", page.next == null).put("items", JSONArray(page.items.map { modelRow(issue, it) }))
                        .put("health_improvement_verified", false)
                    if (!current()) throw HealthCareConflict()
                    result
                }
            }
        }
    }

    internal fun modelRow(issue: HealthCareConcern, receipt: HealthCareFeedbackReceipt): JSONObject {
        require(receipt.concernId == issue.id && receipt.revision <= issue.revision)
        val row = JSONObject().put("revision", receipt.revision)
        if (receipt.feedback.scope != HealthCareQuestionPolicy.scope(issue)) return row
            .put("redacted", true).put("reason", "outside_current_sharing_scope")
        val action = issue.actions.firstOrNull { it.id == receipt.actionId }
        val basisCurrent = receipt.feedback.basis.isNotEmpty() && receipt.feedback.basis == HealthCareFollowUpPolicy.basis(issue)
        return row.put("action_id", receipt.actionId).put("action_title", receipt.actionTitle)
            .put("action_in_current_plan", action != null).put("current_action_state", action?.state?.name ?: JSONObject.NULL)
            .put("kind", receipt.feedback.kind.name).put("note", receipt.feedback.note)
            .put("recorded_at", receipt.feedback.recordedAt).put("self_reported", true).put("health_improvement_verified", false)
            .put("plan_basis_current", basisCurrent)
            .put("action_requires_review", action == null || !basisCurrent || action.instruction?.invalidated == true)
            .apply { action?.instruction?.let {
                put("instruction_invalidated", it.invalidated).put("instruction_source_verified", false)
            } }
    }
}
