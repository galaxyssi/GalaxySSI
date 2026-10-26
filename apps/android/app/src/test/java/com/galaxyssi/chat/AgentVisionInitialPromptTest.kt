package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentVisionInitialPromptTest {
    private val turn = "vision-prompt-test"

    @Test fun imageQuestionUsesCompactPromptAndRetainsPhoneBoundary() {
        val request = request()
        val prompt = requireNotNull(AgentVisionInitialPrompt.render(request, listOf("image/jpeg")))
        assertTrue(prompt.length < 5_000)
        assertTrue(prompt.contains("final_response"))
        assertTrue(prompt.contains("galaxyssi.tools.discover"))
        assertTrue(prompt.contains("execution belongs to Android"))
        assertFalse(prompt.contains("Available phone tools:"))
        assertFalse(prompt.contains("Git:"))
        assertTrue(prompt.contains(request.goal))
    }

    @Test fun editsAreNotKeywordRoutedOrDeclaredComplete() {
        val prompt = requireNotNull(AgentVisionInitialPrompt.render(request().copy(goal = "Annotate and send back this image"), listOf("image/jpeg")))
        assertTrue(prompt.contains("edit/export images"))
        assertTrue(prompt.contains("completes_goal\":false"))
        assertTrue(prompt.contains("Wait for its real receipt"))
    }

    @Test fun recoveryMixedFilesMissingAndOtherTurnImagesKeepFullLoop() {
        assertNull(AgentVisionInitialPrompt.render(request()))
        assertNull(AgentVisionInitialPrompt.render(request(), listOf("application/pdf")))
        assertNull(AgentVisionInitialPrompt.render(request(), listOf("image/jpeg", "application/pdf")))
        assertNull(AgentVisionInitialPrompt.render(request().copy(replanReason = "failed tool"), listOf("image/jpeg")))
        assertNull(AgentVisionInitialPrompt.render(request().copy(executionTurnId = "other")))
        assertNull(AgentVisionInitialPrompt.render(request().let { it.copy(runtimeContext = it.runtimeContext.copy(nativeTools = emptyList())) }, listOf("image/jpeg")))
        assertTrue(AgentSupervisedProjectLoop.continuationPrompt(request()).contains("Available phone tools:"))
    }

    @Test fun conversationContextIsPreserved() {
        val req = request()
        val prompt = requireNotNull(AgentVisionInitialPrompt.render(req.copy(conversationContext =
            req.conversationContext.copy(summary = "User asks to read the handwritten equation.")), listOf("image/jpeg")))
        assertTrue(prompt.contains("handwritten equation"))
        assertNotNull(AgentSupervisedProjectPromptEnvelope.split(prompt))
    }

    private fun request(): AgentRequest {
        val screen = ScreenContext("test", pageTitle = "test")
        val discover = AgentNativeToolDescriptor(id = "galaxyssi.tools.discover", version = "1.0.0",
            title = "Discover", description = "Discover capabilities", location = AgentNativeToolLocation.PHONE,
            inputSchema = AgentNativeJsonSchema.objectSchema(emptyMap()),
            outputSchema = AgentNativeJsonSchema.objectSchema(emptyMap()), risk = AgentNativeToolRisk.LOW,
            idempotency = AgentNativeToolIdempotency.IDEMPOTENT)
        return AgentRequest("Read this image", screen, emptyList(), memories = emptyList(),
            runtimeContext = AgentRuntimeContextBuilder.build("test", "Read this image", screen,
                PermissionMode.FULL_ACCESS, false, false, emptyList(), emptyList(),
                nativeTools = listOf(discover)), executionTurnId = turn)
    }
}
