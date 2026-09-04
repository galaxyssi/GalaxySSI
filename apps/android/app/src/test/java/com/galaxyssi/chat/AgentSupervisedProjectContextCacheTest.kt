package com.galaxyssi.chat

import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

class AgentSupervisedProjectContextCacheTest {
    @Test
    fun `same immutable conversation and goal reuse compiled project context`() {
        val context = context("Continue work on https://github.com/galaxyssi/GalaxySSI")
        val request = request(context, "Update https://github.com/galaxyssi/GalaxySSI")

        val first = requireNotNull(AgentSupervisedProjectContextCache.render(request))
        val second = requireNotNull(AgentSupervisedProjectContextCache.render(request.copy()))

        assertSame(first, second)
    }

    @Test
    fun `new conversation context compiles current project evidence`() {
        val original = context("Continue work on https://github.com/galaxyssi/GalaxySSI")
        val updated = context("Continue work on https://github.com/example/new-project")

        val first = requireNotNull(
            AgentSupervisedProjectContextCache.render(request(original, "Continue the project"))
        )
        val second = requireNotNull(
            AgentSupervisedProjectContextCache.render(request(updated, "Continue the project"))
        )

        assertNotSame(first, second)
        assertTrue(first.contains("galaxyssi/GalaxySSI"))
        assertTrue(second.contains("example/new-project"))
    }

    @Test
    fun `changed goal recompiles context for the same conversation snapshot`() {
        val context = context("Keep the existing Android project constraints")

        val first = requireNotNull(
            AgentSupervisedProjectContextCache.render(
                request(context, "Update https://github.com/galaxyssi/GalaxySSI")
            )
        )
        val second = requireNotNull(
            AgentSupervisedProjectContextCache.render(
                request(context, "Update https://github.com/example/companion")
            )
        )

        assertNotSame(first, second)
        assertTrue(first.contains("galaxyssi/GalaxySSI"))
        assertTrue(second.contains("example/companion"))
    }

    @Test
    fun `concurrent project context compilation converges on one cached value`() {
        val context = context(
            "Continue work on https://github.com/galaxyssi/GalaxySSI " + "constraint ".repeat(2_000)
        )
        val request = request(context, "Update https://github.com/galaxyssi/GalaxySSI")
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(8)

        val futures = (1..8).map {
            executor.submit<String> {
                start.await()
                requireNotNull(AgentSupervisedProjectContextCache.render(request.copy()))
            }
        }
        start.countDown()
        val results = futures.map { future -> future.get() }
        executor.shutdownNow()

        assertTrue(results.drop(1).all { result -> result === results.first() })
    }

    private fun context(text: String): AgentConversationContext = AgentConversationContext(
        conversationId = "project-context-cache-test",
        summary = "",
        turns = listOf(
            AgentTranscriptEntry(
                id = "user-turn",
                role = AgentTranscriptRole.USER,
                text = text,
                timestampMillis = 1L,
                conversationId = "project-context-cache-test",
                turnId = "turn-1"
            )
        ),
        privateMode = false
    )

    private fun request(context: AgentConversationContext, goal: String): AgentRequest {
        val screen = ScreenContext(
            foregroundApp = "com.galaxyssi.chat",
            pageTitle = "GalaxySSI"
        )
        return AgentRequest(
            goal = goal,
            screen = screen,
            targets = emptyList(),
            memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build(
                sessionId = "project-context-cache-test",
                goal = goal,
                screen = screen,
                permissionMode = PermissionMode.FULL_ACCESS,
                highRiskGuard = false,
                memoryCapture = false,
                callableTargets = emptyList(),
                memories = emptyList()
            ),
            conversationContext = context
        )
    }
}
