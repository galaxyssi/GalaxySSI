package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatMessageViewportPolicyTest {
    @Test
    fun systemNotificationsOpenFromTheTop() {
        assertFalse(ChatMessageViewportPolicy.stackFromEnd())
        assertTrue(ChatMessageViewportPolicy.anchorToStartOnOpen(systemNotifications = true))
    }

    @Test
    fun regularChatsFillFromTopButStillOpenAtTheLatestMessage() {
        assertFalse(ChatMessageViewportPolicy.stackFromEnd())
        assertFalse(ChatMessageViewportPolicy.anchorToStartOnOpen(systemNotifications = false))
    }

    @Test
    fun liveSystemNotificationsDoNotForceTheReaderToTheBottom() {
        assertFalse(
            ChatMessageViewportPolicy.followLatest(
                systemNotifications = true,
                nearBottom = true
            )
        )
        assertTrue(
            ChatMessageViewportPolicy.followLatest(
                systemNotifications = false,
                nearBottom = true
            )
        )
    }

    @Test
    fun newMessagesDoNotInterruptReadingOlderHistory() {
        assertFalse(ChatMessageViewportPolicy.followLatest(systemNotifications = false, nearBottom = false))
        assertFalse(ChatMessageViewportPolicy.followLatest(systemNotifications = true, nearBottom = false))
    }
}
