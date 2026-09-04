package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PeerChatAttachmentTest {
    @Test
    fun codecPreservesVerifiedTransferAndVoiceDuration() {
        val original = PeerChatAttachment(
            name = "voice-42.m4a",
            mimeType = "audio/mp4",
            sizeBytes = 18_432L,
            uri = "content://com.galaxyssi.chat.files/peer/voice-42.m4a",
            transferId = "a".repeat(64),
            sha256 = "b".repeat(64),
            durationMillis = 4_000L
        )

        val decoded = PeerChatAttachment.decode(PeerChatAttachment.encode(listOf(original))).single()

        assertEquals(original, decoded)
    }

    @Test
    fun peerPresentationDoesNotInventAttachmentText() {
        val payload = JSONObject()
            .put("type", "peer_message")
            .put("content", "")

        assertEquals("", PeerChatPresentation.incomingContent(payload.toString(), payload))
    }

    @Test
    fun foregroundTrackerNotifiesOnlyOutsideVisibleConversation() {
        val activity = Any()
        AppForegroundTracker.onActivityForeground(activity)
        AppForegroundTracker.onConversationVisible(activity, "galaxyssi:0123456789abcdef")

        assertTrue(AppForegroundTracker.isForeground())
        assertTrue(AppForegroundTracker.isConversationVisible("galaxyssi:0123456789abcdef"))
        assertFalse(AppForegroundTracker.isConversationVisible("galaxyssi:fedcba9876543210"))

        AppForegroundTracker.onActivityBackground(activity)
        assertFalse(AppForegroundTracker.isForeground())
        assertFalse(AppForegroundTracker.isConversationVisible("galaxyssi:0123456789abcdef"))
    }
}
