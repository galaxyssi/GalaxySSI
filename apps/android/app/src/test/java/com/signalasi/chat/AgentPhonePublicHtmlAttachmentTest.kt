package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class AgentPhonePublicHtmlAttachmentTest {
    @Test
    fun extractsMultipleExplicitPublicHttpsUrls() {
        assertEquals(
            listOf(
                "https://mp.weixin.qq.com/s/example?a=1",
                "https://example.com/other"
            ),
            AgentPhonePublicHtmlAttachment.explicitPublicUrls(
                "Read https://mp.weixin.qq.com/s/example?a=1, then summarize https://example.com/other"
            )
        )
    }

    @Test
    fun boundsExplicitPublicUrlsPerTurn() {
        val urls = (1..6).joinToString(" ") { "https://source-$it.example/article" }

        assertEquals(4, AgentPhonePublicHtmlAttachment.explicitPublicUrls(urls).size)
    }

    @Test
    fun ignoresNonHttpsUrls() {
        assertTrue(AgentPhonePublicHtmlAttachment.explicitPublicUrls("http://example.com/a").isEmpty())
    }

    @Test
    fun separatesAnAsciiUrlFromAdjacentChineseInstructions() {
        val url = "https://mp.weixin.qq.com/s/sRAngxDkA5FNRteEhAUPVQ"

        assertEquals(
            listOf(url),
            AgentPhonePublicHtmlAttachment.explicitPublicUrls(
                "${url}\u7406\u89e3\u548c\u603b\u7ed3\u4e00\u4e0b\uff0c\u4e3a\u5565\u5b83\u80fd\u81ea\u5df1\u8fdb\u5316"
            )
        )
        assertEquals(
            url,
            AgentPhonePublicHtmlAttachment.preferredPublicUrl(
                "${url}\u7406\u89e3\u548c\u603b\u7ed3\u4e00\u4e0b\uff0c\u4e3a\u5565\u5b83\u80fd\u81ea\u5df1\u8fdb\u5316"
            )
        )
    }

    @Test
    fun preservesPercentEncodedInternationalUrlPaths() {
        assertEquals(
            listOf("https://example.com/%E4%B8%AD%E6%96%87?lang=zh-CN"),
            AgentPhonePublicHtmlAttachment.explicitPublicUrls(
                "Read https://example.com/%E4%B8%AD%E6%96%87?lang=zh-CN \u5e76\u603b\u7ed3"
            )
        )
    }

    @Test
    fun prefersArticleUrlFromEarlierConversationContext() {
        assertEquals(
            "https://mp.weixin.qq.com/s/article",
            AgentPhonePublicHtmlAttachment.preferredPublicUrl(
                "User: https://mp.weixin.qq.com/s/article\nAssistant: source https://example.com/help\nUser: save it"
            )
        )
    }

    @Test
    fun onlyUsesHistoryForAContinuationRequest() {
        assertTrue(AgentPhonePublicHtmlAttachment.shouldUseConversationContext("save it"))
        assertTrue(AgentPhonePublicHtmlAttachment.shouldUseConversationContext("\u628a\u5b83\u4fdd\u5b58\u4e0b\u6765"))
        assertFalse(AgentPhonePublicHtmlAttachment.shouldUseConversationContext("hello"))
    }

    @Test
    fun recognizesExplicitSaveRequests() {
        assertTrue(AgentPhonePublicHtmlAttachment.isSaveRequest("download this page"))
        assertTrue(AgentPhonePublicHtmlAttachment.isSaveRequest("\u4fdd\u5b58\u8fd9\u4e2a\u7f51\u9875"))
        assertFalse(AgentPhonePublicHtmlAttachment.isSaveRequest("summarize this page"))
    }

    @Test
    fun followUpRestoresLatestPublicUrlFromRawUserMessages() {
        val request = AgentPhonePublicHtmlAttachment.captureRequest(
            currentRequest = "save it",
            recentUserMessages = listOf(
                "Read https://example.com/older",
                "Read https://mp.weixin.qq.com/s/latest-article",
                "save it"
            )
        )

        assertTrue(request.contains("https://mp.weixin.qq.com/s/latest-article"))
    }

    @Test
    fun unrelatedRequestDoesNotRestoreHistoricalUrl() {
        val request = AgentPhonePublicHtmlAttachment.captureRequest(
            currentRequest = "hello",
            recentUserMessages = listOf("Read https://example.com/older")
        )

        assertEquals("hello", request)
    }

    @Test
    fun rendersReadableUntrustedHtml() {
        val html = AgentPhonePublicHtmlAttachment.render(
            AgentPhonePublicHtmlDocument(
                url = "https://example.com/article?a=1&b=2",
                title = "A <title>",
                content = "First paragraph.\n\nSecond <paragraph>.",
                author = "Author & Editor",
                images = listOf(mapOf("url" to "https://example.com/image.jpg", "alt" to "Chart"))
            )
        )

        assertTrue(html.contains("<!doctype html>"))
        assertTrue(html.contains("untrusted-public-source"))
        assertTrue(html.contains("A &lt;title&gt;"))
        assertTrue(html.contains("Second &lt;paragraph&gt;."))
        assertTrue(html.contains("https://example.com/image.jpg"))
        assertFalse(html.contains("Second <paragraph>."))
    }

    @Test
    fun stagesGeneratedArticleAsPlainHtml() {
        val directory = Files.createTempDirectory("signalasi-public-html").toFile()
        val file = directory.resolve("article.html")
        val html = "<!doctype html><html><body>Readable article</body></html>"

        try {
            val size = AgentPhonePublicHtmlAttachment.writePlaintextHtml(file, html)

            assertEquals(html.toByteArray(Charsets.UTF_8).size.toLong(), size)
            assertEquals(html, file.readText(Charsets.UTF_8))
            assertEquals("html", file.extension)
            assertFalse(file.name.endsWith(".sasie"))
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun inlineFallbackMarksHtmlAsUntrustedAttachmentEvidence() {
        val html = "<!doctype html><html><body>Article evidence</body></html>"
        val prompt = AgentPhonePublicHtmlAttachment.inlineEvidence(
            displayName = "article.html",
            sourceUrl = "https://example.com/article",
            savedToDownloads = false,
            readableHtml = html
        )

        assertTrue(prompt.contains(AgentPhonePublicHtmlAttachment.PROMPT_MARKER))
        assertTrue(prompt.contains(AgentUntrustedEvidenceBoundary.CONTRACT_VERSION))
        assertTrue(prompt.contains("Article evidence"))
        assertTrue(prompt.contains("article.html"))
    }
}
