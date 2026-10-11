package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local synthetic records only; no model calls and no execution of saved methods. */
@RunWith(AndroidJUnit4::class)
class CollaborationWorkflowCheckDeviceTest {
    @Test fun nativeAndCloudCheckDurableRuleWithPartialInputsAndRevocableMemberAccess() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "workflow-check-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("curator", "author", "planner", "executor", "analyst", "reviewer").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "curator") }
        try {
            val ledger = CollaborationEvidenceLedger(context)
            val f = CollaborationRetentionFixture(CollaborationResearchWorkspace(context), ledger, group)
            val study = f.study()
            val lesson = f.accepted(f.lesson(study))
            fun condition(id: String, pointer: String, value: Any) = JSONObject().put("id", id).put("input", "data")
                .put("pointer", pointer).put("operator", "eq").put("value", value).put("rationale", "Local synthetic condition")
            val spec = JSONObject().put("purpose", "Inspect before dispatch").put("domain", "fixture").put("lesson", f.ref(lesson))
                .put("condition_basis", "Synthetic comparison only").put("limitations", "No real method improvement")
                .put("prospective_test", "Future controlled tasks").put("when_all", JSONArray().put(condition("repeat", "/count", 3)))
                .put("unless_any", JSONArray().put(condition("mutable", "/mutable", true)))
            val rule = f.accepted(f.publish(CollaborationWorkflowSelection.KIND, spec))
            val access = f.access()
            val source = System.currentTimeMillis()
            ledger.bind(source, access)
            val args = JSONObject().put("mode", CollaborationWorkflowCheck.MODE).put("object_id", rule.getString("object_id"))
                .put("revision", rule.getInt("revision")).put("sha256", rule.getString("sha256"))
                .put("inputs", JSONObject().put("data", JSONObject().put("count", 3)))
            val first = JSONObject(CollaborationCloudRecall.execute(context, access, args))
            assertEquals(first.toString(), "returned", first.getString("status"))
            val result = JSONObject(first.getString("content"))
            assertTrue(result.getBoolean("unknowns_may_change_selection"))
            assertEquals("pointer_unavailable", result.getJSONArray("unless_any").getJSONObject(0).getString("unknown_reason"))
            assertFalse(result.getBoolean("baseline_applicability_verified"))
            assertFalse(result.getBoolean("executes_work"))
            assertFalse(first.has(CollaborationEvidenceReadCoverage.FIELD))
            val registry = AgentNativeToolRegistry().registerAll(CollaborationRecallNativeTool.definitions(context))
            val completedArgs = JSONObject(args.toString()).apply { getJSONObject("inputs").getJSONObject("data").put("mutable", false) }
            val native = registry.invoke(CollaborationRecallNativeTool.ID, completedArgs.toNativeObject(),
                AgentNativeToolInvocationContext(conversationId = group, turnId = access.turnId, collaborationSourceMessageId = source))
            assertTrue(native.toJson(), native.isSuccess)
            val checked = JSONObject(native.output["content"] as String)
            assertEquals("candidate", checked.getJSONObject("selection").getString("variant"))
            assertFalse(checked.getBoolean("unknowns_may_change_selection"))
            val repeated = JSONObject(CollaborationCloudRecall.execute(context, access, args))
            assertEquals(first.getString("content"), repeated.getString("content"))
            val stored = CollaborationResearchWorkspace(context).read(access, rule.getString("object_id"), rule.getInt("revision"))!!
            assertEquals(rule.toString(), stored.toString())
            val isolated = access.copy(round = rule.getLong("round"), nodeId = "independent-check", personId = "author")
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, isolated, args)).getString("status"))
            val shared = isolated.copy(pinnedReads = setOf(requireNotNull(CollaborationMilestoneDispatch.grant(rule))))
            assertEquals("returned", JSONObject(CollaborationCloudRecall.execute(context, shared, args)).getString("status"))
            val unbound = registry.invoke(CollaborationRecallNativeTool.ID, completedArgs.toNativeObject(),
                AgentNativeToolInvocationContext(conversationId = group, turnId = access.turnId))
            assertFalse(unbound.isSuccess)
            val wrongMode = JSONObject(CollaborationCloudRecall.execute(context, access, JSONObject(args.toString()).put("mode", "workspace")))
            assertEquals("failed", wrongMode.getString("status"))
            groups.update(group) { it.copy(members = it.members.filterNot { member -> member.id == "curator" }) }
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, access, args)).getString("status"))
        } finally {
            CollaborationResearchWorkspace.remove(context, group)
            CollaborationEvidenceLedger.remove(context, group)
            groups.remove(group)
        }
    }
}
