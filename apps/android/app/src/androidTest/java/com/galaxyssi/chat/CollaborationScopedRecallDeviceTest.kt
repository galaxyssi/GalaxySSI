package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationScopedRecallDeviceTest {
    @Test fun cloudAndNativeReadAssignedDependencyButNotIndependentMember() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "scoped-recall-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("author", "reviewer", "independent").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "author") }
        try {
            val access = CollaborationWorkspaceAccess(group, "run", "turn", 1, "author-node", "author")
            val reviewer = access.copy(nodeId = "review-node", personId = "reviewer", dependencyNodes = setOf("author-node"))
            val ledger = CollaborationEvidenceLedger(context)
            val original = JSONObject().put("text", "original:" + "x".repeat(12_000)).toString()
            val ref = ledger.record(access, "command", "commandExecution", "{}", original, 1, 2,
                CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL)
            ledger.bind(902, reviewer)
            val input = JSONObject().put("mode", "evidence").put("evidence_id", ref.getString("evidence_id"))
                .put("sha256", ref.getString("sha256"))
            val session = CloudImageAnnotationSession(context, emptyList(), collaborationEvidence = CollaborationCloudEvidence(ledger, reviewer))
            val prepared = PreparedCloudConversationStream("fixture", com.galaxyssi.chat.voice.modelstream.ModelStreamProvider.OPENAI_COMPATIBLE,
                "https://example.invalid", emptyMap(), JSONObject(), org.json.JSONArray(), "messages")
            CloudImageAnnotationSession(context, emptyList()).installCollaborationTools(prepared)
            assertFalse("Ordinary conversations must not get group recall", prepared.body.has("tools"))
            session.installCollaborationTools(prepared)
            assertEquals(CollaborationCloudRecall.NAME, prepared.body.getJSONArray("tools").getJSONObject(0)
                .getJSONObject("function").getString("name"))
            val first = JSONObject(session.execute(CollaborationCloudRecall.NAME, input))
            assertEquals("returned", first.getString("status"))
            assertNotNull(first.getJSONObject("galaxyssi_evidence_receipt"))
            assertEquals(ref.getString("evidence_id"), first.getJSONObject("source_reference").getString("evidence_id"))
            assertEquals(ref.getString("sha256"), first.getJSONObject("source_reference").getString("sha256"))
            assertNotEquals(first.getJSONObject("source_reference").getString("evidence_id"),
                first.getJSONObject("galaxyssi_evidence_receipt").getString("evidence_id"))
            assertEquals("desktop_codex_tool", first.getJSONObject("source_reference").getString("origin"))
            assertTrue(first.getString("content").contains("original:"))
            val second = JSONObject(session.execute(CollaborationCloudRecall.NAME, JSONObject(input.toString())
                .put("offset", first.getInt("next_offset"))))
            val reconstructed = JSONObject(first.getString("content") + second.getString("content"))
            assertEquals(first.getJSONObject("source_reference").toString(), second.getJSONObject("source_reference").toString())
            assertEquals(original, reconstructed.getString("output_json"))
            val hidden = JSONObject(CollaborationCloudRecall.execute(context,
                access.copy(nodeId = "independent-node", personId = "independent"), input))
            assertEquals("failed", hidden.getString("status"))
            assertFalse(hidden.has("source_reference"))
            val mismatch = JSONObject(CollaborationCloudRecall.execute(context, reviewer,
                JSONObject(input.toString()).put("sha256", "0".repeat(64))))
            assertEquals("failed", mismatch.getString("status"))
            assertFalse(mismatch.has("source_reference"))
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, reviewer,
                JSONObject(input.toString()).put("source_message_id", 902))).getString("status"))
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, reviewer,
                JSONObject(input.toString()).put("offset", -1))).getString("status"))
            val registry = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
                .subset { it.id == CollaborationRecallNativeTool.ID }
            val native = registry.invoke(CollaborationRecallNativeTool.ID,
                mapOf("mode" to "evidence", "evidence_id" to ref.getString("evidence_id"), "sha256" to ref.getString("sha256")),
                AgentNativeToolInvocationContext(conversationId = group, turnId = "turn", collaborationSourceMessageId = 902))
            assertTrue(native.toJson(), native.isSuccess)
            assertTrue(native.output["content"].toString().contains("original:"))
            assertEquals(ref.getString("evidence_id"), (native.output["source_reference"] as Map<*, *>)["evidence_id"])
            groups.update(group) { it.copy(members = it.members.filterNot { member -> member.id == "reviewer" }) }
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, reviewer, input)).getString("status"))
        } finally { groups.remove(group) }
    }
}
