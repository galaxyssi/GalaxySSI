package com.galaxyssi.chat

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
              <span id="js_name">GalaxySSI Lab</span>
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
        assertEquals("GalaxySSI Lab", article.author)
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
    fun `empty pages are left to the bounded text fallback`() {
        assertEquals(null, AgentPublicArticleParser.parse("https://example.com/", "<html></html>"))
    }

    @Test
    fun `generic article uses json ld metadata and removes page chrome`() {
        val article = AgentPublicArticleParser.parse(
            "https://news.example.com/reports/agent-web",
            """
            <html>
              <head>
                <title>Fallback site title</title>
                <meta property="og:image" content="https://cdn.example.com/lead.jpg">
                <script type="application/ld+json">
                {
                  "@context":"https://schema.org",
                  "@type":"NewsArticle",
                  "headline":"A structured report",
                  "datePublished":"2026-08-30T10:15:00+08:00",
                  "author":[{"@type":"Person","name":"Ada"},{"@type":"Person","name":"Lin"}],
                  "image":{"url":"https://cdn.example.com/structured.jpg"}
                }
                </script>
              </head>
              <body>
                <nav>Home Products Pricing Account</nav>
                <main>
                  <article>
                    <h1>Visible heading</h1>
                    <p>The first paragraph contains enough detail to identify the main article body.</p>
                    <div class="advertisement">Buy unrelated things now.</div>
                    <p>The second paragraph explains the evidence and its practical limitations.</p>
                    <figure>
                      <img data-lazy-src="/media/chart.png" width="1200" height="800">
                      <figcaption>Measured results</figcaption>
                    </figure>
                    <a href="/sources/method">Method source</a>
                  </article>
                </main>
                <footer>Terms Privacy Newsletter</footer>
              </body>
            </html>
            """.trimIndent()
        )

        requireNotNull(article)
        assertEquals("A structured report", article.title)
        assertEquals("Ada, Lin", article.author)
        assertEquals("2026-08-30T10:15:00+08:00", article.publishedAt)
        assertEquals("structured_web_article", article.sourceType)
        assertTrue(article.content.contains("first paragraph"))
        assertTrue(article.content.contains("second paragraph"))
        assertFalse(article.content.contains("Buy unrelated"))
        assertFalse(article.content.contains("Terms Privacy"))
        assertEquals("https://news.example.com/sources/method", article.links.single())
        assertEquals(
            listOf(
                "https://cdn.example.com/structured.jpg",
                "https://cdn.example.com/lead.jpg",
                "https://news.example.com/media/chart.png"
            ),
            article.images.map { it["url"] }
        )
        assertEquals("Measured results", article.images.last()["alt"])
        assertEquals(1200, article.images.last()["width"])
    }

    @Test
    fun `generic page uses open graph metadata and density selected content`() {
        val article = AgentPublicArticleParser.parse(
            "https://docs.example.org/guide/start",
            """
            <html><head>
              <meta property="og:title" content="Agent setup guide">
              <meta name="author" content="GalaxySSI Docs">
              <meta property="article:published_time" content="2026-08-29">
              <script type="application/ld+json">
                {"@type":"Organization","name":"This is the publisher, not the page title"}
              </script>
            </head><body>
              <div class="menu">One Two Three Four Five Six Seven Eight Nine Ten</div>
              <section class="documentation">
                <h1>Setup</h1>
                <p>This guide explains how to prepare the runtime before starting a task.</p>
                <p>It also records verification output so failures can be diagnosed later.</p>
                <img srcset="/img/small.png 320w, /img/large.png 1280w" alt="Setup screen">
              </section>
            </body></html>
            """.trimIndent()
        )

        requireNotNull(article)
        assertEquals("Agent setup guide", article.title)
        assertEquals("GalaxySSI Docs", article.author)
        assertEquals("2026-08-29", article.publishedAt)
        assertEquals("generic_web_page", article.sourceType)
        assertFalse(article.content.contains("One Two Three"))
        assertEquals("https://docs.example.org/img/large.png", article.images.single()["url"])
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

    @Test
    fun `web intelligence exposes structured generic article metadata`() {
        val html = """
            <html><head>
              <meta property="og:title" content="Generic result">
              <meta name="author" content="Research Team">
            </head><body><article>
              <p>A generic public article now uses the shared structured extraction pipeline.</p>
              <p>The resulting evidence includes normalized metadata and readable body content.</p>
            </article></body></html>
        """.trimIndent()
        val fetcher = AgentWebIntelligenceFetcher { url, _, _, _, _ ->
            AgentWebIntelligenceFetched(url, "text/html; charset=utf-8", html.toByteArray())
        }
        val service = AgentWebIntelligenceService(fetcher, AgentInMemoryWebIntelligenceStore())

        val response = service.fetch(mapOf("url" to "https://example.com/article"))
        val document = (response["documents"] as List<*>).single() as Map<*, *>
        val metadata = document["metadata"] as Map<*, *>

        assertEquals("structured_public_https", metadata["fetch_tier"])
        assertEquals("structured_web_article", metadata["article_source"])
        assertEquals("Research Team", metadata["author"])
        assertEquals("Generic result", document["title"])
        assertTrue(document["content"].toString().contains("structured extraction pipeline"))
    }
}
