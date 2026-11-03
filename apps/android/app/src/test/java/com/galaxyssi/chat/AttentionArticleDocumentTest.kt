package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

class AttentionArticleDocumentTest {
    private val body = "研究人员表示，新设备预计下个月发布，实际效果仍需要进一步验证。".repeat(8)
    private fun parse(html: String, images: List<AgentNativeJsonObject> = emptyList()) =
        AttentionArticleDocumentParser.parse("https://example.com/news/one", Jsoup.parseBodyFragment(html).body(), images)

    @Test fun retainsHeadingsEmphasisQuotesAndImageOrder() {
        val document = parse("<h2>研究进展</h2><p>目前<strong>尚未确认</strong>效果。</p>" +
            "<figure><img src='/photo.jpg' width='800' height='600'><figcaption>实验现场</figcaption></figure>" +
            "<blockquote><p>仍需复核</p></blockquote><ul><li>计划公开数据</li></ul>")
        assertEquals(listOf("heading", "paragraph", "image", "caption", "quote", "list"), document.blocks.map { it.kind })
        assertEquals(listOf("尚未确认"), document.blocks[1].emphasis)
        assertEquals("https://example.com/photo.jpg", document.cover!!.url)
        assertEquals(800, document.cover!!.width)
    }

    @Test fun inlineImageDoesNotMoveSurroundingParagraphs() {
        val document = parse("<p>图片前面的文字<img data-src='/photo.jpg'>图片后面的文字</p>")
        assertEquals(listOf("paragraph", "image", "paragraph"), document.blocks.map { it.kind })
        assertEquals("图片后面的文字", document.blocks.last().text)
    }

    @Test fun lazyImagesAndSrcsetResolveAgainstArticleUrl() {
        val document = parse("<img src='/placeholder' data-src='real.jpg'><img srcset='/small.jpg 1x, /large.jpg 2x'>")
        assertEquals(listOf("https://example.com/news/real.jpg", "https://example.com/large.jpg"), document.blocks.map { it.url })
    }

    @Test fun ignoresScriptsTrackersCredentialsAndNonWebImages() {
        val document = parse("<script>alert(1)</script><img src='file:///secret'><img src='data:image/png,test'>" +
            "<img src='https://user:password@example.com/a'><img src='/track' width='1' height='1'>")
        assertTrue(document.blocks.isEmpty())
    }

    @Test fun deduplicatesImagesAndOnlyUsesMetadataAsFallback() {
        val metadata = listOf<AgentNativeJsonObject>(mapOf("url" to "https://example.com/cover.jpg"))
        assertEquals(1, parse("<img src='/one.jpg'><img src='/one.jpg'>", metadata).blocks.size)
        assertEquals("https://example.com/cover.jpg", parse("<p>正文</p>", metadata).cover!!.url)
    }

    @Test fun dropsSubmissionThanksButPreservesQualifiedClaims() {
        val document = parse("<p>感谢IT之家网友 小明 的线索投递！</p><p>$body</p>")
        assertFalse(document.body.contains("感谢"))
        assertTrue(AttentionArticleReadingPolicy.preview(document).contains("仍需要进一步验证"))
    }

    @Test fun metadataFallbackIgnoresTrackersAndKeepsCoverDimensions() {
        val metadata = listOf<AgentNativeJsonObject>(
            mapOf("url" to "https://example.com/tracker", "width" to 1, "height" to 1),
            mapOf("url" to "https://example.com/cover.jpg", "width" to 800, "height" to 600)
        )
        val cover = parse("<p>Article body</p>", metadata).cover!!
        assertEquals("https://example.com/cover.jpg", cover.url)
        assertEquals(800, cover.width)
        assertEquals(600, cover.height)
    }

    @Test fun excerptsAreVerbatimDistinctAndNotGeneratedClaims() {
        val document = AttentionArticleDocument.plain(listOf(body, body, "公司表示目前尚未确定最终售价，也未公开完整的上市时间表。").joinToString("\n\n"))
        val excerpts = AttentionArticleReadingPolicy.excerpts(document)
        assertEquals(2, excerpts.size)
        assertTrue(excerpts.all(document.body::contains))
    }

    @Test fun tableRowsAndCodeAreNotFlattenedIntoAdjacentProse() {
        val document = parse("<p>正文</p><table><tr><th>型号</th><th>价格</th></tr><tr><td>A</td><td>100</td></tr></table>" +
            "<pre>line 1\n  line 2</pre>")
        assertEquals(listOf("paragraph", "table", "table", "code"), document.blocks.map { it.kind })
        assertTrue(document.blocks.last().text.contains("\n  line 2"))
    }

    @Test fun structuredDocumentRoundTripsPerArticle() {
        val document = parse("<p><strong>重点</strong>$body</p><img src='/a.jpg'>")
        assertEquals(document, AttentionArticleDocument.decode(document.encode()))
        assertNull(AttentionArticleDocument.decode("invalid"))
    }

    @Test fun chineseDocumentDoesNotCallAnyTranslationProvider() = runBlocking {
        val document = parse("<h2>研究进展</h2><p>$body</p><img src='/a.jpg' alt='设备照片'>")
        val result = AttentionArticleTranslation { error("Unexpected translation") }.run("研究进展", document)
        assertEquals(document, result.document)
        assertEquals("", result.provider)
    }

    @Test fun translationPreservesBlockTypesImageLocationAndActualNumbers() = runBlocking {
        val english = "The device costs 100 dollars and has not been independently tested. ".repeat(5)
        val document = parse("<h2>Details</h2><p>$english</p><img src='/a.jpg' alt='Device'><blockquote>Not yet verified</blockquote>")
        val result = AttentionArticleTranslation { source -> when (source) {
            "Details" -> "详细信息"; "Device" -> "设备"; "Not yet verified" -> "尚未核实"
            else -> "设备售价100美元，目前尚未经过独立测试。".repeat(5)
        } }.run("Details", document)
        assertEquals(document.blocks.map { it.kind }, result.document!!.blocks.map { it.kind })
        assertEquals(document.cover!!.url, result.document.cover!!.url)
        assertTrue(result.body.contains("尚未核实"))
        assertFalse(result.body.contains("The device"))
    }

    @Test fun translationCancellationNeverReturnsPartlyTranslatedDocument() = runBlocking {
        val document = parse("<p>${"An English article about a new device. ".repeat(10)}</p>")
        assertTrue(runCatching { AttentionArticleTranslation { throw CancellationException() }.run("Title", document) }
            .exceptionOrNull() is CancellationException)
    }

    @Test fun jsonLdFullArticleWinsOverShortDomTeaser() {
        val page = AgentWebIntelligenceFetched("https://example.com/one", "text/html", ("<html><head>" +
            "<script type='application/ld+json'>{\"@type\":\"NewsArticle\",\"articleBody\":\"$body${body}\"}</script>" +
            "</head><body><article><p>$body</p><img src='/a.jpg'></article></body></html>").toByteArray())
        val source = AttentionArticlePolicy.extractStructured(page)
        assertEquals(source.article.content, source.document.body)
        assertNotNull(source.document.cover)
    }
}
