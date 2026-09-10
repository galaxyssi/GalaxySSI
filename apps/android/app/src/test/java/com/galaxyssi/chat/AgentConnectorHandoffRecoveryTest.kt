package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentConnectorHandoffRecoveryTest {
    private val action = AgentAction("connector-codex", AgentActionKind.CALL_CONNECTOR, "Codex", AgentRisk.LOW,
        AgentActionStatus.WAITING_RESPONSE, "Test", mapOf("prompt" to "Math", "connector_id" to "codex"), false)
    private val context = AgentNativeToolInvocationContext(sessionId = "session", conversationId = "chat", turnId = "turn")

    @Test fun recoveryHasIndependentStableReceiptWithoutWeakeningInputChecks() {
        val store = InMemoryAgentNativeToolReplayStore()
        val executor = AgentActionEffectExecutor(store)
        var calls = 0
        val delegate = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext) =
                AgentActionResult(action.id, true, "Accepted ${++calls}", mapOf("awaiting_response" to "true"))
        }
        val screen = ScreenContext("Test", pageTitle = "Test")
        val retry = AgentConnectorHandoffRecovery.prepare(action, 123, 1, "session")
        assertNotEquals(AgentConnectorHandoffRecovery.effectAttemptKey(action), AgentConnectorHandoffRecovery.effectAttemptKey(retry))
        assertTrue(executor.execute(action, screen, context, delegate).success)
        assertTrue(executor.execute(retry, screen, context, delegate).success)
        assertEquals("Accepted 2", AgentActionEffectExecutor(store).execute(retry, screen, context, delegate).message)
        val changed = retry.copy(parameters = retry.parameters + ("prompt" to "Different task"))
        assertEquals("idempotency_key_conflict", executor.execute(changed, screen, context, delegate).metadata["error_code"])
        assertEquals(2, calls)
    }

    @Test fun recoveryDoesNotLeakIntoOtherActionsOrOtherConversations() {
        val retry = AgentConnectorHandoffRecovery.prepare(action, 123, 1, "session")
        assertEquals("other", AgentConnectorHandoffRecovery.effectAttemptKey(retry.copy(id = "other")))
        assertEquals(action.id, AgentConnectorHandoffRecovery.effectAttemptKey(retry.copy(kind = AgentActionKind.TYPE_TEXT)))
        val store = InMemoryAgentNativeToolReplayStore()
        val executor = AgentActionEffectExecutor(store)
        val delegate = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext) = AgentActionResult(action.id, true, "Receipt")
        }
        executor.execute(retry, ScreenContext("Test", pageTitle = "Test"), context, delegate)
        assertNotNull(executor.dispatchedResult(retry, context))
        assertNull(executor.dispatchedResult(retry, context.copy(conversationId = "other")))
        assertNull(executor.dispatchedResult(retry, context.copy(turnId = "other")))
    }

    @Test fun knownDesktopAndUnknownDesktopStateRequireObservationNotRedispatch() {
        assertTrue(AgentConnectorHandoffRecovery.requiresRemoteObservation(emptyMap(), true))
        assertTrue(AgentConnectorHandoffRecovery.requiresRemoteObservation(mapOf("resource_location" to "desktop"), false))
        for (status in listOf("accepted", "queued", "starting", "recovering", "running", "waiting_input",
            "waiting_approval", "completed", "failed", "timed_out", "cancelled")) {
            assertTrue(status, AgentConnectorHandoffRecovery.requiresRemoteObservation(mapOf("remote_task_status" to status), false))
        }
        assertFalse(AgentConnectorHandoffRecovery.requiresRemoteObservation(emptyMap(), false))
    }

    @Test fun onlyAnUnresolvedTimeoutWithFallbackNeedsAnExtraObservation() {
        val fallback = mapOf("remaining_fallback_ids" to "cloud:deepseek")
        for (stage in listOf(AgentConnectorTimeoutStage.NOT_ACCEPTED, AgentConnectorTimeoutStage.NOT_RUNNING)) {
            assertTrue(AgentConnectorHandoffRecovery.needsPreTimeoutObservation(fallback, stage))
            assertFalse(AgentConnectorHandoffRecovery.needsPreTimeoutObservation(emptyMap(), stage))
            assertFalse(AgentConnectorHandoffRecovery.needsPreTimeoutObservation(
                mapOf("remaining_fallback_ids" to " , "), stage))
            for (status in listOf("running", "completed", "failed", "timed_out", "cancelled")) {
                assertFalse(status, AgentConnectorHandoffRecovery.needsPreTimeoutObservation(
                    fallback + ("remote_task_status" to status), stage))
            }
        }
        for (status in listOf("accepted", "queued", "starting")) {
            val pending = fallback + ("remote_task_status" to status)
            assertFalse(AgentConnectorHandoffRecovery.needsPreTimeoutObservation(pending, AgentConnectorTimeoutStage.NOT_ACCEPTED))
            assertTrue(AgentConnectorHandoffRecovery.needsPreTimeoutObservation(pending, AgentConnectorTimeoutStage.NOT_RUNNING))
        }
        assertFalse(AgentConnectorHandoffRecovery.needsPreTimeoutObservation(
            fallback + ("remote_task_status" to "running"), AgentConnectorTimeoutStage.READ_ONLY_STALE))
    }

    @Test fun tenConcurrentScopesKeepPrimaryRetryAndFallbackReceiptsIndependent() {
        val store = InMemoryAgentNativeToolReplayStore()
        val executor = AgentActionEffectExecutor(store)
        val calls = java.util.concurrent.atomic.AtomicInteger()
        val workers = java.util.concurrent.Executors.newFixedThreadPool(10)
        val gate = java.util.concurrent.CountDownLatch(1)
        val delegate = object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                calls.incrementAndGet()
                return AgentActionResult(action.id, true, action.parameters.getValue("prompt"))
            }
        }
        try {
            val jobs = (1..10).map { index -> workers.submit {
                gate.await()
                val scope = context.copy(sessionId = "session-$index", conversationId = "chat-$index", turnId = "turn-$index")
                val primary = action.copy(parameters = action.parameters + ("prompt" to "Task $index"))
                val recovery = AgentConnectorHandoffRecovery.prepare(primary, index.toLong(), 1, scope.sessionId)
                val fallback = AgentConnectorFallbackAction.prepare(primary,
                    AgentConnectorFallbackSelection("deepseek", emptyList(), emptyList(), emptySet(), setOf("codex")), null)
                listOf(primary, recovery, fallback).forEach { step ->
                    assertEquals("Task $index", executor.execute(step, ScreenContext("Test", pageTitle = "Test"), scope, delegate).message)
                    val restored = AgentActionEffectExecutor(store).execute(step, ScreenContext("Test", pageTitle = "Test"), scope, delegate)
                    assertEquals("Task $index", restored.message)
                    assertEquals("true", restored.metadata["action_effect_replayed"])
                }
            } }
            gate.countDown()
            jobs.forEach { it.get(20, java.util.concurrent.TimeUnit.SECONDS) }
            assertEquals(30, calls.get())
        } finally {
            workers.shutdownNow()
            assertTrue(workers.awaitTermination(20, java.util.concurrent.TimeUnit.SECONDS))
        }
    }
}
