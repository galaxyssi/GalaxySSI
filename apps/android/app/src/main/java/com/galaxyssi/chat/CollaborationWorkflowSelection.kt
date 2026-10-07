package com.galaxyssi.chat

import java.math.BigDecimal
import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.LESSON
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.PLAN
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Agent-authored conditions select a preserved method; host matching is not causal validation. */
internal object CollaborationWorkflowSelection {
    const val KIND = "workflow_selection_rule"
    const val FIELD = "selection_rule"
    const val DECISION = "method_selection"

    fun definition(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        listOf("purpose", "domain", "condition_basis", "limitations", "prospective_test").forEach { text(value, it) }
        val lesson = exact(value.getJSONObject("lesson"), setOf(LESSON))
        require(lesson.getJSONObject(HOST).optString("state") == "eligible_for_scoped_reuse") {
            "A selection rule needs an independently retained method comparison"
        }
        CollaborationInnovationValidation.checkRecord(lesson, exact)
        val plan = exact(lesson.getJSONObject(HOST).getJSONObject("plan"), setOf(PLAN))
        val comparison = requireNotNull(plan.getJSONObject(HOST).optJSONObject(CollaborationWorkflowMethod.COMPARISON)) {
            "Selection requires an exact baseline/candidate workflow comparison"
        }
        val methods = listOf("baseline", "candidate").associateWith {
            exact(comparison.getJSONObject("${it}_method"), setOf(CollaborationWorkflowMethod.KIND))
        }
        val specs = methods.mapValues { it.value.getJSONObject("body").getJSONObject(CollaborationWorkflowMethod.KIND) }
        require(specs.values.all { it.getString("domain") == value.getString("domain") }) { "Rule and method domains differ" }
        for (field in listOf("inputs", "roles")) require(names(specs.getValue("baseline"), field) == names(specs.getValue("candidate"), field)) {
            "Conditional methods must share their public $field contract; use explicit planning for a different interface"
        }
        val conditions = conditions(value, "when_all")
        require(conditions.isNotEmpty()) { "when_all must describe a nonempty applicability condition" }
        val exclusions = conditions(value, "unless_any")
        val all = conditions + exclusions
        require(all.map { text(it, "id") }.distinct().size == all.size) { "Condition IDs must be distinct" }
        all.forEach { condition ->
            require(condition.keys().asSequence().toSet() == setOf("id", "input", "pointer", "operator", "value", "rationale")) {
                "Condition fields are id, input, pointer, operator, value and rationale"
            }
            text(condition, "rationale")
            require(text(condition, "input") in names(specs.getValue("baseline"), "inputs")) { "Condition input is outside the method contract" }
            require(condition.opt("pointer") is String) { "Condition pointer must be a JSON pointer" }
            val pointer = condition.getString("pointer")
            require((pointer.isEmpty() || pointer.startsWith('/')) && !Regex("~(?![01])").containsMatchIn(pointer)) { "Invalid condition JSON pointer" }
            val operator = text(condition, "operator")
            require(operator in setOf("eq", "neq", "lt", "lte", "gt", "gte")) { "Unknown condition operator" }
            val expected = condition.get("value")
            require(expected == JSONObject.NULL || expected is String || expected is Boolean || expected is Number) { "Condition value must be a JSON scalar" }
            if (expected is Number) CollaborationEvolutionExperiment.decimal(condition, "value")
            require(operator in setOf("eq", "neq") || expected is Number) { "Ordered comparisons require a numeric value" }
        }
        return JSONObject().put("state", "evidence_linked_conditional_hypothesis")
            .put("lesson", CollaborationResearchCandidates.reference(lesson)).put("plan", CollaborationResearchCandidates.reference(plan))
            .put("domain", value.getString("domain")).put("conditions_prospectively_validated", false).put("causality_proven", false)
            .put("grants_permissions", false).apply { methods.forEach { (variant, saved) -> put("${variant}_method", CollaborationResearchCandidates.reference(saved)) } }
    }

