package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationGoalContractDeviceTest {
    @Test fun encryptedGoalPagesReachCloudAndNativeWithoutSnapshotSelection() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "goal-contract-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("reader", "other").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "reader") }
        try {
            val access = CollaborationWorkspaceAccess(group, "run", "turn", 1, "node", "reader")
            val ledger = CollaborationEvidenceLedger(context)
            val sourceMessageId = AgentTeamDispatchIds.sourceMessageId("$group:reader")
            ledger.bind(sourceMessageId, access)
            val store = CollaborationGoalContractStore(context)
            val goal = "First constraint.\n" + "Preserve original evidence.\n".repeat(1000) + "FINAL_REQUIRED_CONSTRAINT"
            val descriptor = store.publish(access, goal, "[]", mapOf("Member roster" to "reader, other"))
            assertEquals(descriptor.toString(), "ok", descriptor.optString("status"))
            assertEquals("ok", store.bind(access, descriptor.getString("snapshot_id")).getString("status"))
            val session = CloudImageAnnotationSession(context, emptyList(), collaborationEvidence = CollaborationCloudEvidence(ledger, access))
            val native = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
                .subset { it.id == CollaborationRecallNativeTool.ID }
            val reconstructed = StringBuilder()
            var cursor = ""
            var count = 0
            do {
                val input = JSONObject().put("mode", "goal_contract").put("cursor", cursor)
                val page = JSONObject(session.execute(CollaborationCloudRecall.NAME, input))
                assertEquals(page.toString(), "returned", page.optString("status"))
                assertTrue(page.has("galaxyssi_evidence_receipt"))
                assertEquals("Projection must preserve contract fragments", page.toString(), CloudEvidencePromptLedger().project(page.toString()))
                val nativePage = native.invoke(CollaborationRecallNativeTool.ID,
                    mapOf("mode" to "goal_contract", "cursor" to cursor),
                    AgentNativeToolInvocationContext(conversationId = group, turnId = "turn", collaborationSourceMessageId = sourceMessageId))
                assertTrue(nativePage.toJson(), nativePage.isSuccess)
                assertEquals(page.getString("page_sha256"), nativePage.output["page_sha256"])
                val fragments = page.getJSONArray("fragments")
                repeat(fragments.length()) { index ->
                    val fragment = fragments.getJSONObject(index)
                    if (fragment.getString("stream") == "goal") {
                        assertEquals(reconstructed.length, fragment.getInt("start_utf16"))
                        reconstructed.append(fragment.getString("text"))
                    }
                }
                count++
                cursor = page.opt("next_cursor")?.takeUnless { it == JSONObject.NULL }?.toString().orEmpty()
            } while (cursor.isNotBlank())
            assertTrue(count > 1)
            assertEquals(goal, reconstructed.toString())
            assertEquals(descriptor.getString("snapshot_id"), CollaborationGoalContractStore(context).lookup(access).getString("snapshot_id"))
            val forged = JSONObject().put("mode", "goal_contract").put("snapshot_id", descriptor.getString("snapshot_id"))
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, access, forged)).getString("status"))
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context,
                access.copy(nodeId = "other-node", personId = "other"), JSONObject().put("mode", "goal_contract"))).getString("status"))
            val unbound = native.invoke(CollaborationRecallNativeTool.ID, mapOf("mode" to "goal_contract"),
                AgentNativeToolInvocationContext(conversationId = group, turnId = "turn"))
            assertFalse(unbound.isSuccess)
            val malformedCursor = native.invoke(CollaborationRecallNativeTool.ID,
                mapOf("mode" to "goal_contract", "cursor" to 7),
                AgentNativeToolInvocationContext(conversationId = group, turnId = "turn", collaborationSourceMessageId = sourceMessageId))
            assertFalse(malformedCursor.isSuccess)
            groups.update(group) { it.copy(members = it.members.filterNot { member -> member.id == "reader" },
                coordinatorId = "other") }
            assertEquals("rejected", store.lookup(access).getString("status"))
        } finally { groups.remove(group) }
    }
}
