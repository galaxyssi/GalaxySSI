package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalModelConversationPolicyTest {
    @Test
    fun agentConversationDoesNotCreateDedicatedLocalModelHistory() {
        assertFalse(LocalModelConversationPolicy.shouldPersistDedicatedHistory("conversation-1"))
    }

    @Test
    fun standaloneLocalModelCallCanKeepDedicatedHistory() {
        assertTrue(LocalModelConversationPolicy.shouldPersistDedicatedHistory(""))
    }
}
