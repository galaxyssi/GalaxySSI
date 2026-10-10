package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

/** Local fixtures only: no model, contact, remote recipient or physical operation. */
@RunWith(AndroidJUnit4::class)
class CollaborationInterimDeliveryDeviceTest {
    @Test fun reviewedContentPersistsOnceAndItsReceiptSurvivesReopeningWithoutCompletingTheGoal() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val transcript = AgentTranscriptStore(context)
        val group = transcript.createAgentConversation("Interim delivery fixture").id
        val run = "interim-fixture-${UUID.randomUUID()}"
        val access = CollaborationWorkspaceAccess(group, run, "fixture-turn", 3, "lead", "lead")
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("lead", "reviewer").map { name ->
            CollaborationMember(name, name, "fixture", "Fixture") }, coordinatorId = "lead") }
        try {
            val workspace = CollaborationResearchWorkspace(context)
            fun publish(who: CollaborationWorkspaceAccess, id: String, kind: String, body: JSONObject,
                        parents: JSONArray = JSONArray()): JSONObject = workspace.publish(who,
                JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture")
                    .put("workspace", JSONArray().put(JSONObject().put("id", id).put("kind", kind).put("title", id)
                        .put("body", body).put("parents", parents))).toString()).getJSONArray("revisions").getJSONObject(0)
            val criterion = JSONObject().put("id", "report").put("requirement", "Deliver the report and await acknowledgement")
                .put("status", "open").put("verification", "documentary").put("evidence", JSONArray())
            val prior = JSONArray().put(JSONObject(criterion.toString())).toString()
            val target = publish(access.copy(round = 1, nodeId = "author"), "report", "artifact",
                JSONObject().put("content", "Fixture report with explicit limitations."))
            val review = publish(access.copy(round = 2, personId = "reviewer", nodeId = "review"), "review",
                CollaborationReviewContract.KIND, JSONObject().put(CollaborationReviewContract.KIND, JSONObject()
                    .put("criterion_id", "report").put("requirement", criterion.getString("requirement")).put("target", target)
                    .put("verdict", "not_tested").put("rationale", "Content reviewed; user acknowledgement is not observed")
                    .put("unresolved", JSONArray().put("User acknowledgement remains pending"))
                    .put(CollaborationInterimDelivery.READINESS, JSONObject().put("verdict", "supported")
                        .put("rationale", "The fixture text is ready to present").put("unresolved", JSONArray()))), JSONArray().put(target))
            criterion.put("delivery", target).put("review", review)
            val raw = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Interim content; goal remains open")
                .put("decision", "continue").put("criteria", JSONArray().put(criterion)).put("work", JSONArray()).put("blockers", JSONArray())
                .put(CollaborationInterimDelivery.FIELD, JSONObject().put("criterion_id", "report").put("target", target))
                .put(CollaborationInterimDelivery.RECEIPT, JSONObject().put("status", "forged")).toString()
            val member = AgentTeamMember("fixture", AgentDeliveryMode.RESPOND, instanceId = "lead", context = mapOf(
                "collaboration_group_id" to group, "collaboration_name" to "Turing", CollaborationResearchWorkflow.PERSON to "lead",
                CollaborationResearchWorkflow.STAGE to "DELIVER", CollaborationGoalLoop.ENABLED to "1"))
            val execution = AgentTeamMemberExecutionContext(member, AgentRunRequest(group, access.turnId, "fixture-task",
                runId = "$run-child", parentRunId = run, goal = criterion.getString("requirement"),
                context = mapOf(CollaborationGoalLoop.ROUND to "3", CollaborationGoalLoop.CRITERIA to prior)),
                AgentSubagentContextHandoff("", emptyList(), 0, 0, false), 1, AgentSubagentProvenance(source = "fixture"))
            AgentTeamDurableControl(context).set(run, AgentTeamUserControl.PAUSE)
            val paused = CollaborationResultFinalizer(context).finish(execution, AgentSubagentOutput(raw))
            assertEquals("not_confirmed", JSONObject(paused.content).getJSONObject(CollaborationInterimDelivery.RECEIPT).getString("status"))
            assertTrue(transcript.list(group).isEmpty())
            AgentTeamDurableControl(context).set(run, AgentTeamUserControl.RUN)
            val first = CollaborationResultFinalizer(context).finish(execution, AgentSubagentOutput(raw))
            val receipt = JSONObject(first.content).getJSONObject(CollaborationInterimDelivery.RECEIPT)
            assertEquals("conversation_persisted", receipt.getString("status"))
            assertEquals("not_observed", receipt.getString("user_read"))
            assertNull(first.collaborationAcceptance)
            val replay = CollaborationResultFinalizer(context).finish(execution, AgentSubagentOutput(raw))
            assertEquals(receipt.toString(), JSONObject(replay.content).getJSONObject(CollaborationInterimDelivery.RECEIPT).toString())
            val entry = AgentTranscriptStore(context).list(group).single()
            assertEquals(AgentTranscriptRole.PROCESS, entry.role)
            assertEquals("Fixture report with explicit limitations.", entry.text)
            assertEquals("continue", CollaborationGoalLoop.disposition(first.content, prior, acceptanceVerified = true))
            val evidence = receipt.getJSONObject("observation")
            val reader = access.copy(round = 4, nodeId = "later-review", personId = "reviewer")
            val original = CollaborationEvidenceLedger(context).read(reader, evidence.getString("evidence_id"), evidence.getString("sha256"))!!
            assertEquals(CollaborationInterimDelivery.TOOL, original.getString("tool"))
            assertEquals(target.getString("sha256"), JSONObject(original.getString("output_json")).getJSONObject("target").getString("sha256"))
        } finally {
            AgentTeamDurableControl(context).remove(run)
            groups.remove(group)
            transcript.deleteConversation(group)
        }
    }
}
