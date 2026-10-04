package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.LESSON

/** A reuse binding belongs to an existing work ID; no second executor or background loop is introduced. */
internal object CollaborationProcedureWork {
    const val TASK = "collaboration_research_procedure_task"
    const val CLAIMS = "collaboration_research_procedure_claims"
    const val OUTCOMES = "collaboration_research_procedure_outcomes"
    private const val BINDING = "host_procedure"
    data class Plan(val work: List<JSONObject>, val claims: String)

    fun plan(record: AgentTeamExecutionRecord, requested: List<JSONObject>,
             provider: (() -> CollaborationResearchWorkspace)?, access: CollaborationWorkspaceAccess): Plan {
        val prior = record.request.context[CLAIMS]?.toString() ?: "{}"
        if (prior == "{}" && requested.none { it.has("procedure_use") || it.has(BINDING) }) return Plan(requested, prior)
        val claims = JSONObject(prior)
        val workspace by lazy { requireNotNull(provider?.invoke()) { "Procedure workspace unavailable; preserve work for recovery" } }
        val skills = hashMapOf<String, JSONObject>()
        val work = requested.map { original ->
            require(!original.has(BINDING)) { "Procedure bindings are host-owned" }
            val item = JSONObject(original.toString())
            val id = CollaborationWorkGraph.id(item)
            val old = claims.optJSONObject(id)
            if (!item.has("procedure_use")) {
                require(old == null) { "Cannot remove the procedure binding from work $id" }
                return@map item
            }
            val use = item.getJSONObject("procedure_use")
            val ref = use.getJSONObject("procedure")
            require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Procedure revision must be an exact integer" }
            val skill = skills.getOrPut(ref.toString()) { CollaborationProceduralMemory.current(workspace, access, ref) }
            require(CollaborationEvolutionContract.text(use, "domain") == skill.getJSONObject(HOST).getString("domain")) {
                "Procedure domain differs from its validated scope; register and test a transfer adaptation first"
            }
            val spec = skill.getJSONObject("body").getJSONObject(CollaborationProceduralMemory.SKILL)
            val inputs = use.getJSONObject("inputs")
            val schema = spec.getJSONArray("inputs")
            val names = (0 until schema.length()).map { schema.getJSONObject(it).getString("name") }.toSet()
            require(inputs.keys().asSequence().all { it in names }) { "Unknown procedure input" }
            repeat(schema.length()) { index -> val input = schema.getJSONObject(index)
                require(!input.getBoolean("required") || inputs.has(input.getString("name")) && !inputs.isNull(input.getString("name"))) {
                    "Missing required procedure input: ${input.getString("name")}"
                }
            }
            val applicability = use.getJSONObject("applicability")
            listOf("why", "remaining_uncertainty").forEach { CollaborationEvolutionContract.text(applicability, it) }
            CollaborationEvolutionContract.strings(applicability, "conditions_checked")
            val failures = use.getJSONArray("failures")
            val notes = JSONArray()
            repeat(failures.length()) { index ->
                val failure = failures.getJSONObject(index)
                require(failure.opt("revision") is Int && failure.getInt("revision") > 0) { "Failure revision must be an exact integer" }
                val saved = requireNotNull(workspace.read(access, failure.getString("object_id"), failure.getInt("revision"))) { "Failure experience missing or isolated" }
                require(saved.getString("kind") == CollaborationProceduralMemory.FAILURE && CollaborationResearchCandidates.same(saved, failure)) {
                    "Failure experience digest or kind mismatch"
                }
                notes.put(JSONObject().put("reference", CollaborationResearchCandidates.reference(saved))
                    .put("experience", saved.getJSONObject("body").getJSONObject(CollaborationProceduralMemory.FAILURE)))
            }
            val host = skill.getJSONObject(HOST)
            val lessonRef = host.getJSONObject("lesson")
            val lesson = requireNotNull(workspace.read(access, lessonRef.getString("object_id"), lessonRef.getInt("revision")))
                .getJSONObject("body").getJSONObject(LESSON)
            val binding = JSONObject().put("procedure", CollaborationResearchCandidates.reference(skill)).put("inputs", inputs)
                .put("member", CollaborationEvolutionContract.text(item, "member"))
                .put("stage", CollaborationEvolutionContract.text(item, "stage"))
                .put("assignment", CollaborationEvolutionContract.text(item, "assignment"))
                .put("applicability", applicability).put("failure_experiences", notes).put("lesson", lessonRef)
                .put("domain", host.getString("domain")).put("method", lesson.getString("procedure"))
                .put("applies_when", lesson.getString("applies_when")).put("avoid_when", lesson.getString("avoid_when"))
                .put("transfer_test", lesson.getString("transfer_test")).put("rollback", host.getJSONObject("rollback"))
                .put("limitations", spec.getString("limitations")).put("grants_permissions", false)
            val digest = AgentNativeJsonCodec.sha256(canonical(binding))
            require(old == null || old.getString("sha256") == digest) { "Cannot rewrite an admitted procedure binding; use a new work ID" }
            claims.put(id, JSONObject().put("sha256", digest).put("procedure", binding.getJSONObject("procedure")))
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
                .put("completed_at", result.completedAtMillis).put("elapsed_ms", if (result.startedAtMillis > 0 && result.completedAtMillis >= result.startedAtMillis)
                    result.completedAtMillis - result.startedAtMillis else JSONObject.NULL)
                .put("output_sha256", AgentNativeJsonCodec.sha256(result.output)).put("output_truncated", result.outputTruncated)
                .put("capability_verified", false).put("learning_gain", JSONObject.NULL))
        }
        return outcomes.toString()
    }
}
