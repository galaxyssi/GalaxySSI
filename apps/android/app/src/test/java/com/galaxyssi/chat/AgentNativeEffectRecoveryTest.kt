package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class AgentNativeEffectRecoveryTest {
    private val descriptor = AgentNativeToolDescriptor(
        id = "phone.test.effect", version = "1.0.0", title = "Effect", description = "Test effect",
        location = AgentNativeToolLocation.PHONE, inputSchema = AgentNativeJsonSchema.objectSchema(),
        outputSchema = AgentNativeJsonSchema.objectSchema(), risk = AgentNativeToolRisk.LOW,
        capabilities = setOf("phone.test"), idempotency = AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED,
        timeoutMillis = 30_000
    )
    private val scope = AgentNativeToolInvocationContext(sessionId = "session", conversationId = "conversation",
        turnId = "turn", idempotencyKey = "action", attributes = mapOf(
            "task_id" to "task", "goal_id" to "goal", "client_route_id" to "phone"))

    private fun registry(store: AgentNativeToolReplayStore, executor: AgentNativeToolExecutor) =
        AgentNativeToolRegistry(replayStore = store).register(AgentNativeToolDefinition(descriptor, executor))

    @Test fun everyScopeDimensionSeparatesIdenticalActionKeys() {
        val calls = AtomicInteger()
        val runtime = registry(InMemoryAgentNativeToolReplayStore()) {
            AgentNativeToolExecutionResult.success(mapOf("count" to calls.incrementAndGet()))
        }
        val scopes = listOf(scope, scope.copy(sessionId = "other"), scope.copy(conversationId = "other"),
            scope.copy(turnId = "other")) + listOf("task_id", "goal_id", "client_route_id").map {
            scope.copy(attributes = scope.attributes + (it to "other"))
        }
        scopes.forEach { context ->
            val first = runtime.invoke(descriptor.id, emptyMap(), context)
            val again = runtime.invoke(descriptor.id, emptyMap(), context.copy(invocationId = "replay"))
            assertTrue(first.toJson(), first.isSuccess)
            assertFalse(first.receipt.replayed)
            assertTrue(again.receipt.replayed)
            assertEquals(first.output, again.output)
        }
        assertEquals(7, calls.get())
    }

    @Test fun concurrentRegistriesCannotExecuteTheSameEffectTwice() {
        val store = InMemoryAgentNativeToolReplayStore()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val calls = AtomicInteger()
        val executor = AgentNativeToolExecutor {
            calls.incrementAndGet()
            entered.countDown()
            check(release.await(10, TimeUnit.SECONDS))
            AgentNativeToolExecutionResult.success(mapOf("saved" to true))
        }
        val worker = Executors.newSingleThreadExecutor()
        try {
            val first = worker.submit<AgentNativeToolResult> { registry(store, executor).invoke(descriptor.id, emptyMap(), scope) }
            assertTrue(entered.await(10, TimeUnit.SECONDS))
            val overlap = registry(store, executor).invoke(descriptor.id, emptyMap(), scope.copy(invocationId = "second"))
            assertEquals("effect_outcome_unknown", overlap.error?.code)
            assertFalse(overlap.error?.retryable == true)
            release.countDown()
            assertTrue(first.get(10, TimeUnit.SECONDS).isSuccess)
            val replay = registry(store, executor).invoke(descriptor.id, emptyMap(), scope.copy(invocationId = "third"))
            assertTrue(replay.receipt.replayed)
            assertEquals(1, calls.get())
        } finally {
            release.countDown()
            worker.shutdownNow()
            assertTrue(worker.awaitTermination(10, TimeUnit.SECONDS))
        }
    }

    @Test fun unfinishedClaimSurvivesRegistryRecreationWithoutRerunningEffect() {
        val store = InMemoryAgentNativeToolReplayStore()
        val key = AgentNativeToolReplayKey(descriptor.id, descriptor.version, "action", AgentNativeEffectScope.from(scope))
        assertTrue(store.claim(key, AgentNativeJsonCodec.sha256(emptyMap<String, Any>()), "interrupted").acquired)
        val runtime = registry(store) { error("Must not execute an uncertain effect") }
        val result = runtime.invoke(descriptor.id, emptyMap(), scope)
        assertEquals("effect_outcome_unknown", result.error?.code)
        assertEquals("interrupted", result.error?.details?.get("original_invocation_id"))
    }

    @Test fun changingInputCannotTakeAnUnfinishedClaim() {
        val store = InMemoryAgentNativeToolReplayStore()
        val key = AgentNativeToolReplayKey(descriptor.id, descriptor.version, "action", AgentNativeEffectScope.from(scope))
        store.claim(key, AgentNativeJsonCodec.sha256(mapOf("value" to 1)), "owner")
        val result = registry(store) { error("Must not run") }.invoke(descriptor.id, mapOf("value" to 2), scope)
        assertEquals("idempotency_key_conflict", result.error?.code)
    }

    @Test fun actualFailureIsObservedAgainInsteadOfRepeatingTheWrite() {
        val calls = AtomicInteger()
        val store = InMemoryAgentNativeToolReplayStore()
        val runtime = registry(store) {
            calls.incrementAndGet()
            AgentNativeToolExecutionResult.failure("external_write_uncertain", "Lost connection after sending")
        }
        val first = runtime.invoke(descriptor.id, emptyMap(), scope)
        val again = runtime.invoke(descriptor.id, emptyMap(), scope.copy(invocationId = "again"))
        assertEquals("external_write_uncertain", first.error?.code)
        assertEquals(first.error, again.error)
        assertTrue(again.receipt.replayed)
        assertEquals(1, calls.get())
    }

    @Test fun executorExceptionCannotEraseAnEffectClaim() {
        val calls = AtomicInteger()
        val runtime = registry(InMemoryAgentNativeToolReplayStore()) { calls.incrementAndGet(); error("after write") }
        val first = runtime.invoke(descriptor.id, emptyMap(), scope)
        val again = runtime.invoke(descriptor.id, emptyMap(), scope.copy(invocationId = "again"))
        assertEquals("tool_invocation_failed", first.error?.code)
        assertTrue(again.receipt.replayed)
        assertEquals(1, calls.get())
    }

    @Test fun completionIsDurableBeforeFinishedHookRuns() {
        val store = InMemoryAgentNativeToolReplayStore()
        val key = AgentNativeToolReplayKey(descriptor.id, descriptor.version, "action", AgentNativeEffectScope.from(scope))
        var observed = false
        registry(store) { AgentNativeToolExecutionResult.success() }.invoke(descriptor.id, emptyMap(), scope,
            AgentNativeToolInvocationHooks(onFinished = { result ->
                observed = store.get(key)?.receipt?.invocationId == result.receipt.invocationId
            }))
        assertTrue(observed)
    }

    @Test fun storageFailureDoesNotPublishSuccessOrAllowBlindRetry() {
        val memory = InMemoryAgentNativeToolReplayStore()
        val broken = object : AgentNativeToolReplayStore by memory {
            override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                error("disk unavailable")
            }
        }
        val calls = AtomicInteger()
        val runtime = registry(broken) { calls.incrementAndGet(); AgentNativeToolExecutionResult.success() }
        val visible = mutableListOf<Boolean>()
        val first = runtime.invoke(descriptor.id, emptyMap(), scope,
            AgentNativeToolInvocationHooks(onFinished = { visible += it.isSuccess }))
        val second = runtime.invoke(descriptor.id, emptyMap(), scope.copy(invocationId = "again"))
        assertFalse(first.isSuccess)
        assertEquals(listOf(false), visible)
        assertEquals("effect_outcome_unknown", second.error?.code)
        assertEquals(1, calls.get())
    }

    @Test fun receiptDoesNotDisappearAfterTwoThousandLaterActions() {
        val calls = AtomicInteger()
        val runtime = registry(InMemoryAgentNativeToolReplayStore()) {
            calls.incrementAndGet(); AgentNativeToolExecutionResult.success()
        }
        repeat(2_101) { index ->
            assertTrue(runtime.invoke(descriptor.id, emptyMap(), scope.copy(idempotencyKey = "key-$index")).isSuccess)
        }
        assertTrue(runtime.invoke(descriptor.id, emptyMap(), scope.copy(idempotencyKey = "key-0")).receipt.replayed)
        assertEquals(2_101, calls.get())
    }
}
