package com.galaxyssi.chat

import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class AgentWebOriginalDocumentTest {
    private val url = "https://example.com/article"
    private fun build(html: String, load: (String) -> OriginalPageAsset? = { null }) =
        AgentWebOriginalDocument.build(url, html.toByteArray(), load)

    @Test fun preservesInterleavedParagraphImagesAndTable() {
        val result = build("<article><p>First</p><img src='/a.png'><p>Second</p><table><tr><td>Value</td></tr></table><img src='/b.png'><p>Last</p></article>") {
            OriginalPageAsset("image/png", byteArrayOf(1, 2, 3))
        }
        val article = Jsoup.parse(result.html).selectFirst("article")!!
        assertEquals(listOf("p", "img", "p", "table", "img", "p"), article.children().map { it.tagName() })
        assertEquals(2, result.embedded)
        assertEquals(0, result.missing)
        assertTrue(article.select("img").all { it.attr("src").startsWith("data:image/png;base64,") })
    }

    @Test fun localizesLazyImagesWithoutReorderingThem() {
        val requests = mutableListOf<String>()
        val result = build("<div id='js_content' style='visibility:hidden'><p>Before</p><img data-src='/real.webp' src='/placeholder.png' srcset='/network.png 2x'><p>After</p></div>") {
            requests += it; OriginalPageAsset("image/webp", byteArrayOf(1))
        }
        assertEquals(listOf("https://example.com/real.webp"), requests)
        val doc = Jsoup.parse(result.html)
        assertFalse(doc.selectFirst("img")!!.hasAttr("srcset"))
        assertTrue(doc.selectFirst("#js_content")!!.attr("style").contains("visibility:visible!important"))
    }

    @Test fun retainsStylesAndEmbedsCssImages() {
        val result = build("<head><link rel='stylesheet' href='/styles/main.css'></head><body><p class='test'>Styled</p></body>") {
            when {
                it.endsWith("main.css") -> OriginalPageAsset("text/css", ".test{color:red;background:url(../bg.png)}".toByteArray())
                it.endsWith("bg.png") -> OriginalPageAsset("image/png", byteArrayOf(1))
                else -> null
            }
        }
        val doc = Jsoup.parse(result.html)
        assertTrue(doc.select("style").text().isEmpty())
        assertTrue(doc.selectFirst("style")!!.data().contains("color:red"))
        assertTrue(doc.selectFirst("style")!!.data().contains("data:image/png"))
        assertTrue(doc.select("link").isEmpty())
    }

    @Test fun removesActiveContentAndBlocksUnexpectedNetworkAccess() {
        val result = build("<meta http-equiv='refresh' content='0;url=https://evil.example'><script>alert(1)</script><p onclick='evil()'>Keep</p><iframe src='file:///private'></iframe><a href='javascript:evil()'>Link</a><img src='http://127.0.0.1/x'>") {
            fail("Unsafe resource must not be fetched: $it"); null
        }
        val doc = Jsoup.parse(result.html)
        assertTrue(doc.select("script,iframe,[onclick]").isEmpty())
        assertFalse(doc.selectFirst("a")!!.hasAttr("href"))
        assertTrue(doc.selectFirst("meta[http-equiv]")!!.attr("content").contains("default-src 'none'"))
        assertTrue(doc.body().text().contains("Keep"))
        assertEquals(1, result.missing)
    }

    @Test fun missingImagesStayInPlaceAndAreReported() {
        val result = build("<article><p>Before</p><img src='/missing.jpg'><p>After</p></article>")
        val article = Jsoup.parse(result.html).selectFirst("article")!!
        assertEquals(listOf("p", "img", "p"), article.children().map { it.tagName() })
        assertEquals(1, result.missing)
        assertFalse(article.selectFirst("img")!!.hasAttr("src"))
    }

    @Test fun articleImagesAreFetchedBeforeDecorationsAndDecorationDownloadsAreBounded() {
        val calls = mutableListOf<String>()
        val css = (1..30).joinToString("") { ".emoji$it{background:url('/icon$it.png')}" }
        val result = build("<style>$css</style><article><img src='/figure.png'></article>") {
            calls += it; OriginalPageAsset("image/png", byteArrayOf(1))
        }
        assertEquals("https://example.com/figure.png", calls.first())
        assertEquals(9, calls.size)
        assertTrue(Jsoup.parse(result.html).selectFirst("article img")!!.attr("src").startsWith("data:"))
    }

    @Test fun archiveCallbackReceivesOriginalMarkupWithoutAddingItToModelEvidence() {
        val raw = "<html><title>Article</title><article><p>Before the picture, enough text for parsing.</p><img src='/a.png'><p>After the picture, the last paragraph.</p></article></html>"
        val service = AgentWebIntelligenceService(AgentWebIntelligenceFetcher { address, _, _, _, _ ->
            AgentWebIntelligenceFetched(address, "text/html", raw.toByteArray())
        }, AgentInMemoryWebIntelligenceStore())
        var captured = ""
        val result = service.prefetchDocuments(listOf(url), captureSource = { _, fetched -> captured = fetched.body.toString(Charsets.UTF_8) })
        assertEquals(raw, captured)
        assertEquals(1, result.documents.size)
        assertFalse(result.documents.single().publicValue().toString().contains("<article>"))
    }
}
