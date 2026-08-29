package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class PeerMessageActionPolicyTest {
    @Test
    fun everyMessageTypeOffersCopyAndDeleteOnly() {
        val messages = listOf(
            message(content = "hello"),
            message(attachment("photo.jpg", "image/jpeg")),
            message(attachment("voice.opus", "audio/ogg; codecs=opus")),
            message(attachment("project.zip", "application/zip"))
        )

        messages.forEach { message ->
            assertEquals(
                listOf(PeerMessageAction.COPY, PeerMessageAction.DELETE),
                PeerMessageActionPolicy.actionsFor(message)
            )
        }
    }

    @Test
    fun copyUsesVisibleTextThenAttachmentNames() {
        assertEquals("hello", PeerMessageActionPolicy.copyText(message(content = "hello")))
        assertEquals(
            "photo.jpg\nproject.zip",
            PeerMessageActionPolicy.copyText(
                message(
                    attachment("photo.jpg", "image/jpeg"),
                    attachment("project.zip", "application/zip")
                )
            )
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

    private fun attachment(name: String, mimeType: String) = PeerChatAttachment(
        name = name,
        mimeType = mimeType,
        sizeBytes = 128L
    )

    private fun message(
        vararg attachments: PeerChatAttachment,
        content: String = ""
    ) = ChatMessage(
        id = 42L,
        content = content,
        isMine = false,
        contact = Contact("peer", "Peer", ""),
        attachments = attachments.toList()
    )
}
