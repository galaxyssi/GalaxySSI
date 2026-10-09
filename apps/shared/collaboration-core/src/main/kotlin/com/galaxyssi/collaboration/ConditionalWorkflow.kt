package com.galaxyssi.collaboration

import java.math.BigDecimal
import org.json.JSONArray
import org.json.JSONObject

/** Deterministic applicability, not evidence of causality, improvement, or authorization. */
object ConditionalWorkflow {
    data class ConditionResult(val id: String, val state: String)
    data class Selection(
        val variant: String,
        val reason: String,
        val whenAll: List<ConditionResult>,
        val unlessAny: List<ConditionResult>
    )

    fun choose(whenAll: JSONArray, unlessAny: JSONArray, inputs: JSONObject): Selection {
        val positive = evaluate(whenAll, inputs)
        val negative = evaluate(unlessAny, inputs)
        val unknown = (positive + negative).any { it.state == "unknown" }
        val excluded = negative.any { it.state == "matched" }
        val candidate = !unknown && !excluded && positive.all { it.state == "matched" }
        return Selection(
            if (candidate) "candidate" else "baseline",
            when {
                excluded -> "countercondition_matched"
                unknown -> "insufficient_condition_data"
                candidate -> "applicability_matched"
                else -> "outside_applicability"
            }, positive, negative
        )
    }

    private fun evaluate(conditions: JSONArray, inputs: JSONObject): List<ConditionResult> =
        (0 until conditions.length()).map { index ->
            val condition = conditions.getJSONObject(index)
            val input = condition.getString("input")
            val selected = if (!inputs.has(input)) Result.failure(IllegalArgumentException("Missing input")) else runCatching {
                pointer(JSONObject().put("value", inputs.get(input)), "/value${condition.getString("pointer")}")
            }
            val actual = selected.getOrNull()
            val expected = condition.get("value")
            val operator = condition.getString("operator")
            val numeric = actual is Number && expected is Number
            val typed = numeric || actual != null && actual.javaClass == expected.javaClass
            val comparison = if (numeric) runCatching {
                decimal(actual!!).compareTo(BigDecimal(expected.toString()))
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
            ConditionResult(condition.getString("id"), if (!known) "unknown" else if (matched) "matched" else "not_matched")
        }

    private fun decimal(value: Any): BigDecimal = BigDecimal(value.toString()).also {
        require(it.precision() <= 128 && kotlin.math.abs(it.scale().toLong()) <= 128) { "Unsupported decimal precision" }
    }

    // Both Android and JVM hosts use this traversal; Android has no JSONPointer API.
    private fun pointer(root: JSONObject, path: String): Any {
        require(path.startsWith('/')) { "Invalid JSON pointer" }
        return path.drop(1).split('/').fold(root as Any) { current, part ->
            require(!Regex("~(?![01])").containsMatchIn(part)) { "Invalid JSON pointer escape" }
            val key = part.replace("~1", "/").replace("~0", "~")
            when (current) {
                is JSONObject -> current.get(key)
                is JSONArray -> {
                    require(key.matches(Regex("0|[1-9][0-9]*"))) { "Invalid array index" }
                    current.get(key.toInt())
                }
                else -> throw IllegalArgumentException("Pointer traverses a non-container")
            }
        }
    }
}
