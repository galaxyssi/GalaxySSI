package com.galaxyssi.chat

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class AgentNativeToolCancellationGroupTest {
    @Test fun `parallel workers finish while coordinator owns agent monitor`() {
        val owner = Any()
        val group = AgentNativeToolCancellationGroup()
        val pool = Executors.newFixedThreadPool(2)
        val bothStarted = CountDownLatch(2)
        try {
            synchronized(owner) {
                val futures = (1..2).map {
                    pool.submit<Boolean> {
                        val invocation = group.begin()
                        try {
                            bothStarted.countDown()
                            bothStarted.await(5, TimeUnit.SECONDS)
                        } finally {
                            group.end(invocation)
                        }
                    }
                }
                futures.forEach { assertTrue(it.get(10, TimeUnit.SECONDS)) }
            }
            assertFalse(group.cancel("Already finished"))
        } finally {
            pool.shutdownNow()
        }
    }

    @Test fun `all active invocations retain their cancellation reason after finishing`() {
        val group = AgentNativeToolCancellationGroup()
        val first = group.begin()
        val second = group.begin()
        assertTrue(group.cancel("  User stopped this run  "))
        group.end(first)
        group.end(second)
        for (invocation in listOf(first, second)) {
            assertTrue(invocation.source.token.isCancellationRequested)
            assertEquals("User stopped this run", invocation.reason)
        }
        val next = group.begin()
        assertEquals("", next.reason)
        assertFalse(next.source.token.isCancellationRequested)
        group.end(next)
    }

    @Test fun `finished invocations are not cancelled by another run`() {
        val group = AgentNativeToolCancellationGroup()
        val first = group.begin()
        group.end(first)
        assertFalse(group.cancel("Later cancellation"))
        assertFalse(first.source.token.isCancellationRequested)
    }

    @Test fun `cancellation callbacks run outside group lock`() {
        val group = AgentNativeToolCancellationGroup()
        val invocation = group.begin()
        val pool = Executors.newSingleThreadExecutor()
        var callbackFinished = false
        try {
            invocation.source.token.invokeOnCancellation {
                pool.submit {
                    val nested = group.begin()
                    group.end(nested)
                }.get(5, TimeUnit.SECONDS)
                callbackFinished = true
            }
            assertTrue(group.cancel("Stop"))
            assertTrue(callbackFinished)
        } finally {
            group.end(invocation)
            pool.shutdownNow()
        }
    }

    @Test fun `throwing cancellation listener cannot strand sibling invocations`() {
        val group = AgentNativeToolCancellationGroup()
        val first = group.begin()
        val second = group.begin()
        first.source.token.invokeOnCancellation { error("Listener failed") }
        assertTrue(group.cancel("Stop"))
        assertTrue(first.source.token.isCancellationRequested)
        assertTrue(second.source.token.isCancellationRequested)
        group.end(first)
        group.end(second)
        assertFalse(group.cancel("Stop again"))
    }

    @Test fun `separate agents do not share cancellation state`() {
        val first = AgentNativeToolCancellationGroup()
        val second = AgentNativeToolCancellationGroup()
        val a = first.begin()
        val b = second.begin()
        assertTrue(first.cancel(""))
        assertEquals("The native tool stopped reporting progress", a.reason)
        assertFalse(b.source.token.isCancellationRequested)
        first.end(a)
        second.end(b)
    }
}
