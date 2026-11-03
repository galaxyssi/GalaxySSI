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

/** Synthetic evidence only: no model, chat, external service or device-control calls. */
@RunWith(AndroidJUnit4::class)
class CollaborationPeerUpdatesDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun group(id: String) = CollaborationGroupStore(context).update(id) {
        it.copy(members = listOf("author", "peer", "independent").map { name -> CollaborationMember(name, name, "fixture", "Fixture") }, coordinatorId = "author")
    }
    private fun publish(w: CollaborationResearchWorkspace, author: CollaborationWorkspaceAccess, evidence: JSONObject? = null): JSONObject {
        w.enrollPublication(author, CollaborationResearchStage.EXPLORE)
        val item = JSONObject().put("id", "alternative").put("kind", "proposal").put("title", "Testable alternative")
            .put("body", JSONObject().put("content", "Compare a synthetic alternative against the baseline"))
        evidence?.let { item.put("observations", JSONArray().put(it)) }
        val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Alternative ready")
            .put("coordination", JSONObject().put("mode", "record_only"))
            .put("requests", JSONArray().put(JSONObject().put("to", JSONArray(listOf("peer", "independent"))).put("question", "Check this alternative")))
            .put("workspace", JSONArray().put(item)).toString()
        val result = w.publishMilestone(author, "alternative", raw)
        assertEquals(result.toString(), "recorded", result.getString("status"))
        return result.getJSONArray("revisions").getJSONObject(0)
    }

    @Test fun cloudAndNativeWorkersReadDuringExecutionAndPauseDoesNotEraseEvidence() {
        val id = "peer-updates-${UUID.randomUUID()}"; group(id)
        val store = CollaborationAdaptivePilotMilestones.executionStore(context, AgentEncryptedDatabase(context, id))
        val w = CollaborationResearchWorkspace(context); val run = "$id-run"
        try {
            val members = listOf("author", "peer", "independent").map { name ->
                AgentTeamMember("fixture", if (name == "author") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                    instanceId = "$name-work", objective = "Synthetic evidence exchange", context = mapOf(
                        "collaboration_group_id" to id, CollaborationResearchWorkflow.PERSON to name,
                        CollaborationGoalLoop.WORK_ID to "$name-task", CollaborationResearchWorkflow.STAGE to "EXECUTE",
                        CollaborationGoalLoop.ROSTER to "false", CollaborationWorkGraph.INDEPENDENT to (name == "independent").toString(),
                        CollaborationPeerExchangePolicy.CONTEXT to JSONArray(if (name == "peer") listOf("author") else emptyList<String>()).toString()))
            }
            store.create(AgentTeamDefinition("fixture", "fixture", members, primaryInstanceId = "author-work"),
                AgentRunRequest(id, "turn", "task", runId = run, goal = "Synthetic fixture only", context = mapOf(CollaborationGoalLoop.ROUND to "1")))
            val author = CollaborationWorkspaceAccess(id, run, "turn", 1, "author-work", "author")
            val peer = author.copy(nodeId = "peer-work", personId = "peer")
            val independent = author.copy(nodeId = "independent-work", personId = "independent")
            val ledger = CollaborationEvidenceLedger(context)
            val source = AgentTeamDispatchIds.sourceMessageId("$id:peer")
            ledger.bind(source, peer); ledger.bind(source + 1, independent)
            val evidence = ledger.record(author, "fixture", "fixture", "{}", "{\"value\":7}", 1, 2)
            val input = JSONObject().put("mode", CollaborationPeerUpdates.MODE)
            fun call(access: CollaborationWorkspaceAccess, input: JSONObject) = JSONObject(CollaborationCloudRecall.execute(context, access, input))
            assertTrue(call(peer, input).getBoolean("caught_up_at_read"))
            val ref = publish(w, author, evidence)
            val read = JSONObject().put("mode", "workspace").put("object_id", ref.getString("object_id")).put("revision", 1)
            assertEquals("failed", call(peer, read).getString("status"))
            val page = call(peer, input)
            assertEquals(page.toString(), "returned", page.getString("status"))
            assertEquals(1, page.getJSONArray("milestones").length())
            assertEquals(listOf("author"), page.getJSONArray("allowed_peers").let { (0 until it.length()).map(it::getString) })
            assertTrue(call(independent, input).getBoolean("caught_up_at_read"))
            assertEquals("failed", call(independent, read).getString("status"))
            assertEquals("returned", call(peer, read).getString("status"))
            val native = AgentPhoneNativeToolCatalog.defaultRegistry(context, { ScreenContext(foregroundApp = "", pageTitle = "") })
                .subset { it.id == CollaborationRecallNativeTool.ID }
            val replay = native.invoke(CollaborationRecallNativeTool.ID, mapOf("mode" to CollaborationPeerUpdates.MODE),
                AgentNativeToolInvocationContext(conversationId = id, turnId = "turn", collaborationSourceMessageId = source))
            assertTrue(replay.toJson(), replay.isSuccess)
            assertEquals(page.getString("next_cursor"), replay.output["next_cursor"])
            assertEquals(peer, ledger.binding(source, id, "turn"))
            assertTrue(AgentTeamExecutionLocations(context).state(peer).first.completed.isEmpty())
            assertEquals(3, AgentTeamExecutionLocations(context).state(peer).first.definition.members.size)
            assertTrue(w.publicationRevisions(author, author.nodeId).isEmpty())
            val evidenceInput = JSONObject().put("mode", "evidence").put("evidence_id", evidence.getString("evidence_id")).put("sha256", evidence.getString("sha256"))
            val original = JSONObject(CollaborationCloudRecall.execute(context, peer, evidenceInput, recordCoverage = false))
            assertEquals("returned", original.getString("status"))
            assertFalse(original.getJSONObject(CollaborationEvidenceReadCoverage.FIELD).getBoolean("complete"))
            assertTrue(ledger.confirmPage(CollaborationPeerUpdates.combinedReadAccess(context, peer), evidence.getString("evidence_id"),
                evidence.getString("sha256"), 0, MqttImmutableContent.sha256(original.getString("content")))!!.getBoolean("complete"))
            AgentTeamDurableControl(context).set(run, AgentTeamUserControl.PAUSE)
            for (request in listOf(input, read, evidenceInput)) assertEquals("failed", call(peer, request).getString("status"))
            AgentTeamDurableControl(context).set(run, AgentTeamUserControl.RUN)
            assertEquals(page.toString(), call(peer, input).toString())
            assertEquals("returned", call(peer, read).getString("status"))
            w.enrollPublication(peer, CollaborationResearchStage.EXECUTE)
            val final = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Alternative compared")
                .put("workspace", JSONArray().put(JSONObject().put("id", "comparison").put("kind", "decision").put("title", "Comparison")
                    .put("parents", JSONArray().put(ref)).put("observations", JSONArray().put(evidence))
                    .put("body", JSONObject().put("content", "Synthetic result, no scientific claim"))))
            assertEquals("recorded", CollaborationResearchWorkspace(context).submitPublication(peer, final.toString()).getString("status"))
            AgentTeamDurableControl(context).set(run, AgentTeamUserControl.STOP)
            assertEquals("failed", call(peer, input).getString("status"))
        } finally {
            AgentTeamDurableControl(context).set(run, AgentTeamUserControl.STOP); store.remove(run)
            CollaborationGroupStore(context).remove(id); AgentTeamDurableControl(context).remove(run)
        }
    }

    @Test fun encryptedPeerPagesAndGrantsSurviveSeparateProcessRestart() {
        val phase = InstrumentationRegistry.getArguments().getString("phase", "all")
        val id = "peer-updates-restart-fixture"; val marker = AgentEncryptedDatabase(context, id)
        val peer = CollaborationWorkspaceAccess(id, "fixture-run", "turn", 1, "peer-work", "peer")
        if (phase in setOf("all", "seed")) {
            CollaborationGroupStore(context).remove(id); group(id)
            val w = CollaborationResearchWorkspace(context)
            val ref = publish(w, peer.copy(nodeId = "author-work", personId = "author"))
            val page = w.peerUpdates(peer, "", setOf("author-work"))
            marker.writeString("page", page.toString()); marker.writeString("ref", ref.toString())
        }
        if (phase in setOf("all", "recover")) {
            val w = CollaborationResearchWorkspace(context)
            assertEquals(marker.readString("page", ""), w.peerUpdates(peer, "", emptySet()).toString())
            val ref = JSONObject(marker.readString("ref", ""))
            assertNotNull(w.read(w.peerReadAccess(peer), ref.getString("object_id"), 1))
            assertNull(w.read(peer, ref.getString("object_id"), 1))
        }
        if (phase in setOf("all", "cleanup")) { CollaborationGroupStore(context).remove(id); marker.clear() }
        InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply { putString("fixture_pid", android.os.Process.myPid().toString()) })
    }
}
