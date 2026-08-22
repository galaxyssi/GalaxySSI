package com.signalasi.chat

import org.junit.Assert.assertNotSame
import org.junit.Assert.assertFalse
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

    @Test
    fun `working set omits only blocked tools and compiles a new reusable prefix`() {
        val context = context()
        val blocked = setOf(AgentMobileProjectNativeTools.CLONE)

        val full = AgentSupervisedProjectPromptTemplate.render(context, false, 240)
        val focused = AgentSupervisedProjectPromptTemplate.render(
            context = context,
            evidenceExpected = false,
            maximumSchemaCharacters = 240,
            temporarilyBlockedToolIds = blocked
        )
        val focusedAgain = AgentSupervisedProjectPromptTemplate.render(
            context = context,
            evidenceExpected = false,
            maximumSchemaCharacters = 240,
            temporarilyBlockedToolIds = blocked
        )

        assertNotSame(full, focused)
        assertSame(focused, focusedAgain)
        assertTrue(focused.length < full.length)
        assertFalse(focused.contains("- ${AgentMobileProjectNativeTools.CLONE} |"))
        assertTrue(focused.contains("- ${AgentMobileProjectNativeTools.CREATE_PULL_REQUEST} |"))
        assertTrue(focused.contains("phase-blocked tools reappear when evidence changes"))
    }

    private fun context(): AgentRuntimeContext {
        fun tool(id: String) = AgentNativeToolDescriptor(
            id = id,
            version = "1.0.0",
            title = id,
            description = "Phone project tool",
            location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(
                properties = mapOf("workspace_id" to AgentNativeJsonSchema.string())
            ),
            outputSchema = AgentNativeJsonSchema.objectSchema(),
            risk = AgentNativeToolRisk.LOW
        )
        val tools = listOf(
            tool(AgentMobileProjectNativeTools.CLONE),
            tool(AgentMobileProjectNativeTools.CREATE_PULL_REQUEST)
        )
        return AgentRuntimeContext(
            sessionId = "template-test",
            goal = "Improve the phone project",
            screen = ScreenContext(foregroundApp = "com.signalasi.chat", pageTitle = "SignalASI"),
            permissionMode = PermissionMode.FULL_ACCESS,
            highRiskGuard = false,
            memoryCapture = false,
            systemTools = emptyList(),
            nativeTools = tools,
            callableTargets = emptyList(),
            memories = emptyList(),
            knowledgeItems = emptyList(),
            knowledgeStats = AgentKnowledgeStats(),
            capabilityMatrix = AgentRuntimeCapabilityMatrix.build(
                nativeTools = tools,
                systemTools = emptyList(),
                targets = emptyList()
            )
        )
    }
}
