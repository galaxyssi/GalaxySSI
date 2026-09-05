package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRunKernelContractTest {
    @Test
    fun canonicalEventPopulatesPortableIdentityWithoutChangingLegacyCallers() {
        val canonical = AgentRunKernelContract.canonical(event())

        assertEquals(AGENT_RUN_EVENT_PROTOCOL, canonical.protocolId)
        assertEquals(AGENT_RUN_EVENT_SCHEMA_VERSION, canonical.schemaVersion)
        assertEquals("event-1", canonical.idempotencyKey)
        assertEquals("phone-s26u", canonical.clientRouteId)
        assertEquals("task-1", canonical.goalId)
        assertEquals("message-1", canonical.turnId)
        assertEquals("step-1", canonical.actionId)
    }

    @Test
    fun rootIdentityIncludesRouteConversationGoalTaskAndRun() {
        val identity = AgentRunKernelContract.rootIdentity(event())

        assertEquals("phone-s26u", identity.clientRouteId)
        assertEquals("conversation-1", identity.conversationId)
        assertEquals("task-1", identity.goalId)
        assertEquals("task-1", identity.taskId)
        assertEquals("run-1", identity.runId)
    }

    @Test
    fun crossRouteOrConversationEventIsRejectedBeforeAppend() {
        val failure = runCatching {
            AgentRunKernelContract.requireSameRoot(
                event(),
                event().copy(
                    eventId = "event-2",
                    clientRouteId = "phone-s20u",
                    conversationId = "conversation-2"
                )
            )
        }.exceptionOrNull()

        assertTrue(failure is IllegalArgumentException)
        assertTrue(failure?.message.orEmpty().contains("Run root identity changed"))
    }

    @Test
    fun interruptedRunRemainsRecoverableInsteadOfBecomingTerminal() {
        assertEquals(
            AgentRunControlState.PAUSED,
            AgentRunEventStore.reduce(
                AgentRunControlState.RUNNING,
                AgentRunControlEventType.RUN_INTERRUPTED
            )
        )
        assertEquals(
            AgentRunControlState.RUNNING,
            AgentRunEventStore.reduce(
                AgentRunControlState.PAUSED,
                AgentRunControlEventType.RUN_RECOVERED
            )
        )
    }

    @Test
    fun savingCheckpointDoesNotResumePausedOrWaitingRuns() {
        AgentRunControlState.entries.forEach { state ->
            assertEquals(
                state,
                AgentRunEventStore.reduce(state, AgentRunControlEventType.CHECKPOINT_SAVED)
            )
        }
    }

    @Test
    fun identityNormalizationMatchesTrimmedDatabaseLookupKeys() {
        val original = event()
        val normalized = AgentRunKernelContract.canonical(original.copy(
            eventId = " event-1 ", runId = " run-1 ", taskId = " task-1 ",
            deviceId = " phone-s26u ", agentId = " codex ",
            conversationId = " conversation-1 ", turnId = " message-1 ", actionId = " step-1 "
        ))
        assertEquals(AgentRunKernelContract.canonical(original), normalized)
    }

    private fun event() = AgentRunControlEvent(
        eventId = "event-1",
        conversationId = "conversation-1",
        messageId = "message-1",
        taskId = "task-1",
        runId = "run-1",
        stepId = "step-1",
        agentId = "codex",
        deviceId = "phone-s26u",
        type = AgentRunControlEventType.RUN_STARTED,
        sequence = 1L
    )
}
