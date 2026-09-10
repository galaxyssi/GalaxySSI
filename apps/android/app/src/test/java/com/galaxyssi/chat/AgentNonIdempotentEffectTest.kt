package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class AgentNonIdempotentEffectTest {
    private val descriptor = AgentNativeToolDescriptor("test.non-idempotent", "1.0.0", "Write", "Append",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.LOW, setOf("test"), idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT)
    private val context = AgentNativeToolInvocationContext(invocationId = "first", sessionId = "session",
        conversationId = "conversation", turnId = "turn", idempotencyKey = "action")

    private fun registry(store: AgentNativeToolReplayStore, execute: AgentNativeToolExecutor) =
        AgentNativeToolRegistry(replayStore = store).register(AgentNativeToolDefinition(descriptor, execute))

    @Test fun sameLogicalCallReplaysReceiptNotEffect() {
        val calls = AtomicInteger()
        val runtime = registry(InMemoryAgentNativeToolReplayStore()) {
            AgentNativeToolExecutionResult.success(mapOf("count" to calls.incrementAndGet()))
        }
        val first = runtime.invoke(descriptor.id, emptyMap(), context)
        val again = runtime.invoke(descriptor.id, emptyMap(), context.copy(invocationId = "second"))
        assertTrue(first.isSuccess)
        assertTrue(again.receipt.replayed)
        assertEquals(first.output, again.output)
        assertEquals(1, calls.get())
    }

    @Test fun unfinishedEffectRequiresObservationInsteadOfRedispatch() {
        val store = InMemoryAgentNativeToolReplayStore()
        val key = AgentNativeToolReplayKey(descriptor.id, descriptor.version, "action", AgentNativeEffectScope.from(context))
        store.claim(key, AgentNativeJsonCodec.sha256(emptyMap<String, Any>()), "dead-process")
        val result = registry(store) { error("Must not dispatch") }.invoke(descriptor.id, emptyMap(), context)
        assertEquals("effect_outcome_unknown", result.error?.code)
        assertFalse(result.error!!.retryable)
    }

    @Test fun overlappingRegistriesCannotRepeatNonIdempotentCall() {
        val store = InMemoryAgentNativeToolReplayStore()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val calls = AtomicInteger()
        val executor = AgentNativeToolExecutor {
            calls.incrementAndGet()
            entered.countDown()
            check(release.await(10, TimeUnit.SECONDS))
            AgentNativeToolExecutionResult.success()
        }
        val worker = Executors.newSingleThreadExecutor()
        try {
            val first = worker.submit<AgentNativeToolResult> {
                registry(store, executor).invoke(descriptor.id, emptyMap(), context)
            }
            assertTrue(entered.await(10, TimeUnit.SECONDS))
            val overlapping = registry(store, executor).invoke(descriptor.id, emptyMap(),
                context.copy(invocationId = "overlap"))
            assertEquals("effect_outcome_unknown", overlapping.error?.code)
            release.countDown()
            assertTrue(first.get(10, TimeUnit.SECONDS).isSuccess)
            assertEquals(1, calls.get())
        } finally {
            release.countDown()
            worker.shutdownNow()
            assertTrue(worker.awaitTermination(10, TimeUnit.SECONDS))
        }
    }

    @Test fun missingLogicalKeyUsesStableInvocationIdentity() {
        val calls = AtomicInteger()
        val runtime = registry(InMemoryAgentNativeToolReplayStore()) {
            calls.incrementAndGet(); AgentNativeToolExecutionResult.success()
        }
        val call = context.copy(idempotencyKey = null)
        val first = runtime.invoke(descriptor.id, emptyMap(), call)
        val again = runtime.invoke(descriptor.id, emptyMap(), call)
        val fresh = runtime.invoke(descriptor.id, emptyMap(), call.copy(invocationId = "new-request"))
        assertTrue(first.isSuccess && fresh.isSuccess)
        assertEquals("first", first.receipt.idempotencyKey)
        assertTrue(again.receipt.replayed)
        assertFalse(fresh.receipt.replayed)
        assertEquals(2, calls.get())
    }

    @Test fun changedInputCannotReuseTheSameLogicalCall() {
        val calls = AtomicInteger()
        val runtime = registry(InMemoryAgentNativeToolReplayStore()) {
            calls.incrementAndGet(); AgentNativeToolExecutionResult.success()
        }
        assertTrue(runtime.invoke(descriptor.id, mapOf("value" to 1), context).isSuccess)
        val changed = runtime.invoke(descriptor.id, mapOf("value" to 2), context)
        assertEquals("idempotency_key_conflict", changed.error?.code)
        assertEquals(1, calls.get())
    }

    @Test fun separateConversationDoesNotShareAnEffect() {
        val calls = AtomicInteger()
        val runtime = registry(InMemoryAgentNativeToolReplayStore()) {
            calls.incrementAndGet(); AgentNativeToolExecutionResult.success()
        }
        assertTrue(runtime.invoke(descriptor.id, emptyMap(), context).isSuccess)
        val other = runtime.invoke(descriptor.id, emptyMap(), context.copy(conversationId = "other"))
        assertTrue(other.isSuccess)
        assertFalse(other.receipt.replayed)
        assertEquals(2, calls.get())
    }

    @Test fun ordinaryIdempotentReadsStayFreshWithoutEffectJournalAccess() {
        val calls = AtomicInteger()
        val store = object : AgentNativeToolReplayStore by InMemoryAgentNativeToolReplayStore() {
            override fun get(key: AgentNativeToolReplayKey): AgentNativeToolResult? = error("No read receipt lookup")
            override fun observe(key: AgentNativeToolReplayKey): AgentNativeEffectClaim? = error("No read effect lookup")
            override fun claim(key: AgentNativeToolReplayKey, inputSha256: String, invocationId: String): AgentNativeEffectClaim =
                error("No read effect claim")
        }
        val runtime = AgentNativeToolRegistry(replayStore = store).register(AgentNativeToolDefinition(
            descriptor.copy(idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
                effect = AgentNativeToolEffect.READ_ONLY), AgentNativeToolExecutor {
                AgentNativeToolExecutionResult.success(mapOf("value" to calls.incrementAndGet()))
            }))
        val call = context.copy(idempotencyKey = null)
        assertEquals(1, runtime.invoke(descriptor.id, emptyMap(), call).output["value"])
        assertEquals(2, runtime.invoke(descriptor.id, emptyMap(), call).output["value"])
    }

    @Test fun missingOutcomeCommitCannotPublishSuccessOrRetryEffect() {
        val backing = InMemoryAgentNativeToolReplayStore()
        val store = object : AgentNativeToolReplayStore by backing {
            override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                error("Disk unavailable after external write")
            }
        }
        val calls = AtomicInteger()
        val runtime = registry(store) { calls.incrementAndGet(); AgentNativeToolExecutionResult.success() }
        assertFalse(runtime.invoke(descriptor.id, emptyMap(), context).isSuccess)
        val again = runtime.invoke(descriptor.id, emptyMap(), context.copy(invocationId = "again"))
        assertEquals("effect_outcome_unknown", again.error?.code)
        assertEquals(1, calls.get())
    }
}
