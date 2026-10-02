package com.galaxyssi.chat

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CollaborationWorkGraphDeviceTest {
    @Test fun savedDependencyGraphResumesAndReviewsBeforeUnrelatedSlowWorkCompletes(): Unit = runBlocking {
        withTimeout(30_000) {
            val context = ApplicationProvider.getApplicationContext<Context>()
            val database = AgentEncryptedDatabase(context, "work-graph-fixture-${UUID.randomUUID()}")
            val store = EncryptedAgentTeamExecutionStore(database)
            val people = (0..3).map { AgentTeamMember("fixture", instanceId = "person-$it",
                deliveryMode = if (it == 0) AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                context = mapOf("collaboration_group_id" to "fixture")) }
            val definition = AgentTeamDefinition("fixture", "fixture", CollaborationGoalLoop.initial(people, "Fixture"), primaryInstanceId = "person-0")
            val request = AgentRunRequest("fixture", "turn", "task", runId = "root", goal = "Fixture")
            fun job(id: String, member: String) = JSONObject().put("id", id).put("member", member).put("stage", "EXECUTE").put("assignment", id)
            val plan = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Fixture progress").put("decision", "continue")
                .put("criteria", JSONArray().put(JSONObject().put("id", "c").put("requirement", "Verified fixture").put("status", "open").put("evidence", JSONArray())))
                .put("work", JSONArray().put(job("producer", "person-1")).put(job("slow", "person-3"))
                    .put(job("review", "person-2").put("depends_on", JSONArray().put("producer")).put("independent_review", true)))
                .put("blockers", JSONArray())
            try {
                AgentTeamExecutionRuntime(store).use { runtime -> runtime.start(definition, request) { AgentSubagentOutput(plan.toString()) }.await() }
                assertTrue(store.advanceGoal("root", "person-0", System.currentTimeMillis()))
                val reopened = EncryptedAgentTeamExecutionStore(database)
                val checkpoint = reopened.resumeCheckpoint("root")!!
                val reviewer = checkpoint.definition.members.single { it.context[CollaborationGoalLoop.WORK_ID] == "review" }
                assertEquals(1, reviewer.dependsOnAgentIds.size)
                val slowStarted = CompletableDeferred<Unit>()
                val reviewStarted = CompletableDeferred<Unit>()
                val release = CompletableDeferred<Unit>()
                AgentTeamExecutionRuntime(reopened, AgentSubagentLimits(maxConcurrency = 2)).use { runtime ->
                    val handle = runtime.resume(checkpoint) { execution ->
                        if (execution.member.deliveryMode == AgentDeliveryMode.RESPOND) AgentSubagentOutput(plan.put("work", JSONArray()).toString())
                        else {
                            when (execution.member.context[CollaborationGoalLoop.WORK_ID]) {
                                "producer" -> slowStarted.await()
                                "slow" -> { slowStarted.complete(Unit); release.await() }
                                "review" -> {
                                    assertEquals("Producer evidence", execution.handoff.dependencies.single().output)
                                    assertFalse(release.isCompleted)
                                    reviewStarted.complete(Unit)
                                }
                            }
                            AgentSubagentOutput("Producer evidence")
                        }
                    }
                    reviewStarted.await()
                    release.complete(Unit)
                    handle.await()
                }
            } finally { database.clear() }
        }
    }
}
