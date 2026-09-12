package com.galaxyssi.chat

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class MqttInboundRoutePoolTest {
    private fun await(latch: CountDownLatch) = assertTrue("worker deadline", latch.await(5, TimeUnit.SECONDS))

    @Test fun samePeerIsSerialAndOrderedWithinAdmission() {
        val active = AtomicInteger()
        val peak = AtomicInteger()
        val seen = Collections.synchronizedList(mutableListOf<Int>())
        MqttInboundRoutePool<Int>(process = {
            peak.accumulateAndGet(active.incrementAndGet(), ::maxOf)
            Thread.yield()
            seen.add(it)
            active.decrementAndGet()
        }, routePending = 1_024).use { pool ->
            repeat(500) { assertEquals(MqttInboundRoutePool.Admission.ACCEPTED, pool.submit("peer", it, 10)) }
            assertTrue(pool.awaitIdle())
            assertEquals(1, peak.get())
            assertEquals((0 until 500).toList(), seen)
            assertEquals(0, pool.snapshot().routes)
            assertEquals(0L, pool.snapshot().retainedBytes)
        }
    }

    @Test fun threeConcurrentBrokerCallbacksNeverRunTheSameRatchetInParallel() {
        val active = AtomicInteger()
        val peak = AtomicInteger()
        val seen = Collections.synchronizedList(mutableListOf<Int>())
        val admissionFailures = AtomicInteger()
        val start = CountDownLatch(1)
        MqttInboundRoutePool<Int>(process = {
            peak.accumulateAndGet(active.incrementAndGet(), ::maxOf)
            seen.add(it)
            Thread.yield()
            active.decrementAndGet()
        }, routePending = 1_024).use { pool ->
            val publishers = (0..2).map { broker -> Thread {
                await(start)
                repeat(100) { index ->
                    if (pool.submit("same-signal-peer", broker * 100 + index, 10) != MqttInboundRoutePool.Admission.ACCEPTED) {
                        admissionFailures.incrementAndGet()
                    }
                }
            }.apply { start() } }
            start.countDown()
            publishers.forEach { it.join(5_000); assertFalse(it.isAlive) }
            assertTrue(pool.awaitIdle())
            assertEquals(0, admissionFailures.get())
            assertEquals(1, peak.get())
            assertEquals((0 until 300).toList(), seen.sorted())
            (0..2).forEach { broker ->
                assertEquals((broker * 100 until (broker + 1) * 100).toList(), seen.filter { it / 100 == broker })
            }
        }
    }

    @Test fun tenThousandHistoricalPeersDoNotRetainTenThousandLanes() {
        MqttInboundRoutePool<Int>(process = {}).use { pool ->
            repeat(100) { batch ->
                repeat(100) { index ->
                    assertEquals(MqttInboundRoutePool.Admission.ACCEPTED,
                        pool.submit("peer-${batch * 100 + index}", index, 10))
                }
                assertTrue(pool.awaitIdle())
                assertEquals(0, pool.snapshot().routes)
                assertTrue(pool.snapshot().workers <= 4)
            }
            assertEquals(10_000L, pool.snapshot().processed)
            assertEquals(0L, pool.snapshot().retainedBytes)
        }
    }

    @Test fun differentPeersRunConcurrentlyButWorkersAreBounded() {
        val entered = CountDownLatch(3)
        val release = CountDownLatch(1)
        MqttInboundRoutePool<Int>(process = { entered.countDown(); await(release) }, maxWorkers = 3).use { pool ->
            try {
                repeat(100) { assertEquals(MqttInboundRoutePool.Admission.ACCEPTED, pool.submit("p$it", it, 10)) }
                await(entered)
                assertEquals(3, pool.snapshot().workers)
                assertEquals(3, pool.snapshot().active)
            } finally { release.countDown() }
            assertTrue(pool.awaitIdle())
            assertEquals(100L, pool.snapshot().processed)
        }
    }

    @Test fun hotPeerRotatesBehindOtherReadyPeers() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val seen = Collections.synchronizedList(mutableListOf<String>())
        MqttInboundRoutePool<String>(process = {
            if (it == "a1") { entered.countDown(); await(release) }
            seen.add(it)
        }, maxWorkers = 1).use { pool ->
            try {
                pool.submit("a", "a1", 1)
                await(entered)
                pool.submit("a", "a2", 1)
                pool.submit("b", "b1", 1)
                pool.submit("c", "c1", 1)
            } finally { release.countDown() }
            assertTrue(pool.awaitIdle())
            assertEquals(listOf("a1", "b1", "c1", "a2"), seen)
        }
    }

    @Test fun activePacketRetainsGlobalBytesUntilHandlerReturns() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        MqttInboundRoutePool<Int>(process = { entered.countDown(); await(release) },
            maxWorkers = 1, maxBytes = 12, routeBytes = 10).use { pool ->
            try {
                pool.submit("a", 1, 8)
                await(entered)
                assertEquals(MqttInboundRoutePool.Admission.GLOBAL_BYTES, pool.submit("b", 2, 5))
                assertEquals(MqttInboundRoutePool.Admission.ROUTE_BYTES, pool.submit("a", 3, 3))
                assertEquals(8L, pool.snapshot().retainedBytes)
            } finally { release.countDown() }
            assertTrue(pool.awaitIdle())
            assertEquals(0L, pool.snapshot().retainedBytes)
            assertEquals(MqttInboundRoutePool.Admission.ACCEPTED, pool.submit("b", 4, 5))
            assertTrue(pool.awaitIdle())
        }
    }

    @Test fun routeQuotaLeavesOtherPeersAdmissionCapacity() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        MqttInboundRoutePool<Int>(process = { entered.countDown(); await(release) }, maxWorkers = 1,
            maxPending = 3, routePending = 2).use { pool ->
            try {
                pool.submit("a", 1, 1)
                await(entered)
                pool.submit("a", 2, 1)
                assertEquals(MqttInboundRoutePool.Admission.ROUTE_COUNT, pool.submit("a", 3, 1))
                assertEquals(MqttInboundRoutePool.Admission.ACCEPTED, pool.submit("b", 4, 1))
                assertEquals(MqttInboundRoutePool.Admission.GLOBAL_COUNT, pool.submit("c", 5, 1))
            } finally { release.countDown() }
            assertTrue(pool.awaitIdle())
        }
    }

    @Test fun closeCancelsPendingNotCurrentHandlerOrLogicalTask() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val completed = AtomicInteger()
        val pool = MqttInboundRoutePool<Int>(process = { entered.countDown(); await(release); completed.incrementAndGet() }, maxWorkers = 1)
        try {
            pool.submit("a", 1, 4)
            await(entered)
            pool.submit("a", 2, 3)
            pool.submit("b", 3, 2)
            pool.close()
            assertEquals(4L, pool.snapshot().retainedBytes)
            assertEquals(2L, pool.snapshot().cancelled)
            assertEquals(MqttInboundRoutePool.Admission.CLOSED, pool.submit("c", 4, 1))
        } finally { release.countDown(); pool.close() }
        assertTrue(pool.awaitIdle())
        assertEquals(1, completed.get())
        assertEquals(0L, pool.snapshot().retainedBytes)
        assertEquals(0, pool.snapshot().routes)
    }

    @Test fun closeCanDrainAlreadyAdmittedPackets() {
        val seen = AtomicInteger()
        val pool = MqttInboundRoutePool<Int>(process = { seen.incrementAndGet() }, maxWorkers = 1)
        repeat(30) { pool.submit("a", it, 1) }
        pool.close(cancelPending = false)
        assertTrue(pool.awaitIdle())
        assertEquals(30, seen.get())
        assertEquals(0L, pool.snapshot().cancelled)
    }

    @Test fun handlerFailureReleasesQuotaAndNextPacketRuns() {
        val failures = AtomicInteger()
        MqttInboundRoutePool<Int>(process = { if (it == 1) error("synthetic") },
            onFailure = { failures.incrementAndGet(); error("observer failed") }).use { pool ->
            pool.submit("a", 1, 10)
            pool.submit("a", 2, 10)
            assertTrue(pool.awaitIdle())
            assertEquals(2L, pool.snapshot().processed)
            assertEquals(1L, pool.snapshot().failed)
            assertEquals(1, failures.get())
            assertEquals(0L, pool.snapshot().retainedBytes)
        }
    }

    @Test fun workerCreationFailureRollsBackAdmission() {
        MqttInboundRoutePool<Int>(process = {}, threadFactory = { throw IllegalStateException() }).use { pool ->
            assertEquals(MqttInboundRoutePool.Admission.WORKER_UNAVAILABLE, pool.submit("a", 1, 10))
            assertEquals(0L, pool.snapshot().retainedBytes)
            assertEquals(0L, pool.snapshot().accepted)
            assertEquals(0, pool.snapshot().routes)
        }
    }

    @Test fun idleWorkersExitAndNewTrafficCanRestartThem() {
        MqttInboundRoutePool<Int>(process = {}, idleMillis = 10).use { pool ->
            pool.submit("a", 1, 10)
            assertTrue(pool.awaitIdle())
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (pool.snapshot().workers != 0 && System.nanoTime() < deadline) Thread.sleep(5)
            assertEquals(0, pool.snapshot().workers)
            assertEquals(MqttInboundRoutePool.Admission.ACCEPTED, pool.submit("b", 2, 10))
            assertTrue(pool.awaitIdle())
            assertEquals(2L, pool.snapshot().processed)
        }
    }

    @Test fun invalidAdmissionDoesNotAllocateARoute() {
        MqttInboundRoutePool<Int>(process = {}).use { pool ->
            listOf("", " ", "x".repeat(513)).forEach {
                assertThrows(IllegalArgumentException::class.java) { pool.submit(it, 1, 10) }
            }
            assertThrows(IllegalArgumentException::class.java) { pool.submit("a", 1, 0) }
            assertEquals(0, pool.snapshot().routes)
        }
    }
}
