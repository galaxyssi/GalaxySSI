package com.galaxyssi.chat

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class AgentTeamRecoveryPolicyTest {
    private class Fixture {
        val rows = mutableMapOf<String, String>()
        var now = 100_000L
        fun policy() = AgentTeamRecoveryPolicy(rows::get, { id, value ->
            if (value == null) rows.remove(id) else rows[id] = value
        }, { now })
    }

    private fun snapshot(run: String = "run", group: String = "") = AgentTeamExecutionSnapshot(
        run, "team", "conversation", "task", "agent", "private goal", AgentTeamVisibilityMode.VISIBLE,
        AgentTeamExecutionState.INTERRUPTED, listOf(AgentTeamMemberSnapshot("agent", "coordinator",
            AgentDeliveryMode.RESPOND, AgentSubagentStatus.QUEUED, collaborationGroupId = group)))

    @Test fun tenthConsecutiveFailureStopsRetriesAcrossRestartsAndTime() {
        val fixture = Fixture()
        var policy = fixture.policy()
        repeat(10) { index ->
            assertTrue(policy.mayAttempt("run"))
            val state = policy.failed(snapshot(), IOException("private request"))
            assertEquals(index + 1, state.failures)
            assertEquals(index == 9, state.stalled)
            assertFalse(policy.mayAttempt("run"))
            fixture.now += 60_000
            policy = fixture.policy()
        }
        fixture.now += 365L * 24 * 60 * 60 * 1000
        assertFalse(policy.mayAttempt("run"))
        assertEquals(10, policy.failed(snapshot(), IllegalStateException()).failures)
        val projection = policy.project(snapshot())
        assertTrue(projection.paused)
        assertEquals(10, projection.recoveryFailureCount)
        assertFalse(projection.recoveryScopeMissing)
    }

    @Test fun backoffIsDurableAndBoundedWithoutLimitingSuccessfulActions() {
        val fixture = Fixture()
        val policy = fixture.policy()
        repeat(4) { index ->
            val state = policy.failed(snapshot(), IOException())
            val delay = listOf(5_000L, 10_000L, 20_000L, 30_000L)[index]
            assertEquals(fixture.now + delay, state.retryAtMillis)
            fixture.now += delay - 1
            assertFalse(fixture.policy().mayAttempt("run"))
            fixture.now++
            assertTrue(fixture.policy().mayAttempt("run"))
        }
        repeat(1_000) { policy.observed(snapshot("healthy").copy(state = AgentTeamExecutionState.SUCCEEDED)) }
        assertEquals(0, policy.state("healthy").failures)
        assertEquals(4, policy.state("run").failures)
    }

    @Test fun bookkeepingActivityDoesNotResetTheFailureCounter() {
        val fixture = Fixture()
        val policy = fixture.policy()
        repeat(10) { index ->
            val run = snapshot().copy(updatedAtMillis = index.toLong(), interruptedAtMillis = index.toLong(),
                members = snapshot().members.map { it.copy(status = AgentSubagentStatus.RUNNING,
                    executionStartedAtMillis = index.toLong(), errorMessage = "different status $index") })
            policy.failed(run, IOException())
            policy.observed(run)
        }
        assertTrue(policy.state("run").stalled)
    }

    @Test fun actualChildCompletionResetsConsecutiveFailuresBeforeExhaustion() {
        val fixture = Fixture()
        val policy = fixture.policy()
        repeat(9) { policy.failed(snapshot(), IOException()) }
        val progressed = snapshot().copy(members = snapshot().members + AgentTeamMemberSnapshot(
            "specialist", "review", AgentDeliveryMode.OBSERVE, AgentSubagentStatus.SUCCEEDED))
        policy.observed(progressed)
        assertEquals(0, policy.state("run").failures)
        assertTrue(policy.mayAttempt("run"))
        assertEquals(1, policy.failed(progressed, IOException()).failures)
    }

    @Test fun lateResultIsRetainedButDoesNotSilentlyRestartAnExhaustedGoal() {
        val fixture = Fixture()
        val policy = fixture.policy()
        repeat(10) { policy.failed(snapshot(), IOException()) }
        val late = snapshot().copy(members = snapshot().members.map { it.copy(status = AgentSubagentStatus.SUCCEEDED) })
        policy.observed(late)
        assertTrue(policy.state("run").stalled)
        policy.observed(late.copy(state = AgentTeamExecutionState.SUCCEEDED))
        assertFalse(policy.state("run").stalled)
    }

    @Test fun explicitResumeResetsOnlyTheSelectedGoal() {
        val fixture = Fixture()
        val policy = fixture.policy()
        repeat(10) {
            policy.failed(snapshot("a"), IOException())
            policy.failed(snapshot("b"), IOException())
        }
        policy.reset("a")
        assertTrue(fixture.policy().mayAttempt("a"))
        assertFalse(fixture.policy().mayAttempt("b"))
    }

    @Test fun outstandingResultsDoNotConsumeTheFailureBudget() {
        val fixture = Fixture()
        val policy = fixture.policy()
        repeat(100) { policy.awaitingResult("run"); fixture.now += 30_000 }
        assertEquals(0, policy.state("run").failures)
        assertTrue(policy.mayAttempt("run"))
        policy.failed(snapshot(), IOException())
        policy.awaitingResult("run")
        assertEquals(1, policy.state("run").failures)
    }

    @Test fun missingGroupIsBlockedBeforeCheckpointExecutionWithoutTenAttempts() {
        val fixture = Fixture()
        val policy = fixture.policy()
        var executed = false
        val error = runCatching {
            AgentTeamRecoveryPolicy.requireScope(snapshot(group = "deleted")) { false }
            executed = true
        }.exceptionOrNull()
        assertTrue(error is CollaborationGroupUnavailableException)
        assertFalse(executed)
        policy.missingScope("run")
        assertFalse(fixture.policy().mayAttempt("run"))
        assertEquals(0, policy.state("run").failures)
        assertTrue(policy.project(snapshot()).recoveryScopeMissing)
        AgentTeamRecoveryPolicy.requireScope(snapshot("normal")) { error("Not a collaboration group") }
        AgentTeamRecoveryPolicy.requireScope(snapshot("valid", "present")) { it == "present" }
    }

    @Test fun scopeReadErrorsAreNotTreatedAsDeletedGroups() {
        val failure = IOException("database temporarily unavailable")
        assertSame(failure, runCatching {
            AgentTeamRecoveryPolicy.requireScope(snapshot(group = "present")) { throw failure }
        }.exceptionOrNull())
    }

    @Test fun wrappedScopeLossIsPermanentButOtherFailuresAreRetryable() {
        val failure = CancellationException("Supervisor interrupted").apply { initCause(CollaborationGroupUnavailableException()) }
        assertTrue(AgentTeamRecoveryPolicy.missingScopeFailure(failure))
        assertFalse(AgentTeamRecoveryPolicy.missingScopeFailure(IOException("Group access was removed")))
        val cycle = IOException().apply { initCause(IOException()) }
        cycle.cause!!.initCause(cycle)
        assertFalse(AgentTeamRecoveryPolicy.missingScopeFailure(cycle))
    }

    @Test fun unexpectedCancellationDoesNotBypassTheFailureLimit() {
        val fixture = Fixture()
        val policy = fixture.policy()
        repeat(10) { policy.failed(snapshot(), CancellationException("External operation timed out")) }
        assertFalse(policy.mayAttempt("run"))
    }

    @Test fun persistenceContainsNoGoalsOutputsOrExceptionMessages() {
        val fixture = Fixture()
        fixture.policy().failed(snapshot(), IOException("secret credential"))
        val saved = fixture.rows.getValue("run")
        assertFalse(saved.contains("secret"))
        assertFalse(saved.contains("private goal"))
        assertTrue(saved.contains("IOException"))
    }

    @Test fun failedPersistenceStillPreventsImmediateRetryInThisProcess() {
        val policy = AgentTeamRecoveryPolicy({ null }, { _, _ -> throw IOException() }, { 10L })
        assertTrue(runCatching { policy.failed(snapshot(), IOException()) }.isFailure)
        assertFalse(policy.mayAttempt("run"))
    }

    @Test fun evictionDoesNotLoseDurableFailureCounts() {
        val fixture = Fixture()
        val policy = fixture.policy()
        repeat(10) { policy.failed(snapshot(), IOException()) }
        repeat(400) { policy.state("other-$it") }
        assertFalse(policy.mayAttempt("run"))
    }

    @Test fun stalledMetadataRoundTripsAndProjectsBlockedInsteadOfRunning() {
        val team = snapshot().copy(paused = true, recoveryFailureCount = 10)
        val metadata = CollaborationCurrentStatePolicy.metadata(team, team.members.single(), null)
        val decoded = requireNotNull(CollaborationTranscriptMetadata.decode(metadata.encode()))
        assertEquals(10, decoded.recoveryFailureCount)
        assertTrue(decoded.paused)
        assertEquals(ConversationHubAgentStatus.BLOCKED, CollaborationCurrentStatePolicy.status(team, emptyMap()))
        assertEquals(ConversationHubAgentStatus.BLOCKED, CollaborationTeamPanelPolicy.status(listOf(
            CollaborationTeamPanelMember(CollaborationMember("agent", "Agent", "agent", "Provider", "coordinator"),
                metadata = decoded))))
    }

    @Test fun watcherPersistsFailureBeforeReleaseAndManualResumeStillCompletes() = runBlocking {
        withTimeout(10_000) {
            val fixture = Fixture()
            val policy = fixture.policy()
            val durable = InMemoryAgentTeamExecutionStore()
            var fail = true
            var executions = 0
            val store = object : AgentTeamExecutionStore by durable {
                override suspend fun append(event: AgentSubagentEvent) {
                    if (fail && event.kind == AgentSubagentEventKinds.SUPERVISOR_STARTED) throw IOException("fixture")
                    durable.append(event)
                }
            }
            val definition = AgentTeamDefinition("team", "agent", listOf(AgentTeamMember("agent", AgentDeliveryMode.RESPOND)))
            val request = AgentRunRequest(conversationId = "conversation", messageId = "message", taskId = "task",
                runId = "run", goal = "Complete the fixture", idempotencyKey = "fixture")
            val worker = AgentTeamMemberWorker { executions++; AgentSubagentOutput("complete") }
            AgentTeamExecutionRuntime(store).use { runtime ->
                repeat(10) { index ->
                    assertTrue(policy.mayAttempt("run"))
                    val handle = if (index == 0) runtime.start(definition, request, worker)
                        else runtime.resume(requireNotNull(store.resumeCheckpoint("run")), worker)
                    watchAgentTeamExecution(handle, onSettled = {}, onReleased = {
                        assertFalse("Release must not immediately retry", policy.mayAttempt("run"))
                    }, onFailed = { policy.failed(requireNotNull(store.snapshot("run")), it) }).join()
                    fixture.now += 60_000
                }
                assertEquals(0, executions)
                assertEquals(10, policy.state("run").failures)
                assertFalse(policy.mayAttempt("run"))
                fail = false
                policy.reset("run")
                val result = runtime.resume(requireNotNull(store.resumeCheckpoint("run")), worker).await()
                policy.observed(result.snapshot)
                assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
                assertEquals(1, executions)
                assertEquals(0, policy.state("run").failures)
            }
        }
    }
}
