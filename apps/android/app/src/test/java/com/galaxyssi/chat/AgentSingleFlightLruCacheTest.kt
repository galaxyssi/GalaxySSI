package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class AgentSingleFlightLruCacheTest {
    @Test
    fun `equivalent concurrent keys compute once`() {
        val cache = AgentSingleFlightLruCache<String, String>(maximumEntries = 4)
        val start = CountDownLatch(1)
        val release = CountDownLatch(1)
        val computations = AtomicInteger()
        val executor = Executors.newFixedThreadPool(8)

        val futures = (1..8).map {
            executor.submit<String> {
                start.await()
                cache.getOrCompute("shared") {
                    computations.incrementAndGet()
                    release.await()
                    String(charArrayOf('v', 'a', 'l', 'u', 'e'))
                }
            }
        }
        start.countDown()
        while (computations.get() == 0) Thread.yield()
        release.countDown()
        val results = futures.map { future -> future.get() }
        executor.shutdownNow()

        assertEquals(1, computations.get())
        assertTrue(results.drop(1).all { result -> result === results.first() })
    }

    @Test
    fun `different keys compute concurrently`() {
        val cache = AgentSingleFlightLruCache<String, String>(maximumEntries = 4)
        val entered = CountDownLatch(2)
        val release = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)

        val futures = listOf("first", "second").map { key ->
            executor.submit<String> {
                cache.getOrCompute(key) {
                    entered.countDown()
                    release.await()
                    "value-$key"
                }
            }
        }

        assertTrue(entered.await(5, TimeUnit.SECONDS))
        release.countDown()
        assertEquals(listOf("value-first", "value-second"), futures.map { it.get() })
        executor.shutdownNow()
    }

    @Test
    fun `failed computation is released and retried`() {
        val cache = AgentSingleFlightLruCache<String, String>(maximumEntries = 2)

        runCatching {
            cache.getOrCompute("retry") { error("synthetic failure") }
        }.onSuccess {
            error("Expected computation to fail")
        }

        assertEquals("recovered", cache.getOrCompute("retry") { "recovered" })
    }

    @Test
    fun `least recently used value is evicted`() {
        val cache = AgentSingleFlightLruCache<String, String>(maximumEntries = 2)
        val firstA = cache.getOrCompute("a") { String(charArrayOf('a')) }
        val firstB = cache.getOrCompute("b") { String(charArrayOf('b')) }
        assertSame(firstA, cache.getOrCompute("a") { "unexpected" })
        cache.getOrCompute("c") { "c" }

        val secondB = cache.getOrCompute("b") { String(charArrayOf('b')) }

        assertNotSame(firstB, secondB)
    }
}
