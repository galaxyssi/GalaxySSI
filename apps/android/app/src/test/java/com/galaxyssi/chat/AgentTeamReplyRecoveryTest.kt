package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

class AgentTeamReplyRecoveryTest {
    private val request = AgentRunRequest("group", "turn", "task", "parent", goal = "Long goal", idempotencyKey = "intent")
    private val member = AgentTeamMember("codex", AgentDeliveryMode.OBSERVE, instanceId = "researcher")
    private val definition = AgentTeamDefinition("team", "lead", listOf(member,
        AgentTeamMember("lead", AgentDeliveryMode.RESPOND, dependsOnAgentIds = setOf("researcher"))))
    private val owner = stableAgentTeamMemberRunId(request.runId, member.memberId)
    private val source = AgentTeamDispatchIds.sourceMessageId("member:${request.idempotencyKey}:${member.memberId}")
    private val delivery = AgentPendingDelivery(source, "group", "turn", "remote-task", "paired-codex")

    private suspend fun seed(): InMemoryAgentTeamExecutionStore = InMemoryAgentTeamExecutionStore().apply {
        create(definition, request)
        append(AgentSubagentEvent(1, request.runId, member.memberId, AgentSubagentEventKinds.CHILD_RUNNING,
            childStatus = AgentSubagentStatus.RUNNING))
        markInterrupted(request.runId)
    }

    @Test fun crashAfterDispatchBeforeRegistrationRecoversOriginalResultWithoutReexecution() = runBlocking {
        val store = seed()
        val ledger = InMemoryAgentManagedResponseLedger()
        val checkpoint = requireNotNull(store.deliveryCheckpoint(request.runId))
        val team = requireNotNull(store.snapshot(request.runId))
        assertNull(store.resumeCheckpoint(request.runId))
        assertEquals(1, AgentTeamReplyRecovery.restore(team, checkpoint, ledger, AgentTeamUserControl.RUN, { false }) { _, _ -> delivery })
        assertEquals(0, AgentTeamReplyRecovery.restore(team, checkpoint, ledger, AgentTeamUserControl.RUN, { false }) { _, _ -> delivery })
        val response = AgentConnectorResponse(source, delivery.contactId, "original evidence", conversationId = "group",
            turnId = "turn", taskId = "remote-task")
        val recovered = requireNotNull(ledger.complete(response))
        assertTrue(store.applyLateResponse(recovered))
        ledger.markApplied(owner)
        val invoked = mutableListOf<String>()
        val runtime = AgentTeamExecutionRuntime(store)
        try {
            val result = withTimeout(5_000) { runtime.resume(requireNotNull(store.resumeCheckpoint(request.runId))) {
                invoked += it.member.memberId
                assertEquals("original evidence", it.handoff.dependencies.single().output)
                AgentSubagentOutput("final")
            }.await() }
            assertEquals(listOf("lead"), invoked)
            assertEquals(AgentTeamExecutionState.SUCCEEDED, result.snapshot.state)
        } finally { runtime.close() }
    }

    @Test fun stopsPausesUndispatchedAndForeignIdentitiesNeverCreateReceiveIntent() = runBlocking {
        val store = seed()
        val team = requireNotNull(store.snapshot(request.runId))
        val checkpoint = requireNotNull(store.deliveryCheckpoint(request.runId))
        val ledger = InMemoryAgentManagedResponseLedger()
        for (control in listOf(AgentTeamUserControl.STOP, AgentTeamUserControl.PAUSE))
            assertEquals(0, AgentTeamReplyRecovery.restore(team, checkpoint, ledger, control, { false }) { _, _ -> delivery })
        assertEquals(0, AgentTeamReplyRecovery.restore(team, checkpoint, ledger, AgentTeamUserControl.RUN, { true }) { _, _ -> delivery })
        for (wire in listOf(delivery.copy(sourceMessageId = source + 1), delivery.copy(conversationId = "foreign"),
            delivery.copy(turnId = "foreign"), delivery.copy(taskId = ""), delivery.copy(recoverySuccessorSourceMessageId = 99)))
            assertEquals(0, AgentTeamReplyRecovery.restore(team, checkpoint, ledger, AgentTeamUserControl.RUN, { false }) { _, _ -> wire })
        for (state in listOf(AgentTeamExecutionState.SUCCEEDED, AgentTeamExecutionState.CANCELLED, AgentTeamExecutionState.FAILED))
            assertEquals(0, AgentTeamReplyRecovery.restore(team.copy(state = state), checkpoint, ledger, AgentTeamUserControl.RUN,
                { false }) { _, _ -> delivery })
        assertNull(ledger.findOwner(owner))
    }

