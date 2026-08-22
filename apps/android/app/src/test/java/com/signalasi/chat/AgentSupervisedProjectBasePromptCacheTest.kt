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
    fun `same request phase and budget reuse one compiled base prompt`() {
        val request = request("Improve the phone project")
        val compilations = AtomicInteger()

        val first = render(request, evidenceExpected = true, maximumCharacters = 20_000, compilations)
        val second = render(request, evidenceExpected = true, maximumCharacters = 20_000, compilations)

        assertSame(first, second)
        assertEquals(1, compilations.get())
    }

    @Test
    fun `phase budget and request identity isolate compiled base prompts`() {
        val firstRequest = request("Improve the phone project")
        val secondRequest = firstRequest.copy()
        val compilations = AtomicInteger()

        val baseline = render(firstRequest, false, 20_000, compilations)
        val continuation = render(firstRequest, true, 20_000, compilations)
        val reduced = render(firstRequest, false, 18_000, compilations)
        val copiedRequest = render(secondRequest, false, 20_000, compilations)

        assertEquals(4, compilations.get())
        assertNotSame(baseline, continuation)
        assertNotSame(baseline, reduced)
        assertNotSame(baseline, copiedRequest)
    }

    @Test
    fun `concurrent base prompt compilation converges on one cached value`() {
        val request = request("Run the phone project verification")
        val compilations = AtomicInteger()
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(8)

        val futures = (1..8).map {
            executor.submit<String> {
                start.await()
                AgentSupervisedProjectBasePromptCache.render(
                    request = request,
                    evidenceExpected = true,
                    maximumCharacters = 19_317
                ) {
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
        request: AgentRequest,
        evidenceExpected: Boolean,
        maximumCharacters: Int,
        compilations: AtomicInteger
    ): String = AgentSupervisedProjectBasePromptCache.render(
        request,
        evidenceExpected,
        maximumCharacters
    ) {
        "compiled-${compilations.incrementAndGet()}-${System.nanoTime()}"
    }

    private fun request(goal: String): AgentRequest {
        val screen = ScreenContext(
            foregroundApp = "com.signalasi.chat",
            pageTitle = "SignalASI"
        )
        return AgentRequest(
            goal = goal,
            screen = screen,
            targets = emptyList(),
            memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(
                sessionId = "base-prompt-cache-test-${System.nanoTime()}",
                goal = goal,
                screen = screen,
                permissionMode = PermissionMode.FULL_ACCESS,
                highRiskGuard = false,
                memoryCapture = false,
                callableTargets = emptyList(),
                memories = emptyList()
            )
        )
    }
}
