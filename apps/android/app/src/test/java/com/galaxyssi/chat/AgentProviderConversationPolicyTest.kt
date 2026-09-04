package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentProviderConversationPolicyTest {
    @Test
    fun providerInsideAgentConversationDoesNotCreateDedicatedContactHistory() {
        assertFalse(AgentProviderConversationPolicy.shouldPersistDedicatedHistory("conversation-1"))
    }

    @Test
    fun standaloneProviderConversationKeepsDedicatedContactHistory() {
        assertTrue(AgentProviderConversationPolicy.shouldPersistDedicatedHistory(""))
    }
}
