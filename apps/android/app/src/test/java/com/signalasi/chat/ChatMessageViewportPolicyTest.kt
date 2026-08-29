package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatMessageViewportPolicyTest {
    @Test
    fun systemNotificationsOpenFromTheTop() {
        assertFalse(ChatMessageViewportPolicy.stackFromEnd(systemNotifications = true))
        assertTrue(ChatMessageViewportPolicy.anchorToStartOnOpen(systemNotifications = true))
    }

    @Test
    fun regularChatsRemainAnchoredToTheLatestMessage() {
        assertTrue(ChatMessageViewportPolicy.stackFromEnd(systemNotifications = false))
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
}
