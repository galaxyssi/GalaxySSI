package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode
import org.jsoup.select.NodeTraversor
import org.jsoup.select.NodeVisitor
import java.net.URI
import java.util.Locale
import kotlin.math.max

internal data class AgentPublicArticle(
    val title: String,
    val author: String,
    val publishedAt: String,
    val content: String,
    val links: List<String>,
    val images: List<AgentNativeJsonObject>,
    val sourceType: String
)

private data class AgentArticleJsonLd(
    val title: String = "",
    val author: String = "",
    val publishedAt: String = "",
    val articleBody: String = "",
    val images: List<String> = emptyList(),
    val articleLike: Boolean = false
)

internal object AgentPublicArticleParser {
    private val WECHAT_HOSTS = setOf("mp.weixin.qq.com")
    private val ARTICLE_TYPES = setOf(
        "article", "newsarticle", "blogposting", "techarticle", "report",
        "scholarlyarticle", "discussionforumposting", "analysisnewsarticle"
    )
    private val BLOCK_TAGS = setOf(
        "article", "blockquote", "br", "div", "figcaption", "h1", "h2", "h3", "h4",
        "h5", "h6", "li", "ol", "p", "pre", "section", "table", "td", "th", "tr", "ul"
    )
    private const val CONTENT_ROOTS =
        "article,main,[role=main],[itemprop=articleBody],.article-body,.article-content," +
            ".article__body,.post-content,.entry-content,.story-body,.story-content,.main-content," +
            "#article-body,#article-content,#main-content"
    private const val NOISE_ELEMENTS =
        "script,style,noscript,template,svg,canvas,iframe,nav,footer,aside,form,button,input," +
            "select,textarea,[hidden],[aria-hidden=true],.advertisement,.advert,.ads,.ad,.cookie," +
            ".consent,.newsletter,.subscribe,.social-share,.share,.comments,.comment,.related," +
            ".recommendation,.recommendations"
    private val NOISE_HINTS = listOf(
        "advert", "banner", "breadcrumb", "comment", "cookie", "footer", "header", "menu",
        "nav", "newsletter", "promo", "recommend", "related", "share", "sidebar", "social"
    )

    fun parse(url: String, source: String): AgentPublicArticle? {
        val host = runCatching { URI(url).host.orEmpty().lowercase(Locale.ROOT) }.getOrDefault("")
        return if (host in WECHAT_HOSTS) {
            parseWechat(url, source) ?: parseGeneric(url, source)
        } else {
            parseGeneric(url, source)
        }
    }

    private fun parseWechat(url: String, source: String): AgentPublicArticle? {
        val document = Jsoup.parse(source, url)
        val body = document.selectFirst("#js_content, .rich_media_content") ?: return null
        val title = firstValue(document, "#activity-name", ".rich_media_title", "meta[property=og:title]")
            .ifBlank { document.title() }
        val author = firstValue(
            document,
            "#js_name",
            ".rich_media_meta_nickname",
            "#js_profile_qrcode .profile_nickname",
            "meta[name=author]"
        )
        val publishedAt = firstValue(document, "#publish_time", "em.rich_media_meta_text")
        return article(
            url = url,
            title = title,
            author = author,
            publishedAt = publishedAt,
            content = plainText(body),
            root = body,
            metadataImages = emptyList(),
            sourceType = "wechat_public_account"
        )
    }

    private fun parseGeneric(url: String, source: String): AgentPublicArticle? {
        val document = Jsoup.parse(source, url)
        val jsonLd = jsonLdMetadata(document)
        val cleaned = document.clone().apply { select(NOISE_ELEMENTS).remove() }
        val root = selectContentRoot(cleaned) ?: return null
        val domContent = plainText(root)
        val structuredContent = normalizeText(jsonLd.articleBody)
        val content = when {
            structuredContent.length >= 40 &&
                structuredContent.length >= (domContent.length * 0.65).toInt() -> structuredContent
            else -> domContent
        }.take(AgentWebIntelligenceService.MAX_CONTENT_CHARS)
        val title = jsonLd.title
            .ifBlank {
                firstValue(
                    document,
                    "meta[property=og:title]",
                    "meta[name=twitter:title]",
                    "meta[name=title]"
                )
            }
            .ifBlank { root.selectFirst("h1")?.text().orEmpty() }
            .ifBlank { document.title() }
        if (content.length < 40 && title.isBlank()) return null
        val author = jsonLd.author
            .ifBlank {
                firstValue(
                    document,
                    "meta[name=author]",
                    "meta[property=article:author]",
                    "meta[name=byl]",
                    "[itemprop=author]",
                    "[rel=author]",
                    ".byline",
                    ".author"
                )
            }
        val publishedAt = jsonLd.publishedAt
            .ifBlank {
                firstValue(
                    document,
                    "meta[property=article:published_time]",
                    "meta[name=date]",
                    "meta[name=pubdate]",
                    "[itemprop=datePublished]",
                    "time[datetime]"
                )
            }
        val metadataImages = buildList {
            addAll(jsonLd.images)
            add(firstValue(document, "meta[property=og:image]", "meta[name=twitter:image]"))
        }.filter(String::isNotBlank)
        return article(
            url = url,
            title = title,
            author = author,
            publishedAt = publishedAt,
            content = content,
            root = root,
            metadataImages = metadataImages,
            sourceType = if (
                jsonLd.articleLike || root.normalName() == "article" ||
                root.attr("itemprop").contains("articleBody", true)
            ) "structured_web_article" else "generic_web_page"
        )
    }

