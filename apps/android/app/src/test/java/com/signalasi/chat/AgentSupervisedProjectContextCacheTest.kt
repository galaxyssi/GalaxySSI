package com.signalasi.chat

import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectContextCacheTest {
    @Test
    fun `same immutable conversation and goal reuse compiled project context`() {
        val context = context("Continue work on https://github.com/signalasi/SignalASI")
        val request = request(context, "Update https://github.com/signalasi/SignalASI")

        val first = requireNotNull(AgentSupervisedProjectContextCache.render(request))
        val second = requireNotNull(AgentSupervisedProjectContextCache.render(request.copy()))

        assertSame(first, second)
    }

    @Test
    fun `new conversation context compiles current project evidence`() {
        val original = context("Continue work on https://github.com/signalasi/SignalASI")
        val updated = context("Continue work on https://github.com/example/new-project")

        val first = requireNotNull(
            AgentSupervisedProjectContextCache.render(request(original, "Continue the project"))
        )
        val second = requireNotNull(
            AgentSupervisedProjectContextCache.render(request(updated, "Continue the project"))
        )

        assertNotSame(first, second)
        assertTrue(first.contains("signalasi/SignalASI"))
        assertTrue(second.contains("example/new-project"))
    }

    @Test
    fun `changed goal recompiles context for the same conversation snapshot`() {
        val context = context("Keep the existing Android project constraints")

        val first = requireNotNull(
            AgentSupervisedProjectContextCache.render(
                request(context, "Update https://github.com/signalasi/SignalASI")
            )
        )
        val second = requireNotNull(
            AgentSupervisedProjectContextCache.render(
                request(context, "Update https://github.com/example/companion")
            )
        )

        assertNotSame(first, second)
        assertTrue(first.contains("signalasi/SignalASI"))
        assertTrue(second.contains("example/companion"))
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
            foregroundApp = "com.signalasi.chat",
            pageTitle = "SignalASI"
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
