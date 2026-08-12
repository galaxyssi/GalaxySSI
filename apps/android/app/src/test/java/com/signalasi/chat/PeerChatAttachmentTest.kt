package com.signalasi.chat

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Test

class PeerChatAttachmentTest {
    @Test
    fun `attachment metadata survives encrypted history serialization`() {
        val source = listOf(
            PeerChatAttachment(
                name = "report.pdf",
                mimeType = "application/pdf",
                sizeBytes = 42_000,
                uri = "content://signalasi/report",
                artifactUri = "signalasi-artifact://report"
            )
        )

        val decoded = PeerChatAttachment.decode(PeerChatAttachment.encode(source))

        assertEquals(source, decoded)
    }

    @Test
    fun `invalid attachment entries are ignored`() {
        val decoded = PeerChatAttachment.decode(JSONArray().put("invalid"))

        assertEquals(emptyList<PeerChatAttachment>(), decoded)
    }
}
