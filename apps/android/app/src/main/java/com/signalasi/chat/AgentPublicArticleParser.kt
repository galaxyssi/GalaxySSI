package com.signalasi.chat

import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode
import org.jsoup.select.NodeTraversor
import org.jsoup.select.NodeVisitor
import java.net.URI
import java.util.Locale

internal data class AgentPublicArticle(
    val title: String,
    val author: String,
    val publishedAt: String,
    val content: String,
    val links: List<String>,
    val images: List<AgentNativeJsonObject>,
    val sourceType: String
)

internal object AgentPublicArticleParser {
    private val WECHAT_HOSTS = setOf("mp.weixin.qq.com")
    private val BLOCK_TAGS = setOf(
        "article", "blockquote", "br", "div", "h1", "h2", "h3", "h4", "h5", "h6",
        "li", "ol", "p", "pre", "section", "table", "td", "th", "tr", "ul"
    )

    fun parse(url: String, source: String): AgentPublicArticle? {
        val host = runCatching { URI(url).host.orEmpty().lowercase(Locale.ROOT) }.getOrDefault("")
        return when (host) {
            in WECHAT_HOSTS -> parseWechat(url, source)
            else -> null
        }
    }

    private fun parseWechat(url: String, source: String): AgentPublicArticle? {
        val document = Jsoup.parse(source, url)
        val body = document.selectFirst("#js_content, .rich_media_content") ?: return null
        val title = firstText(document, "#activity-name", ".rich_media_title", "meta[property=og:title]")
            .ifBlank { document.title() }
        val author = firstText(
            document,
            "#js_name",
            ".rich_media_meta_nickname",
            "#js_profile_qrcode .profile_nickname",
            "meta[name=author]"
        )
        val publishedAt = firstText(document, "#publish_time", "em.rich_media_meta_text")
        val links = body.select("a[href]").mapNotNull { element ->
            canonicalHttpsUrl(element.absUrl("href").ifBlank { element.attr("href") }, url)
        }.distinct().take(AgentWebIntelligenceService.MAX_LINKS)
        val images = body.select("img").mapIndexedNotNull { index, element ->
            val rawUrl = sequenceOf("data-src", "data-original", "src")
                .map(element::attr)
                .firstOrNull(String::isNotBlank)
                .orEmpty()
            val imageUrl = canonicalHttpsUrl(rawUrl, url) ?: return@mapIndexedNotNull null
            linkedMapOf<String, Any?>(
                "index" to index,
                "url" to imageUrl,
                "alt" to element.attr("alt").trim().take(500),
                "width" to positiveDimension(element.attr("data-w").ifBlank { element.attr("width") }),
                "height" to positiveDimension(element.attr("data-h").ifBlank { element.attr("height") })
            ).filterValues { value -> value != null && value != "" }
        }.distinctBy { it["url"] }.take(100)
        return AgentPublicArticle(
            title = title.trim().take(2_048),
            author = author.trim().take(1_024),
            publishedAt = publishedAt.trim().take(256),
            content = plainText(body).take(AgentWebIntelligenceService.MAX_CONTENT_CHARS),
            links = links,
            images = images,
            sourceType = "wechat_public_account"
        )
    }

    private fun firstText(document: Element, vararg selectors: String): String {
        selectors.forEach { selector ->
            val element = document.selectFirst(selector) ?: return@forEach
            val value = when {
                selector.startsWith("meta[") -> element.attr("content")
                else -> element.text()
            }.trim()
            if (value.isNotBlank()) return value
        }
        return ""
    }

    private fun plainText(root: Element): String {
        val output = StringBuilder()
        NodeTraversor.traverse(object : NodeVisitor {
            override fun head(node: Node, depth: Int) {
                when (node) {
                    is TextNode -> output.append(node.wholeText)
                    is Element -> if (node.normalName() == "br") output.append('\n')
                }
            }

            override fun tail(node: Node, depth: Int) {
                if (node is Element && node.normalName() in BLOCK_TAGS) output.append('\n')
            }
        }, root)
        return output.toString()
            .replace('\u00a0', ' ')
            .replace(Regex("[ \\t]+"), " ")
            .replace(Regex(" *\\n *"), "\n")
            .replace(Regex("\\n{3,}"), "\n\n")
            .trim()
    }

    private fun canonicalHttpsUrl(value: String, baseUrl: String): String? = runCatching {
        if (value.isBlank() || value.startsWith("data:", true)) return@runCatching null
        val decoded = AgentWebIntelligenceText.decodeHtml(value.trim())
        var resolved = URI(baseUrl).resolve(decoded)
        if (resolved.scheme.equals("http", true) && resolved.host.orEmpty().endsWith("qpic.cn", true)) {
            resolved = URI("https", resolved.userInfo, resolved.host, resolved.port, resolved.path, resolved.query, null)
        }
        resolved.takeIf { it.scheme.equals("https", true) && !it.host.isNullOrBlank() }
            ?.toString()
            ?.let(AgentWebIntelligenceText::canonicalUrl)
    }.getOrNull()

    private fun positiveDimension(value: String): Int? = value.trim().toIntOrNull()?.takeIf { it > 0 }
}
