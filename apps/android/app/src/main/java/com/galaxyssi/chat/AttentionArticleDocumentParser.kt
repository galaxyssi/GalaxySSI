package com.galaxyssi.chat

import java.net.URI
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode

/** Preserve reading order without carrying scripts, page CSS, or interactive HTML into the reader. */
internal object AttentionArticleDocumentParser {
    fun parse(url: String, root: Element, metadata: List<AgentNativeJsonObject>): AttentionArticleDocument {
        val blocks = mutableListOf<AttentionArticleBlock>()
        val images = mutableSetOf<String>()
        val containerTags = setOf("article", "section", "div", "main", "body", "figure", "ul", "ol")
        fun image(element: Element) {
            val raw = sequenceOf("data-src", "data-original", "data-lazy-src", "src")
                .map(element::attr).firstOrNull(String::isNotBlank)
                ?: element.attr("srcset").split(',').lastOrNull()?.trim()?.substringBefore(' ').orEmpty()
            val source = imageUrl(url, raw) ?: return
            val width = dimension(element, "width", "data-w", "data-width")
            val height = dimension(element, "height", "data-h", "data-height")
            if (width in 1..32 || height in 1..32 || !images.add(source)) return
            blocks += AttentionArticleBlock("image", element.attr("alt").trim().take(500), source, width, height)
        }
        fun visit(node: Node, inherited: String = "paragraph", depth: Int = 0) {
            if (node is TextNode) {
                val text = node.text().trim()
                if (text.isNotEmpty()) blocks += AttentionArticleBlock(inherited, text)
                return
            }
            val element = node as? Element ?: return
            val tag = element.normalName()
            if (tag in setOf("script", "style", "iframe", "svg", "canvas", "noscript")) return
            if (depth > 64) {
                val text = element.text().trim()
                if (text.isNotBlank()) blocks += AttentionArticleBlock(inherited, text)
                return
            }
            if (tag == "img") { image(element); return }
            val kind = when (tag) {
                "h1", "h2", "h3", "h4", "h5", "h6" -> "heading"
                "li" -> "list"
                "blockquote" -> "quote"
                "pre" -> "code"
                "figcaption" -> "caption"
                "tr" -> "table"
                else -> inherited
            }
            // Group inline runs, but split at block elements and images so figures retain their position.
            val inline = Element("span")
            fun flush() {
                val text = inline.text().trim()
                if (text.isNotBlank() && AttentionArticleReadingPolicy.informative(text)) {
                    val strong = inline.select("strong,b").map(Element::text).filter(String::isNotBlank).distinct()
                    blocks += AttentionArticleBlock(kind, text, emphasis = strong)
                }
                inline.empty()
            }
            if (tag == "pre") {
                blocks += AttentionArticleBlock(kind, element.wholeText().trim())
                return
            }
            if (tag == "tr") {
                blocks += AttentionArticleBlock(kind, element.select("th,td").joinToString("  |  ") { it.text() })
                return
            }
            for (child in element.childNodes()) {
                val childElement = child as? Element
                if (childElement != null && (childElement.normalName() in containerTags ||
                        childElement.isBlock || childElement.normalName() in setOf("img", "br") ||
                        childElement.select("img").isNotEmpty())) {
                    flush()
                    visit(child, kind, depth + 1)
                } else inline.appendChild(child.clone())
            }
            flush()
        }
        visit(root)
        // OpenGraph covers are used only when the article body has no usable image.
        if (images.isEmpty()) metadata.firstNotNullOfOrNull { item ->
            val width = item["width"]?.toString()?.toIntOrNull() ?: 0
            val height = item["height"]?.toString()?.toIntOrNull() ?: 0
            if (width in 1..32 || height in 1..32) null
            else imageUrl(url, item["url"]?.toString().orEmpty())?.let {
                AttentionArticleBlock("image", url = it, width = width, height = height)
            }
        }?.let {
            blocks.add(0, it)
        }
        return AttentionArticleDocument(blocks)
    }

    internal fun imageUrl(base: String, value: String): String? = runCatching {
        if (value.isBlank()) return null
        val uri = URI(base).resolve(value.trim())
        if (uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null) return null
        uri.toString()
    }.getOrNull()

    private fun dimension(element: Element, vararg names: String) = names.asSequence().map(element::attr)
        .mapNotNull(String::toIntOrNull).firstOrNull { it > 0 } ?: 0
}
