package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class AgentSupervisedProjectBasePromptCacheTest {
    @Test
    fun `equivalent prompt components reuse one compiled base prompt`() {
        val key = key(
            goal = "Reuse equivalent prompt components",
            progressLedger = "verified action one"
        )
        val compilations = AtomicInteger()

        val first = render(key, compilations)
        val second = render(key.copy(), compilations)

        assertSame(first, second)
        assertEquals(1, compilations.get())
    }

    @Test
    fun `new observation and budget isolate compiled base prompts`() {
        val baselineKey = key(
            goal = "Invalidate changed prompt components",
            progressLedger = "verified action one"
        )
        val compilations = AtomicInteger()

        val baseline = render(baselineKey, compilations)
        val newObservation = render(
            baselineKey.copy(progressLedger = "verified action two"),
            compilations
        )
        val reducedBudget = render(
            baselineKey.copy(maximumCharacters = 18_000),
            compilations
        )

        assertEquals(3, compilations.get())
        assertNotSame(baseline, newObservation)
        assertNotSame(baseline, reducedBudget)
    }

    @Test
    fun `concurrent equivalent prompt compilation converges on one cached value`() {
        val key = key(
            goal = "Converge concurrent prompt compilation",
            progressLedger = "concurrent verified action"
        )
        val compilations = AtomicInteger()
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(8)

        val futures = (1..8).map {
            executor.submit<String> {
                start.await()
                AgentSupervisedProjectBasePromptCache.render(key.copy()) {
                    compilations.incrementAndGet()
                    "compiled-${System.nanoTime()}"
                }
            }
        }
        start.countDown()
        val results = futures.map { future -> future.get() }
        executor.shutdownNow()

        assertTrue(compilations.get() in 1..8)
        assertTrue(results.drop(1).all { result -> result === results.first() })
    }

    private fun render(
        key: AgentSupervisedProjectBasePromptKey,
        compilations: AtomicInteger
    ): String = AgentSupervisedProjectBasePromptCache.render(key) {
        "compiled-${compilations.incrementAndGet()}-${System.nanoTime()}"
    }

    private fun key(
        goal: String,
        progressLedger: String
    ): AgentSupervisedProjectBasePromptKey =
        AgentSupervisedProjectBasePromptKey(
            stablePrefix = "stable tool contract",
            goal = goal,
            durableContext = "repository context",
            conversationTransport = "conversation context",
            progressLedger = progressLedger,
            maximumCharacters = 20_000,
            minimumBaseCharacters = 12_000
        )
}