    fun choose(rule: JSONObject, inputs: JSONObject): JSONObject {
        val spec = rule.getJSONObject("body").getJSONObject(KIND)
        fun evaluate(field: String) = conditions(spec, field).map { condition ->
            val input = condition.getString("input")
            val pointer = condition.getString("pointer")
            val selected = if (!inputs.has(input)) Result.failure(IllegalArgumentException("Missing input")) else runCatching {
                CollaborationEvolutionExperiment.pointer(JSONObject().put("value", inputs.get(input)), "/value$pointer")
            }
            val actual = selected.getOrNull()
            val expected = condition.get("value")
            val operator = condition.getString("operator")
            val numeric = actual is Number && expected is Number
            val typed = numeric || actual != null && actual.javaClass == expected.javaClass
            val comparison = if (numeric) runCatching {
                CollaborationEvolutionExperiment.decimal(JSONObject().put("actual", actual), "actual").compareTo(BigDecimal(expected.toString()))
            }.getOrNull() else null
            val known = selected.isSuccess && actual !is JSONObject && actual !is JSONArray && typed &&
                (!numeric || comparison != null) && (operator in setOf("eq", "neq") || comparison != null)
            val matched = known && when (operator) {
                "eq" -> if (numeric) comparison == 0 else actual == expected
                "neq" -> if (numeric) comparison != 0 else actual != expected
                "lt" -> comparison!! < 0
                "lte" -> comparison!! <= 0
                "gt" -> comparison!! > 0
                "gte" -> comparison!! >= 0
                else -> false
            }
            JSONObject().put("condition_id", condition.getString("id")).put("state", if (!known) "unknown" else if (matched) "matched" else "not_matched")
        }
        val positive = evaluate("when_all")
        val negative = evaluate("unless_any")
        val unknown = (positive + negative).any { it.getString("state") == "unknown" }
        val excluded = negative.any { it.getString("state") == "matched" }
        val candidate = !unknown && !excluded && positive.all { it.getString("state") == "matched" }
        val variant = if (candidate) "candidate" else "baseline"
        return JSONObject().put("rule", CollaborationResearchCandidates.reference(rule)).put("variant", variant)
            .put("method", rule.getJSONObject(HOST).getJSONObject("${variant}_method"))
            .put("reason", when { excluded -> "countercondition_matched"; unknown -> "insufficient_condition_data"; candidate -> "applicability_matched"; else -> "outside_applicability" })
            .put("when_all", JSONArray(positive)).put("unless_any", JSONArray(negative))
            .put("input_evidence", "declared_workflow_inputs_not_independently_verified")
            .put("quality_effect", JSONObject.NULL).put("causality_proven", false)
    }

    fun read(ref: JSONObject, workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess): JSONObject {
        require(ref.opt("revision") is Int && ref.getInt("revision") > 0) { "Use an exact selection rule revision" }
        val saved = requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))) { "Selection rule unavailable or isolated" }
        require(saved.getString("kind") == KIND && CollaborationResearchCandidates.same(saved, ref)) { "Selection rule digest or kind mismatch" }
        return saved
    }

    fun binding(use: JSONObject, method: JSONObject, workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess,
                replay: Boolean): JSONObject? {
        if (!use.has(FIELD)) return null
        val rule = read(use.getJSONObject(FIELD), workspace, access)
        if (!replay) CollaborationCapabilityChannel.requireCurrentLineage(rule, workspace, access)
        val decision = choose(rule, use.getJSONObject("inputs"))
        require(CollaborationResearchCandidates.same(method, decision.getJSONObject("method"))) { "Workflow method does not match its conditional selection" }
        return decision
    }

    private fun conditions(value: JSONObject, field: String): List<JSONObject> = value.getJSONArray(field).let { a -> (0 until a.length()).map(a::getJSONObject) }
    private fun names(value: JSONObject, field: String): Set<String> = value.getJSONArray(field).let { a -> (0 until a.length()).mapTo(hashSetOf()) { a.getString(it) } }
}
