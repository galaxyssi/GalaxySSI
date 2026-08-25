package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConnectorPromptContextPolicyTest {
    @Test
    fun supervisedProjectUsesItsCompiledPromptWithoutGeneralContextWrapping() {
        var wrapped = false

        val selected = AgentConnectorPromptContextPolicy.select(
            connectorTaskMode = PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
            compiledPrompt = "compiled project prompt"
        ) {
            wrapped = true
            "duplicated context"
        }

        assertEquals("compiled project prompt", selected)
        assertFalse(wrapped)
    }

    @Test
    fun ordinaryConnectorRequestsKeepGeneralConversationContext() {
        var wrapped = false

        val selected = AgentConnectorPromptContextPolicy.select(
            connectorTaskMode = "ordinary",
            compiledPrompt = "current request"
        ) {
            wrapped = true
            "request with conversation context"
        }

        assertEquals("request with conversation context", selected)
        assertTrue(wrapped)
    }

    @Test
    fun legacyPhoneDevelopmentAuthoringStillReceivesGeneralContext() {
        val selected = AgentConnectorPromptContextPolicy.select(
            connectorTaskMode = PHONE_DEVELOPMENT_CONNECTOR_MODE,
            compiledPrompt = "author code"
        ) {
            "author code with context"
        }

        assertEquals("author code with context", selected)
    }
}
