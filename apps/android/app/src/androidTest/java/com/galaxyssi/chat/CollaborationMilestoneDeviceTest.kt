package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
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

    @Test fun durablePublicationWakesCoordinatorAndPeerWhileOriginalWorkerStillRuns() = dispatchScenario(false)

    @Test fun reopenedGraphDiscoversPublicationWhoseWakeWasMissed() = dispatchScenario(true)

    @Test fun saturatedWorkersDoNotBlockDurableMilestoneCoordination() = dispatchScenario(false, saturated = true)

    private fun dispatchScenario(publishBeforeStart: Boolean, saturated: Boolean = false) = fixture { author -> runBlocking {
        withTimeout(45_000) {
            val db = AgentEncryptedDatabase(context, "milestone-dispatch-${UUID.randomUUID()}")
            try {
                fun store() = CollaborationAdaptivePilotMilestones.executionStore(context, db)
                val people = listOf("author", "peer").map { person -> AgentTeamMember("fixture", AgentDeliveryMode.IGNORE,
                    instanceId = person, context = mapOf("collaboration_group_id" to author.groupId,
                        CollaborationResearchWorkflow.PERSON to person, CollaborationGoalLoop.ROSTER to "true",
                        CollaborationLiveGraph.ENABLED to "1", CollaborationResearchWorkflow.STAGE to "DELIVER")) }
                val producer = people[0].copy(instanceId = author.nodeId, deliveryMode = AgentDeliveryMode.OBSERVE,
                    objective = "Synthetic candidate", context = people[0].context + mapOf(CollaborationGoalLoop.ROSTER to "false",
                        CollaborationResearchWorkflow.STAGE to "EXECUTE", CollaborationGoalLoop.WORK_ID to "original"))
                val final = people[1].copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
                    dependsOnAgentIds = setOf(author.nodeId), context = people[1].context + (CollaborationGoalLoop.ROSTER to "false"))
                val extras = if (saturated) listOf("second-worker", "queued-worker").map { id -> producer.copy(instanceId = id,
                    context = producer.context + (CollaborationGoalLoop.WORK_ID to id)) } else emptyList()
                val definition = AgentTeamDefinition(author.groupId, "fixture", people + producer + extras + final, primaryInstanceId = "final")
                val request = AgentRunRequest(author.groupId, author.turnId, "fixture", runId = author.runId,
                    goal = "Synthetic interim version review", context = mapOf(CollaborationGoalLoop.ROUND to "1"))
                val started = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
                val secondStarted = CompletableDeferred<Unit>(); val releaseSecond = CompletableDeferred<Unit>()
                val coordinated = CompletableDeferred<Unit>(); val queuedStarted = CompletableDeferred<Unit>()
                val reviewed = CompletableDeferred<CollaborationWorkspaceAccess>(); val releaseReview = CompletableDeferred<Unit>()
                val finalStarted = CompletableDeferred<Unit>(); val calls = CopyOnWriteArrayList<String>()
                var phase = "producer startup"
                fun publish() = JSONObject(CollaborationMilestoneTool.execute(context, author, input("early"))).also {
                    assertTrue(it.toString(), it.getBoolean("success"))
                }
                store().create(definition, request)
                if (publishBeforeStart) publish()
                val reopened = store()
                AgentTeamExecutionRuntime(reopened, AgentSubagentLimits(maxConcurrency = 2)).use { runtime ->
                    val handle = runtime.start(definition, request) { execution ->
                        calls += execution.member.memberId
                        when {
                            execution.member.memberId == author.nodeId -> { started.complete(Unit); release.await(); AgentSubagentOutput("producer ended") }
                            execution.member.memberId == "second-worker" -> { secondStarted.complete(Unit); releaseSecond.await(); AgentSubagentOutput("second ended") }
                            execution.member.memberId == "queued-worker" -> { queuedStarted.complete(Unit); AgentSubagentOutput("queued work ended") }
                            execution.member.memberId == "final" -> { finalStarted.complete(Unit); AgentSubagentOutput("Final fixture assessment") }
                            CollaborationLiveGraph.planner(execution.member) -> {
                                val inputs = CollaborationMilestoneDispatch.inputs(execution.member)
                                if (inputs.isNotEmpty()) coordinated.complete(Unit)
                                AgentSubagentOutput(JSONObject().put("format", CollaborationLiveGraph.FORMAT).put("summary", "Review early")
                                    .put("work", JSONArray().apply { if (inputs.isNotEmpty()) put(JSONObject().put("id", "early-review")
                                        .put("member", "peer").put("stage", "VERIFY").put("assignment", "Check the published version")
                                        .put("independent_review", true).put("uses_milestones", JSONArray().put(inputs.single().getString("token")))) }).toString())
                            }
                            else -> try {
                                val access = CollaborationWorkspaceAccess.from(execution)
                                val ref = CollaborationMilestoneDispatch.inputs(execution.member).single().getJSONArray("revisions").getJSONObject(0)
                                assertNotNull(CollaborationResearchWorkspace(context).read(access, ref.getString("object_id"), ref.getInt("revision")))
                                assertNull(CollaborationResearchWorkspace(context).read(access.copy(pinnedReads = emptySet()), ref.getString("object_id"), ref.getInt("revision")))
                                assertTrue(store().deliveryCheckpoint(author.runId)!!.definition.members.contains(execution.member))
                                reviewed.complete(access); releaseReview.await(); AgentSubagentOutput("Pinned version checked")
                            } catch (failure: Throwable) {
                                reviewed.completeExceptionally(failure)
                                throw failure
                            }
                        }
                    }
                    try {
                        started.await()
                        if (saturated) secondStarted.await()
                        if (!publishBeforeStart) publish()
                        if (saturated) {
                            phase = "coordinator admission under saturation"
                            coordinated.await()
                            assertFalse(release.isCompleted); assertFalse(queuedStarted.isCompleted)
                            releaseSecond.complete(Unit)
                        }
                        phase = "peer admission"
                        val peer = reviewed.await()
                        assertFalse(finalStarted.isCompleted)
                        assertEquals(AgentSubagentStatus.RUNNING, store().snapshot(author.runId)!!.members.single { it.memberId == author.nodeId }.status)
                        val saved = store().deliveryCheckpoint(author.runId)!!
                        assertEquals(peer.pinnedReads, CollaborationMilestoneDispatch.strings(saved.definition.members.single { it.memberId == peer.nodeId }.context[CollaborationMilestoneDispatch.GRANTS]))
                        val archive = CollaborationAdaptivePilotMilestones(author.groupId, author.runId, author.turnId,
                            CollaborationResearchWorkspace(context)) { access, ref -> CollaborationEvidenceLedger(context)
                                .read(access, ref.getString("evidence_id"), ref.getString("sha256")) }
                        val captured = archive.capture(saved)
                        assertEquals(1, captured.getJSONArray("milestones").length())
                        assertEquals("Original candidate for review", captured.getJSONArray("milestones").getJSONObject(0)
                            .getJSONArray("originals").getJSONObject(0).getJSONObject("body").getString("content"))
                        assertFalse(captured.getBoolean("peer_read_proven"))
                        repeat(5) { publish() }
                        assertEquals(captured.toString(), archive.capture(store().deliveryCheckpoint(author.runId)!!).toString())
                        release.complete(Unit)
                        assertFalse(finalStarted.isCompleted)
                        releaseReview.complete(Unit)
                        phase = "final assessment"
                        assertEquals(AgentSubagentRunStatus.SUCCEEDED, handle.await().subagentResult.status)
                        assertEquals(1, calls.count { it == peer.nodeId })
                        assertEquals(calls.size, calls.distinct().size)
                    } catch (failure: Throwable) {
                        throw AssertionError("Failed during $phase; calls=$calls; snapshot=${store().snapshot(author.runId)}", failure)
                    } finally { release.complete(Unit); releaseSecond.complete(Unit); releaseReview.complete(Unit); handle.cancel() }
                }
            } finally { db.clear() }
        }
    } }

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
