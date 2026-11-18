package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class PeerAttachmentOpenPolicyTest {
    @Test fun pdfReceivesItsCanonicalMediaType() {
        for (type in listOf("", "application/octet-stream", "binary/octet-stream", "*/*", "application/x-pdf", " APPLICATION/PDF ; charset=binary")) {
            assertEquals(type, "application/pdf", PeerAttachmentOpen.mimeType("report.PDF", type))
        }
    }

    @Test fun fileNamesDoNotOverrideAKnownMediaType() {
        assertEquals("image/png", PeerAttachmentOpen.mimeType("misnamed.pdf", "image/png"))
        assertEquals("application/octet-stream", PeerAttachmentOpen.mimeType("report.pdf.exe", ""))
        assertEquals("text/plain", PeerAttachmentOpen.mimeType("note.txt", "text/plain; charset=utf-8"))
    }
}
