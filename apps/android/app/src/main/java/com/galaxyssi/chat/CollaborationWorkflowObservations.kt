package com.galaxyssi.chat

import com.galaxyssi.collaboration.ObservationProjection
import org.json.JSONArray
import org.json.JSONObject

/** Original tool data drive a saved method's conditions; observations are not certified truths. */
internal object CollaborationWorkflowObservations {
    const val FIELD = "observed_inputs"
    const val BINDING = "input_observations"
    data class Resolved(val values: JSONObject, val bindings: JSONObject, val milestones: Set<String>)

    fun resolve(selectors: JSONObject, workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess,
                milestones: Map<String, JSONObject>): Resolved {
        val values = JSONObject()
        val bindings = JSONObject()
        val uses = linkedSetOf<String>()
        selectors.keys().forEach { name ->
            require(name.isNotBlank()) { "observed_inputs names must be nonblank" }
            val selector = selectors.getJSONObject(name)
            val required = setOf("observation", "pointer")
            val allowed = required + setOf("report_pointer", "milestone")
            require(selector.keys().asSequence().toSet().let { it.containsAll(required) && allowed.containsAll(it) }) {
                "observed_inputs.$name requires observation, pointer and optional report_pointer/milestone only"
            }
            require(selector.opt("pointer") is String && (!selector.has("report_pointer") || selector.opt("report_pointer") is String)) {
                "observed_inputs.$name pointers must be strings"
            }
            val original = workspace.workflowObservation(access, selector.getJSONObject("observation"))
            require(original.getString("observation_kind") == "tool_output_recorded" &&
                !original.getString("tool").contains("recall", true) && original.getString("tool") != ResearchEvidenceAudit.TOOL) {
                "observed_inputs.$name requires an original tool result, not recall or an assessment"
            }
            val neutral = access.copy(nodeId = "", dependencyNodes = emptySet(), pinnedReads = emptySet())
            val token = if (selector.has("milestone")) {
                require(selector.opt("milestone") is String) { "observed_inputs.$name milestone must be a host token" }
                selector.getString("milestone").also { token ->
                    val published = requireNotNull(milestones[token]) { "observed_inputs.$name milestone is unavailable to this plan" }
                    val grants = CollaborationMilestoneDispatch.strings(published.getJSONArray("grants").toString())
                    require(CollaborationMilestoneDispatch.grant(original) in grants) {
                        "observed_inputs.$name milestone does not grant this exact observation"
                    }
                    uses += token
                }
            } else null
            require(neutral.canRead(original) || token != null) {
                "observed_inputs.$name is same-round evidence; publish a milestone and bind its token for recipient access"
            }
            val reportPointer = selector.optString("report_pointer")
            val pointer = selector.getString("pointer")
            val selected = try {
                ObservationProjection.select(JSONObject(original.getString("output_json")), reportPointer, pointer)
            } catch (failure: Exception) {
                throw IllegalArgumentException("observed_inputs.$name cannot read report_pointer='$reportPointer', pointer='$pointer': ${failure.message}", failure)
            }
            values.put(name, JSONObject().put("value", selected).toString().let(::JSONObject).get("value"))
            bindings.put(name, JSONObject().put("observation", JSONObject().put("evidence_id", original.getString("evidence_id"))
                .put("sha256", original.getString("sha256")))
                .put("report_pointer", reportPointer).put("pointer", pointer).put("value_sha256", digest(selected))
                .put("tool", original.getString("tool")).put("origin", original.getString("origin"))
                .put("status", original.getString("status")).put("run_id", original.getString("run_id"))
                .put("turn_id", original.getString("turn_id")).put("round", original.getLong("round"))
                .put("node_id", original.getString("node_id")).put("finished_at", original.getLong("finished_at"))
                .put("truth_verified", false).put("freshness_verified", false)
                .apply { token?.let { put("milestone", it) } })
        }
        return Resolved(values, bindings, uses)
    }

    fun combine(declared: JSONObject, resolved: Resolved): JSONObject = JSONObject(declared.toString()).apply {
        resolved.values.keys().forEach { name ->
            require(!has(name)) { "Input $name is both declared and observed; remove the declared value instead of overriding evidence" }
            put(name, resolved.values.get(name))
        }
    }

    fun verifySnapshot(inputs: JSONObject, resolved: Resolved) {
        resolved.values.keys().forEach { name ->
            require(inputs.has(name) && digest(inputs.get(name)) == digest(resolved.values.get(name))) {
                "Workflow input $name differs from its exact original observation; no work was admitted"
            }
        }
    }

    private fun digest(value: Any?): String = AgentNativeJsonCodec.sha256(canonical(value))
    private fun canonical(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { canonical(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { canonical(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }
}
