package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentAndroidDownloadCoordinatorTest {
    @Test
    fun `article urls receive a unique html file name`() {
        val fileName = AgentAndroidDownloadPolicy.destinationFileName(
            url = "https://mp.weixin.qq.com/s/example",
            timestampMillis = 1_700_000_000_000L
        )

        assertTrue(fileName.startsWith("article-"))
        assertTrue(fileName.endsWith(".html"))
        assertEquals("Download/GalaxySSI/$fileName", AgentAndroidDownloadPolicy.relativePath(fileName))
    }

    @Test
    fun `real extensions are preserved and generic titles are ignored`() {
        val fileName = AgentAndroidDownloadPolicy.destinationFileName(
            url = "https://example.com/releases/report%20final.zip?download=1",
            title = "GalaxySSI download",
            timestampMillis = 1_700_000_000_000L
        )

        assertTrue(fileName.startsWith("report final-"))
        assertTrue(fileName.endsWith(".zip"))
        assertFalse(fileName.contains("GalaxySSI download"))
    }

    @Test
    fun `unsafe title characters are removed`() {
        val fileName = AgentAndroidDownloadPolicy.destinationFileName(
            url = "https://example.com/file.pdf",
            title = "report: July/2026",
            timestampMillis = 1_700_000_000_000L
        )

        assertFalse(fileName.contains(':'))
        assertFalse(fileName.contains('/'))
        assertTrue(fileName.endsWith(".pdf"))
    }

    @Test
    fun `download copy follows configured language`() {
        assertTrue(AgentAndroidDownloadPolicy.startedMessage(true).startsWith("\u5df2\u5f00\u59cb\u4e0b\u8f7d"))
        assertTrue(AgentAndroidDownloadPolicy.completedMessage(true, "article.html").contains("Download/GalaxySSI"))
        assertTrue(AgentAndroidDownloadPolicy.startedMessage(false).startsWith("Download started"))
        assertTrue(AgentAndroidDownloadPolicy.failedMessage(false, "article.html").startsWith("Download failed"))
    }

    @Test
    fun `completion artifact is a local openable file card`() {
        val encoded = AgentRichContentCodec.encode(listOf(AgentRichBlock(
            id = "android-download:42",
            type = AgentRichBlockType.FILE,
            title = "article.html",
            text = "Download/GalaxySSI/article.html",
            uri = "content://downloads/my_downloads/42",
            mimeType = "text/html",
            metadata = mapOf("saved_to_downloads" to "true")
        )))
        val block = AgentRichContentCodec.decode(encoded).single()

        assertEquals(AgentRichBlockType.FILE, block.type)
        assertEquals("content://downloads/my_downloads/42", block.uri)
        assertEquals("true", block.metadata["saved_to_downloads"])
    }
}
