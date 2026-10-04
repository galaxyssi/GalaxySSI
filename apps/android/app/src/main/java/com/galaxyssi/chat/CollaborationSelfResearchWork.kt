package com.galaxyssi.chat

import org.json.JSONObject

/** Runs research through the same durable goal/live DAG, without idle model calls or another scheduler. */
internal object CollaborationSelfResearchWork {
    const val FIELD = "self_research"
    const val TASK = "collaboration_research_self_task"
    const val CLAIMS = "collaboration_research_self_claims"
    const val OUTCOMES = "collaboration_research_self_outcomes"
    private const val BINDING = "host_self_research"
    data class Plan(val work: List<JSONObject>, val claims: String)

    fun plan(record: AgentTeamExecutionRecord, requested: List<JSONObject>, provider: (() -> CollaborationResearchWorkspace)?,
             access: CollaborationWorkspaceAccess): Plan {
        val prior = record.request.context[CLAIMS]?.toString() ?: "{}"
        if (prior == "{}" && requested.none { it.has(FIELD) || it.has(BINDING) }) return Plan(requested, prior)
        val claims = JSONObject(prior)
        val workspace by lazy { requireNotNull(provider?.invoke()) { "Self-research workspace unavailable; retain checkpoint" } }
        val work = requested.map { original ->
            require(!original.has(BINDING)) { "Self-research bindings are host-owned" }
            val item = JSONObject(original.toString())
            val id = CollaborationWorkGraph.id(item)
            val old = claims.optJSONObject(id)
            val spec = if (item.has(FIELD)) item.getJSONObject(FIELD) else null
            if (spec == null) {
                require(old == null) { "Cannot remove admitted self-research work" }
                return@map item
            }
            val ref = spec.getJSONObject("cycle")
            require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Use an exact research cycle revision" }
            val cycle = requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Research cycle missing or isolated" }
            require(cycle.getString("kind") == CollaborationSelfResearch.CYCLE && CollaborationResearchCandidates.same(cycle, ref)) { "Research cycle digest mismatch" }
            if (old == null) CollaborationInnovationValidation.checkRecord(cycle) { target, kinds ->
                require(target.opt("revision") is Int && target.getInt("revision") > 0) { "Use exact research lineage revisions" }
                val saved = requireNotNull(workspace.read(access, target.getString("object_id"), target.getInt("revision"))) { "Research lineage missing or isolated" }
                require(saved.getString("kind") in kinds && CollaborationResearchCandidates.same(saved, target) &&
                    workspace.isCurrent(access, target.getString("object_id"), target.getInt("revision"))) { "Bottleneck evidence changed; reconsider before new research work" }
                saved
            }
            val host = cycle.getJSONObject(CollaborationEvolutionContract.HOST)
            require(host.getString("goal_sha256") == CollaborationSemanticGoalCoverage.source(record.request.goal).getString("goal_sha256")) {
                "Self research must serve the active authorized goal"
            }
            val innovation = item.getJSONObject("innovation_work")
            require(CollaborationResearchCandidates.same(host.getJSONObject("opportunity"), innovation.getJSONObject("opportunity"))) {
                "Research work must use its admitted goal-bound innovation opportunity"
            }
            innovation.optJSONObject("innovation")?.let { ideaRef ->
                val idea = requireNotNull(workspace.read(access, ideaRef.getString("object_id"), ideaRef.getInt("revision")))
                require(CollaborationResearchCandidates.same(idea, ideaRef) &&
                    CollaborationResearchCandidates.same(cycle, idea.getJSONObject(CollaborationEvolutionContract.HOST).getJSONObject(CollaborationSelfResearch.CYCLE))) {
                    "Research work cannot execute another cycle's candidate"
                }
            }
            val action = CollaborationEvolutionContract.text(spec, "action_id")
            CollaborationEvolutionContract.text(spec, "why_now")
            val key = "${ref.getString("sha256")}:$action"
            require(claims.keys().asSequence().none { it != id && claims.getJSONObject(it).getString("action_key") == key }) {
                "This research action already has a work ID; recover it instead of renaming and repeating it"
            }
            val binding = JSONObject().put("cycle", CollaborationResearchCandidates.reference(cycle)).put("action_id", action)
                .put("why_now", spec.getString("why_now")).put("question", cycle.getJSONObject("body").getJSONObject(CollaborationSelfResearch.CYCLE).getString("question"))
                .put("checkpoint", host).put("innovation_work", innovation).put("member", item.getString("member"))
                .put("stage", item.getString("stage")).put("assignment", item.getString("assignment"))
                .put("grants_permissions", false).put("improvement_verified", false)
            val digest = AgentNativeJsonCodec.sha256(canonical(binding))
            require(old == null || old.getString("sha256") == digest) { "Research checkpoint changed; preserve admitted work and register a new action" }
            claims.put(id, JSONObject().put("sha256", digest).put("action_key", key).put("cycle", ref))
            item.put(BINDING, binding)
        }
        return Plan(work, claims.toString())
    }

    fun context(item: JSONObject): Map<String, String> = item.optJSONObject(BINDING)?.let { mapOf(TASK to it.toString()) } ?: emptyMap()

    fun capture(record: AgentTeamExecutionRecord, results: Collection<AgentSubagentChildResult>): String {
        val prior = record.request.context[OUTCOMES]?.toString() ?: "{}"
        val members = record.definition.members.filter { TASK in it.context }.associateBy { it.memberId }
        if (members.isEmpty()) return prior
        val outcomes = JSONObject(prior)
        results.filter { it.childId in members && it.supervisorId == record.request.runId && it.status.isTerminal }.forEach { result ->
            if (outcomes.has(result.childId)) return@forEach
            val member = members.getValue(result.childId)
            outcomes.put(result.childId, JSONObject().put("node_id", result.childId).put("work_id", member.context[CollaborationGoalLoop.WORK_ID])
                .put("binding", JSONObject(member.context.getValue(TASK))).put("status", result.status.name.lowercase())
                .put("started_at", result.startedAtMillis).put("completed_at", result.completedAtMillis)
                .put("output_sha256", AgentNativeJsonCodec.sha256(result.output)).put("output_truncated", result.outputTruncated)
                .put("improvement_verified", false).put("goal_verified", false))
        }
        return outcomes.toString()
    }

    private fun canonical(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { canonical(value.get(it)) }
        is org.json.JSONArray -> (0 until value.length()).map { canonical(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }
}
