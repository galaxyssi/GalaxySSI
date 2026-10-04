package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Synthetic saved replies only. No provider calls, original research, or external side effects. */
@RunWith(AndroidJUnit4::class)
class CollaborationResultFinalizerDeviceTest {
    @Test fun lateArtifactAndReceiptSurviveReopeningWithoutRedispatch() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "delivery-fixture-${UUID.randomUUID()}"
        val run = "run-$group"
        val store = EncryptedAgentTeamExecutionStore(context)
        val workspace = CollaborationResearchWorkspace(context)
        try {
            CollaborationGroupStore(context).update(group) { it.copy(members = listOf(
                CollaborationMember("person", "Fixture", "fixture", "Local")), coordinatorId = "person") }
            val member = AgentTeamMember("fixture", AgentDeliveryMode.OBSERVE, instanceId = "node", context = mapOf(
                "collaboration_group_id" to group, "collaboration_name" to "Fixture",
                CollaborationResearchWorkflow.PERSON to "person", CollaborationResearchWorkflow.STAGE to "EXECUTE"))
            val request = AgentRunRequest(group, "turn", "task-$group", runId = run, goal = "Local delivery fixture")
            store.create(AgentTeamDefinition("team-$group", "fixture", listOf(member), primaryInstanceId = "node"), request)
            store.markInterrupted(run)
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
                .put("summary", "Partial fixture, not accepted science").put("candidates", JSONArray()).put("findings", JSONArray())
                .put("workspace", JSONArray().put(JSONObject().put("id", "report").put("kind", "artifact")
                    .put("title", "Local saved report").put("body", JSONObject().put("content", "Full fixture evidence ".repeat(2000))))).toString()
            val managed = AgentManagedResponseRecord(stableAgentTeamMemberRunId(run, "node"), run, "fixture",
                AgentDeliveryMode.OBSERVE, 9191L, "fixture", conversationId = group, turnId = "turn",
                response = AgentConnectorResponse(9191L, "fixture", raw))
            val execution = requireNotNull(CollaborationLateResult.execution(store.deliveryCheckpoint(run)!!, managed))
            val access = CollaborationWorkspaceAccess.from(execution)
            workspace.enrollPublication(access, CollaborationResearchStage.EXECUTE)
            val output = CollaborationResultFinalizer(context).finish(execution, AgentSubagentOutput(raw))
            assertEquals("recorded", output.collaborationDelivery!!.status)
            assertTrue(store.applyLateResponse(managed, output))
            val reopened = EncryptedAgentTeamExecutionStore(context).deliveryCheckpoint(run)!!.completed.getValue("node")
            assertEquals(output.collaborationDelivery, reopened.collaborationDelivery)
            assertFalse(reopened.outputTruncated)
            assertNull(reopened.collaborationAcceptance)
            val archived = CollaborationResearchArchive(context, group).read(reopened.collaborationDelivery!!.archiveRecordId)!!
            assertEquals(raw, JSONObject(archived.content).getString("raw_output"))
            assertTrue(store.applyLateResponse(managed, CollaborationResultFinalizer(context).finish(execution, AgentSubagentOutput(raw))))
            assertEquals(1, CollaborationResearchWorkspace(context).browse(access).revisions.size)
        } finally {
            store.remove(run)
            CollaborationGroupStore(context).remove(group)
        }
    }
}
