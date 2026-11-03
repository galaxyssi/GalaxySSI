package com.galaxyssi.chat

import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.awaitCancellation
import org.junit.Assert.*
import org.junit.Test

class AgentLocalDispatchLeaseTest {
    @Test fun stopBeforeQueuedExecutionSkipsInferenceAndReleasesTheSubscription() = fixture { task ->
        val queue = mutableListOf<Runnable>()
        var requests = 0
        var replies = 0
        var stopped = 0
        AgentLocalDispatchLease(task).enqueue(Executor { queue.add(it) },
            request = { requests++; "reply" }, completed = { replies++ }, cancelled = { stopped++ })
        assertEquals(1, PhoneExecutionAuthority.cancellationListenerCount(task))
        PhoneExecutionAuthority.requestCancellation(task)
        queue.single().run()
        assertEquals(0, requests)
        assertEquals(0, replies)
        assertEquals(1, stopped)
        assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount(task))
    }

    @Test fun stopDuringARequestCancelsItsTokenAndSuppressesTheLateResultAfterUnwind() = fixture { task ->
        val running = CountDownLatch(1)
        val unwound = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        var replies = 0
        var stopped = 0
        try {
            val future = executor.submit {
                AgentLocalDispatchLease(task).execute(request = { token ->
                    val cancelled = CountDownLatch(1)
                    val observer = token.invokeOnCancellation { cancelled.countDown() }
                    try {
                        running.countDown()
                        assertTrue(cancelled.await(2, TimeUnit.SECONDS))
                        assertTrue(token.isCancellationRequested)
                        "late reply"
                    } finally { observer.dispose(); unwound.countDown() }
                }, completed = { replies++ }, cancelled = { assertEquals(0L, unwound.count); stopped++ })
            }
            assertTrue(running.await(2, TimeUnit.SECONDS))
            PhoneExecutionAuthority.requestCancellation(task)
            future.get(3, TimeUnit.SECONDS)
            assertEquals(0, replies)
            assertEquals(1, stopped)
            assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount(task))
        } finally { executor.shutdownNow() }
    }

    @Test fun completionAndStopHaveExactlyOneTerminalWinner() = fixture { prefix ->
        val executor = Executors.newFixedThreadPool(2)
        try {
            repeat(100) { index ->
                val task = "$prefix-$index"
                val ready = CountDownLatch(1)
                val start = CountDownLatch(1)
                val completions = AtomicInteger()
                val cancellations = AtomicInteger()
                val lease = AgentLocalDispatchLease(task)
                val request = executor.submit {
                    lease.execute({ ready.countDown(); start.await(); "result" },
                        { completions.incrementAndGet() }, { cancellations.incrementAndGet() })
                }
                assertTrue(ready.await(2, TimeUnit.SECONDS))
                val stop = executor.submit { start.countDown(); PhoneExecutionAuthority.requestCancellation(task) }
                request.get(3, TimeUnit.SECONDS)
                stop.get(3, TimeUnit.SECONDS)
                assertEquals(1, completions.get() + cancellations.get())
                assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount(task))
                PhoneExecutionAuthority.clearCancellation(task)
            }
        } finally { executor.shutdownNow() }
    }

    @Test fun lateStopCannotRewriteAnAlreadyClaimedCompletion() = fixture { task ->
        var replies = 0
        val lease = AgentLocalDispatchLease(task)
        lease.execute({ "result" }, {
            PhoneExecutionAuthority.requestCancellation(task)
            assertEquals("result", it.getOrThrow())
            replies++
        }, { fail("Completion already owns the terminal decision") })
        assertEquals(1, replies)
        assertFalse(lease.token.isCancellationRequested)
    }

    @Test fun ordinaryFailureKeepsItsActualCauseAndDoesNotBecomeCancellation() = fixture { task ->
        val failure = IllegalStateException("public dependency failure")
        AgentLocalDispatchLease(task).execute<String>({ throw failure }, {
            assertSame(failure, it.exceptionOrNull())
        }, { fail("Ordinary failure is not cancellation") })
        assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount(task))
    }

    @Test fun nativeAndCoroutineCancellationNeverPublishAnOrdinaryFailure() = fixture { prefix ->
        listOf(CancellationException("public stop"), AgentNativeToolCancelledException()).forEachIndexed { index, failure ->
            var stops = 0
            AgentLocalDispatchLease("$prefix-$index").execute<String>({ throw failure },
                { fail("Cancellation must not create a late failure reply") }, { stops++ })
            assertEquals(1, stops)
            assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount("$prefix-$index"))
        }
    }

    @Test fun rejectedQueueAndThrowingDeliveryReleaseTheirListeners() = fixture { task ->
        assertThrows(java.util.concurrent.RejectedExecutionException::class.java) {
            AgentLocalDispatchLease(task).enqueue(Executor { throw java.util.concurrent.RejectedExecutionException() },
                { "result" }, { })
        }
        assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount(task))
        assertThrows(IllegalStateException::class.java) {
            AgentLocalDispatchLease(task).execute({ "result" }, { error("Public delivery failure") })
        }
        assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount(task))
    }

    @Test fun taskStopCancelsASuspendedLocalRequestWithoutPolling() = fixture { task ->
        val ready = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        var stops = 0
        try {
            val future = executor.submit {
                AgentLocalDispatchLease(task).execute({ token ->
                    runCancellableLocalRequest(token) { ready.countDown(); awaitCancellation() }
                }, { fail("Suspended inference must be cancelled") }, { stops++ })
            }
            assertTrue(ready.await(2, TimeUnit.SECONDS))
            PhoneExecutionAuthority.requestCancellation(task)
            future.get(3, TimeUnit.SECONDS)
            assertEquals(1, stops)
        } finally { executor.shutdownNow() }
    }

    @Test fun oneTaskCannotCancelAnotherAndFinishedDispatchCannotExecuteTwice() = fixture { task ->
        AgentLocalDispatchLease("$task-other").use { other ->
            val lease = AgentLocalDispatchLease(task)
            PhoneExecutionAuthority.requestCancellation(task)
            assertFalse(other.token.isCancellationRequested)
            lease.execute({ fail("Stopped task cannot start") }, { fail("No stopped reply") })
            assertThrows(IllegalStateException::class.java) { lease.execute({ "duplicate" }, { }) }
        }
    }

    private fun fixture(test: (String) -> Unit) {
        val task = "public-local-stop-${UUID.randomUUID()}"
        try { test(task) } finally { PhoneExecutionAuthority.clearCancellation(task) }
    }
}
