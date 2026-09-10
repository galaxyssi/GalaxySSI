package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class AgentActionEffectExecutorTest {
    private val store = InMemoryAgentNativeToolReplayStore()
    private val executor = AgentActionEffectExecutor(store)
    private val screen = ScreenContext("Test", pageTitle = "Test")
    private val action = AgentAction("action-1", AgentActionKind.CALL_CONNECTOR, "test-connector",
        AgentRisk.LOW, AgentActionStatus.RUNNING, "Test request", mapOf("prompt" to "hello"), false)
    private val context = AgentNativeToolInvocationContext(invocationId = "first", sessionId = "session",
        conversationId = "conversation", turnId = "turn", attributes = mapOf(
            "client_route_id" to "device", "task_id" to "task", "goal_id" to "goal"))

    @Test fun dispatchReceiptRetainsAwaitingResponseAndAllOriginalMetadata() {
        val expected = AgentActionResult(action.id, true, "Accepted", mapOf("awaiting_response" to "true",
            "run_id" to "remote-run", "request_id" to "request", "artifacts" to "[{\"path\":\"test.html\"}]"))
        var calls = 0
        val delegate = delegate { _, _ -> calls++; expected }
        assertEquals(expected, executor.execute(action, screen, context, delegate))
        val replay = executor.execute(action.copy(status = AgentActionStatus.WAITING_RESPONSE, result = "Changed UI"),
            screen.copy(pageTitle = "Other screen"), context.copy(invocationId = "recovery"), delegate)
        assertEquals(expected.message, replay.message)
        expected.metadata.forEach { (key, value) -> assertEquals(value, replay.metadata[key]) }
        assertEquals("true", replay.metadata["action_effect_replayed"])
        assertEquals(1, calls)
    }

    @Test fun missingCommitReturnsUnknownAndNeverDispatchesTheSameActionAgain() {
        val faulty = object : AgentNativeToolReplayStore by store {
            override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                error("Receipt disk failure")
            }
        }
        var calls = 0
        val delegate = delegate { _, _ -> calls++; AgentActionResult(action.id, true, "Written") }
        val first = AgentActionEffectExecutor(faulty).execute(action, screen, context, delegate)
        assertEquals("effect_outcome_unknown", first.metadata["error_code"])
        val replay = executor.execute(action, screen, context.copy(invocationId = "after"), delegate)
        assertEquals("effect_outcome_unknown", replay.metadata["error_code"])
        assertEquals(1, calls)
    }

    @Test fun unreadableJournalFailsBeforeDispatch() {
        val faulty = object : AgentNativeToolReplayStore by store {
            override fun observe(key: AgentNativeToolReplayKey): AgentNativeEffectClaim? = error("Corrupt journal")
        }
        val result = AgentActionEffectExecutor(faulty).execute(action, screen, context, delegate { _, _ -> error("Must not dispatch") })
        assertEquals("action_effect_journal_unavailable", result.metadata["error_code"])
        assertTrue(result.message.contains("Corrupt journal"))
    }

    @Test fun changedParametersOrActionKindCannotReuseTheSameActionIdentity() {
        var calls = 0
        val delegate = delegate { a, _ -> calls++; AgentActionResult(a.id, true, "Done") }
        executor.execute(action, screen, context, delegate)
        listOf(action.copy(parameters = mapOf("prompt" to "different")),
            action.copy(kind = AgentActionKind.TYPE_TEXT), action.copy(target = "another-connector")).forEach {
            assertEquals("idempotency_key_conflict", executor.execute(it, screen, context, delegate).metadata["error_code"])
        }
        assertEquals(1, calls)
    }

    @Test fun everyExecutionScopeDimensionKeepsIndependentActionsSeparate() {
        var calls = 0
        val delegate = delegate { a, _ -> calls++; AgentActionResult(a.id, true, "Done") }
        val contexts = listOf(context, context.copy(sessionId = "other"), context.copy(conversationId = "other"),
            context.copy(turnId = "other")) + listOf("client_route_id", "task_id", "goal_id").map {
            context.copy(attributes = context.attributes + (it to "other"))
        }
        contexts.forEach { assertTrue(executor.execute(action, screen, it, delegate).success) }
        assertEquals(contexts.size, calls)
    }

    @Test fun failureIsReplayedAndADeliberateNewActionCanRepairIt() {
        var calls = 0
        val delegate = delegate { a, _ ->
            calls++
            if (calls == 1) AgentActionResult(a.id, false, "Original platform error", mapOf("error_code" to "actual_error"))
            else AgentActionResult(a.id, true, "Repaired")
        }
        val failed = executor.execute(action, screen, context, delegate)
        val replay = executor.execute(action, screen, context.copy(invocationId = "retry"), delegate)
        assertFalse(replay.success)
        assertEquals(failed.message, replay.message)
        assertEquals("actual_error", replay.metadata["error_code"])
        assertEquals(1, calls)
        assertTrue(executor.execute(action.copy(id = "new-repair"), screen, context, delegate).success)
        assertEquals(2, calls)
    }

    @Test fun pureScreenReadsDoNotLoadOrClaimTheEffectJournal() {
        var calls = 0
        val faulty = object : AgentNativeToolReplayStore by store {
            override fun observe(key: AgentNativeToolReplayKey): AgentNativeEffectClaim? = error("Read must stay fresh")
        }
        val read = action.copy(kind = AgentActionKind.READ_SCREEN)
        val delegate = delegate { a, _ -> AgentActionResult(a.id, true, (++calls).toString()) }
        val reader = AgentActionEffectExecutor(faulty)
        assertEquals("1", reader.execute(read, screen, context, delegate).message)
        assertEquals("2", reader.execute(read, screen, context, delegate).message)
    }

    @Test fun simultaneousDuplicateIsNotDispatchedAndDifferentActionsAreNotGloballySerialized() {
        val workers = Executors.newFixedThreadPool(2)
        val started = CountDownLatch(2)
        val release = CountDownLatch(1)
        val calls = AtomicInteger()
        val delegate = delegate { a, _ ->
            calls.incrementAndGet(); started.countDown()
            check(release.await(10, TimeUnit.SECONDS))
            AgentActionResult(a.id, true, "Completed")
        }
        try {
            val first = workers.submit<AgentActionResult> { executor.execute(action, screen, context, delegate) }
            val second = workers.submit<AgentActionResult> { executor.execute(action.copy(id = "independent"), screen, context, delegate) }
            assertTrue(started.await(10, TimeUnit.SECONDS))
            val duplicate = executor.execute(action, screen, context.copy(invocationId = "duplicate"), delegate)
            assertEquals("effect_outcome_unknown", duplicate.metadata["error_code"])
            release.countDown()
            assertTrue(first.get(10, TimeUnit.SECONDS).success)
            assertTrue(second.get(10, TimeUnit.SECONDS).success)
            assertEquals(2, calls.get())
        } finally { release.countDown(); workers.shutdownNow(); assertTrue(workers.awaitTermination(10, TimeUnit.SECONDS)) }
    }

    @Test fun nativeActionAdapterKeepsSuccessfulOutcomeAfterLateCancellation() {
        val cancellation = AgentNativeToolCancellationSource()
        val descriptor = AgentNativeToolDescriptor("test.platform.action", "1.0.0", "Platform action", "Test platform action",
            AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
            AgentNativeToolRisk.LOW)
        var calls = 0
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor,
            AgentActionNativeToolExecutor.forKind(delegate = delegate { a, _ ->
                calls++; cancellation.cancel(); AgentActionResult(a.id, true, "Actually completed")
            }, kind = AgentActionKind.TAP, screenProvider = { screen })))
        val result = registry.invoke(descriptor.id, emptyMap(), context,
            AgentNativeToolInvocationHooks(cancellationToken = cancellation.token))
        assertTrue(result.toJson(), result.isSuccess)
        assertEquals("Actually completed", result.message)
        assertTrue(registry.invoke(descriptor.id, emptyMap(), context).receipt.replayed)
        assertEquals(1, calls)
    }

    @Test fun providerFallbackAndDeferredReturnHaveIndependentDurableReceipts() {
        val primary = action.copy(parameters = action.parameters + ("connector_id" to "codex"))
        val next = requireNotNull(AgentConnectorFallbackTrail.selectNext("codex", listOf("cloud"),
            emptyList(), emptySet(), true))
        val fallback = AgentConnectorFallbackAction.prepare(primary, next, null)
        val back = requireNotNull(AgentConnectorFallbackTrail.selectNext("cloud", next.remainingResourceIds,
            next.deferredRetryIds, next.retriedResourceIds, false, next.attemptedResourceIds))
        val returned = AgentConnectorFallbackAction.prepare(fallback, back, null)
        val calls = mutableListOf<String>()
        val delegate = delegate { a, _ ->
            calls += a.parameters.getValue("connector_id")
            AgentActionResult(a.id, true, "Accepted ${calls.size}", mapOf("awaiting_response" to "true",
                "request_id" to "request-${calls.size}"))
        }
        listOf(primary, fallback, returned).forEachIndexed { index, attempt ->
            val accepted = executor.execute(attempt, screen, context, delegate)
            assertTrue(accepted.message, accepted.success)
            assertEquals(action.id, accepted.actionId)
            assertEquals("request-${index + 1}", accepted.metadata["request_id"])
        }
        listOf(primary, fallback, returned).forEachIndexed { index, attempt ->
            val restored = AgentActionEffectExecutor(store).execute(attempt,
                screen, context.copy(invocationId = "restored"), delegate)
            assertEquals("request-${index + 1}", restored.metadata["request_id"])
            assertEquals("true", restored.metadata["action_effect_replayed"])
        }
        assertEquals(listOf("codex", "cloud", "codex"), calls)
        val changed = fallback.copy(parameters = fallback.parameters + ("prompt" to "Different effect"))
        assertEquals("idempotency_key_conflict", executor.execute(changed, screen, context, delegate).metadata["error_code"])
        assertEquals(3, calls.size)
    }

    @Test fun staleOrManualFallbackTrailCannotCreateANewEffectIdentity() {
        val fallback = AgentConnectorFallbackAction.prepare(action,
            AgentConnectorFallbackSelection("cloud", emptyList(), emptyList(), emptySet(), setOf("codex")), null)
        assertEquals("new-action", AgentConnectorFallbackAction.effectAttemptKey(fallback.copy(id = "new-action")))
        assertEquals(action.id, AgentConnectorFallbackAction.effectAttemptKey(fallback.copy(kind = AgentActionKind.TYPE_TEXT)))
        assertEquals(action.id, AgentConnectorFallbackAction.effectAttemptKey(fallback.copy(
            parameters = fallback.parameters + ("manual_target_locked" to "true"))))
        assertEquals(action.id, AgentConnectorFallbackAction.effectAttemptKey(fallback.copy(
            parameters = fallback.parameters + ("connector_id" to ""))))
    }

    @Test fun interruptedFallbackRemainsUncertainAfterRuntimeRecreation() {
        val fallback = AgentConnectorFallbackAction.prepare(action,
            AgentConnectorFallbackSelection("cloud", emptyList(), emptyList(), emptySet(), setOf("codex")), null)
        val faulty = object : AgentNativeToolReplayStore by store {
            override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                error("Commit interrupted")
            }
        }
        var calls = 0
        val delegate = delegate { a, _ -> calls++; AgentActionResult(a.id, true, "Accepted") }
        assertEquals("effect_outcome_unknown", AgentActionEffectExecutor(faulty)
            .execute(fallback, screen, context, delegate).metadata["error_code"])
        assertEquals("effect_outcome_unknown", executor.execute(fallback, screen,
            context.copy(invocationId = "restored"), delegate).metadata["error_code"])
        assertEquals(1, calls)
    }

    private fun delegate(block: (AgentAction, ScreenContext) -> AgentActionResult) = object : AgentActionExecutor {
        override fun execute(action: AgentAction, screen: ScreenContext) = block(action, screen)
    }
}
