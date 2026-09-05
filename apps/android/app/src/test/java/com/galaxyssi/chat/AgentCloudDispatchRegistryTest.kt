package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

class AgentCloudDispatchRegistryTest {
    private val identity = AgentCloudDispatchIdentity(1, "cloud", "conversation", "turn", "task", "action")
    private fun pending(id: AgentCloudDispatchIdentity = identity) = AgentActionResult(id.actionId, true, "", mapOf(
        "resource_location" to "cloud", "source_message_id" to id.sourceMessageId.toString(),
        "contact_id" to id.contactId, "conversation_id" to id.conversationId, "turn_id" to id.turnId, "task_id" to id.taskId))

    @Test fun pendingIdentityMustMatchEveryRoutingDimension() {
        val lease = AgentCloudDispatchRegistry.register(identity)
        try {
            listOf(identity.copy(sourceMessageId = 2), identity.copy(contactId = "other"),
                identity.copy(conversationId = "other"), identity.copy(turnId = "other"),
                identity.copy(taskId = "other"), identity.copy(actionId = "other")).forEach {
                assertFalse(AgentCloudDispatchRegistry.cancel(pending(it)))
            }
            assertFalse(AgentCloudDispatchRegistry.cancel(pending().copy(metadata = pending().metadata + ("resource_location" to "desktop"))))
            assertFalse(lease.isCancelled)
            assertTrue(AgentCloudDispatchRegistry.cancel(pending()))
        } finally { AgentCloudDispatchRegistry.release(identity, lease) }
    }

    @Test fun cancellationBeforeRequestRegistrationCancelsLateJob() {
        val lease = AgentCloudDispatchLease()
        assertTrue(lease.cancel())
        val job = Job()
        lease.bind(job).dispose()
        assertTrue(job.isCancelled)
        assertFalse(lease.claimCompletion())
        assertThrows(CancellationException::class.java) { lease.runRequest { error("Must not call model") } }
    }

    @Test fun completedReplyCannotBeCancelledAfterwards() {
        val lease = AgentCloudDispatchLease()
        assertTrue(lease.claimCompletion())
        assertFalse(lease.cancel())
        assertFalse(lease.claimCompletion())
    }

    @Test fun cancellationWakesRetryWaitWithoutDispatchingAnotherAttempt() {
        val lease = AgentCloudDispatchLease()
        val waiting = CountDownLatch(1)
        val done = CountDownLatch(1)
        val retries = AtomicInteger()
        thread {
            waiting.countDown()
            if (lease.awaitRetry(60_000)) retries.incrementAndGet()
            done.countDown()
        }
        assertTrue(waiting.await(2, TimeUnit.SECONDS))
        lease.cancel()
        assertTrue(done.await(2, TimeUnit.SECONDS))
        assertEquals(0, retries.get())
    }

    @Test fun staleReleaseCannotRemoveReplacementDispatch() {
        val old = AgentCloudDispatchRegistry.register(identity)
        old.cancel()
        AgentCloudDispatchRegistry.release(identity, old)
        val next = AgentCloudDispatchRegistry.register(identity)
        try {
            AgentCloudDispatchRegistry.release(identity, old)
            assertTrue(AgentCloudDispatchRegistry.cancel(pending()))
            assertTrue(next.isCancelled)
        } finally { AgentCloudDispatchRegistry.release(identity, next) }
    }

    @Test fun terminalRaceHasExactlyOneWinner() {
        repeat(100) {
            val lease = AgentCloudDispatchLease()
            val gate = CountDownLatch(1)
            val winners = AtomicInteger()
            val a = thread { gate.await(); if (lease.cancel()) winners.incrementAndGet() }
            val b = thread { gate.await(); if (lease.claimCompletion()) winners.incrementAndGet() }
            gate.countDown()
            a.join(2_000); b.join(2_000)
            assertEquals(1, winners.get())
        }
    }

    @Test fun cancelledAttemptIsDurableButNotARetryableFailure() {
        val tracker = AgentProviderAttemptTracker(AgentProviderAttemptReport(1, "c", "t", "task", "a"))
        tracker.start("request", "cloud", "provider", "model", 100)
        tracker.progress("first_output", 20)
        tracker.cancel(150)
        tracker.progress("connected", 99)
        val restored = AgentProviderAttemptCodec.decode(AgentProviderAttemptCodec.encode(tracker.report))
        assertEquals("cancelled", restored.attempts.single().state)
        assertEquals(50L, restored.attempts.single().elapsedMillis)
        assertFalse(restored.attempts.single().retryable)
        assertNull(restored.attempts.single().failure())
    }

    @Test fun cancellationDuringBackoffPreservesRealFailure() {
        val tracker = AgentProviderAttemptTracker(AgentProviderAttemptReport(1, "c", "t", "task", "a"))
        tracker.start("request", "cloud", "provider", "model", 100)
        tracker.finish(10, AgentProviderFailure(AgentProviderFailureClass.PERMANENT_BILLING, false), 402)
        val before = tracker.report
        tracker.cancel(200)
        assertEquals(before, tracker.report)
    }
}
