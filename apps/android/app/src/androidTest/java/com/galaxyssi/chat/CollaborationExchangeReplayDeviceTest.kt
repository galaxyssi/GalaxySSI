package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local fault injection only: no model, broker, contacts or device-control tools. */
@RunWith(AndroidJUnit4::class)
class CollaborationExchangeReplayDeviceTest {
    @Test fun lostMilestoneAndOriginalPageRepliesPreserveVersionsAndRequireConfirmation() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "exchange-replay-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("author", "peer").map { id ->
            CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "author") }
        try {
            val author = CollaborationWorkspaceAccess(group, "run", "turn", 1, "producer", "author")
            val peer = author.copy(nodeId = "review", personId = "peer", dependencyNodes = setOf("producer"))
            val workspace = CollaborationResearchWorkspace(context)
            val ledger = CollaborationEvidenceLedger(context)
            workspace.enrollPublication(author, CollaborationResearchStage.EXECUTE)
            val original = ledger.record(author, "synthetic-observation", "fixture.measure", "{}",
                "{\"fixture_value\":1}", 1, 2, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            val artifact = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Fixture only")
                .put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                    .put("id", "fixture-method").put("kind", "artifact").put("title", "Synthetic fixture method")
                    .put("body", JSONObject().put("content", "Fixture executable description, not a real experiment"))
                    .put("observations", JSONArray().put(original)))).toString()
            val publication = request("publication", "publish", JSONObject().put("mode", "publish")
                .put("milestone_id", "v1").put("artifact", artifact))
            val replies = CollaborationExchangeReplay(clock = { 0 })
            val first = replies.acquire("fixture-desktop", publication, 0).lease!!
            val committed = CollaborationMilestoneTool.execute(workspace, author, publication.getJSONObject("arguments")) {}
            assertTrue(committed.toString(), committed.getBoolean("success"))
            replies.remember(first, author, committed)
            replies.release(first) // Simulate a lost response after the durable commit.
            val repeat = replies.acquire("fixture-desktop", publication, 0).lease!!
            assertTrue(repeat.replay)
            assertEquals(committed.toString(), replies.read(repeat, author)!!.toString())
            assertNull(replies.read(repeat, peer))
            replies.release(repeat)
            val reopened = CollaborationResearchWorkspace(context)
            assertEquals(1, reopened.milestones(author).getJSONArray("milestones").length())
            assertEquals(committed.toString(), CollaborationMilestoneTool.execute(reopened, author,
                publication.getJSONObject("arguments")) {}.toString())

            val read = request("original-page", "read", JSONObject().put("mode", "evidence")
                .put("evidence_id", original.getString("evidence_id")).put("sha256", original.getString("sha256")))
            val delivery = CollaborationRecallDelivery()
            var reads = 0
            fun page(): JSONObject {
                val lease = replies.acquire("fixture-desktop", read, 0).lease!!
                return try {
                    if (lease.replay) requireNotNull(replies.read(lease, peer)) else {
                        reads++
                        val value = JSONObject(CollaborationCloudRecall.execute(context, peer,
                            read.getJSONObject("arguments"), recordCoverage = false)).put("success", true)
                        delivery.prepare(read, peer, value).also { replies.remember(lease, peer, it) }
                    }
                } finally { replies.release(lease) }
            }
            val dropped = page()
            val received = page()
            assertEquals(1, reads)
            assertEquals(dropped.getJSONObject("delivery").toString(), received.getJSONObject("delivery").toString())
            fun coverage() = CollaborationEvidenceLedger(context).references(peer, JSONArray().put(original))
                .getJSONObject(0).getJSONObject(CollaborationEvidenceReadCoverage.FIELD)
            assertEquals(0, coverage().getInt("covered_characters"))
            val confirm = JSONObject(read.toString()).put("request_id", "confirm-page").put("phase", "confirm")
                .put("delivery", received.getJSONObject("delivery"))
            val acknowledged = delivery.confirm(confirm, peer) { args, hash ->
                CollaborationEvidenceLedger(context).confirmPage(peer, args.getString("evidence_id"),
                    args.getString("sha256"), args.optInt("offset", 0), hash)
            }
            assertTrue(acknowledged.toString(), acknowledged.getBoolean("success"))
            assertTrue(coverage().getBoolean("complete"))
        } finally {
            CollaborationResearchWorkspace.remove(context, group)
            CollaborationEvidenceLedger.remove(context, group)
            groups.remove(group)
        }
    }

    private fun request(id: String, phase: String, arguments: JSONObject) = JSONObject().apply {
        AgentResultRecoveryClient.FIELDS.forEach { put(it, if (it == "agent_id") "codex" else it) }
        put("execution_generation", 1).put("request_id", id).put("expires_at", 20_000)
        put("type", if (phase == "publish") AndroidCollaborationRemoteMilestone.REQUEST else CollaborationRemoteRecallProtocol.REQUEST)
        put("contract", if (phase == "publish") AndroidCollaborationRemoteMilestone.CONTRACT else CollaborationRemoteRecallProtocol.CONTRACT)
        put("phase", phase).put("arguments", arguments)
    }
}
