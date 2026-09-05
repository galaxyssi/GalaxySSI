package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentEvalRunEventsTest {
    private val run = AgentRecordedRun("run", "conversation", "task", "private request")
    private val type = AgentRunControlEventType.RUN_FAILED

    @Test fun interruptionBeforeProviderSelectionUsesExplicitObserver() {
        val event = AgentEvalRunEvents.create(run, null, type, mapOf("reason" to "process death"))
        assertEquals(AgentEvalRunEvents.OBSERVER, event.agentId)
        assertEquals(true, event.payload["execution_resource_unassigned"])
        assertEquals(true, event.payload["observation_only"])
        assertEquals(event, AgentRunKernelContract.canonical(event))
        assertFalse(event.payload.toString().contains(run.originalRequest))
    }

    @Test fun selectedResourceIsNotReplacedByObserver() {
        val event = AgentEvalRunEvents.create(run.copy(executionResourceId = "codex"), null, type, emptyMap())
        assertEquals("codex", event.agentId)
        assertEquals(false, event.payload["execution_resource_unassigned"])
    }

    @Test fun existingRootTurnAndAgentRemainExactDespiteStaleRecorder() {
        val prior = AgentRunControlEvent(conversationId = "original-conversation", messageId = "message",
            taskId = "original-task", runId = "run", agentId = "hermes", deviceId = "original-phone",
            clientRouteId = "route", goalId = "goal", turnId = "turn", sequence = 3L,
            type = AgentRunControlEventType.RUN_STARTED, payload = mapOf("old_snapshot" to "private"))
        val event = AgentEvalRunEvents.create(run, prior, type, mapOf("condition" to "process_death"))
        AgentRunKernelContract.requireSameRoot(prior, event)
        assertEquals(prior.turnId, event.turnId)
        assertEquals(prior.messageId, event.messageId)
        assertEquals(prior.agentId, event.agentId)
        assertNotEquals(prior.eventId, event.eventId)
        assertEquals(0L, event.sequence)
        assertFalse(event.payload.containsKey("old_snapshot"))
    }

    @Test fun anotherRunCannotSupplyRecoveryIdentity() {
        val prior = AgentEvalRunEvents.create(run, null, type, emptyMap()).copy(runId = "other")
        assertTrue(runCatching { AgentEvalRunEvents.create(run, prior, type, emptyMap()) }.isFailure)
    }

    @Test fun missingLegacyTaskGetsStableObserverTaskButMissingRunIsRejected() {
        val event = AgentEvalRunEvents.create(run.copy(taskThreadId = "", conversationId = ""), null, type, emptyMap())
        assertEquals("eval-task:run", event.taskId)
        assertTrue(event.conversationId.isNotBlank())
        assertTrue(runCatching { AgentEvalRunEvents.create(run.copy(runId = ""), null, type, emptyMap()) }.isFailure)
    }

    @Test fun eachObservationHasAnIndependentEventIdentity() {
        val first = AgentEvalRunEvents.create(run, null, type, emptyMap())
        val second = AgentEvalRunEvents.create(run, first, AgentRunControlEventType.RUN_RECOVERED, emptyMap())
        assertNotEquals(first.idempotencyKey, second.idempotencyKey)
        assertNotEquals(first.actionId, second.actionId)
    }
}
