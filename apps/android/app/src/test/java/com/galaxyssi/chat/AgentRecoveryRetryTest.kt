package com.galaxyssi.chat

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentRecoveryRetryTest {
    @Test fun timedOutReadOnlyQueriesRetryOriginalIdentityWithoutExternalWake(): Unit = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        try {
            val client = AgentRemoteRecoveryClient()
            val sent = mutableListOf<JSONObject>()
            val done = CompletableDeferred<Unit>()
            val item = JSONObject().put("client_route_id", "route").put("conversation_id", "conversation")
                .put("task_id", "task").put("turn_id", "turn").put("contact_id", "contact")
                .put("source_message_id", "42").put("agent_id", "codex")
            val wake = AgentRecoveryWakeCoordinator(scope, recover = { retry ->
                val replies = client.query("desktop", "route", listOf(item), timeoutMillis = 20,
                    report = { if (it == "response_timeout") retry() }) { payload ->
                    sent.add(payload)
                    if (sent.size == 3) client.receive(JSONObject(payload.toString())
                        .put("type", "agent_task_recovery_result"), "desktop")
                    true
                }
                if (replies.isNotEmpty()) done.complete(Unit)
            }, initialRetryMillis = 10, maxRetryMillis = 20)
            wake.connectionChanged(true)
            withTimeout(3000) { done.await(); while (wake.isRunning) delay(1) }
            assertEquals(3, sent.size)
            assertEquals(3, sent.map { it.getString("request_id") }.distinct().size)
            assertTrue(sent.all { it.getString("type") == "agent_task_recovery_request" })
            assertTrue(sent.all { it.getJSONArray("items").getJSONObject(0).toString() == item.toString() })
            assertFalse(client.receive(JSONObject(sent.first().toString()), "desktop"))
            assertEquals(0, client.pendingCount)
            assertFalse(wake.hasPendingWake)
        } finally { scope.cancel() }
    }

    @Test fun unresolvedWorkIsNotAbandonedAfterEightNormalObservations(): Unit = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        try {
            var calls = 0
            val wake = AgentRecoveryWakeCoordinator(scope, recover = { retry ->
                if (++calls < 12) retry()
            }, initialRetryMillis = 5, maxRetryMillis = 10)
            wake.request(true)
            withTimeout(3000) { while (wake.isRunning) delay(1) }
            assertEquals(12, calls)
            delay(30)
            assertEquals("Successful recovery must stop retries", 12, calls)
        } finally { scope.cancel() }
    }

    @Test fun disconnectCancelsBackoffAndReconnectImmediatelyUsesPersistedWork(): Unit = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        try {
            var calls = 0
            val wake = AgentRecoveryWakeCoordinator(scope, recover = { retry ->
                if (++calls == 1) retry()
            }, initialRetryMillis = 10_000, maxRetryMillis = 10_000)
            wake.request(true)
            assertEquals(1, calls)
            wake.connectionChanged(false)
            withTimeout(1000) { while (wake.isRunning) delay(1) }
            assertTrue(wake.hasPendingWake)
            delay(30)
            assertEquals(1, calls)
            wake.connectionChanged(true)
            assertEquals(2, calls)
            assertFalse(wake.hasPendingWake)
        } finally { scope.cancel() }
    }

    @Test fun foregroundWakeInterruptsBackoffWithoutAConcurrentWorker(): Unit = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        try {
            var calls = 0
            var active = 0
            var maximum = 0
            val wake = AgentRecoveryWakeCoordinator(scope, recover = { retry ->
                active++
                maximum = maxOf(maximum, active)
                if (++calls == 1) retry()
                active--
            }, initialRetryMillis = 10_000, maxRetryMillis = 10_000)
            wake.request(true)
            wake.request()
            withTimeout(1000) { while (wake.isRunning) delay(1) }
            assertEquals(2, calls)
            assertEquals(1, maximum)
        } finally { scope.cancel() }
    }

    @Test fun passWithoutTransientFailureDoesNotEnableRetryHeartbeat(): Unit = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        try {
            var calls = 0
            val wake = AgentRecoveryWakeCoordinator(scope, recover = { calls++ },
                initialRetryMillis = 5, maxRetryMillis = 10)
            wake.request(true)
            delay(40)
            assertEquals(1, calls)
            assertFalse(wake.isRunning)
        } finally { scope.cancel() }
    }

    @Test fun cancellationReleasesBackoffWorkerAndDoesNotRestart(): Unit = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        var calls = 0
        val wake = AgentRecoveryWakeCoordinator(scope, recover = { retry -> calls++; retry() },
            initialRetryMillis = 10_000, maxRetryMillis = 10_000)
        wake.request(true)
        scope.cancel()
        withTimeout(1000) { while (wake.isRunning) delay(1) }
        wake.request(true)
        assertEquals(1, calls)
        assertFalse(wake.isRunning)
    }
}
