package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class AgentTeamDurableRecoveryTest {
    private val request = AgentRunRequest(conversationId = "recovery-conversation", messageId = "recovery-turn",
        taskId = "recovery-turn", runId = "recovery-run", goal = "Compare evidence", idempotencyKey = "recovery-key")
    private val definition = AgentTeamDefinition(teamId = "recovery-team", primaryAgentId = "lead", members = listOf(
        AgentTeamMember("researcher", AgentDeliveryMode.OBSERVE),
        AgentTeamMember("lead", AgentDeliveryMode.RESPOND, dependsOnAgentIds = setOf("researcher"))))

    private suspend fun seed(store: AgentTeamExecutionStore, status: AgentSubagentStatus = AgentSubagentStatus.SUCCEEDED) {
        store.create(definition, request)
        store.append(AgentSubagentEvent(1, request.runId, kind = AgentSubagentEventKinds.SUPERVISOR_STARTED))
        store.append(AgentSubagentEvent(2, request.runId, "researcher", AgentSubagentEventKinds.CHILD_SUCCEEDED,
            childStatus = status, result = if (status.isTerminal) AgentSubagentChildResult(
                supervisorId = request.runId, childId = "researcher", parentId = request.runId, depth = 1,
                status = status, output = "persisted evidence", startedAtMillis = 1, completedAtMillis = 2) else null))
        store.markInterrupted(request.runId)
    }

    @Test fun resumeUsesCompletedEvidenceWithoutReplayingWorker() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        seed(store)
        val checkpoint = requireNotNull(store.resumeCheckpoint(request.runId))
        val invoked = mutableListOf<String>()
        val runtime = AgentTeamExecutionRuntime(store)
        try {
            val result = withTimeout(5_000) { runtime.resume(checkpoint) {
                invoked += it.member.memberId
                assertEquals("persisted evidence", it.handoff.dependencies.single().output)
                AgentSubagentOutput("verified final")
            }.await() }
            assertEquals(listOf("lead"), invoked)
            assertEquals("verified final", result.finalOutput)
            assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
            assertEquals(0L, result.snapshot.interruptedAtMillis)
            assertEquals(store.records().single().events.size, store.records().single().events.map { it.sequence }.distinct().size)
        } finally { runtime.close() }
    }

    @Test fun runningRemoteMemberMustReturnBeforeQueuedWorkCanResume() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        seed(store, AgentSubagentStatus.RUNNING)
        assertNull(store.resumeCheckpoint(request.runId))
        store.applyLateResponse(AgentManagedResponseRecord(
            stableAgentTeamMemberRunId(request.runId, "researcher"), request.runId, "researcher",
            AgentDeliveryMode.OBSERVE, 90L, "researcher", response = AgentConnectorResponse(90L, "researcher", "evidence")))
        assertNotNull(store.resumeCheckpoint(request.runId))
    }

    @Test fun onlyVersionedUndispatchedWaitsAreRequeuedAfterProcessDeath() = runBlocking {
        for (version in listOf("", "2")) {
            val store = InMemoryAgentTeamExecutionStore()
            store.create(definition, request.copy(context = mapOf("collaboration_research_recovery_version" to version)))
            store.append(AgentSubagentEvent(1, request.runId, "researcher", AgentSubagentEventKinds.CHILD_RUNNING,
                childStatus = AgentSubagentStatus.RUNNING))
            store.markInterrupted(request.runId)
            store.requeueUndispatched(request.runId) { false }
            assertNull(store.resumeCheckpoint(request.runId))
            store.requeueUndispatched(request.runId) { true }
            assertEquals(version == "2", store.resumeCheckpoint(request.runId) != null)
        }
    }

    @Test fun terminalTeamsCannotBeRestartedAsRecovery() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        val runtime = AgentTeamExecutionRuntime(store)
        try {
            runtime.start(definition, request) { AgentSubagentOutput("done") }.await()
            assertNull(store.resumeCheckpoint(request.runId))
        } finally { runtime.close() }
    }

    @Test fun cancelledCheckpointDoesNotBecomeResumable() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        seed(store)
        store.append(AgentSubagentEvent(3, request.runId, kind = AgentSubagentEventKinds.SUPERVISOR_CANCELLED,
            runStatus = AgentSubagentRunStatus.CANCELLED))
        assertNull(store.resumeCheckpoint(request.runId))
    }

    @Test fun backoffNeverBecomesHotLoopOrStopsAfterManyAttempts() {
        assertEquals(listOf(1000L, 2000L, 4000L, 8000L), (0..3).map(AgentTeamReconnectPolicy::delayMillis))
        assertEquals(60_000L, AgentTeamReconnectPolicy.delayMillis(100_000))
        assertTrue((0..1000).all { AgentTeamReconnectPolicy.delayMillis(it) in 1000L..60_000L })
    }

    @Test fun remoteStopRequiresExactPersistedMemberOwnership() = runBlocking {
        val store = InMemoryAgentTeamExecutionStore()
        seed(store, AgentSubagentStatus.RUNNING)
        val team = requireNotNull(store.snapshot(request.runId))
        val record = AgentManagedResponseRecord(stableAgentTeamMemberRunId(request.runId, "researcher"),
            request.runId, "researcher", AgentDeliveryMode.OBSERVE, 90L, "paired-desktop",
            conversationId = request.conversationId, turnId = "member-turn", taskId = "remote-task")
        assertTrue(AgentTeamRemoteStopPolicy.owns(team, record))
        assertFalse(AgentTeamRemoteStopPolicy.owns(team, record.copy(ownerRunId = "unrelated")))
        assertFalse(AgentTeamRemoteStopPolicy.owns(team, record.copy(conversationId = "other")))
        assertFalse(AgentTeamRemoteStopPolicy.owns(team, record.copy(taskId = "")))
        assertFalse(AgentTeamRemoteStopPolicy.owns(team, record.copy(state = AgentManagedResponseState.COMPLETED)))
    }

    @Test fun remoteStopIsRateLimitedUntilTerminalReceipt() {
        assertTrue(AgentTeamRemoteStopPolicy.due(0, 100_000))
        assertFalse(AgentTeamRemoteStopPolicy.due(100_000, 159_999))
        assertTrue(AgentTeamRemoteStopPolicy.due(100_000, 160_000))
        assertTrue(AgentTeamRemoteStopPolicy.due(100_000, 99_000))
    }

    @Test fun offlineWaitReleasesTheOnlyPermitForOtherMembers() = runBlocking {
        val healthyFinished = kotlinx.coroutines.CompletableDeferred<Unit>()
        val team = definition.copy(members = listOf(AgentTeamMember("slow", AgentDeliveryMode.OBSERVE),
            AgentTeamMember("healthy", AgentDeliveryMode.OBSERVE), AgentTeamMember("lead", AgentDeliveryMode.RESPOND)))
        val runtime = AgentTeamExecutionRuntime(InMemoryAgentTeamExecutionStore(), AgentSubagentLimits(maxConcurrency = 1))
        try {
            val result = withTimeout(5000) { runtime.start(team, request) {
                when (it.member.memberId) {
                    "slow" -> it.suspendExecutionPermit { healthyFinished.await() }
                    "healthy" -> healthyFinished.complete(Unit)
                }
                AgentSubagentOutput("verified")
            }.await() }
            assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
        } finally { runtime.close() }
    }

    @Test fun localParentsAreNeverDesktopContacts() {
        assertTrue(AgentTeamParentDeliveryPolicy.isLocalTeam(AgentTeamDispatchIds.responseContactId("team")))
        assertFalse(AgentTeamParentDeliveryPolicy.isLocalTeam("desktop:agent"))
        assertFalse(AgentTeamParentDeliveryPolicy.isLocalTeam("cloud:deepseek"))
    }

    private fun snapshot() = AgentTeamExecutionSnapshot(request.runId, definition.teamId, request.conversationId,
        request.taskId, "lead", request.goal, AgentTeamVisibilityMode.VISIBLE, AgentTeamExecutionState.SUCCEEDED,
        emptyList(), createdAtMillis = 100)
    private fun workspace() = AgentWorkspace(request.taskId, "task:${request.taskId}", request.conversationId,
        request.taskId, status = AgentWorkspaceStatus.FAILED, errorMessage = "offline")
    private fun terminal() = AgentTerminalDelivery(AgentTeamDispatchIds.sourceMessageId(request.runId), request.conversationId,
        request.taskId, request.taskId, AgentTeamDispatchIds.responseContactId(definition.teamId), "offline", 200)

    @Test fun onlyExactKnownFalseFailureMayBeRepaired() {
        assertTrue(AgentTeamParentDeliveryPolicy.mayRepair(snapshot(), workspace(), terminal(), true))
        assertTrue(AgentTeamParentDeliveryPolicy.mayRepair(snapshot(), workspace().copy(status = AgentWorkspaceStatus.WAITING_RESPONSE), terminal(), true))
        assertFalse(AgentTeamParentDeliveryPolicy.mayRepair(snapshot(), workspace(), terminal(), false))
        assertFalse(AgentTeamParentDeliveryPolicy.mayRepair(snapshot(), workspace(), terminal().copy(turnId = "new"), true))
        assertFalse(AgentTeamParentDeliveryPolicy.mayRepair(snapshot(), workspace(), terminal().copy(contactId = "desktop"), true))
        assertFalse(AgentTeamParentDeliveryPolicy.mayRepair(snapshot(), workspace(), terminal().copy(sourceMessageId = 1), true))
    }

    @Test fun explicitPauseStopAndOtherFailuresCannotBeCleared() {
        assertFalse(AgentTeamParentDeliveryPolicy.mayRepair(snapshot(), workspace().copy(cancellationRequested = true), terminal(), true))
        assertFalse(AgentTeamParentDeliveryPolicy.mayRepair(snapshot(), workspace().copy(status = AgentWorkspaceStatus.PAUSED), terminal(), true))
        assertFalse(AgentTeamParentDeliveryPolicy.mayRepair(snapshot().copy(state = AgentTeamExecutionState.CANCELLED), workspace(), terminal(), true))
        assertFalse(AgentTeamParentDeliveryPolicy.mayRepair(snapshot(), workspace().copy(errorMessage = "user stopped"), terminal(), true))
    }

    @Test fun observedResponseStaysDurableUntilTeamCheckpointAcknowledgesIt() {
        val ledger = InMemoryAgentManagedResponseLedger()
        ledger.register(AgentManagedResponseRecord("child", request.runId, "researcher", AgentDeliveryMode.OBSERVE,
            91L, "researcher"))
        ledger.acknowledge(AgentConnectorResponse(91L, "researcher", "keep this evidence"))
        assertEquals("keep this evidence", ledger.completedUnapplied().single().response?.content)
        ledger.markApplied("child")
        assertTrue(ledger.completedUnapplied().isEmpty())
    }
}
