package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class AgentActiveRunRuntimeContextPolicyTest {
    @Test
    fun reusesTheStableContextForEveryActiveTaskPhase() {
        val base = runtimeContext()

        listOf(
            AgentPhase.PLANNING,
            AgentPhase.WAITING_CONFIRMATION,
            AgentPhase.EXECUTING,
            AgentPhase.VERIFYING,
            AgentPhase.WAITING_RESPONSE,
            AgentPhase.PAUSED
        ).forEach { phase ->
            assertSame(
                base,
                AgentActiveRunRuntimeContextPolicy.reuse(base, base.goal, base.screen, phase)
            )
        }
    }

    @Test
    fun updatesOnlyTheScreenWithoutDroppingPlanningEvidence() {
        val base = runtimeContext()
        val updatedScreen = ScreenContext(foregroundApp = "com.example.editor", pageTitle = "Editor")

        val reused = requireNotNull(
            AgentActiveRunRuntimeContextPolicy.reuse(
                base,
                base.goal,
                updatedScreen,
                AgentPhase.EXECUTING
            )
        )

        assertEquals(updatedScreen, reused.screen)
        assertSame(base.memories, reused.memories)
        assertSame(base.knowledgeItems, reused.knowledgeItems)
        assertSame(base.nativeTools, reused.nativeTools)
        assertSame(base.callableTargets, reused.callableTargets)
    }

    @Test
    fun refusesTerminalOrDifferentGoalContexts() {
        val base = runtimeContext()

        assertNull(
            AgentActiveRunRuntimeContextPolicy.reuse(
                base,
                "another goal",
                base.screen,
                AgentPhase.EXECUTING
            )
        )
        listOf(
            AgentPhase.OBSERVING,
            AgentPhase.CANCELLED,
            AgentPhase.BLOCKED,
            AgentPhase.COMPLETED,
            AgentPhase.FAILED
        ).forEach { phase ->
            assertNull(
                AgentActiveRunRuntimeContextPolicy.reuse(base, base.goal, base.screen, phase)
            )
        }
    }

    private fun runtimeContext() = AgentRuntimeContext(
        sessionId = "session",
        goal = "Develop the project on this phone",
        screen = ScreenContext(foregroundApp = "com.signalasi.chat", pageTitle = "Agent"),
        permissionMode = PermissionMode.FULL_ACCESS,
        highRiskGuard = false,
        memoryCapture = true,
        systemTools = emptyList(),
        nativeTools = emptyList(),
        callableTargets = emptyList(),
        memories = listOf(
            AgentMemoryItem(
                kind = AgentMemoryKind.TASK,
                value = "Use the phone workspace",
                timestampMillis = 1L
            )
        ),
        knowledgeItems = listOf(
            AgentKnowledgeItem(
                id = "knowledge",
                kind = AgentKnowledgeKind.DOCUMENT,
                title = "Project",
                content = "Use the phone workspace",
                source = "test"
            )
        ),
        knowledgeStats = AgentKnowledgeStats(itemCount = 1)
    )
}