    @Test fun transportReceiptCannotReplaceMissingSupervisorResult() = runBlocking {
        val store = seed()
        val checkpoint = requireNotNull(store.deliveryCheckpoint(request.runId))
        val team = requireNotNull(store.snapshot(request.runId))
        val record = AgentManagedResponseRecord(owner, request.runId, member.agentId, member.deliveryMode, source,
            delivery.contactId, "group", "turn", "remote-task")
        assertTrue(AgentTeamReplyRecovery.awaitsResult(team, checkpoint, record, AgentTeamUserControl.RUN))
        assertFalse(AgentTeamReplyRecovery.awaitsResult(team, checkpoint, record.copy(ownerRunId = "foreign"), AgentTeamUserControl.RUN))
        assertFalse(AgentTeamReplyRecovery.awaitsResult(team, checkpoint, record.copy(turnId = "foreign"), AgentTeamUserControl.RUN))
        assertFalse(AgentTeamReplyRecovery.awaitsResult(team, checkpoint, record, AgentTeamUserControl.STOP))
        assertFalse(AgentTeamReplyRecovery.awaitsResult(team.copy(state = AgentTeamExecutionState.SUCCEEDED), checkpoint, record, AgentTeamUserControl.RUN))
    }

    @Test fun lateDispatchReceiptNeverErasesCompletedOrAppliedBody() {
        val ledger = InMemoryAgentManagedResponseLedger()
        val record = AgentManagedResponseRecord(owner, request.runId, member.agentId, member.deliveryMode, source,
            delivery.contactId, "group", "turn", "remote-task")
        ledger.register(record)
        ledger.complete(AgentConnectorResponse(source, delivery.contactId, "fast reply", conversationId = "group", turnId = "turn", taskId = "remote-task"))
        ledger.register(record)
        assertEquals("fast reply", ledger.findOwner(owner)?.response?.content)
        ledger.markApplied(owner)
        ledger.register(record)
        assertEquals(AgentManagedResponseState.APPLIED, ledger.findOwner(owner)?.state)
        assertNull(ledger.findOwner(owner)?.response)
        assertThrows(IllegalArgumentException::class.java) { ledger.register(record.copy(contactId = "foreign")) }
    }

    @Test fun managedIntentUsesActualWireTaskAndStableOriginalOwnership() {
        val child = request.copy(runId = owner, parentRunId = request.runId,
            idempotencyKey = "${request.idempotencyKey}:${member.memberId}", context = mapOf("managed_team" to true))
        val action = AgentAction("action", AgentActionKind.CALL_CONNECTOR, "Codex", AgentRisk.LOW,
            status = AgentActionStatus.RUNNING, description = "Assignment", parameters = mapOf(MANAGED_AGENT_TEAM_ACTION_PARAMETER to "true",
                "agent_instance_id" to member.memberId, "idempotency_key" to child.idempotencyKey))
        val bound = AgentManagedDispatchIntent.bind(action, child, member.agentId)
        val intent = requireNotNull(AgentManagedDispatchIntent.record(bound, source, delivery.contactId, "group", "turn", "remote-task"))
        assertEquals(owner, intent.ownerRunId)
        assertEquals(request.runId, intent.supervisorRunId)
        assertEquals("remote-task", intent.taskId)
        assertThrows(IllegalArgumentException::class.java) {
            AgentManagedDispatchIntent.record(bound, source + 1, delivery.contactId, "group", "turn", "remote-task")
        }
        assertNull(AgentManagedDispatchIntent.record(action, source, delivery.contactId, "group", "turn", "remote-task"))
    }
}
