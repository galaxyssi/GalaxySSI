package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.IDEA
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.PLAN
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text
import com.galaxyssi.chat.CollaborationInnovationValidation.OPPORTUNITY

/** Innovation uses the existing durable DAG, not a fixed research sequence or a second executor. */
internal object CollaborationInnovationWork {
    const val TASK = "collaboration_research_innovation_task"
    const val CLAIMS = "collaboration_research_innovation_claims"
    const val OUTCOMES = "collaboration_research_innovation_outcomes"
    private const val BINDING = "host_innovation_work"
    data class Plan(val work: List<JSONObject>, val claims: String)

    fun plan(record: AgentTeamExecutionRecord, requested: List<JSONObject>, provider: (() -> CollaborationResearchWorkspace)?,
             access: CollaborationWorkspaceAccess, criteria: JSONArray? = null): Plan {
        val prior = record.request.context[CLAIMS]?.toString() ?: "{}"
        if (prior == "{}" && requested.none { it.has("innovation_work") || it.has(BINDING) }) return Plan(requested, prior)
        val claims = JSONObject(prior)
        val workspace by lazy { requireNotNull(provider?.invoke()) { "Innovation workspace unavailable; preserve work for recovery" } }
        val cache = hashMapOf<String, JSONObject>()
        fun exact(ref: JSONObject, kinds: Set<String>): JSONObject {
            require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Innovation revision must be an exact integer" }
            val key = "${ref.getString("object_id")}:${ref.getInt("revision")}:${ref.getString("sha256")}"
            val saved = cache.getOrPut(key) { requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))) {
                "Innovation source unavailable or isolated"
            } }
            require(saved.getString("kind") in kinds && CollaborationResearchCandidates.same(saved, ref) &&
                workspace.isCurrent(access, ref.getString("object_id"), ref.getInt("revision"))) { "Innovation source changed; reconsider against current evidence" }
            return saved
        }
        val work = requested.map { original ->
            require(!original.has(BINDING)) { "Innovation work bindings are host-owned" }
            val item = JSONObject(original.toString())
            val id = CollaborationWorkGraph.id(item)
            val old = claims.optJSONObject(id)
            if (!item.has("innovation_work")) {
                require(old == null) { "Cannot remove an admitted innovation binding from work $id" }
                return@map item
            }
            val spec = item.getJSONObject("innovation_work")
            val opportunity = CollaborationInnovationValidation.currentOpportunity(spec.getJSONObject("opportunity"), ::exact)
            val source = opportunity.getJSONObject("body").getJSONObject(OPPORTUNITY)
            val goal = CollaborationSemanticGoalCoverage.source(record.request.goal)
            require(source.getString("goal_sha256") == goal.getString("goal_sha256")) { "Innovation opportunity belongs to another original goal" }
            val contract = criteria ?: JSONArray(record.request.context[CollaborationGoalLoop.CRITERIA]?.toString() ?: "[]")
            val criterion = (0 until contract.length()).map(contract::getJSONObject).singleOrNull {
                it.getString("id") == source.getString("criterion_id") && it.getString("requirement") == source.getString("requirement")
            }
            requireNotNull(criterion) { "Innovation opportunity must preserve an existing goal criterion, not replace it" }
            val requirement = JSONObject(criterion.toString()).apply { remove("status"); remove("evidence") }
            val phase = text(spec, "phase")
            require(phase in setOf("explore", "compare_prior_art", "prototype", "experiment", "assess", "revise")) { "Unknown innovation work phase" }
            text(spec, "expected_output"); text(spec, "why_now")
            val idea = spec.optJSONObject("innovation")?.let { exact(it, setOf(IDEA)).also { saved ->
                CollaborationInnovationValidation.currentIdea(saved, ::exact)
                require(CollaborationResearchCandidates.same(opportunity, saved.getJSONObject("body").getJSONObject(IDEA).getJSONObject(OPPORTUNITY))) {
                    "Innovation work references a different opportunity"
                }
            } }
            if (phase in setOf("prototype", "experiment", "assess", "revise")) requireNotNull(idea) { "$phase needs an exact saved innovation" }
            val plan = spec.optJSONObject("plan")?.let { exact(it, setOf(PLAN)).also { saved ->
                require(idea != null && CollaborationResearchCandidates.same(idea, saved.getJSONObject("body").getJSONObject(PLAN).getJSONObject("innovation"))) {
                    "Experiment plan belongs to another innovation"
                }
                CollaborationInnovationValidation.checkRecord(saved, ::exact)
            } }
            if (phase == "experiment") requireNotNull(plan) { "Execute only after preregistering the experiment plan" }
            val assessment = spec.optJSONObject("assessment")?.let { ref ->
                val saved = CollaborationInnovationValidation.currentAssessment(ref, ::exact)
                require(idea != null && CollaborationResearchCandidates.same(idea, saved.getJSONObject("host_evolution").getJSONObject("innovation"))) {
                    "Prior assessment belongs to another innovation"
                }
                saved
            }
            val pinnedWork = JSONObject().put("phase", phase).put("expected_output", spec.getString("expected_output"))
                .put("why_now", spec.getString("why_now")).put("opportunity", CollaborationResearchCandidates.reference(opportunity))
            idea?.let { pinnedWork.put("innovation", CollaborationResearchCandidates.reference(it)) }
            plan?.let { pinnedWork.put("plan", CollaborationResearchCandidates.reference(it)) }
            assessment?.let { pinnedWork.put("assessment", CollaborationResearchCandidates.reference(it)) }
            val binding = JSONObject().put("opportunity", CollaborationResearchCandidates.reference(opportunity)).put("question", source.getString("question"))
                .put("null_hypothesis", source.getString("null_hypothesis")).put("discriminating_test", source.getString("discriminating_test"))
                .put("alternative_routes", source.getJSONArray("alternative_routes")).put("goal", goal).put("criterion", requirement)
                .put("work", pinnedWork).put("member", text(item, "member")).put("stage", text(item, "stage"))
                .put("assignment", text(item, "assignment")).put("grants_permissions", false).put("goal_verified", false)
            val digest = AgentNativeJsonCodec.sha256(canonical(binding))
            require(old == null || old.getString("sha256") == digest) { "Cannot rewrite admitted innovation work; use a new work ID" }
            claims.put(id, JSONObject().put("sha256", digest).put("opportunity", binding.getJSONObject("opportunity")))
            item.put(BINDING, binding)
        }
        return Plan(work, claims.toString())
    }

    fun context(item: JSONObject): Map<String, String> = item.optJSONObject(BINDING)?.let { mapOf(TASK to it.toString()) } ?: emptyMap()

    private fun canonical(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { canonical(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { canonical(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }

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
                .put("completed_at", result.completedAtMillis).put("output_sha256", AgentNativeJsonCodec.sha256(result.output))
                .put("output_truncated", result.outputTruncated).put("innovation_verified", false).put("goal_verified", false))
        }
        return outcomes.toString()
    }
}
