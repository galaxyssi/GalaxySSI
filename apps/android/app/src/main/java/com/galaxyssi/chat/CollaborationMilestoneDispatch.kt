package com.galaxyssi.chat

import java.io.Closeable
import java.util.concurrent.CopyOnWriteArrayList
import org.json.JSONArray
import org.json.JSONObject

/** Wakeups are hints; the committed journal and graph checkpoint own replay and deduplication. */
internal object CollaborationMilestoneSignals {
    private val listeners = CopyOnWriteArrayList<(String) -> Unit>()
    fun subscribe(listener: (String) -> Unit): Closeable {
        listeners.add(listener)
        return Closeable { listeners.remove(listener) }
    }
    fun committed(runId: String) { listeners.forEach { runCatching { it(runId) } } }
}

internal object CollaborationMilestoneDispatch {
    const val INPUTS = "collaboration_research_milestone_inputs"
    const val GRANTS = "collaboration_research_milestone_grants"
    const val USES = "uses_milestones"
    private val HASH = Regex("[a-f0-9]{64}")

    fun strings(raw: String?): Set<String> = raw?.let(::JSONArray)?.let { array ->
        (0 until array.length()).mapTo(linkedSetOf()) { array.getString(it) }
    }.orEmpty()

    fun inputs(member: AgentTeamMember): List<JSONObject> = member.context[INPUTS]?.let(::JSONArray)?.let { array ->
        (0 until array.length()).map { array.getJSONObject(it) }
    }.orEmpty()

    fun uses(item: JSONObject): Set<String> {
        require(!item.has(USES) || item.optJSONArray(USES) != null) { "$USES must be an array of host milestone tokens" }
        return strings(item.optJSONArray(USES)?.toString()).also { ids ->
            require(ids.all { it.matches(HASH) }) { "Use exact host milestone tokens, not member names or local milestone IDs" }
        }
    }

    fun grant(ref: JSONObject): String? {
        val hash = ref.optString("sha256").takeIf { it.matches(HASH) } ?: return null
        return when {
            ref.optString("object_id").matches(HASH) && ref.optInt("revision") > 0 ->
                "workspace:${ref.getString("object_id")}:${ref.getInt("revision")}:$hash"
            ref.optString("evidence_id").matches(HASH) -> "evidence:${ref.getString("evidence_id")}:$hash"
            else -> null
        }
    }

    fun context(inputs: List<JSONObject>): Map<String, String> = if (inputs.isEmpty()) emptyMap() else mapOf(
        INPUTS to JSONArray(inputs).toString(),
        GRANTS to JSONArray(inputs.flatMap { strings(it.getJSONArray("grants").toString()) }.distinct().sorted()).toString())

    fun prompt(member: AgentTeamMember): String? = inputs(member).takeIf { it.isNotEmpty() }?.let { entries ->
        JSONArray(entries.map { JSONObject(it.toString()).apply { remove("grants") } }).toString()
    }

    fun access(record: AgentTeamExecutionRecord, member: AgentTeamMember) = CollaborationWorkspaceAccess(
        member.context["collaboration_group_id"].orEmpty(), record.request.runId, record.request.messageId,
        record.request.context[CollaborationGoalLoop.ROUND]?.toString()?.toLongOrNull() ?: 0L,
        member.memberId, member.context[CollaborationResearchWorkflow.PERSON].orEmpty(), member.dependsOnAgentIds,
        strings(member.context[GRANTS]))

    fun inherited(record: AgentTeamExecutionRecord, planner: AgentTeamMember): Map<String, JSONObject> =
        (record.definition.members.flatMap(::inputs) + inputs(planner)).associateBy { it.getString("token") }
}
