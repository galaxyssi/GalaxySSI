package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentPublicArticleParserTest {
    @Test
    fun `wechat article extracts structured text and original images`() {
        val article = AgentPublicArticleParser.parse(
            "https://mp.weixin.qq.com/s/example",
            """
            <html><head><meta property="og:title" content="Fallback title"></head><body>
              <h1 id="activity-name">A useful article</h1>
              <span id="js_name">SignalASI Lab</span>
              <em id="publish_time">2026-08-11</em>
              <div id="js_content">
                <section><p>First paragraph.</p><p>Second paragraph.</p></section>
                <img data-src="https://mmbiz.qpic.cn/test/image?wx_fmt=png&amp;x=1" alt="Diagram">
                <a href="/s/related">Related article</a>
              </div>
            </body></html>
            """.trimIndent()
        )

        requireNotNull(article)
        assertEquals("A useful article", article.title)
        assertEquals("SignalASI Lab", article.author)
        assertEquals("2026-08-11", article.publishedAt)
        assertTrue(article.content.contains("First paragraph."))
        assertTrue(article.content.contains("Second paragraph."))
        assertEquals("wechat_public_account", article.sourceType)
        assertEquals("https://mp.weixin.qq.com/s/related", article.links.single())
        assertEquals(
            "https://mmbiz.qpic.cn/test/image?wx_fmt=png&x=1",
            article.images.single()["url"]
        )
    }

    @Test
    fun `non article pages are left to the generic parser`() {
        assertEquals(null, AgentPublicArticleParser.parse("https://example.com/", "<html></html>"))
    }

    @Test
    fun `ten megabyte fetch budget is shared by native and intelligence tools`() {
        assertEquals(10L * 1_048_576L, AgentWebMediaNativeTools.MAX_FETCH_BYTES)
        assertEquals(AgentWebMediaNativeTools.MAX_FETCH_BYTES, AgentWebIntelligenceService.MAX_FETCH_BYTES)
        assertFalse(AgentDynamicArticleRequestPolicy.headers("https://example.com/").isNotEmpty())
    }

    @Test
    fun `wechat request receives mobile browser headers without changing other hosts`() {
        val headers = AgentDynamicArticleRequestPolicy.headers("https://mp.weixin.qq.com/s/example")

        assertTrue(headers.getValue("User-Agent").contains("MicroMessenger"))
        assertEquals("https://mp.weixin.qq.com/", headers["Referer"])
        assertTrue(headers.getValue("Accept-Language").startsWith("zh-CN"))
    }

    @Test
    fun `web intelligence response exposes article image evidence once`() {
        val html = """
            <html><body>
              <h1 id="activity-name">Article result</h1>
              <div id="js_content">
                <p>Readable evidence.</p>
                <img data-src="https://mmbiz.qpic.cn/test/result.jpg" alt="Result">
              </div>
            </body></html>
        """.trimIndent()
        val fetcher = AgentWebIntelligenceFetcher { url, _, _, _, _ ->
            AgentWebIntelligenceFetched(url, "text/html; charset=utf-8", html.toByteArray())
        }
        val service = AgentWebIntelligenceService(fetcher, AgentInMemoryWebIntelligenceStore())

        val response = service.fetch(mapOf("url" to "https://mp.weixin.qq.com/s/example"))
        val document = (response["documents"] as List<*>).single() as Map<*, *>
        val metadata = document["metadata"] as Map<*, *>

        assertEquals("mobile_article_https", metadata["fetch_tier"])
        assertEquals(1, metadata["image_count"])
        assertEquals(1, (metadata["images"] as List<*>).size)
        assertEquals("Article result", document["title"])
        assertTrue(document["content"].toString().contains("Readable evidence."))
    }
}
