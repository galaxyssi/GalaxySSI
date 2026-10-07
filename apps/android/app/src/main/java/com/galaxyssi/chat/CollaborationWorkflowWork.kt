package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Pins whole method graphs to ordinary scheduler work. No extra executor, loop or model call. */
internal object CollaborationWorkflowWork {
    const val FIELD = "workflow_step"
    const val TASK = "collaboration_workflow_task"
    const val CLAIMS = "collaboration_workflow_claims"
    const val OUTCOMES = "collaboration_workflow_outcomes"
    private const val BINDING = "host_workflow"
    data class Plan(val work: List<JSONObject>, val claims: String)

    fun plan(record: AgentTeamExecutionRecord, requested: List<JSONObject>, provider: (() -> CollaborationResearchWorkspace)?,
             access: CollaborationWorkspaceAccess): Plan {
        val prior = record.request.context[CLAIMS]?.toString() ?: "{}"
        if (prior == "{}" && requested.none { it.has(FIELD) || it.has(BINDING) }) return Plan(requested, prior)
        val claims = JSONObject(prior)
        val previouslyBound = JSONObject(prior).let { json -> json.keys().asSequence().flatMap { key ->
            json.getJSONObject(key).getJSONArray("work_ids").let { a -> (0 until a.length()).map { a.getString(it) to key } }.asSequence()
        }.toMap() }
        val knownWork = CollaborationGoalLoop.finishedWork(record) + record.definition.members.mapNotNull { it.context[CollaborationGoalLoop.WORK_ID] }
        val workspace by lazy { requireNotNull(provider?.invoke()) { "Workflow workspace unavailable; retain plan for recovery" } }
        val selected = requested.filter { it.has(FIELD) }
        require(requested.none { it.has(BINDING) }) { "Workflow bindings are host-owned" }
        val people = record.definition.members.filter { it.context[CollaborationGoalLoop.ROSTER] == "true" }
            .mapTo(hashSetOf()) { it.context.getValue(CollaborationResearchWorkflow.PERSON) }
        val bindings = hashMapOf<String, JSONObject>()
        selected.groupBy { it.getJSONObject(FIELD).getString("execution_id") }.forEach { (execution, work) ->
            require(execution.isNotBlank() && execution.length <= 160) { "Use a stable workflow execution ID" }
            val request = work.first().getJSONObject(FIELD)
            require(request.keys().asSequence().toSet() == setOf("execution_id", "method", "step_id", "inputs") +
                (if (request.has(CollaborationCapabilityChannel.FIELD)) setOf(CollaborationCapabilityChannel.FIELD) else emptySet()) +
                (if (request.has(CollaborationWorkflowSelection.FIELD)) setOf(CollaborationWorkflowSelection.FIELD) else emptySet())) { "Unexpected workflow dispatch field" }
            val ref = request.getJSONObject("method")
            require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Use exact integer method revision" }
            val method = requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Workflow unavailable or isolated" }
            require(method.getString("kind") == CollaborationWorkflowMethod.KIND && CollaborationResearchCandidates.same(method, ref) &&
                workspace.isCurrent(access, ref.getString("object_id"), ref.getInt("revision"))) { "Workflow version mismatch" }
            val spec = method.getJSONObject("body").getJSONObject(CollaborationWorkflowMethod.KIND)
            val steps = CollaborationEvolutionContract.objects(spec, "steps").associateBy { it.getString("id") }
            val byStep = work.associateBy { it.getJSONObject(FIELD).getString("step_id") }
            require(byStep.size == work.size && byStep.keys == steps.keys) { "Admit the complete workflow once, including checks; do not omit or duplicate steps" }
            val inputs = request.getJSONObject("inputs")
            val names = spec.getJSONArray("inputs").let { a -> (0 until a.length()).mapTo(hashSetOf()) { a.getString(it) } }
            require(inputs.keys().asSequence().toSet() == names && names.all { !inputs.isNull(it) }) { "Workflow inputs must match the saved contract" }
            val selection = CollaborationWorkflowSelection.binding(request, method, workspace, access,
                claims.has(execution))
            val members = hashMapOf<String, String>()
            val graph = work.map { item ->
                val use = item.getJSONObject(FIELD)
                require(use.keys().asSequence().toSet() == request.keys().asSequence().toSet() &&
                    CollaborationResearchCandidates.same(use.getJSONObject("method"), method) && digest(use.getJSONObject("inputs")) == digest(inputs)) { "One workflow execution must use the same method and inputs" }
                require(digest(use.opt(CollaborationWorkflowSelection.FIELD)) == digest(request.opt(CollaborationWorkflowSelection.FIELD))) {
                    "One workflow execution must preserve its selection rule"
                }
                val step = steps.getValue(use.getString("step_id"))
                val person = item.getString("member")
                require(person in people) { "Use an existing authorized member; workflow is not recruitment or permission" }
                val role = step.getString("role")
                require(members.putIfAbsent(role, person).let { it == null || it == person }) { "A workflow role cannot switch member mid-execution" }
                require(item.getString("stage") == step.getString("stage") && item.getString("assignment") == step.getString("assignment") &&
                    item.optString("dependency_policy", "success") == step.optString("dependency_policy", "success") &&
                    item.optBoolean("independent_review") == step.optBoolean("independent_review")) { "Dispatch must match saved workflow step; publish a new method for changes" }
                val expected = CollaborationWorkGraph.dependencies(step).mapTo(hashSetOf()) { CollaborationWorkGraph.id(byStep.getValue(it)) }
                require(CollaborationWorkGraph.dependencies(item) == expected) { "Workflow dependencies differ from the saved graph" }
                val id = CollaborationWorkGraph.id(item)
                require(!bindings.containsKey(id)) { "Workflow work IDs must be unique" }
                require(id !in knownWork || previouslyBound[id] == execution) { "Cannot retroactively label existing work as a new workflow experiment" }
                val binding = JSONObject().put("execution_id", execution).put("method", CollaborationResearchCandidates.reference(method))
                    .put("step_id", step.getString("id")).put("role", role).put("inputs", inputs).put("work_id", id)
                    .put("member", person).put("stage", item.getString("stage")).put("assignment", item.getString("assignment"))
                    .put("depends_on", JSONArray(expected.sorted())).put("dependency_policy", item.optString("dependency_policy", "success"))
                    .put("independent_review", item.optBoolean("independent_review")).put("quality_improved", false).put("grants_permissions", false)
                bindings[id] = binding
                selection?.let { binding.put(CollaborationWorkflowSelection.DECISION, it) }
                CollaborationCapabilityChannel.binding(use, method, workspace, access, previouslyBound[id] == execution)?.let {
                    binding.put(CollaborationCapabilityChannel.FIELD, it)
                }
                item
            }
            val checked = CollaborationWorkGraph.compile(graph, emptySet())
            require(checked.error.isBlank()) { checked.error }
            val bound = JSONObject().put("steps", JSONArray(bindings.values.filter { it.getString("execution_id") == execution }.sortedBy { it.getString("step_id") }))
            val hash = digest(bound)
            require(!claims.has(execution) || claims.getJSONObject(execution).getString("sha256") == hash) { "Cannot rewrite or rename admitted workflow work; create a distinct experiment for a changed method" }
            if (!claims.has(execution)) claims.put(execution, JSONObject().put("sha256", hash).put("work_ids", JSONArray(graph.map(CollaborationWorkGraph::id))))
        }
        val work = requested.map { item ->
            val id = CollaborationWorkGraph.id(item)
            val binding = bindings[id]
            require(id !in previouslyBound || binding != null && previouslyBound[id] == binding.getString("execution_id")) { "Cannot remove or move an admitted workflow binding" }
            if (binding == null) item else JSONObject(item.toString()).put(BINDING, binding)
        }
        return Plan(work, claims.toString())
    }

    fun context(item: JSONObject): Map<String, String> = item.optJSONObject(BINDING)?.let { mapOf(TASK to it.toString()) } ?: emptyMap()
    private fun digest(value: Any?): String = AgentNativeJsonCodec.sha256(canonical(value))
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
            val validTime = result.startedAtMillis > 0 && result.completedAtMillis >= result.startedAtMillis
            outcomes.put(result.childId, JSONObject().put("binding", JSONObject(members.getValue(result.childId).context.getValue(TASK)))
                .put("status", result.status.name.lowercase()).put("started_at", result.startedAtMillis).put("completed_at", result.completedAtMillis)
                .put("elapsed_ms", if (validTime) result.completedAtMillis - result.startedAtMillis else JSONObject.NULL)
                .put("output_sha256", AgentNativeJsonCodec.sha256(result.output)).put("output_truncated", result.outputTruncated)
                .put("quality_improved", false).put("cost_measured", false))
        }
        return outcomes.toString()
    }
}
