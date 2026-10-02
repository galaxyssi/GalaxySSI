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
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local fixtures only; no provider requests, contact messages, or physical tools. */
@RunWith(AndroidJUnit4::class)
class CollaborationLiveGraphDeviceTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private fun database(name: String) = AgentEncryptedDatabase(context, name)
    private fun plan() = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Fixture checkpoint")
        .put("decision", "continue").put("criteria", JSONArray().put(JSONObject().put("id", "criterion")
            .put("requirement", "Fixture verified independently").put("verification", "documentary")
            .put("status", "open").put("evidence", JSONArray())))
        .put("work", JSONArray().put(job("producer", "person-1")).put(job("slow", "person-2")))
        .put("blockers", JSONArray())
    private fun job(id: String, member: String) = JSONObject().put("id", id).put("member", member)
        .put("stage", "EXECUTE").put("assignment", id)
    private fun expansion(review: Boolean) = JSONObject().put("format", CollaborationLiveGraph.FORMAT)
        .put("summary", "Add independent check").put("work", JSONArray().apply { if (review) put(
            job("review", "person-2").put("stage", "VERIFY").put("depends_on", JSONArray().put("producer"))
                .put("independent_review", true)) }).toString()

    private suspend fun seed(store: AgentTeamExecutionStore): AgentTeamExecutionCheckpoint {
        val people = (0..2).map { AgentTeamMember("fixture", instanceId = "person-$it",
            deliveryMode = if (it == 0) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
            context = mapOf("collaboration_group_id" to "live-graph-fixture")) }
        val definition = AgentTeamDefinition("live-graph-fixture", "fixture",
            CollaborationGoalLoop.initial(people, "Fixture").map { it.copy(context = it.context + (CollaborationLiveGraph.ENABLED to "1")) },
            primaryInstanceId = "person-0")
        val request = AgentRunRequest("live-graph-fixture", "turn", "task", runId = "root", goal = "Original goal. ".repeat(1500),
            context = mapOf("preserved_context" to "Original context. ".repeat(800)))
        AgentTeamExecutionRuntime(store).use { runtime ->
            runtime.start(definition, request) { AgentSubagentOutput(plan().toString()) }.await()
        }
        assertTrue(store.advanceGoal("root", "person-0", System.currentTimeMillis()))
        return store.resumeCheckpoint("root")!!
    }

    @Test fun liveReviewStartsBeforeUnrelatedMemberAndFinalWaits(): Unit = runBlocking {
        withTimeout(45_000) {
            val db = database("live-graph-${UUID.randomUUID()}")
            try {
                val store = EncryptedAgentTeamExecutionStore(db)
                val checkpoint = seed(store)
                val slowStarted = CompletableDeferred<Unit>()
                val releaseSlow = CompletableDeferred<Unit>()
                val reviewStarted = CompletableDeferred<Unit>()
                val releaseReview = CompletableDeferred<Unit>()
                val finalStarted = CompletableDeferred<Unit>()
                val calls = ConcurrentHashMap<String, Int>()
                AgentTeamExecutionRuntime(store, AgentSubagentLimits(maxConcurrency = 3)).use { runtime ->
                    val handle = runtime.resume(checkpoint) { execution ->
                        val work = execution.member.context[CollaborationGoalLoop.WORK_ID].orEmpty()
                        if (CollaborationLiveGraph.planner(execution.member)) AgentSubagentOutput(expansion(!calls.containsKey("review")))
                        else if (execution.member.deliveryMode == AgentDeliveryMode.RESPOND) {
                            assertTrue(releaseSlow.isCompleted && releaseReview.isCompleted)
                            finalStarted.complete(Unit)
                            AgentSubagentOutput(plan().put("work", JSONArray()).toString())
                        } else {
                            calls.merge(work, 1, Int::plus)
                            when (work) {
                                "producer" -> slowStarted.await()
                                "slow" -> { slowStarted.complete(Unit); releaseSlow.await() }
                                "review" -> {
                                    assertFalse(releaseSlow.isCompleted)
                                    assertEquals("producer evidence", execution.handoff.dependencies.single().output)
                                    assertTrue(EncryptedAgentTeamExecutionStore(db).snapshot("root")!!.members.any { it.memberId == execution.member.memberId })
                                    reviewStarted.complete(Unit)
                                    releaseReview.await()
                                }
                            }
                            AgentSubagentOutput("$work evidence")
                        }
                    }
                    reviewStarted.await()
                    assertFalse(finalStarted.isCompleted)
                    releaseSlow.complete(Unit)
                    assertFalse(finalStarted.isCompleted)
                    releaseReview.complete(Unit)
                    handle.await()
                    assertTrue(finalStarted.isCompleted)
                    assertEquals(mapOf("producer" to 1, "slow" to 1, "review" to 1), calls)
                }
            } finally { db.clear() }
        }
    }

    @Test fun separateProcessRecovery(): Unit = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val phase = args.getString("liveGraphPhase").orEmpty()
        org.junit.Assume.assumeTrue(phase in setOf("seed", "recover"))
        val db = database("live-graph-process-fixture")
        val store = EncryptedAgentTeamExecutionStore(db)
        withTimeout(45_000) {
            if (phase == "seed") {
                require(store.snapshot("root") == null) { "Recover or explicitly clean the previous fixture first" }
                val checkpoint = seed(store)
                val producer = checkpoint.definition.members.single { it.context[CollaborationGoalLoop.WORK_ID] == "producer" }
                suspend fun complete(child: String, output: String, sequence: Long) {
                    val result = AgentSubagentChildResult("root", child, "root", 1, AgentSubagentStatus.SUCCEEDED, output = output,
                        startedAtMillis = 1, completedAtMillis = 2)
                    store.append(AgentSubagentEvent(sequence, "root", child, AgentSubagentEventKinds.CHILD_SUCCEEDED,
                        childStatus = AgentSubagentStatus.SUCCEEDED, result = result, timestampMillis = 2))
                }
                complete(producer.memberId, "producer evidence", checkpoint.lastSequence + 1)
                val first = store.expandResearchGraph("root", checkpoint.definition.primaryMemberId, setOf(producer.memberId), 3)!!
                val planner = first.definition.members.single(CollaborationLiveGraph::planner)
                complete(planner.memberId, expansion(true), first.lastSequence + 1)
                val expanded = store.expandResearchGraph("root", checkpoint.definition.primaryMemberId,
                    setOf(producer.memberId, planner.memberId), 4)!!
                assertTrue(expanded.definition.members.any { it.context[CollaborationGoalLoop.WORK_ID] == "review" })
                context.getSharedPreferences("live-graph-fixture", Context.MODE_PRIVATE).edit()
                    .putInt("seed_pid", android.os.Process.myPid()).commit()
            } else {
                try {
                    assertNotEquals(context.getSharedPreferences("live-graph-fixture", Context.MODE_PRIVATE)
                        .getInt("seed_pid", -1), android.os.Process.myPid())
                    val checkpoint = store.resumeCheckpoint("root")!!
                    assertEquals("Original goal. ".repeat(1500), checkpoint.request.goal)
                    assertEquals("Original context. ".repeat(800), checkpoint.request.context["preserved_context"])
                    assertEquals(2, checkpoint.completed.size)
                    val calls = ConcurrentHashMap<String, Int>()
                    AgentTeamExecutionRuntime(store).use { runtime -> runtime.resume(checkpoint) { execution ->
                        if (CollaborationLiveGraph.planner(execution.member)) AgentSubagentOutput(expansion(false))
                        else if (execution.member.deliveryMode == AgentDeliveryMode.RESPOND)
                            AgentSubagentOutput(plan().put("work", JSONArray()).toString())
                        else {
                            val work = execution.member.context.getValue(CollaborationGoalLoop.WORK_ID)
                            assertNotEquals("producer", work)
                            calls.merge(work, 1, Int::plus)
                            if (work == "review") assertEquals("producer evidence", execution.handoff.dependencies.single().output)
                            AgentSubagentOutput("$work evidence")
                        }
                    }.await() }
                    assertEquals(mapOf("slow" to 1, "review" to 1), calls)
                } finally {
                    db.clear()
                    context.getSharedPreferences("live-graph-fixture", Context.MODE_PRIVATE).edit().clear().commit()
                }
            }
            InstrumentationRegistry.getInstrumentation().sendStatus(0, Bundle().apply {
                putString("live_graph_phase", phase); putInt("process_id", android.os.Process.myPid())
            })
        }
    }
}
