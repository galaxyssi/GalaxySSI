package com.signalasi.chat

import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSupervisedProjectPromptTemplateTest {
    @Test
    fun `same catalog and mode reuse the compiled prefix`() {
        val context = context()

        val first = AgentSupervisedProjectPromptTemplate.render(context, false, 240)
        val second = AgentSupervisedProjectPromptTemplate.render(context, false, 240)

        assertSame(first, second)
    }

    @Test
    fun `planning and continuation keep separate compiled prefixes`() {
        val context = context()

        val planning = AgentSupervisedProjectPromptTemplate.render(context, false, 240)
        val continuation = AgentSupervisedProjectPromptTemplate.render(context, true, 240)

        assertNotSame(planning, continuation)
        assertTrue(planning.startsWith("Role: supervise one Android-initiated project step at a time."))
        assertTrue(continuation.startsWith("Continue the Android project from verified evidence."))
        assertTrue(planning.contains("Available phone tools:\n- ${AgentMobileProjectNativeTools.CLONE} |"))
        assertTrue(continuation.contains("Available phone tools:\n- ${AgentMobileProjectNativeTools.CLONE} |"))
    }

    private fun context(): AgentRuntimeContext {
        val tool = AgentNativeToolDescriptor(
            id = AgentMobileProjectNativeTools.CLONE,
            version = "1.0.0",
            title = "Clone repository",
            description = "Clone a project repository",
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(
                properties = mapOf("repository_url" to AgentNativeJsonSchema.string())
            ),
            outputSchema = AgentNativeJsonSchema.objectSchema(),
            risk = AgentNativeToolRisk.LOW
        )
        return AgentRuntimeContext(
            sessionId = "template-test",
            goal = "Improve the phone project",
            screen = ScreenContext(foregroundApp = "com.signalasi.chat", pageTitle = "SignalASI"),
            permissionMode = PermissionMode.FULL_ACCESS,
            highRiskGuard = false,
            memoryCapture = false,
            systemTools = emptyList(),
            nativeTools = listOf(tool),
            callableTargets = emptyList(),
            memories = emptyList(),
            knowledgeItems = emptyList(),
            knowledgeStats = AgentKnowledgeStats(),
            capabilityMatrix = AgentRuntimeCapabilityMatrix.build(
                nativeTools = listOf(tool),
                systemTools = emptyList(),
                targets = emptyList()
            )
        )
    }
}
