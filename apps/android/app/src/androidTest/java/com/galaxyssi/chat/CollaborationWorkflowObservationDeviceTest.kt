package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.collaboration.ConditionalWorkflow
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local synthetic computation only. No model calls, UI automation, or existing task mutation. */
@RunWith(AndroidJUnit4::class)
class CollaborationWorkflowObservationDeviceTest {
    private fun fixture(test: (Fixture) -> Unit) {
        val f = Fixture()
        try { test(f) } finally { f.close() }
    }

    private class Fixture {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "observed-workflow-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        init { groups.update(group) { it.copy(members = listOf("lead", "peer").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "lead") } }
        fun access(round: Long = 2, person: String = "lead") = CollaborationWorkspaceAccess(group, "run", "turn", round, person, person)
        fun workspace() = CollaborationResearchWorkspace(context)
        fun original(id: String, values: List<Int>) = CollaborationEvidenceLedger(context).record(access(1, "peer"), id,
            "fixture.local_count", JSONArray(values).toString(), JSONObject().put("data", JSONObject()
                .put("count", values.size).put("unique", values.distinct().size)).toString(), 100, 101, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
        fun selectors(ref: JSONObject) = JSONObject().put("data", JSONObject().put("observation", ref).put("pointer", "/data"))
        fun resolve(ref: JSONObject) = CollaborationWorkflowObservations.resolve(selectors(ref), workspace(), access(), emptyMap())
        fun close() {
            CollaborationResearchWorkspace.remove(context, group)
            CollaborationEvidenceLedger.remove(context, group)
            groups.remove(group)
        }
    }

    @Test fun measuredLocalInputsChangeDecisionAndPersistAcrossReopen() = fixture { f ->
        val repeated = f.original("repeated", listOf(3, 3, 3))
        val varied = f.original("varied", listOf(1, 2, 3))
        val conditions = JSONArray().put(JSONObject().put("id", "one-value").put("input", "data")
            .put("pointer", "/unique").put("operator", "eq").put("value", 1))
        val first = f.resolve(repeated)
        assertEquals("candidate", ConditionalWorkflow.choose(conditions, JSONArray(), first.values).variant)
        assertEquals("baseline", ConditionalWorkflow.choose(conditions, JSONArray(), f.resolve(varied).values).variant)
        val reopened = f.resolve(repeated)
        assertEquals(first.bindings.toString(), reopened.bindings.toString())
        assertEquals(3, reopened.values.getJSONObject("data").getInt("count"))
        assertFalse(reopened.bindings.getJSONObject("data").getBoolean("truth_verified"))
    }

    @Test fun actualWorkspaceAndSchedulerBindOriginalInputWithoutChangingInstructions() = fixture { f ->
        val spec = JSONObject().put("purpose", "Check synthetic data").put("domain", "fixture").put("bottleneck", "Unknown count")
            .put("change_rationale", "Read observed count").put("applies_when", "Local fixture").put("avoid_when", "Outside fixture")
            .put("risks", "Limited scope").put("expected_gain", "Unknown").put("falsifier", "Incorrect count")
            .put("dimensions", JSONArray().put("verification")).put("roles", JSONArray().put("worker"))
            .put("inputs", JSONArray().put("data")).put("steps", JSONArray().put(JSONObject().put("id", "check").put("role", "worker")
                .put("stage", "VERIFY").put("assignment", "Check the supplied local counts").put("depends_on", JSONArray())))
        val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic method")
            .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject().put("id", "method")
                .put("kind", CollaborationWorkflowMethod.KIND).put("title", "Fixture method")
                .put("body", JSONObject().put("content", "Local test").put(CollaborationWorkflowMethod.KIND, spec))))
        val receipt = f.workspace().publish(f.access(1), raw.toString(), 10)
        assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
        val method = receipt.getJSONArray("revisions").getJSONObject(0)
        val ref = f.original("counts", listOf(1, 2, 2))
        val request = JSONObject().put(CollaborationWorkflowInstantiation.FIELD, JSONObject().put("execution_id", "local")
            .put("method", method).put("inputs", JSONObject()).put("roles", JSONObject().put("worker", "peer"))
            .put(CollaborationWorkflowObservations.FIELD, f.selectors(ref)))
        val work = CollaborationWorkflowInstantiation.expand(JSONArray().put(request), f::workspace, f.access()).let { a ->
            (0 until a.length()).map(a::getJSONObject) }
        val members = CollaborationGoalLoop.initial(listOf(AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead"),
            AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "peer")), "Check fixture")
        val record = AgentTeamExecutionRecord(AgentTeamDefinition("fixture", "fixture", members, primaryInstanceId = "lead"),
            AgentRunRequest(f.group, "turn", "fixture", runId = "run", goal = "Check fixture"))
        val first = CollaborationWorkflowWork.plan(record, work, f::workspace, f.access())
        val binding = JSONObject(CollaborationWorkflowWork.context(first.work.single()).getValue(CollaborationWorkflowWork.TASK))
        assertEquals(2, binding.getJSONObject("inputs").getJSONObject("data").getInt("unique"))
        assertEquals("Check the supplied local counts", binding.getString("assignment"))
        val restored = record.copy(request = record.request.copy(context = record.request.context + (CollaborationWorkflowWork.CLAIMS to first.claims)))
        assertEquals(first.claims, CollaborationWorkflowWork.plan(restored, work, f::workspace, f.access()).claims)
        work.single().getJSONObject(CollaborationWorkflowWork.FIELD).getJSONObject("inputs").getJSONObject("data").put("count", 999)
        assertTrue(runCatching { CollaborationWorkflowWork.plan(restored, work, f::workspace, f.access()) }.isFailure)
    }

    @Test fun unrelatedGroupAndAlteredDigestCannotReadObservation() = fixture { f ->
        val ref = f.original("counts", listOf(1))
        assertTrue(runCatching { f.workspace().workflowObservation(f.access().copy(groupId = "not-this-group"), ref) }.isFailure)
        assertTrue(runCatching { f.workspace().workflowObservation(f.access(), JSONObject(ref.toString()).put("sha256", "0".repeat(64))) }.isFailure)
        assertTrue(runCatching { CollaborationWorkflowObservations.combine(JSONObject().put("data", "override"), f.resolve(ref)) }.isFailure)
    }
}
