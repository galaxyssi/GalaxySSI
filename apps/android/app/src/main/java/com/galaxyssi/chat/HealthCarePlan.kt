package com.galaxyssi.chat

import java.net.URI
import java.time.OffsetDateTime
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

internal enum class HealthCarePlanState { PENDING, ACCEPTED, DISMISSED }

/** Model citations are provenance claims, not independently verified medical evidence. */
internal data class HealthCarePlanSource(val title: String, val url: String, val version: String, val applicability: String) {
    init {
        require(title.isNotBlank() && title.length <= 300 && version.isNotBlank() && version.length <= 80)
        require(applicability.isNotBlank() && applicability.length <= 2000 && url.length <= 1000)
        val uri = URI(url)
        require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null)
    }
    fun json() = JSONObject().put("title", title).put("url", url).put("version", version).put("applicability", applicability)
    companion object { fun from(j: JSONObject) = HealthCarePlanSource(j.getString("title"), j.getString("url"),
        j.getString("version"), j.getString("applicability")) }
}

internal data class HealthCarePlan(val grant: HealthCareDiscussionGrant, val inputVersion: String, val createdAt: Long,
    val requestHash: String, val uncertainty: String, val sources: List<HealthCarePlanSource>, val actions: List<HealthCareAction>,
    val state: HealthCarePlanState = HealthCarePlanState.PENDING, val selected: Set<String> = emptySet(), val resolvedAt: Long? = null) {
    val id get() = grant.turnId
    init {
        require(inputVersion.isNotBlank() && createdAt > 0 && requestHash.matches(Regex("[a-f0-9]{64}")))
        require(uncertainty.isNotBlank() && uncertainty.length <= 2000 && sources.size in 1..8 && actions.size in 1..8)
        require(sources.map { it.url }.distinct().size == sources.size && actions.map { it.id }.distinct().size == actions.size)
        require(actions.all { it.state == HealthCareActionState.PROPOSED && it.confirmedAt == null && it.outcome.isEmpty() })
        require(selected.all { id -> actions.any { it.id == id } })
        require(if (state == HealthCarePlanState.PENDING) resolvedAt == null && selected.isEmpty()
            else resolvedAt != null && resolvedAt >= createdAt && (state != HealthCarePlanState.ACCEPTED || selected.isNotEmpty()))
    }
    fun json() = JSONObject().put("grant", grant.json()).put("input_version", inputVersion).put("created_at", createdAt)
        .put("hash", requestHash).put("uncertainty", uncertainty).put("sources", JSONArray(sources.map { it.json() }))
        .put("actions", JSONArray(actions.map { it.json() })).put("state", state.name).put("selected", JSONArray(selected.sorted()))
        .put("resolved_at", resolvedAt ?: JSONObject.NULL)
    companion object {
        fun from(j: JSONObject) = HealthCarePlan(HealthCareDiscussionGrant.from(j.getJSONObject("grant")), j.getString("input_version"),
            j.getLong("created_at"), j.getString("hash"), j.getString("uncertainty"), j.getJSONArray("sources").let { a ->
                (0 until a.length()).map { HealthCarePlanSource.from(a.getJSONObject(it)) } }, j.getJSONArray("actions").let { a ->
                (0 until a.length()).map { HealthCareAction.from(a.getJSONObject(it)) } }, HealthCarePlanState.valueOf(j.getString("state")),
            j.getJSONArray("selected").let { a -> (0 until a.length()).map { a.getString(it) }.toSet() },
            if (j.isNull("resolved_at")) null else j.getLong("resolved_at"))
    }
}

internal object HealthCarePlanPolicy {
    fun parse(request: AgentNativeJsonObject, grant: HealthCareDiscussionGrant, issue: HealthCareConcern, now: Long): HealthCarePlan {
        val input = JSONObject(AgentNativeJsonCodec.stringify(request))
        keys(input, setOf("uncertainty", "sources", "actions"))
        require(grant.concernId == issue.id && grant.revision == issue.revision)
        val sources = input.getJSONArray("sources").let { a -> (0 until a.length()).map {
            val source = a.getJSONObject(it); keys(source, setOf("title", "url", "version", "applicability"))
            HealthCarePlanSource.from(source)
        } }
        val actions = input.getJSONArray("actions").let { a -> (0 until a.length()).map { index ->
            val action = a.getJSONObject(index)
            keys(action, setOf("kind", "description", "rationale", "source_index", "due_from", "due_until"))
            val sourceIndex = action.getInt("source_index")
            require(action.getDouble("source_index") == sourceIndex.toDouble())
            val source = requireNotNull(sources.getOrNull(sourceIndex)) { "Unknown plan source" }
            val from = date(action.getString("due_from")); val until = date(action.getString("due_until"))
            require(until == null || until >= now) { "The suggested review window has already ended" }
            HealthCareAction(UUID.nameUUIDFromBytes("${grant.turnId}:$index".toByteArray(Charsets.UTF_8)).toString(),
                HealthCareActionKind.valueOf(action.getString("kind")), action.getString("description"), action.getString("rationale"),
                "${source.title}\n${source.version}\n${source.url}", dueFrom = from, dueUntil = until)
        } }
        return HealthCarePlan(grant, issue.inputVersion, now, AgentNativeJsonCodec.sha256(request), input.getString("uncertainty"), sources, actions)
    }
    private fun keys(j: JSONObject, expected: Set<String>) { require(j.keys().asSequence().toSet() == expected) }
    private fun date(value: String): Long? = if (value.isEmpty()) null else
        requireNotNull(runCatching { OffsetDateTime.parse(value).toInstant().toEpochMilli() }.getOrNull()) { "Use a date/time with an explicit offset" }

    fun current(plan: HealthCarePlan, issue: HealthCareConcern?, settings: HealthCareSettings, privacy: HealthPrivacyPolicy,
        sourceVersion: String): Boolean = issue != null && issue.id == plan.grant.concernId && issue.revision == plan.grant.revision &&
        issue.inputVersion == plan.inputVersion && sourceVersion == plan.inputVersion && settings.enabled &&
        settings.version == plan.grant.settingsVersion && privacy.metrics && privacy.profile && privacy.version == plan.grant.privacyVersion &&
        issue.stage !in setOf(HealthCareStage.PAUSED, HealthCareStage.CLOSED) && HealthCareSignal.SOURCE_REMOVED !in issue.assessment.signals

    fun accept(plan: HealthCarePlan, issue: HealthCareConcern, selected: Set<String>, now: Long): HealthCareConcern {
        require(plan.state == HealthCarePlanState.PENDING && selected.isNotEmpty() && now >= plan.createdAt)
        require(selected.all { id -> plan.actions.any { it.id == id } })
        val accepted = plan.actions.filter { it.id in selected }.map {
            require(it.dueUntil == null || it.dueUntil >= now) { "The suggested review window has already ended" }
            it.copy(state = HealthCareActionState.CONFIRMED, confirmedAt = now, basis = HealthCareFollowUpPolicy.basis(issue))
        }
        require(issue.actions.none { it.id in selected })
        return issue.copy(actions = issue.actions + accepted, stage = if (accepted.any { it.kind == HealthCareActionKind.RECHECK })
            HealthCareStage.WAITING_RESULTS else HealthCareStage.REVIEW_PLAN)
    }
}
