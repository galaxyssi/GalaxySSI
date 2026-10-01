package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class WechatArticleDocumentsTest {
    private val url = "https://mp.weixin.qq.com/s/article-id"
    @Test fun recognizesVerificationWithoutTreatingItAsAnArticle() {
        assertTrue(WechatArticleDocuments.requiresVerification("<a id=js_verify>Verify</a>".toByteArray()))
        assertFalse(WechatArticleDocuments.requiresVerification("<div id=js_content>Article</div><a id=js_verify>Link</a>".toByteArray()))
        assertFalse(WechatArticleDocuments.requiresVerification("<h1>Normal error</h1>".toByteArray()))
    }
    @Test fun acceptsOnlyExplicitHttpsArticleUrls() {
        assertEquals(url, WechatArticleDocuments.articleUrl(" $url "))
        assertNotNull(WechatArticleDocuments.articleUrl("https://mp.weixin.qq.com/s?__biz=abc&mid=123"))
        listOf("http://mp.weixin.qq.com/s/a", "https://mp.weixin.qq.com.evil.org/s/a",
            "https://user@mp.weixin.qq.com/s/a", "https://mp.weixin.qq.com:8443/s/a",
            "https://mp.weixin.qq.com/mp/profile", "javascript:alert(1)", "$url more text").forEach {
            assertNull(it, WechatArticleDocuments.articleUrl(it))
        }
    }
    @Test fun rejectsLoginAndEmptyArticlesInsteadOfSavingPartialPage() {
        listOf("<h1>Login</h1>", "<h1 id=activity-name>Title</h1><div id=js_content></div>",
            "<div id=js_content>Body</div>").forEach { html ->
            assertTrue(runCatching { WechatArticleDocuments.extract(url, html.toByteArray()) }.isFailure)
        }
    }
    @Test fun retainsFullBodyAndImageOrderWithoutArticleChrome() {
        val html = "<h1 id=activity-name>中文文章</h1><a id=js_name>作者</a><div id=js_content>" +
            "<p>第一段</p><img src='data:image/png;base64,AA=='/><p>末尾内容</p></div><footer>不相关推荐</footer>"
        val article = WechatArticleDocuments.extract(url, html.toByteArray())
        assertEquals("中文文章", article.title)
        val blocks = WechatArticleDocuments.blocks(article.html)
        assertEquals(3, blocks.size)
        assertTrue((blocks[0] as WechatArticleBlock.Text).html.contains("第一段"))
        assertTrue(blocks[1] is WechatArticleBlock.Image)
        assertTrue((blocks[2] as WechatArticleBlock.Text).html.contains("末尾内容"))
        assertFalse(article.html.contains("不相关推荐"))
    }
    @Test fun longArticlesAreNotTruncatedAtScreenOrSearchLimits() {
        val content = (1..1000).joinToString("") { "<p>Section $it: evidence and explanation.</p>" }
        val article = WechatArticleDocuments.extract(url, "<h1 id=activity-name>Long</h1><div id=js_content>$content</div>".toByteArray())
        assertTrue(article.html.contains("Section 1000"))
        assertTrue(WechatArticleDocuments.blocks(article.html).isNotEmpty())
    }
    @Test fun sanitizesNamesAndUsesDedicatedDownloadDirectory() {
        val name = WechatArticleDocuments.fileName("../文章/标题:*?", "1234abcd")
        assertFalse(name.contains('/'))
        assertFalse(name.startsWith('.'))
        assertTrue(name.endsWith("-1234abcd.pdf"))
        assertEquals("Download/GalaxySSI/GongZhongHao", WechatArticleDocuments.DIRECTORY)
    }
}