    private fun article(
        url: String,
        title: String,
        author: String,
        publishedAt: String,
        content: String,
        root: Element,
        metadataImages: List<String>,
        sourceType: String
    ): AgentPublicArticle {
        val links = root.select("a[href]").mapNotNull { element ->
            canonicalHttpsUrl(element.absUrl("href").ifBlank { element.attr("href") }, url)
        }.distinct().take(AgentWebIntelligenceService.MAX_LINKS)
        val images = extractImages(root, url, metadataImages)
        return AgentPublicArticle(
            title = normalizeInline(title).take(2_048),
            author = normalizeInline(author).take(1_024),
            publishedAt = normalizeInline(publishedAt).take(256),
            content = normalizeText(content).take(AgentWebIntelligenceService.MAX_CONTENT_CHARS),
            links = links,
            images = images,
            sourceType = sourceType
        )
    }

    private fun selectContentRoot(document: Document): Element? {
        val explicit = document.select(CONTENT_ROOTS)
            .filter { normalizeText(it.text()).length >= 40 }
        val candidates = if (explicit.isNotEmpty()) {
            explicit
        } else {
            document.select("section,div")
                .filter { normalizeText(it.text()).length >= 120 }
                .take(80) + listOfNotNull(document.body())
        }
        return candidates.maxByOrNull(::contentScore)
            ?: document.body()?.takeIf { normalizeText(it.text()).length >= 40 }
    }

    private fun contentScore(element: Element): Double {
        val text = normalizeText(element.text())
        if (text.isBlank()) return Double.NEGATIVE_INFINITY
        val linkTextLength = element.select("a[href]").sumOf { normalizeText(it.text()).length }
        val linkDensity = linkTextLength.toDouble() / max(1, text.length)
        val paragraphCount = element.select("p,li,blockquote,pre").count {
            normalizeText(it.text()).length >= 30
        }
        val punctuationCount = text.count {
            it in charArrayOf(
                '.', ',', ';', ':', '!', '?', '\u3002', '\uff0c', '\uff1b', '\uff1a', '\uff01', '\uff1f'
            )
        }
        val identity = "${element.id()} ${element.className()}".lowercase(Locale.ROOT)
        val noisePenalty = NOISE_HINTS.count(identity::contains) * 600.0
        val semanticBonus = when (element.normalName()) {
            "article" -> 1_200.0
            "main" -> 900.0
            "section" -> 150.0
            else -> 0.0
        } + if (element.hasAttr("itemprop") &&
            element.attr("itemprop").contains("articleBody", true)
        ) 1_000.0 else 0.0
        return text.length + paragraphCount * 100.0 + punctuationCount * 4.0 + semanticBonus -
            text.length * linkDensity * 1.8 - noisePenalty
    }

    private fun extractImages(
        root: Element,
        baseUrl: String,
        metadataImages: List<String>
    ): List<AgentNativeJsonObject> {
        val values = mutableListOf<AgentNativeJsonObject>()
        metadataImages.forEach { rawUrl ->
            canonicalHttpsUrl(rawUrl, baseUrl)?.let { imageUrl ->
                values += linkedMapOf("index" to values.size, "url" to imageUrl, "alt" to "")
            }
        }
        root.select("img").forEach { element ->
            val rawUrl = sequenceOf("data-src", "data-original", "data-lazy-src", "src")
                .map(element::attr)
                .firstOrNull(String::isNotBlank)
                ?: srcsetUrl(element.attr("srcset"))
            val imageUrl = canonicalHttpsUrl(rawUrl, baseUrl) ?: return@forEach
            val caption = element.closest("figure")?.selectFirst("figcaption")?.text().orEmpty()
            values += linkedMapOf<String, Any?>(
                "index" to values.size,
                "url" to imageUrl,
                "alt" to normalizeInline(element.attr("alt").ifBlank { caption }).take(500),
                "width" to positiveDimension(
                    element.attr("data-w").ifBlank {
                        element.attr("data-width").ifBlank { element.attr("width") }
                    }
                ),
                "height" to positiveDimension(
                    element.attr("data-h").ifBlank {
                        element.attr("data-height").ifBlank { element.attr("height") }
                    }
                )
            ).filterValues { value -> value != null && value != "" }
        }
        return values.distinctBy { it["url"] }.take(100).mapIndexed { index, image ->
            LinkedHashMap(image).apply { put("index", index) }
        }
    }

