package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatHistoryLoadPolicyTest {
    @Test
    fun emptyMemoryAlwaysReloadsEncryptedHistory() {
        assertTrue(ChatHistoryLoadPolicy.shouldReload(true, true))
    }

    @Test
    fun populatedLoadedConversationDoesNotReloadNeedlessly() {
        assertFalse(ChatHistoryLoadPolicy.shouldReload(false, true))
    }

    @Test
    fun neverLoadedConversationReloads() {
        assertTrue(ChatHistoryLoadPolicy.shouldReload(false, false))
    }
}
