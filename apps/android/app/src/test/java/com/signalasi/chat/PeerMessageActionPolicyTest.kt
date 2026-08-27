package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class PeerMessageActionPolicyTest {
    @Test
    fun voiceMessagesOfferTranscriptionAndDeleteOnly() {
        val message = message(
            PeerChatAttachment(
                name = "voice-42.opus",
                mimeType = "audio/ogg; codecs=opus",
                sizeBytes = 128L
            )
        )

        assertNotNull(PeerMessageActionPolicy.voiceAttachment(message))
        assertEquals(
            listOf(PeerMessageAction.TRANSCRIBE, PeerMessageAction.DELETE),
            PeerMessageActionPolicy.actions(message)
        )
    }

    @Test
    fun ordinaryMessagesKeepCopyAndDelete() {
        assertEquals(
            listOf(PeerMessageAction.COPY, PeerMessageAction.DELETE),
            PeerMessageActionPolicy.actions(message())
        )
    }

    @Test
    fun peerTranscriptionReturnsTextWithoutCommandExecution() {
        assertEquals(
            true,
            PeerVoiceTranscriptionPolicy.returnsTextWithoutCommandExecution(
                PEER_VOICE_TRANSCRIPTION_PURPOSE
            )
        )
        assertEquals(
            false,
            PeerVoiceTranscriptionPolicy.returnsTextWithoutCommandExecution("chat")
        )
    }

    private fun message(vararg attachments: PeerChatAttachment) = ChatMessage(
        id = 42L,
        content = "",
        isMine = false,
        contact = Contact("peer", "Peer", ""),
        attachments = attachments.toList()
    )
}
