package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic publication and recall only. No model call or assertion of learned behaviour. */
@RunWith(AndroidJUnit4::class)
class CollaborationSingleResearchDeviceTest {
    @Test fun oneMemberCanPersistAnUnverifiedMethodAndRecallItInANewTask() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "single-research-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        val raw = JSONObject().put("format", CollaborationAdaptivePilotPlan.SINGLE_RESEARCH_FORMAT)
            .put("pilot_id", "single-research-device").put("device_model", android.os.Build.MODEL)
            .put("target_id", "fixture:codex").put("model_id", "selected-model").put("reasoning_effort", "high")
            .put("tool_scope", CollaborationRemotePilotPlan.TOOL_SCOPE).put("goal", "Preserve a synthetic method; do not call models")
            .put("trial_timeout_ms", 1_000).put("maximum_dispatches", 1)
            .put("members", JSONArray().put(JSONObject().put("id", "solo").put("name", "Solo").put("role", "Researcher")))
        val plan = CollaborationAdaptivePilotPlan.from(raw, 1, 1_000)
        val definition = plan.definition(group, "first-run")
        val member = definition.members.single()
        groups.update(group) { it.copy(members = plan.members, coordinatorId = "solo") }
        val workspace = CollaborationResearchWorkspace(context)
        try {
            assertTrue(plan.matchesExecution(member, definition))
            assertFalse(CollaborationLiveGraph.enabled(definition))
            assertEquals(plan.goal, member.objective)
            val access = CollaborationWorkspaceAccess(group, "first-run", "first-turn", 0, member.memberId, "solo")
            workspace.enrollPublication(access, requireNotNull(CollaborationResearchWorkflow.stage(member)))
            assertTrue(workspace.publicationCapability(access).getBoolean("publish_allowed"))
            val method = JSONObject().put("purpose", "Check an input before reusing a result").put("domain", "synthetic fixture")
                .put("bottleneck", "An input may change").put("change_rationale", "Check before reuse")
                .put("applies_when", "Input is accessible").put("avoid_when", "Input cannot be inspected")
                .put("risks", "Incomplete inspection").put("expected_gain", "Fewer stale results").put("falsifier", "Stale result reused")
                .put("dimensions", JSONArray().put("verification")).put("roles", JSONArray().put("analyst"))
                .put("inputs", JSONArray().put("source")).put("steps", JSONArray().put(JSONObject().put("id", "inspect")
                    .put("role", "analyst").put("stage", "EXECUTE").put("assignment", "Inspect supplied fixture before reuse")
                    .put("depends_on", JSONArray())))
            val artifact = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic candidate, not learned")
                .put("workspace", JSONArray().put(JSONObject().put("id", "fixture-method").put("kind", CollaborationWorkflowMethod.KIND)
                    .put("title", "Synthetic inspection candidate").put("body", JSONObject().put("content", "Test-authored, unverified")
                        .put(CollaborationWorkflowMethod.KIND, method))))
            val receipt = CollaborationMilestoneTool.execute(workspace, access, JSONObject().put("mode", "publish")
                .put("milestone_id", "candidate").put("artifact", artifact.toString())) {}
            assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
            val ref = receipt.getJSONArray("revisions").getJSONObject(0)
            val future = access.copy(runId = "next-run", turnId = "next-turn", nodeId = "next-node")
            val reopened = CollaborationResearchWorkspace(context)
            val original = requireNotNull(reopened.read(future, ref.getString("object_id"), ref.getInt("revision")))
            assertEquals(ref.getString("sha256"), original.getString("sha256"))
            assertEquals(method.toString(), original.getJSONObject("body").getJSONObject(CollaborationWorkflowMethod.KIND).toString())
            val host = original.getJSONObject(CollaborationEvolutionContract.HOST)
            assertEquals("unverified_workflow_candidate", host.getString("state"))
            assertFalse(host.getBoolean("quality_improved"))
            val query = JSONObject().put("mode", "workspace").put("object_id", ref.getString("object_id")).put("revision", ref.getInt("revision"))
            val recalled = JSONObject(CollaborationCloudRecall.execute(context, future, query))
            assertEquals(recalled.toString(), "returned", recalled.getString("status"))
            assertTrue(recalled.toString().contains(ref.getString("sha256")))
            assertEquals(1, groups.load(group)!!.members.size)
        } finally {
            groups.remove(group)
        }
    }
}
