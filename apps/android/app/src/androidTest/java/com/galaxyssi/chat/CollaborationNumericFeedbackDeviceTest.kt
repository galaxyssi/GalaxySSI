package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real encrypted workspace and both recall adapters; no model or external calls. */
@RunWith(AndroidJUnit4::class)
class CollaborationNumericFeedbackDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun cloudAndDesktopPhoneToolReturnIdenticalPagedCounterexamples() = fixture { group, reader ->
        val ref = publish(reader.copy(round = 1, nodeId = "baseline", personId = "author"), "baseline")
        val source = AgentTeamDispatchIds.sourceMessageId("numeric-feedback:$group")
        CollaborationEvidenceLedger(context).bind(source, reader)
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
            .subset { it.id == CollaborationRecallNativeTool.ID }
        val cloud = StringBuilder(); var cursor = ""; var pages = 0
        do {
            val input = CollaborationNumericFeedbackFixture.input(ref, cursor = cursor)
            val page = JSONObject(CollaborationCloudRecall.execute(context, reader, JSONObject(input)))
            assertEquals(page.toString(), "returned", page.getString("status"))
            val native = registry.invoke(CollaborationRecallNativeTool.ID, input,
                AgentNativeToolInvocationContext(conversationId = group, turnId = "turn", collaborationSourceMessageId = source))
            assertTrue(native.toJson(), native.isSuccess)
            assertEquals(page.getString("content"), native.output["content"])
            assertEquals(ref.getString("sha256"), page.getJSONObject("source_reference").getString("sha256"))
            assertEquals(119, page.getInt("matched_case_count"))
            cloud.append(page.getString("content"))
            cursor = if (page.isNull("next_cursor")) "" else page.getString("next_cursor")
            assertEquals(cursor.ifEmpty { null }, native.output["next_cursor"])
            assertTrue(++pages < 100)
        } while (cursor.isNotEmpty())
        assertTrue(pages > 1)
        val rows = JSONObject(cloud.toString()).getJSONArray("cases")
        assertEquals(119, rows.length())
        repeat(rows.length()) { i -> assertFalse(rows.getJSONObject(i).getJSONObject("observed").getBoolean("passed")) }
    }

    @Test fun reopenedWorkspaceRetainsFailedBaselineCorrectionAndRegressionDetails() = fixture { _, reader ->
        val first = publish(reader.copy(round = 1, nodeId = "baseline", personId = "author"), "baseline")
        val second = publish(reader.copy(round = 2, nodeId = "revision", personId = "peer"), "revision", first, """{"constant":1}""")
        val fullBefore = CollaborationResearchWorkspace(context).read(reader, first.getString("object_id"), 1)!!.toString()
        val partial = JSONObject(CollaborationCloudRecall.execute(context, reader, JSONObject(CollaborationNumericFeedbackFixture.input(second, "regressed"))))
        assertEquals("returned", partial.getString("status")); assertEquals(1, partial.getInt("matched_case_count"))
        assertEquals("case-60", JSONObject(partial.getString("content")).getJSONArray("cases").getJSONObject(0).getString("id"))
        val corrected = publish(reader.copy(round = 3, nodeId = "corrected", personId = "author"), "corrected", second, CollaborationNumericFeedbackFixture.SQUARE)
        val restored = CollaborationResearchWorkspace(context)
        assertEquals(fullBefore, restored.read(reader, first.getString("object_id"), 1)!!.toString())
        val host = restored.read(reader, corrected.getString("object_id"), 1)!!.getJSONObject("host_evolution")
        assertTrue(host.getJSONObject("evaluation").getBoolean("passed"))
        assertFalse(host.getBoolean("eligible_for_retention")); assertFalse(host.getBoolean("goal_accepted"))
        assertFalse(host.getBoolean("automatically_installed"))
        assertEquals(3, restored.browseEvolution(reader).revisions.size)
    }

    @Test fun changedDigestIsolationAndRevokedMembershipRejectRecall() = fixture { group, reader ->
        val ref = publish(reader.copy(round = 1, nodeId = "baseline", personId = "author"), "baseline")
        val input = JSONObject(CollaborationNumericFeedbackFixture.input(ref))
        assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, reader,
            JSONObject(input.toString()).put("sha256", "0".repeat(64)))).getString("status"))
        assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, reader.copy(round = 1), input)).getString("status"))
        assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, reader.copy(groupId = "$group-other"), input)).getString("status"))
        val registry = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
            .subset { it.id == CollaborationRecallNativeTool.ID }
        assertFalse(registry.invoke(CollaborationRecallNativeTool.ID, CollaborationNumericFeedbackFixture.input(ref),
            AgentNativeToolInvocationContext(conversationId = group, turnId = "turn")).isSuccess)
        CollaborationGroupStore(context).update(group) { it.copy(members = it.members.filterNot { member -> member.id == "peer" }) }
        assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, reader, input)).getString("status"))
    }

    @Test fun filtersDoNotLeakIntoOtherRecallModesAndInvalidRequestsAreExplicit() = fixture { _, reader ->
        val ref = publish(reader.copy(round = 1, nodeId = "baseline", personId = "author"), "baseline")
        val input = JSONObject(CollaborationNumericFeedbackFixture.input(ref))
        for (bad in listOf(JSONObject(input.toString()).put("case_filter", "unknown"), JSONObject(input.toString()).put("revision", 1.5),
            JSONObject(input.toString()).put("mode", "workspace"), JSONObject(input.toString()).put("offset", 0),
            JSONObject(input.toString()).put("group_id", "other"))) {
            assertEquals("failed", JSONObject(CollaborationCloudRecall.execute(context, reader, bad)).getString("status"))
        }
    }

    private fun publish(access: CollaborationWorkspaceAccess, id: String, previous: JSONObject? = null,
                        model: String = """{"constant":0}"""): JSONObject {
        val result = CollaborationResearchWorkspace(context).publish(access, CollaborationNumericFeedbackFixture.raw(id, model = model, previous = previous))
        assertEquals(result.toString(), "recorded", result.getString("status"))
        val ref = result.getJSONArray("revisions").getJSONObject(0)
        assertTrue(ref.toString().length < 6000)
        return ref
    }
    private fun fixture(block: (String, CollaborationWorkspaceAccess) -> Unit) {
        val group = "numeric-feedback-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("author", "peer").map { id -> CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "author") }
        try { block(group, CollaborationWorkspaceAccess(group, "run", "turn", 10, "reader", "peer")) }
        finally { groups.remove(group); assertNull(groups.load(group)) }
    }
}
