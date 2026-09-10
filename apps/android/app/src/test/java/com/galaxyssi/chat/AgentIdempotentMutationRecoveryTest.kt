package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class AgentIdempotentMutationRecoveryTest {
    @Test fun lostReceiptMustNotReplayAnOldOverwriteOverNewerExternalState() {
        val backing = InMemoryAgentNativeToolReplayStore()
        val failCommit = AtomicBoolean(true)
        val store = object : AgentNativeToolReplayStore by backing {
            override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
                check(!failCommit.get()) { "Simulated receipt commit failure" }
                backing.complete(key, invocationId, result)
            }
            override fun put(key: AgentNativeToolReplayKey, result: AgentNativeToolResult) {
                check(!failCommit.get()) { "Simulated receipt commit failure" }
                backing.put(key, result)
            }
        }
        var externalState = "original"
        var executions = 0
        val registry = AgentNativeToolRegistry(replayStore = store).register(AgentNativeToolDefinition(
            descriptor(), AgentNativeToolExecutor {
                executions++
                externalState = "old-write"
                AgentNativeToolExecutionResult.success(mapOf("written" to true))
            }))
        assertFalse(registry.invoke("test.overwrite", emptyMap(), context("owner")).isSuccess)
        externalState = "newer-user-write"
        failCommit.set(false)
        val recovered = registry.invoke("test.overwrite", emptyMap(), context("recovery"))
        assertEquals("effect_outcome_unknown", recovered.error?.code)
        assertEquals("newer-user-write", externalState)
        assertEquals(1, executions)
    }

    @Test fun sameInvocationWithoutExplicitKeyDoesNotApplyAMutationTwice() {
        var calls = 0
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor(),
            AgentNativeToolExecutor { calls++; AgentNativeToolExecutionResult.success(mapOf("written" to true)) }))
        val invocation = context("same-invocation").copy(idempotencyKey = null)
        assertTrue(registry.invoke("test.overwrite", emptyMap(), invocation).isSuccess)
        val replay = registry.invoke("test.overwrite", emptyMap(), invocation)
        assertEquals(1, calls)
        assertTrue(replay.receipt.replayed)
    }

    @Test fun concurrentDuplicateCannotEnterAnAlreadyRunningMutation() {
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val calls = AtomicInteger()
        val worker = Executors.newSingleThreadExecutor()
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor(),
            AgentNativeToolExecutor {
                calls.incrementAndGet()
                started.countDown()
                check(release.await(10, TimeUnit.SECONDS))
                AgentNativeToolExecutionResult.success()
            }))
        try {
            val owner = worker.submit<AgentNativeToolResult> { registry.invoke("test.overwrite", emptyMap(), context("owner")) }
            assertTrue(started.await(10, TimeUnit.SECONDS))
            val duplicate = registry.invoke("test.overwrite", emptyMap(), context("duplicate"))
            assertEquals("effect_outcome_unknown", duplicate.error?.code)
            assertEquals(1, calls.get())
            release.countDown()
            assertTrue(owner.get(10, TimeUnit.SECONDS).isSuccess)
            assertTrue(registry.invoke("test.overwrite", emptyMap(), context("later")).receipt.replayed)
        } finally {
            release.countDown()
            worker.shutdownNow()
            assertTrue(worker.awaitTermination(10, TimeUnit.SECONDS))
        }
    }

    @Test fun failedSerialReadCanRetryWithoutLeavingAnUncertainEffect() {
        var calls = 0
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(
            descriptor().copy(effect = AgentNativeToolEffect.READ_ONLY), AgentNativeToolExecutor {
                if (++calls == 1) AgentNativeToolExecutionResult.failure("temporary", "Read failed", retryable = true)
                else AgentNativeToolExecutionResult.success(mapOf("fresh" to true))
            }))
        assertFalse(registry.invoke("test.overwrite", emptyMap(), context("first")).isSuccess)
        assertTrue(registry.invoke("test.overwrite", emptyMap(), context("retry")).isSuccess)
        assertEquals(2, calls)
    }

    @Test fun inputConflictIsRejectedButOtherConversationsAndTurnsRemainIndependent() {
        var calls = 0
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor(),
            AgentNativeToolExecutor { calls++; AgentNativeToolExecutionResult.success() }))
        assertTrue(registry.invoke("test.overwrite", mapOf("value" to 1), context("first")).isSuccess)
        assertEquals("idempotency_key_conflict", registry.invoke("test.overwrite", mapOf("value" to 2), context("conflict")).error?.code)
        assertTrue(registry.invoke("test.overwrite", emptyMap(), context("conversation").copy(conversationId = "other")).isSuccess)
        assertTrue(registry.invoke("test.overwrite", emptyMap(), context("turn").copy(turnId = "other")).isSuccess)
        assertEquals(3, calls)
    }

    @Test fun effectPolicyDoesNotInvalidateThePublicCatalogOrCopiedReadDescriptors() {
        val serial = descriptor()
        assertTrue(serial.requiresEffectClaim)
        val read = serial.copy(effect = AgentNativeToolEffect.READ_ONLY)
        assertFalse(read.requiresEffectClaim)
        assertEquals(serial.catalogValue(), read.catalogValue())
        val parallel = serial.copy(risk = AgentNativeToolRisk.LOW, concurrency = AgentNativeToolConcurrency.PARALLEL_READ_ONLY)
        assertFalse(parallel.requiresEffectClaim)
        assertThrows(IllegalArgumentException::class.java) { parallel.copy(effect = AgentNativeToolEffect.MUTATION) }
        assertTrue(read.copy(idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT).requiresEffectClaim)
    }

    @Test fun explicitKeyRequirementIsNotBypassedByTheInvocationFallback() {
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(
            descriptor().copy(idempotency = AgentNativeToolIdempotency.IDEMPOTENCY_KEY_REQUIRED),
            AgentNativeToolExecutor { error("Missing-key invocation must not execute") }))
        assertEquals("missing_idempotency_key", registry.invoke("test.overwrite", emptyMap(),
            context("missing").copy(idempotencyKey = null)).error?.code)
    }

    @Test fun aDeliberateNewActionCanRepairAFailedMutation() {
        var calls = 0
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(descriptor(),
            AgentNativeToolExecutor {
                if (++calls == 1) AgentNativeToolExecutionResult.failure("write_failed", "Inspect and repair")
                else AgentNativeToolExecutionResult.success()
            }))
        assertFalse(registry.invoke("test.overwrite", emptyMap(), context("first")).isSuccess)
        assertTrue(registry.invoke("test.overwrite", emptyMap(), context("same")).receipt.replayed)
        assertEquals(1, calls)
        assertTrue(registry.invoke("test.overwrite", emptyMap(), context("repair").copy(idempotencyKey = "new-action")).isSuccess)
        assertEquals(2, calls)
    }

    private fun descriptor() = AgentNativeToolDescriptor("test.overwrite", "1.0.0", "Overwrite", "Overwrite test state",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.MEDIUM, idempotency = AgentNativeToolIdempotency.IDEMPOTENT)
    private fun context(invocation: String) = AgentNativeToolInvocationContext(invocationId = invocation,
        sessionId = "session", conversationId = "conversation", turnId = "turn", idempotencyKey = "same-effect")
}
