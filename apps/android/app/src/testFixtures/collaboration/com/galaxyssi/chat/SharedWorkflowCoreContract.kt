package com.galaxyssi.chat

import com.galaxyssi.collaboration.ConditionalWorkflow
import com.galaxyssi.collaboration.WorkflowMaterializer
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*

/** Runs under JVM org.json and Android's platform org.json; never calls a model or stores a run. */
object SharedWorkflowCoreContract {
    fun decisionParity() {
        val spec = JSONObject("""{"when_all":[{"id":"reuse","input":"data","pointer":"/count","operator":"gte","value":2}],
            "unless_any":[{"id":"mutable","input":"data","pointer":"/mutable","operator":"eq","value":true}]}""")
        fun ref(id: String) = JSONObject().put("object_id", id).put("revision", 1).put("sha256", "a".repeat(64))
        val rule = ref("rule").put("body", JSONObject().put(CollaborationWorkflowSelection.KIND, spec))
            .put(CollaborationEvolutionContract.HOST, JSONObject().put("baseline_method", ref("baseline")).put("candidate_method", ref("candidate")))
        for (data in listOf("{\"count\":3,\"mutable\":false}", "{\"count\":1,\"mutable\":false}",
            "{\"count\":3,\"mutable\":true}", "{\"count\":3}", "{\"count\":\"3\",\"mutable\":false}")) {
            val inputs = JSONObject().put("data", JSONObject(data))
            val expected = ConditionalWorkflow.choose(spec.getJSONArray("when_all"), spec.getJSONArray("unless_any"), inputs)
            val actual = CollaborationWorkflowSelection.choose(rule, inputs)
            assertEquals(expected.variant, actual.getString("variant"))
            assertEquals(expected.variant, actual.getJSONObject("method").getString("object_id"))
            assertEquals(expected.reason, actual.getString("reason"))
            assertEquals(expected.whenAll.single().state, actual.getJSONArray("when_all").getJSONObject(0).getString("state"))
            assertEquals(expected.unlessAny.single().state, actual.getJSONArray("unless_any").getJSONObject(0).getString("state"))
            assertFalse(actual.getBoolean("causality_proven"))
            assertTrue(actual.isNull("quality_effect"))
        }
    }

    fun graphAndLegacyIdentityParity() {
        val steps = JSONArray("""[
            {"id":"model","role":"worker","stage":"EXECUTE","assignment":"Create local fixture"},
            {"id":"probe","role":"reviewer","stage":"EXECUTE","assignment":"Gather independent input"},
            {"id":"verify","role":"reviewer","stage":"VERIFY","assignment":"Check fixture","depends_on":["model","probe"],
             "independent_review":true,"review_targets":["model"]}]
        """)
        for (execution in listOf("shared-fixture", "\u7814\u7a76", "</tag>", "quote\"slash\\", "\n\t")) {
            val work = WorkflowMaterializer.expand(execution, (0 until steps.length()).map(steps::getJSONObject),
                JSONObject().put("worker", "Hopper").put("reviewer", "Turing")).map { it.work }
            val legacy = "workflow:" + UUID.nameUUIDFromBytes(JSONArray().put(execution).put("model").toString().toByteArray(Charsets.UTF_8))
            assertEquals(legacy, work.first().getString("id"))
            assertEquals(legacy, CollaborationWorkflowInstantiation.workId(execution, "model"))
            assertEquals(setOf(legacy), CollaborationReviewTargets.read(work.last()))
            assertEquals(2, CollaborationWorkGraph.dependencies(work.last()).size)
            assertEquals("", CollaborationWorkGraph.compile(work, emptySet()).error)
            work.first().put("member", "Turing")
            assertTrue(CollaborationWorkGraph.compile(work, emptySet()).error.contains("different author"))
        }
    }

    fun noWorkspaceForOrdinaryPlans() {
        val ordinary = JSONArray().put(JSONObject().put("id", "untouched"))
        val access = CollaborationWorkspaceAccess("fixture", "run", "turn", 1, "lead", "lead")
        assertSame(ordinary, CollaborationWorkflowInstantiation.expand(ordinary, { error("Unexpected workspace read") }, access))
    }
}
