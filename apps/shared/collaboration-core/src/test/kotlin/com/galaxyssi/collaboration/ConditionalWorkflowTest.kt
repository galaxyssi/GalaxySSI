package com.galaxyssi.collaboration

import java.math.BigDecimal
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ConditionalWorkflowTest {
    private fun condition(value: Any = 2, operator: String = "gte", pointer: String = "/count", id: String = "reuse") =
        JSONObject().put("id", id).put("input", "data").put("pointer", pointer).put("operator", operator).put("value", value)
    private fun choose(data: JSONObject, expected: Any = 2, operator: String = "gte", pointer: String = "/count",
                       excluded: JSONArray = JSONArray()) = ConditionalWorkflow.choose(
        JSONArray().put(condition(expected, operator, pointer)), excluded, JSONObject().put("data", data))

    @Test fun applicabilitySelectsCandidateButOutOfScopeUsesBaseline() {
        assertEquals("candidate", choose(JSONObject().put("count", 2)).variant)
        val fallback = choose(JSONObject().put("count", 1))
        assertEquals("baseline", fallback.variant)
        assertEquals("outside_applicability", fallback.reason)
    }

    @Test fun missingInputsPointersContainersAndWrongTypesAreUnknown() {
        for (data in listOf(JSONObject(), JSONObject().put("count", "3"), JSONObject().put("count", true),
            JSONObject().put("count", JSONObject()), JSONObject().put("count", JSONArray()))) {
            val decision = choose(data)
            assertEquals(data.toString(), "baseline", decision.variant)
            assertEquals("unknown", decision.whenAll.single().state)
        }
        assertEquals("insufficient_condition_data", ConditionalWorkflow.choose(JSONArray().put(condition()), JSONArray(), JSONObject()).reason)
    }

    @Test fun unknownCounterconditionCannotSilentlyEnableCandidate() {
        val result = choose(JSONObject().put("count", 3), excluded = JSONArray().put(condition(true, "eq", "/mutable", "exclusion")))
        assertEquals("baseline", result.variant)
        assertEquals("insufficient_condition_data", result.reason)
        assertEquals("unknown", result.unlessAny.single().state)
    }

    @Test fun matchedCounterconditionTakesPrecedenceOverMissingPositiveEvidence() {
        val result = choose(JSONObject().put("mutable", true), excluded = JSONArray().put(condition(true, "eq", "/mutable", "exclusion")))
        assertEquals("baseline", result.variant)
        assertEquals("countercondition_matched", result.reason)
    }

    @Test fun nullIsNotMissingAndNeverCoercesToString() {
        assertEquals("candidate", choose(JSONObject().put("count", JSONObject.NULL), JSONObject.NULL, "eq").variant)
        assertEquals("unknown", choose(JSONObject(), JSONObject.NULL, "eq").whenAll.single().state)
        assertEquals("unknown", choose(JSONObject().put("count", "null"), JSONObject.NULL, "eq").whenAll.single().state)
    }

    @Test fun decimalComparisonsPreservePrecisionAndAllOperators() {
        val data = JSONObject().put("count", BigDecimal("9007199254740993.0001"))
        assertEquals("candidate", choose(data, BigDecimal("9007199254740993"), "gt").variant)
        for ((operator, expected) in mapOf("eq" to true, "neq" to false, "lt" to false, "lte" to true, "gt" to false, "gte" to true)) {
            assertEquals(operator, if (expected) "candidate" else "baseline", choose(JSONObject().put("count", 2.0), 2, operator).variant)
        }
        assertEquals("unknown", choose(JSONObject().put("count", BigDecimal("1e129"))).whenAll.single().state)
    }

    @Test fun escapedPointersAndArrayIndicesWorkWithoutJsonPointerLibrary() {
        val data = JSONObject().put("a/b", JSONObject().put("~key", JSONArray().put(3)))
        assertEquals("candidate", choose(data, pointer = "/a~1b/~0key/0").variant)
        for (pointer in listOf("/a~1b/~0key/01", "/a~1b/~0key/-1", "/a~2b", "/a~1b/~0key/2147483648")) {
            assertEquals(pointer, "unknown", choose(data, pointer = pointer).whenAll.single().state)
        }
    }

    @Test fun selectionDoesNotMutateInputsOrRule() {
        val inputs = JSONObject().put("data", JSONObject().put("count", 4))
        val conditions = JSONArray().put(condition())
        val before = inputs.toString() to conditions.toString()
        repeat(3) { ConditionalWorkflow.choose(conditions, JSONArray(), inputs) }
        assertEquals(before, inputs.toString() to conditions.toString())
    }
}
