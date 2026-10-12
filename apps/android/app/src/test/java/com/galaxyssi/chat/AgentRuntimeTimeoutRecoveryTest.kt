package com.galaxyssi.chat

import java.io.IOException
import java.net.SocketTimeoutException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class AgentRuntimeTimeoutRecoveryTest {
    @Test fun acknowledgedCancellationPreservesTheConnectionAndUncertainSideEffects() {
        Harness { envelope, channel ->
            when (envelope.type) {
                AgentRuntimeGuestMessageType.CANCEL -> channel.reply(envelope, AgentRuntimeGuestMessageType.CANCELLED)
                AgentRuntimeGuestMessageType.EXECUTE -> if (envelope.requestId == "next") channel.result(envelope)
                else -> Unit
            }
        }.use { harness ->
            val error = assertThrows(AgentNativeToolTimeoutException::class.java) { harness.bridge.execute(request("slow")) }
            assertEquals(true, error.details["cancellation_observed"])
            assertEquals(true, error.details["outcome_unknown"])
            assertEquals(true, error.details["execution_terminal_observed"])
            assertEquals(false, error.details["goal_terminal"])
            assertEquals("next", harness.bridge.execute(request("next", 1_000)).stdout)
            assertEquals(1, harness.opens.get())
            assertEquals(1, harness.cancels.get())
        }
    }

    @Test fun authoritativeLateResultIsReturnedWithoutResubmittingTheExecution() {
        Harness { envelope, channel ->
            if (envelope.type == AgentRuntimeGuestMessageType.CANCEL) channel.result(envelope)
        }.use { harness ->
            assertEquals("late", harness.bridge.execute(request("late")).stdout)
            assertEquals(1, harness.executions.get())
            assertEquals(1, harness.cancels.get())
            assertEquals(1, harness.opens.get())
        }
    }

    @Test fun missingCancellationResponseIsUnknownRatherThanAWholeRuntimeFailure() {
        Harness { envelope, channel ->
            if (envelope.type == AgentRuntimeGuestMessageType.EXECUTE && envelope.requestId == "next") channel.result(envelope)
        }.use { harness ->
            val error = assertThrows(AgentNativeToolTimeoutException::class.java) { harness.bridge.execute(request("missing")) }
            assertEquals(false, error.details["cancellation_observed"])
            assertEquals(true, error.details["outcome_unknown"])
            assertEquals("response_not_observed", error.details["cancellation_observation_error"])
            assertTrue(harness.bridge.refreshHealth().ready)
            assertEquals("next", harness.bridge.execute(request("next", 1_000)).stdout)
            assertEquals(1, harness.opens.get())
        }
    }

    @Test fun oneTimeoutDoesNotCancelAnotherPendingExecution() {
        val waiting = CountDownLatch(1)
        Harness { envelope, channel ->
            when (envelope.type) {
                AgentRuntimeGuestMessageType.EXECUTE -> if (envelope.requestId == "slow") waiting.countDown() else channel.result(envelope)
                AgentRuntimeGuestMessageType.CANCEL -> channel.reply(envelope, AgentRuntimeGuestMessageType.CANCELLED)
                else -> Unit
            }
        }.use { harness ->
            val executor = Executors.newFixedThreadPool(2)
            try {
                val slow = executor.submit<Throwable?> { runCatching { harness.bridge.execute(request("slow", 150)) }.exceptionOrNull() }
                assertTrue(waiting.await(2, TimeUnit.SECONDS))
                val fast = executor.submit<AgentRuntimeExecutionResponse> { harness.bridge.execute(request("parallel", 1_000)) }
                assertEquals("parallel", fast.get(3, TimeUnit.SECONDS).stdout)
                assertTrue(slow.get(3, TimeUnit.SECONDS) is AgentNativeToolTimeoutException)
                assertEquals(1, harness.opens.get())
                assertEquals(1, harness.cancels.get())
            } finally { executor.shutdownNow() }
        }
    }

    @Test fun freshHealthBypassesCacheAndPreservesConfirmedNegativeReadiness() {
        Harness { _, _ -> }.use { harness ->
            assertTrue(harness.bridge.health().ready)
            val previous = harness.heartbeats.get()
            harness.heartbeatReady = false
            assertTrue(harness.bridge.health().ready)
            assertEquals(previous, harness.heartbeats.get())
            val health = harness.bridge.refreshHealth()
            assertFalse(health.ready)
            assertTrue(health.observationConfirmed)
            assertEquals(previous + 1, harness.heartbeats.get())
            assertTrue(AgentRuntimeTimeoutRecovery.shouldQuarantine(AgentNativeToolTimeoutException(), health))
        }
    }

    @Test fun unobservedHeartbeatDoesNotDestroyTheConnectionOrBecomeConfirmedFailure() {
        Harness { envelope, channel ->
            if (envelope.type == AgentRuntimeGuestMessageType.EXECUTE) channel.result(envelope)
        }.use { harness ->
            assertTrue(harness.bridge.health().ready)
            harness.respondToHeartbeat = false
            val health = harness.bridge.refreshHealth()
            assertFalse(health.ready)
            assertFalse(health.observationConfirmed)
            assertFalse(AgentRuntimeTimeoutRecovery.shouldQuarantine(AgentNativeToolTimeoutException(), health))
            assertEquals("after-heartbeat-timeout", harness.bridge.execute(request("after-heartbeat-timeout", 1_000)).stdout)
            harness.respondToHeartbeat = true
            val previous = harness.heartbeats.get()
            assertTrue(harness.bridge.health().ready)
            assertEquals(previous + 1, harness.heartbeats.get())
            assertEquals(1, harness.opens.get())
        }
    }

    @Test fun quarantineRequiresConfirmedNegativeReadinessAndARequestTimeout() {
        val timeout = AgentNativeToolTimeoutException()
        for (health in listOf(null, AgentRuntimeBridgeHealth(true), AgentRuntimeBridgeHealth(false, observationConfirmed = false))) {
            assertFalse(AgentRuntimeTimeoutRecovery.shouldQuarantine(timeout, health))
            assertEquals(false, AgentRuntimeTimeoutRecovery.evidence(health, false)["runtime_reset"])
        }
        assertFalse(AgentRuntimeTimeoutRecovery.shouldQuarantine(IOException(), AgentRuntimeBridgeHealth(false)))
        assertTrue(AgentRuntimeTimeoutRecovery.shouldQuarantine(timeout, AgentRuntimeBridgeHealth(false)))
        assertFalse(AgentRuntimeTimeoutRecovery.evidence(AgentRuntimeBridgeHealth(false, observationConfirmed = false), false).containsKey("runtime_ready"))
    }

    @Test fun explicitUserCancellationWinsOverALateResult() {
        val cancellation = AgentNativeToolCancellationSource()
        Harness { envelope, channel ->
            if (envelope.type == AgentRuntimeGuestMessageType.CANCEL && cancellation.cancel()) channel.result(envelope)
        }.use { harness ->
            assertThrows(AgentNativeToolCancelledException::class.java) {
                harness.bridge.execute(request("user-cancel").copy(cancellationToken = cancellation.token))
            }
            assertEquals(1, harness.executions.get())
        }
    }

    private fun request(id: String, timeout: Long = 50) = AgentRuntimeExecutionRequest(
        language = AgentRuntimeLanguage.SHELL, source = "true", arguments = emptyList(), timeoutMillis = timeout,
        networkEnabled = false, artifactPaths = emptyList(), workspaceId = "timeout-test-$id", requestId = id,
        resourceLimits = AgentRuntimeResourceLimits(wallClockMillis = 30_000, cpuMillis = 1_000),
        guestWorkspacePath = "/workspace/timeout-test-$id")

    private class Harness(private val action: (AgentRuntimeGuestEnvelope, Harness) -> Unit) : AutoCloseable, AgentRuntimeGuestChannel {
        private val responses = LinkedBlockingQueue<Any>()
        val opens = AtomicInteger()
        val cancels = AtomicInteger()
        val executions = AtomicInteger()
        val heartbeats = AtomicInteger()
        @Volatile var heartbeatReady = true
        @Volatile var respondToHeartbeat = true
        val bridge = AgentRuntimeGuestBridge(AgentRuntimeGuestChannelFactory { opens.incrementAndGet(); this }, { ByteArray(32) { 1 } })

        override fun send(envelope: AgentRuntimeGuestEnvelope, sessionKey: ByteArray) {
            when (envelope.type) {
                AgentRuntimeGuestMessageType.HELLO -> reply(envelope, AgentRuntimeGuestMessageType.HELLO_ACK, mapOf(
                    "guest_api_version" to 1, "guest_version" to "timeout-test", "ready" to true,
                    "capabilities" to listOf("runtime.execute", "runtime.cancel", "runtime.progress", "runtime.concurrent")))
                AgentRuntimeGuestMessageType.HEARTBEAT -> {
                    heartbeats.incrementAndGet()
                    if (respondToHeartbeat) reply(envelope, AgentRuntimeGuestMessageType.HEARTBEAT_ACK, mapOf("ready" to heartbeatReady))
                }
                else -> {
                    if (envelope.type == AgentRuntimeGuestMessageType.EXECUTE) executions.incrementAndGet()
                    if (envelope.type == AgentRuntimeGuestMessageType.CANCEL) cancels.incrementAndGet()
                    action(envelope, this)
                }
            }
        }

        fun reply(envelope: AgentRuntimeGuestEnvelope, type: AgentRuntimeGuestMessageType, payload: Map<String, Any?> = emptyMap()) {
            responses.put(AgentRuntimeGuestEnvelope(requestId = envelope.requestId, type = type, sequence = 1, payload = payload))
        }

        fun result(envelope: AgentRuntimeGuestEnvelope) = reply(envelope, AgentRuntimeGuestMessageType.RESULT,
            mapOf("exit_code" to 0, "stdout" to envelope.requestId, "stderr" to ""))

        override fun receive(timeoutMillis: Long, sessionKey: ByteArray): AgentRuntimeGuestEnvelope {
            val response = if (timeoutMillis <= 0) responses.take() else responses.poll(timeoutMillis, TimeUnit.MILLISECONDS)
                ?: throw SocketTimeoutException("Guest runtime response timed out")
            if (response is Throwable) throw response
            return response as AgentRuntimeGuestEnvelope
        }

        override fun close() { responses.offer(IOException("Test channel closed")) }
    }
}
