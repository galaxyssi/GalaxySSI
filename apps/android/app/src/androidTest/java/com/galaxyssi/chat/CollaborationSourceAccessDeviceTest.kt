package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationSourceAccessDeviceTest {
    @Test fun cloudAndNativeInspectDirectSourcesWithoutBroadeningAccessOrRecordingReads() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val groups = CollaborationGroupStore(context)
        val group = "source-access-${UUID.randomUUID()}"
        groups.update(group) { it.copy(members = listOf("author", "producer", "reviewer", "independent").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "author") }
        try {
            val access = CollaborationWorkspaceAccess(group, "run", "turn", 1, "producer-node", "producer")
            val author = access.copy(nodeId = "author-node", personId = "author", dependencyNodes = setOf("producer-node"))
            val reviewer = access.copy(nodeId = "review-node", personId = "reviewer", dependencyNodes = setOf("author-node"))
            val workspace = CollaborationResearchWorkspace(context)
            val ledger = CollaborationEvidenceLedger(context)
            val observation = ledger.record(access, "source-access-tool", "fixture", "{}", "{\"private_result\":42}", 1, 2)
            fun publish(who: CollaborationWorkspaceAccess, id: String, parents: JSONArray = JSONArray(), observations: JSONArray = JSONArray()): JSONObject {
                val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture")
                    .put("candidates", JSONArray()).put("findings", JSONArray()).put("questions", JSONArray())
                    .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", "artifact").put("title", id)
                        .put("body", JSONObject().put("content", "private_content")).put("parents", parents).put("observations", observations)))
                val result = workspace.publish(who, raw.toString())
                assertEquals(result.toString(), "recorded", result.getString("status"))
                return result.getJSONArray("revisions").getJSONObject(0)
            }
            val parent = publish(access, "original")
            val root = publish(author, "report", JSONArray().put(parent), JSONArray().put(observation))
            val input = JSONObject().put("mode", CollaborationSourceAccess.MODE).put("object_id", root.getString("object_id"))
                .put("revision", root.getInt("revision")).put("sha256", root.getString("sha256"))
            val cloud = JSONObject(CollaborationCloudRecall.execute(context, reviewer, input))
            assertEquals("returned", cloud.getString("status"))
            assertEquals(2, cloud.getInt("total_references"))
            repeat(2) { assertEquals("missing_changed_or_out_of_scope", cloud.getJSONArray("references").getJSONObject(it).getString("status")) }
            assertFalse(cloud.toString().contains("private_result"))
            assertFalse(cloud.toString().contains("private_content"))
            assertNull(workspace.read(reviewer, parent.getString("object_id"), parent.getInt("revision")))
            assertNull(ledger.read(reviewer, observation.getString("evidence_id"), observation.getString("sha256")))
            assertFalse(cloud.has(CollaborationEvidenceReadCoverage.FIELD))

            val granted = reviewer.copy(pinnedReads = setOf(requireNotNull(CollaborationMilestoneDispatch.grant(parent)),
                requireNotNull(CollaborationMilestoneDispatch.grant(observation))))
            ledger.bind(19_041, granted)
            val before = ledger.references(granted, JSONArray().put(observation)).toString()
            val registry = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
                .subset { it.id == CollaborationRecallNativeTool.ID }
            val native = registry.invoke(CollaborationRecallNativeTool.ID, input.toNativeObject(),
                AgentNativeToolInvocationContext(conversationId = group, turnId = "turn", collaborationSourceMessageId = 19_041))
            assertTrue(native.toJson(), native.isSuccess)
            val result = JSONObject(native.output)
            repeat(2) { assertEquals("available", result.getJSONArray("references").getJSONObject(it).getString("status")) }
            assertEquals(before, CollaborationEvidenceLedger(context).references(granted, JSONArray().put(observation)).toString())
            val reopened = CollaborationResearchWorkspace(context).sourceAccess(granted, input.toNativeObject())
            assertEquals(result.getJSONArray("references").toString(), reopened.getJSONArray("references").toString())

            assertFalse(registry.invoke(CollaborationRecallNativeTool.ID, input.toNativeObject(),
                AgentNativeToolInvocationContext(conversationId = group, turnId = "turn")).isSuccess)
            val independent = access.copy(nodeId = "independent-node", personId = "independent")
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, independent, input)).getString("status"))
            listOf(JSONObject(input.toString()).put("sha256", "0".repeat(64)), JSONObject(input.toString()).put("offset", 0),
                JSONObject(input.toString()).put("node_id", "author-node"), JSONObject(input.toString()).put("cursor", "wrong"))
                .forEach { assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, reviewer, it)).getString("status")) }
            groups.update(group) { it.copy(members = it.members.filterNot { member -> member.id == "reviewer" }) }
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, granted, input)).getString("status"))
        } finally { groups.remove(group) }
    }
}
