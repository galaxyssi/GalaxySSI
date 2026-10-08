package com.galaxyssi.chat

import android.content.Context
import android.os.Bundle
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Dedicated local fixtures only: no models, broker messages, contacts or physical tools. */
@RunWith(AndroidJUnit4::class)
class CollaborationReviewRebindingDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private fun author(group: String) = CollaborationWorkspaceAccess(group, "root", "turn", 1, "producer", "author")
    private fun store(db: AgentEncryptedDatabase, workspace: CollaborationResearchWorkspace) =
        EncryptedAgentTeamExecutionStore(db, candidateWorkspace = { workspace }, milestoneWorkspace = { workspace })
    private fun seed(store: AgentTeamExecutionStore, group: String, ordinaryData: Boolean = false) {
        CollaborationGroupStore(context).update(group) { it.copy(
            members = listOf("lead", "author", "peer").map { person -> CollaborationMember(person, person, "fixture", "Fixture") },
            coordinatorId = "lead") }
        val people = listOf("lead", "author", "peer").map { person -> AgentTeamMember("fixture", AgentDeliveryMode.IGNORE,
            instanceId = person, context = mapOf(CollaborationResearchWorkflow.PERSON to person, "collaboration_group_id" to group,
                CollaborationGoalLoop.ROSTER to "true", CollaborationLiveGraph.ENABLED to "1", CollaborationResearchWorkflow.STAGE to "DELIVER")) }
        fun work(id: String, person: String, stage: String) = people.single { it.memberId == person }.copy(
            instanceId = id, deliveryMode = AgentDeliveryMode.OBSERVE, objective = "Original $id assignment",
            context = people.single { it.memberId == person }.context + mapOf(CollaborationGoalLoop.ROSTER to "false",
                CollaborationGoalLoop.WORK_ID to id, CollaborationResearchWorkflow.STAGE to stage, CollaborationWorkGraph.POLICY to "success"))
        val producer = work("producer", "author", "EXECUTE")
        val probe = work("probe", "peer", "EXPLORE")
        val stage = if (ordinaryData) "CHALLENGE" else "VERIFY"
        val review = work("review", "peer", stage).copy(dependsOnAgentIds = setOf("producer", "probe"),
            context = work("review", "peer", stage).context + if (ordinaryData) mapOf(
                CollaborationWorkGraph.INDEPENDENT to "false", CollaborationDataDependencies.CONTEXT to
                    CollaborationDataDependencies.array(mapOf("producer" to "Frozen candidate data")).toString())
            else mapOf(CollaborationWorkGraph.INDEPENDENT to "true", CollaborationReviewTargets.CONTEXT to "[\"producer\"]"))
        val final = people[0].copy(instanceId = "final", deliveryMode = AgentDeliveryMode.RESPOND,
            dependsOnAgentIds = setOf("producer", "probe", "review"), context = people[0].context + (CollaborationGoalLoop.ROSTER to "false"))
        store.create(AgentTeamDefinition("rebind-fixture", "fixture", people + producer + probe + review + final, primaryInstanceId = "final"),
            AgentRunRequest(group, "turn", "task", runId = "root", goal = "Original goal and acceptance requirements", createdAtMillis = 1,
                context = mapOf(CollaborationGoalLoop.ROUND to "1")))
    }
    private fun publish(workspace: CollaborationResearchWorkspace, group: String, id: String = "v1", ref: JSONObject? = null,
                        access: CollaborationWorkspaceAccess = author(group)): JSONObject {
        workspace.enrollPublication(access, if (access.nodeId == "probe") CollaborationResearchStage.EXPLORE else CollaborationResearchStage.EXECUTE)
        val item = JSONObject().put("id", "candidate").put("kind", "artifact").put("title", id)
            .put("body", JSONObject().put("content", "exact candidate $id"))
        ref?.let { item.put("object_id", it.getString("object_id")).put("base_revision", it.getInt("revision")) }
        return workspace.publishMilestone(access, id, JSONObject().put("format", CollaborationResearchArtifact.FORMAT)
            .put("summary", id).put("candidates", JSONArray()).put("findings", JSONArray()).put("workspace", JSONArray().put(item)).toString())
            .getJSONArray("revisions").getJSONObject(0)
    }
    private fun expansion(token: String? = null, probeToken: String? = null, ordinaryData: Boolean = false): String {
        val result = JSONObject().put("format", CollaborationLiveGraph.FORMAT)
            .put("summary", "Bind exact published inputs without completing their producers").put("work", JSONArray())
        if (token != null) {
            val inputs = JSONArray().put(JSONObject().put("dependency", "producer").put("uses_milestones", JSONArray().put(token)))
            probeToken?.let { inputs.put(JSONObject().put("dependency", "probe").put("uses_milestones", JSONArray().put(it))) }
            result.put(if (ordinaryData) CollaborationReviewRebinding.INPUT_FIELD else CollaborationReviewRebinding.FIELD, JSONArray().put(JSONObject()
                .put("work_id", "review").put("expected_revision", 0).put("reason", "The frozen versions suffice for the existing check")
                .put("inputs", inputs)))
        }
        return result.toString()
    }
    private fun checkBound(checkpoint: AgentTeamExecutionCheckpoint, boundProbe: Boolean = false, ordinaryData: Boolean = false): AgentTeamMember {
        val review = checkpoint.definition.members.single { it.memberId == "review" }
        assertEquals("1", review.context[CollaborationReviewRebinding.REVISION])
        assertEquals(if (boundProbe) emptySet<String>() else setOf("probe"), review.dependsOnAgentIds)
        assertEquals(if (ordinaryData) 0 else 1, CollaborationReviewTargets.milestones(review).size)
        if (ordinaryData) {
            assertEquals("CHALLENGE", review.context[CollaborationResearchWorkflow.STAGE])
            assertEquals("false", review.context[CollaborationWorkGraph.INDEPENDENT])
            assertEquals("[]", review.context[CollaborationDataDependencies.CONTEXT])
            assertEquals("Frozen candidate data", JSONArray(review.context.getValue(CollaborationReviewRebinding.HISTORY))
                .getJSONObject(0).getJSONObject("data_requirements").getString("producer"))
        }
        assertEquals(if (boundProbe) 2 else 1, CollaborationMilestoneDispatch.inputs(review).size)
        assertEquals("Original review assignment", review.objective)
        assertEquals("Original goal and acceptance requirements", checkpoint.request.goal)
        assertEquals(1, JSONArray(review.context.getValue(CollaborationReviewRebinding.HISTORY)).length())
        return review
    }

    @Test fun persistedRebindingStartsExactVersionReviewWhileProducerContinues() = runBinding(false)

    @Test fun frozenProbeAndCandidateStartReviewWhileBothReportsContinue() = runBinding(true)

    @Test fun ordinaryChallengeStartsFromDeclaredDataWhileProducerContinues() = runBinding(false, ordinaryData = true)

    private fun runBinding(boundProbe: Boolean, ordinaryData: Boolean = false): Unit = runBlocking {
        withTimeout(45_000) {
            val group = "review-binding-${UUID.randomUUID()}"
            val db = AgentEncryptedDatabase(context, group)
            val workspace = CollaborationResearchWorkspace(context)
            try {
                val store = store(db, workspace); seed(store, group, ordinaryData)
                val probeStarted = CompletableDeferred<Unit>()
                val releaseProbe = CompletableDeferred<Unit>()
                val releaseProducer = CompletableDeferred<Unit>()
                val reviewStarted = CompletableDeferred<Unit>()
                val versionsPublished = CompletableDeferred<Unit>()
                val rebound = CompletableDeferred<Unit>()
                val ref = CompletableDeferred<JSONObject>()
                val probeRef = CompletableDeferred<JSONObject>()
                val calls = ConcurrentHashMap<String, Int>()
                AgentTeamExecutionRuntime(store, onSnapshot = {
                    if (store.deliveryCheckpoint("root")?.definition?.members?.singleOrNull { it.memberId == "review" }
                        ?.context?.get(CollaborationReviewRebinding.REVISION) == "1") rebound.complete(Unit)
                }).use { runtime ->
                    val handle = runtime.resume(store.deliveryCheckpoint("root")!!) { execution ->
                        if (CollaborationLiveGraph.planner(execution.member)) {
                            val bound = store.deliveryCheckpoint("root")!!.definition.members.single { it.memberId == "review" }
                                .context[CollaborationReviewRebinding.REVISION] == "1"
                            val checkpoint = store.deliveryCheckpoint("root")!!
                            val inputs = CollaborationMilestoneDispatch.inherited(AgentTeamExecutionRecord(checkpoint.definition, checkpoint.request), execution.member)
                                .values.associateBy { it.getString("milestone_id") }
                            val ready = !bound && "v1" in inputs && (!boundProbe || "data-v1" in inputs)
                            AgentSubagentOutput(expansion(if (ready) inputs.getValue("v1").getString("token") else null,
                                if (ready && boundProbe) inputs.getValue("data-v1").getString("token") else null, ordinaryData))
                        } else {
                            calls.merge(execution.member.memberId, 1, Int::plus)
                            when (execution.member.memberId) {
                                "producer" -> { probeStarted.await(); ref.complete(publish(workspace, group)); releaseProducer.await() }
                                "probe" -> {
                                    if (boundProbe) probeRef.complete(publish(workspace, group, "data-v1",
                                        access = author(group).copy(nodeId = "probe", personId = "peer")))
                                    probeStarted.complete(Unit); releaseProbe.await()
                                }
                                "review" -> {
                                    assertFalse(releaseProducer.isCompleted)
                                    assertEquals(!boundProbe, releaseProbe.isCompleted)
                                    checkBound(store(db, workspace).deliveryCheckpoint("root")!!, boundProbe, ordinaryData)
                                    versionsPublished.await()
                                    val access = CollaborationMilestoneDispatch.access(
                                        AgentTeamExecutionRecord(store.deliveryCheckpoint("root")!!.definition, execution.request.copy(runId = "root")), execution.member)
                                    assertNotNull(workspace.read(access, ref.await().getString("object_id"), 1))
                                    assertNull(workspace.read(access, ref.await().getString("object_id"), 2))
                                    assertNull(execution.handoff.dependencies.firstOrNull { it.childId == "producer" })
                                    if (boundProbe) {
                                        assertTrue(execution.handoff.dependencies.isEmpty())
                                        assertNotNull(workspace.read(access, probeRef.await().getString("object_id"), 1))
                                        assertNull(workspace.read(access, probeRef.await().getString("object_id"), 2))
                                    } else assertEquals("probe evidence", execution.handoff.dependencies.single().output)
                                    reviewStarted.complete(Unit)
                                }
                            }
                            AgentSubagentOutput("${execution.member.memberId} evidence")
                        }
                    }
                    check(withTimeoutOrNull(15_000) { rebound.await(); true } == true) {
                        "Binding not observed: calls=$calls; checkpoint=${store.deliveryCheckpoint("root")}; snapshot=${store.snapshot("root")}"
                    }
                    if (!boundProbe) assertFalse(reviewStarted.isCompleted)
                    publish(workspace, group, "v2", ref.await())
                    if (boundProbe) publish(workspace, group, "data-v2", probeRef.await(),
                        author(group).copy(nodeId = "probe", personId = "peer"))
                    versionsPublished.complete(Unit)
                    if (!boundProbe) releaseProbe.complete(Unit)
                    check(withTimeoutOrNull(15_000) { reviewStarted.await(); true } == true) {
                        "Review did not start: calls=$calls; checkpoint=${store.deliveryCheckpoint("root")}; snapshot=${store.snapshot("root")}"
                    }
                    assertFalse(calls.containsKey("final"))
                    releaseProbe.complete(Unit)
                    releaseProducer.complete(Unit)
                    handle.await()
                    assertEquals(mapOf("producer" to 1, "probe" to 1, "review" to 1, "final" to 1), calls)
                    checkBound(store(db, workspace).deliveryCheckpoint("root")!!, boundProbe, ordinaryData)
                }
            } finally { db.clear(); workspace.removeGroup(group); CollaborationGroupStore(context).remove(group) }
        }
    }

    @Test fun separateProcessRecovery(): Unit = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("reviewBindingPhase").orEmpty()
        val boundProbe = args.getString("reviewBindingFrozenProbe") == "true"
        val ordinaryData = args.getString("reviewBindingOrdinaryData") == "true"
        require(!ordinaryData || !boundProbe)
        org.junit.Assume.assumeTrue(phase in setOf("seed", "recover", "cleanup"))
        val group = "review-binding-process-fixture"
        val db = AgentEncryptedDatabase(context, group)
        val workspace = CollaborationResearchWorkspace(context)
        val store = store(db, workspace)
        val prefs = context.getSharedPreferences(group, Context.MODE_PRIVATE)
        if (phase == "cleanup") {
            db.clear(); workspace.removeGroup(group); CollaborationGroupStore(context).remove(group)
            prefs.edit().clear().commit(); return@runBlocking
        }
        withTimeout(45_000) {
            if (phase == "seed") {
                require(store.snapshot("root") == null) { "Recover or explicitly clean the previous fixture first" }
                seed(store, group, ordinaryData); publish(workspace, group)
                if (boundProbe) publish(workspace, group, "data-v1", access = author(group).copy(nodeId = "probe", personId = "peer"))
                val planned = store.expandResearchGraph("root", "final", emptySet(), 2, admittedIds = emptySet())!!
                val planner = planned.definition.members.single(CollaborationLiveGraph::planner)
                val provenance = AgentTeamGraphPlan.build(planned.definition, planned.request).children.single { it.childId == planner.memberId }.provenance
                val result = AgentSubagentChildResult("root", planner.memberId, "root", 1, AgentSubagentStatus.SUCCEEDED,
                    output = expansion(CollaborationMilestoneDispatch.inputs(planner).single { it.getString("milestone_id") == "v1" }.getString("token"),
                        if (boundProbe) CollaborationMilestoneDispatch.inputs(planner).single { it.getString("milestone_id") == "data-v1" }.getString("token") else null, ordinaryData),
                    startedAtMillis = 2, completedAtMillis = 3, provenance = provenance)
                store.append(AgentSubagentEvent(planned.lastSequence + 1, "root", planner.memberId, AgentSubagentEventKinds.CHILD_SUCCEEDED,
                    childStatus = result.status, result = result, provenance = provenance, timestampMillis = 3))
                checkBound(store.expandResearchGraph("root", "final", setOf(planner.memberId), 4, admittedIds = emptySet())!!, boundProbe, ordinaryData)
                prefs.edit().putInt("seed_pid", android.os.Process.myPid()).commit()
            } else {
                try {
                    assertNotEquals(prefs.getInt("seed_pid", -1), android.os.Process.myPid())
                    val checkpoint = store.deliveryCheckpoint("root")!!
                    checkBound(checkpoint, boundProbe, ordinaryData)
                    val calls = ConcurrentHashMap<String, Int>()
                    val releaseProducer = CompletableDeferred<Unit>()
                    val releaseProbe = CompletableDeferred<Unit>()
                    val reviewRan = CompletableDeferred<Unit>()
                    AgentTeamExecutionRuntime(store).use { runtime ->
                        val handle = runtime.resume(checkpoint) { execution ->
                            if (CollaborationLiveGraph.planner(execution.member)) AgentSubagentOutput(expansion()) else {
                                calls.merge(execution.member.memberId, 1, Int::plus)
                                when (execution.member.memberId) {
                                    "producer" -> releaseProducer.await()
                                    "probe" -> if (boundProbe) releaseProbe.await()
                                    "review" -> {
                                        assertFalse(releaseProducer.isCompleted)
                                        val access = CollaborationMilestoneDispatch.access(AgentTeamExecutionRecord(checkpoint.definition, checkpoint.request), execution.member)
                                        assertEquals(if (boundProbe) 2 else 1, workspace.browse(access).revisions.size)
                                        if (boundProbe) assertFalse(releaseProbe.isCompleted)
                                        reviewRan.complete(Unit)
                                    }
                                }
                                AgentSubagentOutput("${execution.member.memberId} evidence")
                            }
                        }
                        reviewRan.await(); releaseProducer.complete(Unit); releaseProbe.complete(Unit); handle.await()
                    }
                    assertEquals(mapOf("producer" to 1, "probe" to 1, "review" to 1, "final" to 1), calls)
                    checkBound(store.deliveryCheckpoint("root")!!, boundProbe, ordinaryData)
                } finally {
                    db.clear(); workspace.removeGroup(group); CollaborationGroupStore(context).remove(group)
                    prefs.edit().clear().commit()
                }
            }
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putString("review_binding_phase", phase); putInt("process_id", android.os.Process.myPid())
            })
        }
    }
}
