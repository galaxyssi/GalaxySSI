package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentNativeEffectObservationTest {
    private val descriptor = AgentNativeToolDescriptor("phone.test.observation", "1.0.0", "Test", "Test",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.LOW, setOf("phone.test"), idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT)
    private val context = AgentNativeToolInvocationContext(invocationId = "original", sessionId = "session",
        conversationId = "conversation", turnId = "turn", idempotencyKey = "effect",
        attributes = mapOf("client_route_id" to "route", "goal_id" to "goal", "task_id" to "task"))
    private val input = mapOf<String, Any?>("value" to 1)
    private val key = AgentNativeToolReplayKey(descriptor.id, descriptor.version, "effect", AgentNativeEffectScope.from(context))
    private val unavailable = AgentNativeToolAvailability(AgentNativeToolAvailabilityStatus.UNAVAILABLE, "Offline")

    @Test fun completedEffectReplaysBeforeCurrentAvailability() {
        val store = InMemoryAgentNativeToolReplayStore()
        val first = runtime(store).invoke(descriptor.id, input, context)
        val again = runtime(store, availability = { error("Do not probe the network for a receipt") })
            .invoke(descriptor.id, input, context.copy(invocationId = "resumed"))
        assertTrue(again.toJson(), again.isSuccess)
        assertTrue(again.receipt.replayed)
        assertEquals(first.output, again.output)
        assertEquals("original", again.receipt.originalInvocationId)
        assertEquals(first.toJson(), store.get(key)?.toJson())
    }

    @Test fun recordedFailureIsNotReplacedByCurrentUnavailability() {
        val store = InMemoryAgentNativeToolReplayStore()
        runtime(store, execute = { AgentNativeToolExecutionResult.failure("remote_rejected", "Original failure") })
            .invoke(descriptor.id, input, context)
        val again = runtime(store, availability = { unavailable }).invoke(descriptor.id, input, context)
        assertEquals("remote_rejected", again.error?.code)
        assertTrue(again.receipt.replayed)
    }

    @Test fun unfinishedEffectReportsUncertaintyBeforeCurrentAvailability() {
        val store = InMemoryAgentNativeToolReplayStore()
        store.claim(key, AgentNativeJsonCodec.sha256(input), "interrupted-owner")
        val again = runtime(store, availability = { error("Must not probe") }).invoke(descriptor.id, input, context)
        assertEquals("effect_outcome_unknown", again.error?.code)
        assertEquals("interrupted-owner", again.error?.details?.get("original_invocation_id"))
        val claim = store.claim(key, AgentNativeJsonCodec.sha256(input), "new-owner")
        assertFalse(claim.acquired)
        assertNull(claim.result)
        assertEquals("interrupted-owner", claim.invocationId)
    }

    @Test fun changedInputIsRejectedEvenWhileOffline() {
        val store = InMemoryAgentNativeToolReplayStore()
        runtime(store).invoke(descriptor.id, input, context)
        val again = runtime(store, availability = { unavailable })
            .invoke(descriptor.id, mapOf("value" to 2), context)
        assertEquals("idempotency_key_conflict", again.error?.code)
        assertEquals(AgentNativeToolResultStatus.REJECTED, again.status)
    }

    @Test fun unfinishedEffectWithChangedInputIsAlsoRejected() {
        val store = InMemoryAgentNativeToolReplayStore()
        store.claim(key, AgentNativeJsonCodec.sha256(input), "interrupted-owner")
        val again = runtime(store, availability = { unavailable })
            .invoke(descriptor.id, mapOf("value" to 2), context)
        assertEquals("idempotency_key_conflict", again.error?.code)
    }

    @Test fun allScopeDimensionsRemainIsolatedWhileOffline() {
        val store = InMemoryAgentNativeToolReplayStore()
        runtime(store).invoke(descriptor.id, input, context)
        val otherScopes = listOf(context.copy(sessionId = "other"), context.copy(conversationId = "other"),
            context.copy(turnId = "other")) + listOf("client_route_id", "goal_id", "task_id").map {
            context.copy(attributes = context.attributes + (it to "other"))
        }
        otherScopes.forEach { other ->
            val result = runtime(store, availability = { unavailable }).invoke(descriptor.id, input, other)
            assertEquals(other.toString(), "tool_unavailable", result.error?.code)
            assertFalse(result.receipt.replayed)
        }
    }

    @Test fun unavailableFreshCallDoesNotAcquireAnEffectClaim() {
        val store = InMemoryAgentNativeToolReplayStore()
        val result = runtime(store, availability = { unavailable }).invoke(descriptor.id, input, context)
        assertEquals("tool_unavailable", result.error?.code)
        assertTrue(store.claim(key, AgentNativeJsonCodec.sha256(input), "later").acquired)
    }

    @Test fun differentToolVersionDoesNotReuseTheOldReceipt() {
        val store = InMemoryAgentNativeToolReplayStore()
        runtime(store).invoke(descriptor.id, input, context)
        val result = runtime(store, availability = { unavailable }, version = "2.0.0")
            .invoke(descriptor.id, input, context)
        assertEquals("tool_unavailable", result.error?.code)
        assertFalse(result.receipt.replayed)
    }

    private fun runtime(store: AgentNativeToolReplayStore,
        availability: () -> AgentNativeToolAvailability = { AgentNativeToolAvailability.AVAILABLE },
        execute: () -> AgentNativeToolExecutionResult = { AgentNativeToolExecutionResult.success(mapOf("written" to true)) },
        version: String = descriptor.version) = AgentNativeToolRegistry(replayStore = store).register(
            AgentNativeToolDefinition(descriptor.copy(version = version), AgentNativeToolExecutor { execute() },
                availabilityProvider = AgentNativeToolAvailabilityProvider { availability() }))
}
