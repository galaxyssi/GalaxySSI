package com.galaxyssi.chat

import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.collaboration.ConditionalWorkflow
import org.json.JSONArray
import org.json.JSONObject

/** Read-only planning feedback. It neither admits work nor certifies the supplied conditions. */
internal object CollaborationWorkflowCheck {
    const val MODE = "workflow_check"
    const val INSTRUCTIONS = "Use mode=workflow_check with exact rule object_id/revision/sha256 and inputs:{} " +
        "to inspect known conditions, missing data and counterconditions before choosing work. " +
        "Inputs may be partial, must be compact JSON (whole request <=4096 characters), and are declared, not verified evidence. " +
        "Keep inputs/reference unchanged when paging with offset. Unknowns may or may not change selection; " +
        "choose evidence acquisition, method revision or alternatives yourself. This does not execute a workflow or certify either method."

    fun inspect(input: Map<String, Any?>, workspace: CollaborationResearchWorkspace,
                access: CollaborationWorkspaceAccess): JSONObject {
        val required = setOf("mode", "object_id", "revision", "sha256", "inputs")
        require(input.keys.containsAll(required) && input.keys.all { it in required || it == "offset" }) {
            "Workflow check requires mode, exact object_id/revision/sha256, inputs object and optional offset"
        }
        require(input["mode"] == MODE) { "Invalid workflow check mode" }
        val revision = input["revision"]
        require(revision is Number && revision.toDouble() == revision.toInt().toDouble() && revision.toInt() > 0) {
            "Rule revision must be a positive integer"
        }
        for (key in listOf("object_id", "sha256")) require(input[key] is String &&
            (input[key] as String).matches(Regex("[0-9a-f]{64}"))) { "Use an exact rule $key" }
        if (input.containsKey("offset")) {
            val offset = input["offset"]
            require(offset is Number && offset.toDouble() == offset.toInt().toDouble() && offset.toInt() >= 0) {
                "Offset must be a nonnegative integer"
            }
        }
        val rawInputs = input["inputs"]
        require(rawInputs is JSONObject || rawInputs is Map<*, *> && rawInputs.keys.all { it is String }) {
            "inputs must be a JSON object, not a JSON-encoded string"
        }
        val envelope = JSONObject(input)
        require(envelope.toString().length <= 4096) { "Workflow check request exceeds 4096 characters; supply compact condition data" }
        val inputs = JSONObject(envelope.getJSONObject("inputs").toString())
        val ref = JSONObject().put("object_id", input["object_id"]).put("revision", revision.toInt()).put("sha256", input["sha256"])
        val rule = CollaborationWorkflowSelection.read(ref, workspace, access)
        CollaborationCapabilityChannel.requireCurrentLineage(rule, workspace, access)
        val host = rule.getJSONObject(HOST)
        val methodRef = host.getJSONObject("baseline_method")
        val baseline = requireNotNull(workspace.read(access, methodRef.getString("object_id"), methodRef.getInt("revision"))) {
            "Baseline method is missing or isolated"
        }
        val names = baseline.getJSONObject("body").getJSONObject(CollaborationWorkflowMethod.KIND).getJSONArray("inputs")
            .let { a -> (0 until a.length()).map(a::getString).toSet() }
        require(inputs.keys().asSequence().all { it in names }) { "Input names must belong to the saved method contract" }
        val spec = rule.getJSONObject("body").getJSONObject(CollaborationWorkflowSelection.KIND)
        val result = ConditionalWorkflow.choose(spec.getJSONArray("when_all"), spec.getJSONArray("unless_any"), inputs)
        val blockers = result.whenAll.filter { it.state == "not_matched" } + result.unlessAny.filter { it.state == "matched" }
        val unknowns = (result.whenAll + result.unlessAny).filter { it.state == "unknown" }
        val mayChange = unknowns.isNotEmpty() && blockers.isEmpty()
        fun rows(field: String, results: List<ConditionalWorkflow.ConditionResult>) = JSONArray(results.mapIndexed { index, value ->
            val condition = JSONObject(spec.getJSONArray(field).getJSONObject(index).toString())
            condition.put("state", value.state).put("unknown_reason", value.unknownReason ?: JSONObject.NULL)
                .put("actual_type", value.actualType ?: JSONObject.NULL)
                .put("resolving_unknown_may_change_selection", value.state == "unknown" && mayChange)
        })
        return JSONObject().put("rule", CollaborationResearchCandidates.reference(rule))
            .put("selection", CollaborationWorkflowSelection.choose(rule, inputs))
            .put("baseline_method", host.getJSONObject("baseline_method")).put("candidate_method", host.getJSONObject("candidate_method"))
            .put("when_all", rows("when_all", result.whenAll)).put("unless_any", rows("unless_any", result.unlessAny))
            .put("unknown_conditions", JSONArray(unknowns.map { it.id })).put("known_blockers", JSONArray(blockers.map { it.id }))
            .put("unknowns_may_change_selection", mayChange)
            .put("decision_scope", "Known predicates only; no joint satisfiability, probe cost or information-value estimate")
            .put("input_evidence", "declared_unverified_not_a_tool_observation")
            .put("lineage", "current_at_read_rechecked_on_new_admission")
            .put("baseline_applicability_verified", false).put("quality_effect", JSONObject.NULL)
            .put("executes_work", false).put("grants_permissions", false)
            .put("next_action", "Choose whether to inspect original evidence, acquire decision-relevant data, revise the method/rule or use alternatives. " +
                "Missing data is not evidence that baseline is suitable. For execution bind original tool outcomes with observed_inputs; " +
                "use probe_continuation for result-dependent work. This inspection is not an original measurement or a validation of either method.")
    }
}
