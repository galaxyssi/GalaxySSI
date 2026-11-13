package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

internal object HealthCareHistoryTool {
    const val ID = "galaxyssi.health.history.read"
    fun cursor(input: AgentNativeJsonObject): HealthPageCursor? {
        val at = input["before_time"] as? Number
        val id = input["before_id"] as? String
        require((at == null) == (id == null))
        if (at == null) return null
        require(at.toDouble() == at.toLong().toDouble() && at.toLong() > 0 && HealthProfilePolicy.uuid(id!!))
        return HealthPageCursor(at.toLong(), id!!)
    }
    fun definition(read: (AgentNativeToolInvocationContext, AgentNativeJsonObject) -> JSONObject) = AgentNativeToolDefinition(
        descriptor = AgentNativeToolDescriptor(ID, "1.1.0", "Read authorized measurement history",
            "Read a contiguous page of up to 30 self-profile measurements. Omit metric for the primary concern; " +
                "supply metric only for an explicitly selected related_measurements entry. Use that metric's own input_version. " +
                "Omit both cursor fields for the recent page; " +
                "otherwise use next.before_time and next.before_id unchanged with the same metric. No value filtering, unselected metric or other person's records. " +
                "Read older pages when needed before claiming a longitudinal window. Numeric agreement is not clinical stability.",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(properties = mapOf(
                "input_version" to AgentNativeJsonSchema.string(minLength = 1, maxLength = 256),
                "metric" to AgentNativeJsonSchema.string(enumValues = HealthMetric.entries.map { it.name }),
                "before_time" to AgentNativeJsonSchema.integer(minimum = 1),
                "before_id" to AgentNativeJsonSchema.string(minLength = 36, maxLength = 36)
            ), required = setOf("input_version"), additionalProperties = false),
            AgentNativeJsonSchema.objectSchema(additionalProperties = true), AgentNativeToolRisk.LOW,
            capabilities = setOf("health.history.read"), effect = AgentNativeToolEffect.READ_ONLY,
            concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY, idempotency = AgentNativeToolIdempotency.IDEMPOTENT),
        executor = AgentNativeToolExecutor { call ->
            try { AgentNativeToolExecutionResult.success(read(call.context, call.input).toNativeObject()) }
            catch (_: HealthCareConflict) { AgentNativeToolExecutionResult.failure("health_scope_changed",
                "The authorized concern, source history or privacy approval changed. Request a current review; do not combine stale pages.") }
            catch (_: IllegalArgumentException) { AgentNativeToolExecutionResult.failure("invalid_health_history_cursor",
                "Supply this concern's input_version and either both cursor fields from next or neither.") }
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
        val after = cursor(input)
        return HealthCareStore(context, names.care).use { care ->
            val grant = care.discussionGrant(invocation.turnId) ?: throw HealthCareConflict()
            val issue = care.concern(grant.concernId) ?: throw HealthCareConflict()
            require(!input.containsKey("metric") || input["metric"] is String)
            val metric = (input["metric"] as? String)?.let(HealthMetric::valueOf) ?: issue.metric
            if (metric != issue.metric && metric !in grant.related.keys) throw HealthCareConflict()
            val selected = if (metric == issue.metric) HealthCareRelatedMeasurement.of(issue)
                else care.relatedMeasurement(metric)?.takeIf { it.available } ?: throw HealthCareConflict()
            val settings = care.settings()
            HealthPrivacyStore(context, names.privacy).use { privacy ->
                val permission = privacy.policy()
                if (!care.researchGrantCurrent(grant) || care.discussion(invocation.conversationId) != issue.id || input["input_version"] != selected.inputVersion ||
                    !HealthCareDiscussionPolicy.permitted(grant, invocation.conversationId, invocation.turnId, issue,
                        settings, permission, grant.destination, now)) throw HealthCareConflict()
                HealthRecordStore(context, names.records).use { records ->
                    fun current() = issue.inputVersion == HealthCareEngine.inputVersion(settings.version, permission.version, records.metricVersion(issue.metric)) &&
                        privacy.policy() == permission && care.settings() == settings && care.concern(issue.id)?.revision == issue.revision &&
                        care.researchGrantCurrent(grant) && HealthCareRelatedContext.sourceCurrent(context, names, grant) &&
                        selected.inputVersion == HealthCareEngine.inputVersion(settings.version, permission.version, records.metricVersion(metric))
                    if (!current()) throw HealthCareConflict()
                    val page = privacy.track(HealthAccessScope(HealthAccessPurpose.PROACTIVE_CARE, setOf(metric))) {
                        records.careHistory(grant.approvedAt, metric, after)
                    }
                    if (!current()) throw HealthCareConflict()
                    val series = HealthCareSeries.of(page)
                    JSONObject().put("protocol", HealthCareHistoryObservation.PROTOCOL)
                        .put("input_version", selected.inputVersion).put("metric", metric.name)
                        .put("page_start", after?.let { JSONObject().put("before_time", it.measuredAt).put("before_id", it.id) } ?: JSONObject.NULL)
                        .put("history", series?.modelJson(selected.assessment?.sample ?: throw HealthCareConflict(), selected.context,
                            selected.assessment?.comparison) ?: JSONObject.NULL)
                        .put("next", page.next?.let { JSONObject().put("before_time", it.measuredAt).put("before_id", it.id) } ?: JSONObject.NULL)
                        .put("done", page.next == null).put("stability_verified", false)
                }
            }
        }
    }
}
