package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A bounded decision cache, not the research archive. No original result or member is removed. */
internal object CollaborationTeamOrganizationHistory {
    const val HISTORY = "collaboration_research_organization_history"
    const val MAX_OBSERVATIONS = 128
    data class Snapshot(val checkpoint: CollaborationTeamOrganization.Checkpoint, val history: String)

    fun capture(record: AgentTeamExecutionRecord,
                projection: CollaborationTeamOrganizationProjection.Projection = CollaborationTeamOrganizationProjection.legacy(record)): Snapshot {
        val scope = CollaborationTeamOrganizationProjection.scope(record)
        require(projection.scope == scope) { "Organization projection scope mismatch" }
        val group = scope.groupId
        val previous = decode(record.request.context[HISTORY]?.toString(), record.request.runId, group)
        val results = projection.latestResults
        val dispatches = projection.ownership.bindings.map { it.member }
        val workers = dispatches.filter { !it.context[CollaborationGoalLoop.WORK_ID].isNullOrBlank() }
        fun signature(member: AgentTeamMember): String = runCatching {
            JSONObject(member.context[CollaborationTeamOrganization.SIGNATURES].orEmpty())
                .optString(member.context.getValue(CollaborationGoalLoop.WORK_ID))
        }.getOrDefault("")
        val fresh = workers.mapNotNull { member ->
            val result = results[member.memberId]?.takeIf { it.status.isTerminal } ?: return@mapNotNull null
            val observed = projection.verifiedResults[member.memberId] == result
            val outcome = when {
                !observed -> CollaborationTeamOrganization.Outcome.UNKNOWN
                result.status == AgentSubagentStatus.SUCCEEDED -> CollaborationTeamOrganization.Outcome.SUCCEEDED
                result.status == AgentSubagentStatus.FAILED -> CollaborationTeamOrganization.Outcome.FAILED
                else -> CollaborationTeamOrganization.Outcome.UNKNOWN
            }
            CollaborationTeamOrganization.Observation(dispatchId = member.memberId,
                personId = CollaborationTeamOrganization.person(member), agentId = member.agentId,
                modelId = member.context["collaboration_model_id"].orEmpty(), role = member.role,
                stage = member.context[CollaborationResearchWorkflow.STAGE].orEmpty(),
                workId = member.context.getValue(CollaborationGoalLoop.WORK_ID),
                signature = if (observed) signature(member) else "", outcome = outcome,
                elapsedMillis = if (outcome != CollaborationTeamOrganization.Outcome.UNKNOWN && result.startedAtMillis > 0 &&
                    result.completedAtMillis >= result.startedAtMillis) result.completedAtMillis - result.startedAtMillis else null,
                provenanceSource = if (observed) result.provenance.source else "")
        }
        val observations = (previous + fresh).associateBy { it.dispatchId }.values.toList().takeLast(MAX_OBSERVATIONS)
        val inFlight = projection.active.map { it.member }.map {
            CollaborationTeamOrganization.InFlight(CollaborationTeamOrganization.person(it),
                it.context[CollaborationGoalLoop.WORK_ID] ?: "dispatch:${it.memberId}", signature(it))
        }
        val coordinator = record.definition.members.firstOrNull { it.memberId == record.definition.primaryMemberId }
            ?.context?.get(CollaborationResearchWorkflow.PERSON).orEmpty()
        val checkpoint = CollaborationTeamOrganization.Checkpoint(coordinatorId = coordinator,
            settled = projection.settled,
            inFlight = inFlight, observations = observations,
            finishedWork = projection.finishedWork, finishedAuthors = projection.finishedAuthors)
        return Snapshot(checkpoint, encode(observations, record.request.runId, group))
    }

    fun encode(observations: List<CollaborationTeamOrganization.Observation>, runId: String, groupId: String): String =
        JSONObject().put("version", 2).put("run_id", runId).put("group_id", groupId)
            .put("observations", JSONArray(observations.distinctBy { it.dispatchId }.takeLast(MAX_OBSERVATIONS).map { row ->
                JSONObject().put("dispatch_id", row.dispatchId).put("person_id", row.personId).put("agent_id", row.agentId)
                    .put("model_id", row.modelId).put("role", row.role).put("stage", row.stage).put("work_id", row.workId)
                    .put("signature", row.signature).put("outcome", row.outcome.name).put("provenance_source", row.provenanceSource).apply {
                        row.elapsedMillis?.takeIf { it >= 0 }?.let { put("elapsed_millis", it) }
                    }
            })).toString()

    fun decode(raw: String?, runId: String, groupId: String): List<CollaborationTeamOrganization.Observation> = runCatching {
        val json = JSONObject(raw ?: "{}")
        require(json.getInt("version") == 2 && json.getString("run_id") == runId && json.getString("group_id") == groupId)
        val rows = json.getJSONArray("observations")
        require(rows.length() <= MAX_OBSERVATIONS)
        (0 until rows.length()).map { index ->
            val row = rows.getJSONObject(index)
            val source = row.optString("provenance_source").takeIf { it in setOf("agent-team", "late-managed-response") }.orEmpty()
            val outcome = if (source.isEmpty()) CollaborationTeamOrganization.Outcome.UNKNOWN else
                runCatching { CollaborationTeamOrganization.Outcome.valueOf(row.getString("outcome")) }
                    .getOrDefault(CollaborationTeamOrganization.Outcome.UNKNOWN)
            fun measurement(key: String) = (row.opt(key) as? Number)?.toString()?.toLongOrNull()?.takeIf { it >= 0 }
            CollaborationTeamOrganization.Observation(dispatchId = row.getString("dispatch_id"),
                personId = row.getString("person_id"), agentId = row.getString("agent_id"), modelId = row.getString("model_id"),
                role = row.getString("role"), stage = row.getString("stage"), workId = row.getString("work_id"),
                signature = if (source.isNotEmpty()) row.optString("signature") else "",
                outcome = outcome,
                elapsedMillis = if (outcome != CollaborationTeamOrganization.Outcome.UNKNOWN) measurement("elapsed_millis") else null,
                provenanceSource = source)
        }.distinctBy { it.dispatchId }
    }.getOrDefault(emptyList())
}
