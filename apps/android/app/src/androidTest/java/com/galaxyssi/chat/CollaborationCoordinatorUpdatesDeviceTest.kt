package com.galaxyssi.chat

import android.os.Bundle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local fixtures only; no model, contact, broker or device-control invocation. */
@RunWith(AndroidJUnit4::class)
class CollaborationCoordinatorUpdatesDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun group(id: String) = CollaborationGroupStore(context).update(id) {
        it.copy(members = listOf("lead", "author", "peer").map { person ->
            CollaborationMember(person, person, "fixture", "Fixture") }, coordinatorId = "lead")
    }
    private fun publish(workspace: CollaborationResearchWorkspace, access: CollaborationWorkspaceAccess,
                        evidence: JSONObject? = null, ref: JSONObject? = null, name: String = "v1"): JSONObject {
        workspace.enrollPublication(access, CollaborationResearchStage.EXPLORE)
        val item = JSONObject().put("id", "frozen-data").put("kind", "artifact").put("title", name)
            .put("body", JSONObject().put("content", "Frozen local fixture $name"))
        evidence?.let { item.put("observations", JSONArray().put(it)) }
        ref?.let { item.put("object_id", it.getString("object_id")).put("base_revision", it.getInt("revision")) }
        val result = workspace.publishMilestone(access, name, JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", name).put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(item)).toString())
        assertEquals(result.toString(), "recorded", result.getString("status"))
        return result.getJSONArray("revisions").getJSONObject(0)
    }

    @Test fun cloudNativeAndEvidenceConfirmationSeeLateVersionsButKeepOriginalBinding() {
        val id = "coordinator-updates-${UUID.randomUUID()}"
        group(id)
        val store = EncryptedAgentTeamExecutionStore(context)
        val workspace = CollaborationResearchWorkspace(context)
        val run = "$id-run"
        try {
            val people = listOf("lead", "author", "peer").map { person -> AgentTeamMember("fixture", AgentDeliveryMode.IGNORE,
                instanceId = person, context = mapOf("collaboration_group_id" to id, CollaborationResearchWorkflow.PERSON to person,
                    CollaborationGoalLoop.ROSTER to "true", CollaborationLiveGraph.ENABLED to "1")) }
            val planner = people[0].copy(instanceId = "planner", deliveryMode = AgentDeliveryMode.OBSERVE,
                context = people[0].context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationLiveGraph.PLANNER to "1",
                    CollaborationResearchWorkflow.STAGE to "BRIEF"))
            val producer = people[1].copy(instanceId = "producer", deliveryMode = AgentDeliveryMode.OBSERVE,
                context = people[1].context + mapOf(CollaborationGoalLoop.ROSTER to "false", CollaborationGoalLoop.WORK_ID to "produce",
                    CollaborationResearchWorkflow.STAGE to "EXPLORE"))
            val final = people[0].copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
                dependsOnAgentIds = setOf("planner", "producer"), context = people[0].context + (CollaborationGoalLoop.ROSTER to "false"))
            store.create(AgentTeamDefinition("fixture", "fixture", people + planner + producer + final, primaryInstanceId = "final"),
                AgentRunRequest(id, "turn", "task", runId = run, goal = "Synthetic fixture only", createdAtMillis = 1,
                    context = mapOf(CollaborationGoalLoop.ROUND to "1")))
            val access = CollaborationWorkspaceAccess(id, run, "turn", 1, "planner", "lead")
            val author = access.copy(nodeId = "producer", personId = "author")
            val ledger = CollaborationEvidenceLedger(context)
            val source = AgentTeamDispatchIds.sourceMessageId("$id:planner")
            ledger.bind(source, access)
            val goals = CollaborationGoalContractStore(context)
            val goal = goals.publish(access, "Original immutable goal", "[]")
            goals.bind(access, goal.getString("snapshot_id"))
            val originalGoal = goals.read(access).toString()
            val input = JSONObject().put("mode", CollaborationCoordinatorUpdates.MODE)
            fun call(access: CollaborationWorkspaceAccess, input: JSONObject) = JSONObject(CollaborationCloudRecall.execute(context, access, input))
            val empty = call(access, input)
            assertEquals(empty.toString(), "returned", empty.getString("status"))
            assertTrue(empty.getBoolean("caught_up_at_read"))
            val evidence = ledger.record(author, "fixture-command", "fixture", "{}", "{\"status\":\"ok\",\"value\":7}", 1, 2)
            val ref = publish(workspace, author, evidence)
            val read = JSONObject().put("mode", "workspace").put("object_id", ref.getString("object_id")).put("revision", 1)
            assertEquals("failed", call(access, read).getString("status"))
            val updates = call(access, input)
            assertEquals("returned", updates.getString("status"))
            assertEquals(1, updates.getJSONArray("milestones").length())
            val native = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
                .subset { it.id == CollaborationRecallNativeTool.ID }
            val replay = native.invoke(CollaborationRecallNativeTool.ID, mapOf("mode" to CollaborationCoordinatorUpdates.MODE),
                AgentNativeToolInvocationContext(conversationId = id, turnId = "turn", collaborationSourceMessageId = source))
            assertTrue(replay.toJson(), replay.isSuccess)
            assertEquals(updates.getString("next_cursor"), replay.output["next_cursor"])
            assertEquals(updates.toString(), call(access, input).toString())
            assertEquals("returned", call(access, read).getString("status"))
            val recalledGoal = call(access, JSONObject().put("mode", "goal_contract"))
            assertEquals("returned", recalledGoal.getString("status"))
            assertEquals(JSONObject(originalGoal).getString("page_sha256"), recalledGoal.getString("page_sha256"))
            assertEquals(access, ledger.binding(source, id, "turn"))
            val enriched = CollaborationCoordinatorUpdates.readAccess(context, access)
            assertFalse(ledger.authorizes(enriched))
            val evidenceInput = JSONObject().put("mode", "evidence").put("evidence_id", evidence.getString("evidence_id"))
                .put("sha256", evidence.getString("sha256"))
            val served = JSONObject(CollaborationCloudRecall.execute(context, access, evidenceInput, recordCoverage = false))
            assertEquals("returned", served.getString("status"))
            assertFalse(served.getJSONObject(CollaborationEvidenceReadCoverage.FIELD).getBoolean("complete"))
            val confirmation = ledger.confirmPage(enriched, evidence.getString("evidence_id"), evidence.getString("sha256"), 0,
                MqttImmutableContent.sha256(served.getString("content")))!!
            assertTrue(confirmation.getBoolean("complete"))
            publish(workspace, author, ref = ref, name = "v2")
            assertEquals("failed", call(access, JSONObject(read.toString()).put("revision", 2)).getString("status"))
            assertEquals(updates.toString(), call(access, input).toString())
            assertEquals(1, call(access, JSONObject(input.toString()).put("cursor", updates.getString("next_cursor")))
                .getJSONArray("milestones").length())
            assertEquals("returned", call(access, JSONObject(read.toString()).put("revision", 2)).getString("status"))
            ledger.bind(source + 1, author)
            assertEquals("failed", call(author, input).getString("status"))
            val isolated = access.copy(nodeId = "independent", personId = "peer")
            assertEquals("failed", call(isolated, read).getString("status"))
            assertEquals("failed", call(isolated, input).getString("status"))
            AgentTeamDurableControl(context).set(run, AgentTeamUserControl.PAUSE)
            assertEquals("failed", call(access, input).getString("status"))
            assertEquals("failed", call(access, read).getString("status"))
            AgentTeamDurableControl(context).set(run, AgentTeamUserControl.RUN)
            assertEquals("returned", call(access, read).getString("status"))
            assertEquals(originalGoal, CollaborationGoalContractStore(context).read(access).toString())
            assertEquals(access, ledger.binding(source, id, "turn"))
        } finally {
            AgentTeamDurableControl(context).set(run, AgentTeamUserControl.STOP)
            store.remove(run)
            CollaborationGroupStore(context).remove(id)
            AgentTeamDurableControl(context).remove(run)
        }
    }

    @Test fun encryptedJournalSurvivesProcessRestart() {
        val phase = InstrumentationRegistry.getArguments().getString("phase", "all")
        val id = "coordinator-updates-restart-fixture"
        val marker = AgentEncryptedDatabase(context, id)
        val access = CollaborationWorkspaceAccess(id, "fixture-run", "turn", 1, "planner", "lead")
        if (phase in setOf("all", "seed")) {
            CollaborationGroupStore(context).remove(id); group(id)
            val workspace = CollaborationResearchWorkspace(context)
            val ref = publish(workspace, access.copy(nodeId = "producer", personId = "author"))
            val page = workspace.coordinatorUpdates(access, "", emptySet(), setOf("producer"))
            marker.writeString("page", page.toString()); marker.writeString("ref", ref.toString())
        }
        if (phase in setOf("all", "recover")) {
            val workspace = CollaborationResearchWorkspace(context)
            assertEquals(marker.readString("page", ""), workspace.coordinatorUpdates(access, "", emptySet(), emptySet()).toString())
            val ref = JSONObject(marker.readString("ref", ""))
            val enriched = CollaborationCoordinatorUpdates.withGrants(access, workspace.coordinatorOffered(access))
            assertNotNull(workspace.read(enriched, ref.getString("object_id"), 1))
        }
        if (phase in setOf("all", "cleanup")) { CollaborationGroupStore(context).remove(id); marker.clear() }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply { putString("fixture_pid", android.os.Process.myPid().toString()) })
    }
}
