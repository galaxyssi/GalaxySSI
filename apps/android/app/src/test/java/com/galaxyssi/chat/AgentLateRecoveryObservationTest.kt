package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentLateRecoveryObservationTest {
    private fun item() = JSONObject().put("client_route_id", "route").put("conversation_id", "conversation")
        .put("task_id", "task").put("turn_id", "turn").put("contact_id", "contact")
        .put("source_message_id", "42").put("agent_id", "codex")
    private fun result(request: JSONObject) = JSONObject(request.toString()).put("type", "agent_task_recovery_result")

    @Test fun timeoutKeepsOnlyBoundedCorrelationAndAcceptsLateObservationOnce(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient()
        lateinit var sent: JSONObject
        val received = mutableListOf<List<JSONObject>>()
        assertTrue(client.query("desktop", "route", listOf(item()), timeoutMillis = 5,
            onResponse = { received += it }) { sent = it; true }.isEmpty())
        assertEquals(0, client.pendingCount)
        assertEquals(1, client.lateCount)
        assertTrue(received.isEmpty())
        assertTrue(client.receive(result(sent), "desktop"))
        assertEquals("task", received.single().single().getString("task_id"))
        assertFalse(client.receive(result(sent), "desktop"))
        assertEquals(0, client.lateCount)
        assertEquals(1, received.size)
    }

    @Test fun lateObservationStillRequiresEveryOriginalIdentityAndDevice(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient()
        lateinit var sent: JSONObject
        var received = 0
        client.query("desktop", "route", listOf(item()), timeoutMillis = 5,
            onResponse = { received++ }) { sent = it; true }
        assertFalse(client.receive(result(sent), "other"))
        assertFalse(client.receive(result(sent).put("client_route_id", "other"), "desktop"))
        for (field in item().keys()) {
            val bad = result(sent)
            bad.getJSONArray("items").getJSONObject(0).put(field, "other")
            assertFalse(field, client.receive(bad, "desktop"))
        }
        assertEquals(0, received)
        assertTrue(client.receive(result(sent), "desktop"))
        assertEquals(1, received)
    }

    @Test fun activeObserverAndWaiterShareOneResponse(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient()
        var observed = 0
        val response = client.query("desktop", "route", listOf(item()), onResponse = { observed++ }) {
            assertTrue(client.receive(result(it), "desktop"))
            assertFalse(client.receive(result(it), "desktop"))
            true
        }
        assertEquals(1, response.size)
        assertEquals(1, observed)
        assertEquals(0, client.pendingCount + client.lateCount)
    }

    @Test fun explicitCancellationRevokesLateOwnership(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient()
        lateinit var sent: JSONObject
        val query = async(start = CoroutineStart.UNDISPATCHED) {
            client.query("desktop", "route", listOf(item()), onResponse = { error("Cancelled observer") }) {
                sent = it; true
            }
        }
        query.cancel()
        query.join()
        assertFalse(client.receive(result(sent), "desktop"))
        assertEquals(0, client.pendingCount + client.lateCount)
    }

    @Test fun rejectedPublishDoesNotRetainAnObserver(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient()
        lateinit var sent: JSONObject
        client.query("desktop", "route", listOf(item()), onResponse = { error("Rejected observer") }) {
            sent = it; false
        }
        assertFalse(client.receive(result(sent), "desktop"))
        assertEquals(0, client.pendingCount + client.lateCount)
    }

    @Test fun metadataOnlyQueryDoesNotKeepUnrequestedLateWork(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient()
        lateinit var sent: JSONObject
        client.query("desktop", "route", listOf(item()), timeoutMillis = 5) { sent = it; true }
        assertFalse(client.receive(result(sent), "desktop"))
        assertEquals(0, client.lateCount)
    }

    @Test fun expiredCorrelationRejectsLateReply(): Unit = runBlocking {
        var clock = 0L
        val client = AgentRemoteRecoveryClient(nowMillis = { clock })
        lateinit var sent: JSONObject
        client.query("desktop", "route", listOf(item()), timeoutMillis = 5,
            onResponse = { error("Expired observer") }) { sent = it; true }
        clock = 120_001L
        assertFalse(client.receive(result(sent), "desktop"))
        assertEquals(0, client.lateCount)
    }

    @Test fun correlationExpiresEvenWithoutAnotherRequestOrClockAdvance(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient(nowMillis = { 0L }, lateRetentionMillis = 10L)
        client.query("desktop", "route", listOf(item()), timeoutMillis = 5,
            onResponse = { error("Expired observer") }) { true }
        withTimeout(2_000) { while (client.lateCount != 0) delay(10) }
        assertEquals(0, client.lateCount)
    }

    @Test fun retainedMetadataBoundDoesNotEvictActiveQueries(): Unit = runBlocking {
        var clock = 0L
        val client = AgentRemoteRecoveryClient(nowMillis = { clock }, maxLateRequests = 2)
        val sent = mutableListOf<JSONObject>()
        var received = 0
        repeat(3) {
            clock++
            client.query("desktop", "route", listOf(item()), timeoutMillis = 5,
                onResponse = { received++ }) { sent += it; true }
        }
        assertEquals(2, client.lateCount)
        lateinit var current: JSONObject
        val active = async(start = CoroutineStart.UNDISPATCHED) {
            client.query("desktop", "route", listOf(item())) { current = it; true }
        }
        assertFalse(client.receive(result(sent[0]), "desktop"))
        assertTrue(client.receive(result(sent[1]), "desktop"))
        assertTrue(client.receive(result(sent[2]), "desktop"))
        assertEquals(1, client.pendingCount)
        assertTrue(client.receive(result(current), "desktop"))
        active.await()
        assertEquals(2, received)
        assertEquals(0, client.pendingCount + client.lateCount)
    }

    @Test fun concurrentDuplicateResponsesCannotInvokeObserverTwice(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient()
        lateinit var sent: JSONObject
        val received = AtomicInteger()
        client.query("desktop", "route", listOf(item()), timeoutMillis = 5,
            onResponse = { received.incrementAndGet(); Unit }) { sent = it; true }
        val gate = CountDownLatch(1)
        val workers = List(2) { thread {
            check(gate.await(5, TimeUnit.SECONDS))
            client.receive(result(sent), "desktop")
        } }
        gate.countDown()
        workers.forEach { it.join(5_000); assertFalse(it.isAlive) }
        assertEquals(1, received.get())
        assertEquals(0, client.lateCount)
    }

    @Test fun observerFailureReleasesCorrelationAndReachesTheWaiter(): Unit = runBlocking {
        val client = AgentRemoteRecoveryClient()
        val failure = IllegalStateException("observation not persisted")
        try {
            client.query("desktop", "route", listOf(item()), onResponse = { throw failure }) {
                assertFalse(client.receive(result(it), "desktop"))
                true
            }
            fail("Observer failure must not be reported as successful recovery")
        } catch (error: IllegalStateException) {
            assertEquals(failure.message, error.message)
            assertTrue(error === failure || error.cause === failure)
        }
        assertEquals(0, client.pendingCount + client.lateCount)
    }
}
