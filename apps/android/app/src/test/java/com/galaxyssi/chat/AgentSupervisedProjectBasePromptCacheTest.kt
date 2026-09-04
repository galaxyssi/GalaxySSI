package com.galaxyssi.chat

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
    fun `concurrent equivalent prompt compilation runs once and shares one value`() {
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

        assertEquals(1, compilations.get())
        assertTrue(results.drop(1).all { result -> result === results.first() })
    }

    @Test
    fun `different prompt keys compile concurrently`() {
        val entered = CountDownLatch(2)
        val release = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)

        val futures = listOf("first", "second").map { suffix ->
            executor.submit<String> {
                AgentSupervisedProjectBasePromptCache.render(
                    key(
                        goal = "Compile $suffix prompt",
                        progressLedger = "$suffix observation"
                    )
                ) {
                    entered.countDown()
                    release.await()
                    "compiled-$suffix"
                }
            }
        }

        assertTrue(entered.await(5, java.util.concurrent.TimeUnit.SECONDS))
        release.countDown()
        assertEquals(listOf("compiled-first", "compiled-second"), futures.map { it.get() })
        executor.shutdownNow()
    }

    @Test
    fun `failed compilation is not cached and can be retried`() {
        val key = key(
            goal = "Retry failed prompt compilation",
            progressLedger = "failed compilation"
        )

        runCatching {
            AgentSupervisedProjectBasePromptCache.render(key) {
                error("synthetic compile failure")
            }
        }.onSuccess {
            error("Expected prompt compilation to fail")
        }

        val recovered = AgentSupervisedProjectBasePromptCache.render(key) { "recovered prompt" }

        assertEquals("recovered prompt", recovered)
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