    private fun jsonLdMetadata(document: Document): AgentArticleJsonLd {
        val objects = mutableListOf<JSONObject>()
        document.select("script[type=application/ld+json]").forEach { script ->
            val source = script.data().ifBlank { script.html() }.trim()
            runCatching {
                when {
                    source.startsWith("{") -> collectJsonObjects(JSONObject(source), objects, 0)
                    source.startsWith("[") -> collectJsonObjects(JSONArray(source), objects, 0)
                }
            }
        }
        val ordered = objects.sortedByDescending(::jsonLdScore)
        val articleLike = ordered.any { jsonTypes(it).any(ARTICLE_TYPES::contains) }
        val contentObjects = ordered.filter { value ->
            val types = jsonTypes(value)
            types.any(ARTICLE_TYPES::contains) || "webpage" in types ||
                value.has("headline") || value.has("articleBody")
        }
        return AgentArticleJsonLd(
            title = firstJsonText(contentObjects, "headline", "name"),
            author = contentObjects.asSequence().map { jsonAuthors(it.opt("author")) }
                .firstOrNull(String::isNotBlank).orEmpty(),
            publishedAt = firstJsonText(contentObjects, "datePublished", "dateCreated", "dateModified"),
            articleBody = firstJsonText(contentObjects, "articleBody", "text"),
            images = contentObjects.flatMap { jsonImages(it.opt("image")) }.distinct().take(20),
            articleLike = articleLike
        )
    }

    private fun collectJsonObjects(value: Any?, output: MutableList<JSONObject>, depth: Int) {
        if (depth > 8 || output.size >= 100) return
        when (value) {
            is JSONObject -> {
                output += value
                value.keys().forEachRemaining { key -> collectJsonObjects(value.opt(key), output, depth + 1) }
            }
            is JSONArray -> for (index in 0 until value.length()) {
                collectJsonObjects(value.opt(index), output, depth + 1)
            }
        }
    }

    private fun jsonLdScore(value: JSONObject): Int {
        val types = jsonTypes(value)
        return when {
            types.any(ARTICLE_TYPES::contains) -> 1_000
            "webpage" in types -> 300
            else -> 0
        } + jsonText(value.opt("articleBody")).length.coerceAtMost(500) +
            if (jsonText(value.opt("headline")).isNotBlank()) 100 else 0
    }

    private fun jsonTypes(value: JSONObject): Set<String> = jsonStrings(value.opt("@type"))
        .map { it.substringAfterLast('/').lowercase(Locale.ROOT) }
        .toSet()

    private fun firstJsonText(objects: List<JSONObject>, vararg keys: String): String {
        objects.forEach { value ->
            keys.forEach { key ->
                val text = jsonText(value.opt(key))
                if (text.isNotBlank()) return text
            }
        }
        return ""
    }

    private fun jsonAuthors(value: Any?): String = when (value) {
        is JSONArray -> (0 until value.length()).map { jsonAuthors(value.opt(it)) }
            .filter(String::isNotBlank).distinct().joinToString(", ")
        is JSONObject -> jsonText(value.opt("name")).ifBlank { jsonText(value.opt("alternateName")) }
        else -> jsonText(value)
    }

    private fun jsonImages(value: Any?): List<String> = when (value) {
        is JSONArray -> (0 until value.length()).flatMap { jsonImages(value.opt(it)) }
        is JSONObject -> listOfNotNull(
            sequenceOf("url", "contentUrl", "thumbnailUrl")
                .map { jsonText(value.opt(it)) }
                .firstOrNull(String::isNotBlank)
        )
        else -> listOf(jsonText(value)).filter(String::isNotBlank)
    }

    private fun jsonStrings(value: Any?): List<String> = when (value) {
        is JSONArray -> (0 until value.length()).flatMap { jsonStrings(value.opt(it)) }
        else -> listOf(jsonText(value)).filter(String::isNotBlank)
    }

    private fun jsonText(value: Any?): String = when (value) {
        null, JSONObject.NULL -> ""
        is String -> value
        is Number, is Boolean -> value.toString()
        is JSONObject -> sequenceOf("name", "headline", "text", "url")
            .map { jsonText(value.opt(it)) }
            .firstOrNull(String::isNotBlank).orEmpty()
        else -> ""
    }

    private fun firstValue(document: Element, vararg selectors: String): String {
        selectors.forEach { selector ->
            val element = document.selectFirst(selector) ?: return@forEach
            val value = when {
                element.normalName() == "meta" -> element.attr("content")
                element.normalName() == "time" && element.hasAttr("datetime") -> element.attr("datetime")
                element.hasAttr("content") -> element.attr("content")
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
        return normalizeText(output.toString())
    }

    private fun normalizeInline(value: String): String = AgentWebIntelligenceText.decodeHtml(value)
        .replace('\u00a0', ' ')
        .replace(Regex("\\s+"), " ")
        .trim()

    private fun normalizeText(value: String): String = AgentWebIntelligenceText.decodeHtml(value)
        .replace('\u00a0', ' ')
        .replace(Regex("[ \\t]+"), " ")
        .replace(Regex(" *\\n *"), "\n")
        .replace(Regex("\\n{3,}"), "\n\n")
        .trim()

    private fun srcsetUrl(value: String): String = value.split(',')
        .map { it.trim().split(Regex("\\s+"), limit = 2).firstOrNull().orEmpty() }
        .filter(String::isNotBlank)
        .lastOrNull()
        .orEmpty()

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
