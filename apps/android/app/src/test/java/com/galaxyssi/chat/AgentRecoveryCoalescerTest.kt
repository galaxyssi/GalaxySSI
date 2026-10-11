package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class AgentRecoveryCoalescerTest {
    @Test fun concurrentWakesCoalesceAndRunOneFollowupObservation() {
        val gate = AgentRecoveryCoalescer()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val calls = AtomicInteger()
        val executor = Executors.newSingleThreadExecutor()
        try {
            val result = executor.submit<Int> { gate.run {
                if (calls.incrementAndGet() == 1) { entered.countDown(); assertTrue(release.await(5, TimeUnit.SECONDS)) }
                1
            } }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            repeat(100) { assertEquals(0, gate.run { error("Must not start another runner") }) }
            release.countDown()
            assertEquals(2, result.get(5, TimeUnit.SECONDS))
            assertEquals(2, calls.get())
        } finally { release.countDown(); executor.shutdownNow() }
    }

    @Test fun reentrantWakeIsNotLost() {
        val gate = AgentRecoveryCoalescer()
        var passes = 0
        assertEquals(2, gate.run {
            if (++passes == 1) assertEquals(0, gate.run { error("Reentrant runner") })
            1
        })
    }

    @Test fun failureDoesNotLeaveRecoveryPermanentlyLocked() {
        val gate = AgentRecoveryCoalescer()
        assertThrows(IllegalStateException::class.java) { gate.run { error("fixture") } }
        assertEquals(7, gate.run { 7 })
    }
}
