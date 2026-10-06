package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Uses local synthetic workers and an isolated database; no model calls or user task recovery. */
@RunWith(AndroidJUnit4::class)
class CollaborationAdmissionOrderDeviceTest {
    @Test fun realDispatcherAdmitsTheFirstTwoPlannedResearchers() = runBlocking {
        withTimeout(15_000) {
            val release = CompletableDeferred<Unit>()
            val both = CompletableDeferred<Unit>()
            val seen = CopyOnWriteArrayList<String>()
            val definition = definition()
            AgentTeamExecutionRuntime(InMemoryAgentTeamExecutionStore(), AgentSubagentLimits(maxConcurrency = 2)).use { runtime ->
                val handle = runtime.start(definition, request("order-${UUID.randomUUID()}")) { execution ->
                    seen += execution.member.memberId
                    if (seen.size == 2) both.complete(Unit)
                    if (execution.member.memberId in setOf("z-model", "m-challenge")) release.await()
                    AgentSubagentOutput("Local synthetic result")
                }
                try {
                    both.await()
                    assertEquals(setOf("z-model", "m-challenge"), seen.toSet())
                    release.complete(Unit)
                    assertEquals(AgentSubagentRunStatus.SUCCEEDED, handle.await().subagentResult.status)
                    assertEquals(listOf("a-audit", "final"), seen.drop(2))
                } finally { release.complete(Unit); handle.cancel("Fixture complete") }
            }
        }
    }

    @Test fun encryptedCheckpointKeepsOrderAndDoesNotReplayCompletedWork() = runBlocking {
        withTimeout(15_000) {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val token = UUID.randomUUID().toString()
            val database = AgentEncryptedDatabase(context, "admission-fixture-$token")
            val request = request("admission-$token")
            val definition = definition()
            try {
                val first = EncryptedAgentTeamExecutionStore(database)
                first.create(definition, request)
                first.append(AgentSubagentEvent(1, request.runId, "z-model", AgentSubagentEventKinds.CHILD_SUCCEEDED,
                    childStatus = AgentSubagentStatus.SUCCEEDED, result = AgentSubagentChildResult(request.runId, "z-model",
                        request.runId, 1, AgentSubagentStatus.SUCCEEDED, "Already persisted synthetic model")))
                assertNull(first.resumeCheckpoint(request.runId))
                assertEquals(AgentTeamExecutionState.INTERRUPTED, first.markInterrupted(request.runId)?.state)
                val reopened = EncryptedAgentTeamExecutionStore(database)
                val checkpoint = requireNotNull(reopened.resumeCheckpoint(request.runId))
                assertEquals(definition.members.map { it.memberId }, checkpoint.definition.members.map { it.memberId })
                val seen = CopyOnWriteArrayList<String>()
                AgentTeamExecutionRuntime(reopened, AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
                    val result = runtime.resume(checkpoint) { execution ->
                        seen += execution.member.memberId
                        AgentSubagentOutput("Local synthetic result")
                    }.await()
                    assertEquals(AgentSubagentRunStatus.SUCCEEDED, result.subagentResult.status)
                }
                assertEquals(listOf("m-challenge", "a-audit", "final"), seen)
            } finally { database.clear() }
        }
    }

    @Test fun dependencyAndPermitWaitsDoNotBlockIndependentWork() = runBlocking {
        withTimeout(15_000) {
            val unblock = CompletableDeferred<Unit>()
            val seen = CopyOnWriteArrayList<String>()
            val plan = AgentSubagentPlan("wait-${UUID.randomUUID()}", listOf(
                AgentSubagentChild("z-review", dependencies = setOf("m-producer")),
                AgentSubagentChild("m-producer"), AgentSubagentChild("a-independent")), preserveChildOrder = true)
            AgentSubagentRuntime(AgentSubagentLimits(maxConcurrency = 1)).use { runtime ->
                val result = runtime.start(plan) {
                    seen += it.childId
                    if (it.childId == "m-producer") it.suspendExecutionPermit { unblock.await() }
                    if (it.childId == "a-independent") unblock.complete(Unit)
                    AgentSubagentOutput("Local synthetic result")
                }.await()
                assertEquals(AgentSubagentRunStatus.SUCCEEDED, result.status)
            }
            assertEquals(listOf("m-producer", "a-independent", "z-review"), seen)
        }
    }

    private fun definition(): AgentTeamDefinition {
        val ids = listOf("z-model", "m-challenge", "a-audit", "final")
        return AgentTeamDefinition("local-fixture", "fixture", ids.map { id ->
            AgentTeamMember("fixture", if (id == "final") AgentDeliveryMode.RESPOND else AgentDeliveryMode.OBSERVE,
                instanceId = id, objective = "Local scheduler fixture", dependsOnAgentIds = if (id == "final") ids.dropLast(1).toSet() else emptySet(),
                context = mapOf("collaboration_group_id" to "local-fixture", CollaborationResearchWorkflow.STAGE to "EXECUTE"))
        }, primaryInstanceId = "final")
    }
    private fun request(run: String) = AgentRunRequest("local-fixture", "turn", "task", runId = run, goal = "Local scheduler verification")
}
