package com.galaxyssi.chat

import com.galaxyssi.collaboration.WorkflowMaterializer
import org.json.JSONArray
import org.json.JSONObject

/** Expands an explicitly chosen saved method into the existing scheduler's work format. */
internal object CollaborationWorkflowInstantiation {
    const val FIELD = "workflow_instance"

    fun expand(requested: JSONArray, provider: (() -> CollaborationResearchWorkspace)?,
               access: CollaborationWorkspaceAccess): JSONArray {
        if ((0 until requested.length()).none { requested.optJSONObject(it)?.has(FIELD) == true }) return requested
        val workspace by lazy { requireNotNull(provider?.invoke()) { "Workflow workspace unavailable; retain the instance for recovery" } }
        val expanded = JSONArray()
        val executions = hashSetOf<String>()
        for (index in 0 until requested.length()) {
            val item = requested.getJSONObject(index)
            if (!item.has(FIELD)) {
                expanded.put(item)
                continue
            }
            require(item.keys().asSequence().toSet() == setOf(FIELD)) { "workflow_instance cannot override work or host fields" }
            val use = item.getJSONObject(FIELD)
            require(use.has("method") != use.has(CollaborationWorkflowSelection.FIELD)) { "Choose either method or selection_rule, not both" }
            val selector = if (use.has("method")) "method" else CollaborationWorkflowSelection.FIELD
            val fields = setOf("execution_id", selector, "inputs", "roles") +
                if (use.has(CollaborationCapabilityChannel.FIELD)) setOf(CollaborationCapabilityChannel.FIELD) else emptySet()
            require(use.keys().asSequence().toSet() == fields) { "workflow_instance requires execution_id, method or selection_rule, inputs and roles only" }
            require(use.opt("execution_id") is String) { "workflow_instance.execution_id must be a string" }
            val execution = use.getString("execution_id")
            require(execution.isNotBlank() && execution.length <= 160 && executions.add(execution)) { "Use a distinct stable workflow execution ID" }
            val ref = if (selector == "method") use.getJSONObject("method") else CollaborationWorkflowSelection.choose(
                CollaborationWorkflowSelection.read(use.getJSONObject(selector), workspace, access), use.getJSONObject("inputs")).getJSONObject("method")
            require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Use exact integer method revision" }
            val method = requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))) {
                "Workflow unavailable or isolated"
            }
            require(method.getString("kind") == CollaborationWorkflowMethod.KIND && CollaborationResearchCandidates.same(method, ref) &&
                workspace.isCurrent(access, ref.getString("object_id"), ref.getInt("revision"))) { "Workflow version mismatch" }
            val spec = method.getJSONObject("body").getJSONObject(CollaborationWorkflowMethod.KIND)
            val inputs = use.getJSONObject("inputs")
            val names = strings(spec.getJSONArray("inputs"))
            require(inputs.keys().asSequence().toSet() == names && names.all { !inputs.isNull(it) }) { "Workflow inputs must match the saved contract" }
            val roles = use.getJSONObject("roles")
            val roleNames = strings(spec.getJSONArray("roles"))
            require(roles.keys().asSequence().toSet() == roleNames && roleNames.all {
                roles.opt(it) is String && roles.getString(it).isNotBlank()
            }) { "Workflow roles must map every saved role to one member" }
            val steps = CollaborationEvolutionContract.objects(spec, "steps")
            // Host review validation remains authoritative before the shared core remaps work IDs.
            steps.forEach { if (it.has(CollaborationReviewTargets.FIELD)) CollaborationReviewTargets.read(it) }
            for (step in WorkflowMaterializer.expand(execution, steps, roles)) {
                val stepId = step.sourceId
                val binding = JSONObject().put("execution_id", execution).put("method", CollaborationResearchCandidates.reference(method))
                    .put("step_id", stepId).put("inputs", JSONObject(inputs.toString()))
                if (use.has(CollaborationCapabilityChannel.FIELD)) binding.put(CollaborationCapabilityChannel.FIELD,
                    JSONObject(use.getJSONObject(CollaborationCapabilityChannel.FIELD).toString()))
                if (use.has(CollaborationWorkflowSelection.FIELD)) binding.put(CollaborationWorkflowSelection.FIELD,
                    JSONObject(use.getJSONObject(CollaborationWorkflowSelection.FIELD).toString()))
                // Inputs stay in their data field; never interpolate them into saved instructions.
                expanded.put(step.work.put(CollaborationWorkflowWork.FIELD, binding))
            }
        }
        return expanded
    }

    fun workId(execution: String, step: String): String = WorkflowMaterializer.workId(execution, step)

    private fun strings(value: JSONArray): Set<String> = (0 until value.length()).mapTo(linkedSetOf()) { value.getString(it) }
}
