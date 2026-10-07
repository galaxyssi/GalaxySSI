package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real encrypted phone persistence; no provider invocation or existing conversation mutation. */
@RunWith(AndroidJUnit4::class)
class CollaborationMilestoneDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun raw(id: String) = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
        .put("summary", "Synthetic intermediate result").put("candidates", JSONArray()).put("findings", JSONArray())
        .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", "proposal").put("title", "Synthetic candidate")
            .put("body", JSONObject().put("content", "Original candidate for review")))).toString()
    private fun input(id: String) = JSONObject().put("mode", "publish").put("milestone_id", id).put("artifact", raw(id))

    @Test fun reopenRetryAndFinalReferenceKeepOriginalWithoutEndingAssignment() = fixture { access ->
        val first = JSONObject(CollaborationMilestoneTool.execute(context, access, input("m1")))
        assertTrue(first.toString(), first.getBoolean("success")); assertFalse(first.getBoolean("assignment_completed"))
        val reopened = CollaborationResearchWorkspace(context)
        assertNull(reopened.publicationCheckpoint(access))
        assertTrue(reopened.publicationRevisions(access, access.nodeId).isEmpty())
        assertEquals(first.toString(), CollaborationMilestoneTool.execute(context, access, input("m1")))
        val list = JSONObject(CollaborationMilestoneTool.execute(context, access, JSONObject().put("mode", "list")))
        assertEquals("m1", list.getJSONArray("milestones").getJSONObject(0).getString("milestone_id"))
        val final = JSONObject(raw("unused")).put("workspace", JSONArray()).put("milestones", JSONArray(listOf("m1")))
        val receipt = reopened.submitPublication(access, final.toString())
        assertEquals(first.getJSONArray("revisions").toString(), receipt.getJSONArray("revisions").toString())
        assertEquals(1, reopened.publicationRevisions(access, access.nodeId).size)
    }

    @Test fun userPauseAndRevocationBlockNewPublicationsAndIndependentReaderStaysIsolated() = fixture { access ->
        val control = AgentTeamDurableControl(context)
        control.set(access.runId, AgentTeamUserControl.PAUSE)
        val paused = JSONObject(CollaborationMilestoneTool.execute(context, access, input("m1")))
        assertFalse(paused.getBoolean("success"))
        assertTrue(CollaborationResearchWorkspace(context).browse(access).revisions.isEmpty())
        control.set(access.runId, AgentTeamUserControl.RUN)
        val result = JSONObject(CollaborationMilestoneTool.execute(context, access, input("m1")))
        assertTrue(result.getBoolean("success"))
        val ref = result.getJSONArray("revisions").getJSONObject(0)
        val peer = access.copy(nodeId = "peer-node", personId = "peer")
        assertNull(CollaborationResearchWorkspace(context).read(peer, ref.getString("object_id"), 1))
        assertNotNull(CollaborationResearchWorkspace(context).read(peer.copy(dependencyNodes = setOf(access.nodeId)), ref.getString("object_id"), 1))
        CollaborationGroupStore(context).update(access.groupId) {
            it.copy(members = it.members.filterNot { member -> member.id == access.personId }, coordinatorId = "peer")
        }
        assertFalse(JSONObject(CollaborationMilestoneTool.execute(context, access, input("m2"))).getBoolean("success"))
    }

    @Test fun failedDraftCanBeRepairedButSuccessfulMilestoneCannotBeReplaced() = fixture { access ->
        val bad = input("m1").put("artifact", "not JSON")
        val failed = JSONObject(CollaborationMilestoneTool.execute(context, access, bad))
        assertFalse(failed.getBoolean("success")); assertTrue(failed.getString("reason").isNotBlank())
        assertTrue(JSONObject(CollaborationMilestoneTool.execute(context, access, input("m1"))).getBoolean("success"))
        val replacement = input("m1").put("artifact", raw("replacement"))
        assertFalse(JSONObject(CollaborationMilestoneTool.execute(context, access, replacement)).getBoolean("success"))
        assertEquals(1, CollaborationResearchWorkspace(context).browse(access).revisions.size)
    }

    private fun fixture(block: (CollaborationWorkspaceAccess) -> Unit) {
        val id = "milestone-test-${UUID.randomUUID()}"
        val access = CollaborationWorkspaceAccess(id, id, "turn", 1, "node", "author")
        val groups = CollaborationGroupStore(context)
        groups.update(id) { it.copy(members = listOf("author", "peer").map { person -> CollaborationMember(person, person, "fixture", "Fixture") }, coordinatorId = "author") }
        CollaborationResearchWorkspace(context).enrollPublication(access, CollaborationResearchStage.EXPLORE)
        try { block(access) }
        finally {
            CollaborationResearchWorkspace(context).removeGroup(id)
            groups.remove(id)
            AgentTeamDurableControl(context).remove(id)
        }
    }
}
