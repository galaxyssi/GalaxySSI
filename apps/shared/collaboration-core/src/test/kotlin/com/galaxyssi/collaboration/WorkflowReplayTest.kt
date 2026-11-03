package com.galaxyssi.collaboration

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WorkflowReplayTest {
    private fun request() = JSONObject("""{
      "execution_id":"fixture", "inputs":{"data":{"count":3,"mutable":false}},
      "roles":{"worker":"Hopper","reviewer":"Turing"},
      "rule":{"when_all":[{"id":"reuse","input":"data","pointer":"/count","operator":"gte","value":2}],
        "unless_any":[{"id":"mutable","input":"data","pointer":"/mutable","operator":"eq","value":true}]},
      "methods":{
        "baseline":{"steps":[{"id":"parse-each","role":"worker","assignment":"Parse each input","stage":"EXECUTE"}]},
        "candidate":{"steps":[{"id":"index","role":"worker","assignment":"Index once","stage":"EXECUTE"},
          {"id":"verify","role":"reviewer","assignment":"Compare against input","stage":"VERIFY",
           "depends_on":["index"],"independent_review":true,"review_targets":["index"]}]}
      }
    }""")

    @Test fun headlessAdapterUsesTheSameDecisionAndActualWorkProjection() {
        val input = request()
        val output = WorkflowReplay.evaluate(input)
        val rule = input.getJSONObject("rule")
        val decision = ConditionalWorkflow.choose(rule.getJSONArray("when_all"), rule.getJSONArray("unless_any"), input.getJSONObject("inputs"))
        assertEquals(decision.variant, output.getString("variant"))
        assertEquals(decision.reason, output.getString("reason"))
        val steps = input.getJSONObject("methods").getJSONObject(decision.variant).getJSONArray("steps")
        val expected = WorkflowMaterializer.expand("fixture", (0 until steps.length()).map(steps::getJSONObject), input.getJSONObject("roles"))
        assertTrue(JSONArray(expected.map { it.work }).similar(output.getJSONArray("work")))
        assertFalse(output.getBoolean("execution_performed"))
        assertFalse(output.getBoolean("host_admission_performed"))
        assertFalse(output.getBoolean("causality_proven"))
        assertTrue(output.isNull("quality_effect"))
    }

    @Test fun changedConditionChangesActualSelectedGraphWithoutClaimingAnEffect() {
        val input = request()
        assertEquals(2, WorkflowReplay.evaluate(input).getJSONArray("work").length())
        input.getJSONObject("inputs").getJSONObject("data").put("mutable", true)
        val output = WorkflowReplay.evaluate(input)
        assertEquals("baseline", output.getString("variant"))
        assertEquals("Parse each input", output.getJSONArray("work").getJSONObject(0).getString("assignment"))
        assertTrue(output.isNull("quality_effect"))
    }

    @Test fun reopeningSameFixtureKeepsDecisionAndWorkIds() {
        val first = WorkflowReplay.evaluate(request())
        val reopened = WorkflowReplay.evaluate(JSONObject(request().toString()))
        assertTrue(first.similar(reopened))
    }
}
