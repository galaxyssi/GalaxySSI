package com.galaxyssi.chat

import java.io.ByteArrayInputStream
import org.junit.Assert.*
import org.junit.Test

class AgentHtmlArtifactPreviewTest {
    private val file = AgentRichBlock("html", AgentRichBlockType.FILE, title = "animation.html")

    @Test fun recognizesHtmlFilesButDoesNotExecuteCodeAndRemoteLinks() {
        assertTrue(AgentHtmlArtifactPreview.supports(file.copy(mimeType = "text/html; charset=utf-8")))
        assertTrue(AgentHtmlArtifactPreview.supports(file.copy(title = "ANIMATION.HTM")))
        assertTrue(AgentHtmlArtifactPreview.supports(file.copy(mimeType = "application/octet-stream")))
        assertFalse(AgentHtmlArtifactPreview.supports(file.copy(mimeType = "text/plain")))
        assertFalse(AgentHtmlArtifactPreview.supports(file.copy(type = AgentRichBlockType.CODE)))
        assertFalse(AgentHtmlArtifactPreview.supports(file.copy(type = AgentRichBlockType.LINK)))
        assertFalse(AgentHtmlArtifactPreview.supports(file.copy(title = "report.pdf")))
    }

    @Test fun readsCompleteScriptsBeyondOld32kLimitAndRejectsOversizeInsteadOfTruncating() {
        val html = "<html>" + " ".repeat(40_000) + "<script>window.complete=true;</script></html>"
        assertEquals(html, AgentHtmlArtifactPreview.readBounded(ByteArrayInputStream(html.toByteArray())).toString(Charsets.UTF_8))
        val maximum = ByteArray(AgentHtmlArtifactPreview.MAX_BYTES) { 32 }
        assertArrayEquals(maximum, AgentHtmlArtifactPreview.readBounded(ByteArrayInputStream(maximum)))
        assertThrows(IllegalArgumentException::class.java) {
            AgentHtmlArtifactPreview.readBounded(ByteArrayInputStream(ByteArray(maximum.size + 1)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            AgentHtmlArtifactPreview.readBounded(ByteArrayInputStream(byteArrayOf()))
        }
    }
}
