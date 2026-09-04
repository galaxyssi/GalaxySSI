package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectRuntimeContextPolicyTest {
    @Test
    fun `same run reuses native catalog and capability matrix`() {
        val target = target(AgentConnectorStatus.AVAILABLE)
        val base = context(target)
        val screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "Project")

        val reused = AgentSupervisedProjectRuntimeContextPolicy.reuse(
            base = base,
            goal = base.goal,
            screen = screen,
            targets = listOf(target)
        )

        assertSame(base.nativeTools, reused.nativeTools)
        assertSame(base.systemTools, reused.systemTools)
        assertSame(base.capabilityMatrix, reused.capabilityMatrix)
        assertEquals(screen, reused.screen)
        assertTrue(reused.memories.isEmpty())
        assertTrue(reused.knowledgeItems.isEmpty())
    }

    @Test
    fun `connector changes refresh only the capability matrix`() {
        val base = context(target(AgentConnectorStatus.AVAILABLE))
        val disconnected = target(AgentConnectorStatus.DISCONNECTED)

        val reused = AgentSupervisedProjectRuntimeContextPolicy.reuse(
            base = base,
            goal = base.goal,
            screen = base.screen,
            targets = listOf(disconnected)
        )

        assertSame(base.nativeTools, reused.nativeTools)
        assertSame(base.systemTools, reused.systemTools)
        assertNotSame(base.capabilityMatrix, reused.capabilityMatrix)
        assertEquals(
            AgentRuntimeCapabilityState.UNAVAILABLE,
            reused.capabilityMatrix.entry(AgentRuntimeCapabilitySource.CONNECTOR, disconnected.id)?.state
        )
        assertTrue(reused.capabilityMatrix.isNativeToolExecutable(TEST_TOOL_ID))
    }

    private fun context(target: AgentCallableTarget): AgentRuntimeContext = AgentRuntimeContextBuilder.build(
        sessionId = "run-context-test",
        goal = "Improve the phone project",
        screen = ScreenContext(foregroundApp = "com.galaxyssi.chat", pageTitle = "GalaxySSI"),
        permissionMode = PermissionMode.FULL_ACCESS,
        highRiskGuard = false,
        memoryCapture = true,
        callableTargets = listOf(target),
        memories = listOf(AgentMemoryItem(kind = AgentMemoryKind.TASK, value = "private project memory")),
        nativeTools = listOf(
            AgentNativeToolDescriptor(
                id = TEST_TOOL_ID,
                version = "1.0.0",
                title = "Test project tool",
                description = "Produces project evidence",
                location = AgentNativeToolLocation.PHONE,
                inputSchema = AgentNativeJsonSchema.objectSchema(),
                outputSchema = AgentNativeJsonSchema.objectSchema(),
                risk = AgentNativeToolRisk.LOW
            )
        ),
        knowledgeItems = listOf(
            AgentKnowledgeItem(
                id = "knowledge",
                kind = AgentKnowledgeKind.TASK,
                title = "Private",
                content = "Private"
            )
        ),
        knowledgeStats = AgentKnowledgeStats(itemCount = 1)
    )

    private fun target(status: AgentConnectorStatus): AgentCallableTarget = AgentCallableTarget(
        id = "codex-phone-reasoner",
        title = "Codex",
        kind = AgentConnectorKind.AGENT,
        status = status,
        capabilities = listOf(AgentCapability.CHAT, AgentCapability.CODE),
        failureDomain = "desktop-codex",
        adapterType = "codex-app-server"
    )

    private companion object {
        const val TEST_TOOL_ID = "galaxyssi.project.test.evidence"
    }
}
