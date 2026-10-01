package com.galaxyssi.chat

import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import java.net.URI

internal data class WechatArticleDocument(val title: String, val html: String)
internal sealed class WechatArticleBlock {
    data class Text(val html: String) : WechatArticleBlock()
    data class Image(val source: String) : WechatArticleBlock()
}

internal object WechatArticleDocuments {
    const val DIRECTORY = "Download/GalaxySSI/GongZhongHao"

    fun requiresVerification(bytes: ByteArray): Boolean {
        val document = bytes.inputStream().use { Jsoup.parse(it, null, "https://mp.weixin.qq.com/") }
        return document.selectFirst("#js_content") == null &&
            (document.selectFirst("#js_verify") != null || document.select("script[src],link[href]").any {
                (it.attr("src") + it.attr("href")).contains("secitptpage/verify")
            })
    }

    fun articleUrl(text: String): String? = runCatching {
        val value = text.trim()
        val uri = URI(value)
        value.takeIf { uri.scheme == "https" && uri.host.equals("mp.weixin.qq.com", true) &&
            uri.userInfo == null && uri.port == -1 && (uri.path == "/s" || uri.path.startsWith("/s/")) }
    }.getOrNull()

    fun fileName(title: String, suffix: String): String {
        require(suffix.matches(Regex("[a-f0-9-]{8,36}")))
        val stem = title.replace(Regex("[\\p{Cntrl}\\\\/:*?\"<>|]"), "_").trim(' ', '.').take(80)
            .ifBlank { "article" }
        return "$stem-$suffix.pdf"
    }

    fun extract(url: String, bytes: ByteArray): WechatArticleDocument {
        require(articleUrl(url) != null)
        val source = bytes.inputStream().use { Jsoup.parse(it, null, url) }
        val content = requireNotNull(source.selectFirst("#js_content")) { "article_body_missing" }.clone()
        val title = source.selectFirst("#activity-name")?.text()?.trim().orEmpty()
            .ifBlank { source.selectFirst("meta[property=og:title]")?.attr("content").orEmpty().trim() }
        require(title.isNotBlank()) { "article_title_missing" }
        require(content.text().isNotBlank() || content.select("img").isNotEmpty()) { "article_body_empty" }
        val document = Jsoup.parse("<html><head><meta charset=utf-8></head><body></body></html>")
        document.title(title)
        document.body().appendElement("h1").text(title)
        source.selectFirst("#js_name")?.text()?.takeIf(String::isNotBlank)?.let {
            document.body().appendElement("p").text(it)
        }
        document.body().appendChild(content)
        return WechatArticleDocument(title, document.outerHtml())
    }

    /** Split at image nodes, not into independent text/image lists, preserving DOM order. */
    fun blocks(html: String): List<WechatArticleBlock> {
        val result = mutableListOf<WechatArticleBlock>()
        val text = StringBuilder()
        fun flush() {
            if (Jsoup.parseBodyFragment(text.toString()).text().isNotBlank()) {
                result += WechatArticleBlock.Text(text.toString())
            }
            text.setLength(0)
        }
        fun visit(node: Node) {
            if (node is Element && node.tagName() == "img") {
                flush()
                result += WechatArticleBlock.Image(node.attr("src"))
            } else if (node is Element && node.select("img").isNotEmpty()) {
                val shell = node.clone().empty().outerHtml()
                val end = shell.indexOf('>') + 1
                text.append(shell.take(end))
                node.childNodes().forEach(::visit)
                text.append("</${node.tagName()}>")
            } else text.append(node.outerHtml())
        }
        Jsoup.parse(html).body().childNodes().forEach(::visit)
        flush()
        return result
    }
}
