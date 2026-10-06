package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.strings
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** A versioned, executable method hypothesis; neither a global policy nor a grant of authority. */
internal object CollaborationWorkflowMethod {
    const val KIND = "workflow_method"
    const val COMPARISON = "workflow_comparison"
    val DIMENSIONS = setOf("decomposition", "retrieval", "tool_use", "collaboration", "verification")

    fun definition(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        listOf("purpose", "domain", "bottleneck", "change_rationale", "applies_when", "avoid_when", "risks", "expected_gain", "falsifier")
            .forEach { text(value, it) }
        require(strings(value, "dimensions").all { it in DIMENSIONS }) { "Unknown workflow improvement dimension" }
        val roles = strings(value, "roles")
        require(roles.distinct().size == roles.size) { "Workflow roles must be unique" }
        val inputs = value.getJSONArray("inputs").let { a -> (0 until a.length()).map { a.getString(it).also { name -> require(name.isNotBlank()) } } }
        require(inputs.distinct().size == inputs.size) { "Workflow inputs must be unique" }
        val steps = objects(value, "steps")
        val work = steps.map { step ->
            require(step.keys().asSequence().all { it in setOf("id", "role", "stage", "assignment", "depends_on", "dependency_policy", "independent_review", CollaborationReviewTargets.FIELD) }) {
                "Workflow steps may not override tools, permissions, models or goal criteria"
            }
            require(text(step, "id").length <= 160 && text(step, "assignment").length <= 8000) { "Workflow step exceeds existing work field size" }
            require(text(step, "role") in roles && text(step, "stage") in setOf("EXECUTE", "EXPLORE", "CHALLENGE", "VERIFY", "REVISE")) { "Unknown role or executable stage" }
            require(!step.has("independent_review") || step.opt("independent_review") is Boolean) { "independent_review must be Boolean" }
            JSONObject(step.toString()).put("member", step.getString("role"))
        }
        require(roles.toSet() == steps.map { it.getString("role") }.toSet()) { "Every declared role must have work" }
        val graph = CollaborationWorkGraph.compile(work, emptySet())
        require(graph.error.isBlank()) { graph.error }
        val host = JSONObject().put("state", "unverified_workflow_candidate").put("grants_permissions", false).put("quality_improved", false)
        value.optJSONObject("previous_method")?.let { previous ->
            val saved = exact(previous, setOf(KIND))
            require(saved.getJSONObject("body").getJSONObject(KIND).getString("domain") == value.getString("domain")) { "A method revision must preserve its domain; use a transfer study for a different domain" }
            host.put("previous_method", CollaborationResearchCandidates.reference(saved))
            val feedback = objects(value, "feedback").map { exact(it, setOf("artifact", "experiment_result", "capability_diagnosis", "failure_experience", "prediction_outcome")) }
            host.put("feedback", JSONArray(feedback.map(CollaborationResearchCandidates::reference)))
        }
        return host
    }

    fun idea(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? = value.optJSONObject(KIND)?.let {
        val method = exact(it, setOf(KIND))
        require(method.getJSONObject("body").getJSONObject(KIND).getString("domain") == value.getString("domain")) { "Innovation and workflow domains differ" }
        CollaborationResearchCandidates.reference(method)
    }

    fun comparison(value: JSONObject, idea: JSONObject, baseline: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject? {
        val candidate = idea.optJSONObject(HOST)?.optJSONObject(KIND)
        val before = baseline.optJSONObject(HOST)?.optJSONObject(KIND)
        val requested = value.optJSONObject(COMPARISON)
        if (candidate == null && before == null && requested == null) return null
        requireNotNull(candidate) { "Workflow comparison candidate must preserve its method reference" }
        requireNotNull(before) { "Workflow baseline must be an innovation with an exact preserved workflow_method" }
        val spec = requireNotNull(requested) { "Register workflow_comparison before comparing methods" }
        val old = exact(before, setOf(KIND)); val next = exact(candidate, setOf(KIND))
        require(!CollaborationResearchCandidates.same(old, next)) { "Compare distinct workflow versions" }
        require(old.getJSONObject("body").getJSONObject(KIND).getString("domain") == next.getJSONObject("body").getJSONObject(KIND).getString("domain")) { "Workflow comparison domains differ" }
        listOf("controlled_conditions", "quality_oracle", "cost_accounting", "selection_bias").forEach { text(spec, it) }
        val dataset = exact(spec.getJSONObject("dataset"), setOf("artifact"))
        require(objects(value, "cases").any { it.getString("purpose") == "regression" }) { "Workflow optimization requires registered regression coverage, not speed alone" }
        return JSONObject().put("baseline_method", CollaborationResearchCandidates.reference(old))
            .put("candidate_method", CollaborationResearchCandidates.reference(next)).put("dataset", CollaborationResearchCandidates.reference(dataset))
    }

    fun sample(binding: JSONObject, sample: JSONObject, variant: String) {
        require(sample.optString("workflow_sha256") == binding.getJSONObject("${variant}_method").getString("sha256") &&
            sample.optString("dataset_sha256") == binding.getJSONObject("dataset").getString("sha256")) { "Workflow measurement changed its registered method or dataset" }
    }
}
