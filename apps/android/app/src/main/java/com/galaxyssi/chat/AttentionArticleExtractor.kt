package com.galaxyssi.chat

import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

/** Select the article before flattening text; page chrome is not article content. */
internal object AttentionArticleExtractor {
    private const val BODY = "[itemprop=articleBody],#js_content,.rich_media_content,.article-body,.article-content," +
        ".article__body,.post-body,.post-content,.post_content,.post__content,.entry-content,.story-body,.story-content," +
        "#article-body,#article-content,#paragraph"
    private const val NOISE = "script:not([type=application/ld+json]),style,noscript,template,nav,footer,form,button," +
        "input,select,textarea,[hidden],[aria-hidden=true],[role=navigation],.back-link,.byline,.post-byline," +
        ".post-meta,.article-meta,.post-header,.article-header,.post-title,.article-title,.read-time"
    private val noiseIdentity = Regex("(^|[-_\\s])(related|recommended|recommendation|recommendations|sidebar|" +
        "breadcrumb|breadcrumbs|comments|newsletter|advertisement|social-share|cookie|site-nav|site-header)([-_\\s]|$)")
    private val absentRegion = Regex("(^|[-_])(no|without)[-_](sidebar|comments|newsletter)([-_]|$)")

    fun parse(url: String, source: Document): AgentPublicArticle? = structured(url, source)?.article

    fun structured(url: String, source: Document): AttentionArticleSource? {
        val document = source.clone()
        // Capture metadata before removing article headers and bylines.
        val title = document.selectFirst("meta[property=og:title]")?.attr("content")
            ?.takeIf(String::isNotBlank) ?: document.selectFirst("h1")?.text()?.takeIf(String::isNotBlank)
            ?: document.title()
        document.select(NOISE).remove()
        document.body().getAllElements().filter {
            it.normalName() !in setOf("body", "html") && (it.classNames() + it.id()).any { identity ->
                val name = identity.lowercase()
                noiseIdentity.containsMatchIn(name) && !absentRegion.containsMatchIn(name)
            }
        }.forEach(Element::remove)
        val explicit = document.select(BODY).filter { it.text().length >= 200 }
        val articles = document.select("article").filter { it.text().length >= 200 }
        // Multiple independent article cards are a listing, not a readable article.
        if (explicit.isEmpty() && articles.count { it.parents().none { parent -> parent in articles } } > 1) return null
        val candidates = explicit.ifEmpty { articles }.ifEmpty {
            document.select("main,[role=main],section,div,body").filter { element ->
                element.select("p").sumOf { it.text().length.takeIf { length -> length >= 80 } ?: 0 } >= 200
            }
        }
        val root = candidates.filter { linkDensity(it) < .45 }.maxByOrNull { element ->
            val prose = element.select("p,blockquote,pre").sumOf { it.text().length }
            // The narrowest container carrying the prose wins over a surrounding page.
            prose * 3.0 - element.text().length * .25 - element.select("a[href]").sumOf { it.text().length } * 2
        } ?: return null
        val cleaned = root.clone()
        cleaned.select("h1").remove()
        val isolated = Document.createShell(url)
        isolated.head().appendChildren(document.head().childNodesCopy())
        isolated.head().appendElement("meta").attr("property", "og:title").attr("content", title)
        isolated.body().appendChild(cleaned)
        val article = AgentPublicArticleParser.parse(url, isolated.outerHtml())?.copy(title = title) ?: return null
        val parsed = AttentionArticleDocumentParser.parse(url, cleaned, article.images)
        // Some sites expose the complete article only in JSON-LD. Never replace it with a shorter DOM teaser.
        val documentBody = if (parsed.body.length < article.content.length * .65)
            AttentionArticleDocument(listOfNotNull(parsed.cover) + AttentionArticleDocument.plain(article.content).blocks) else parsed
        require(documentBody.blocks.size <= 2000) { "article_structure_too_large" }
        return AttentionArticleSource(article, documentBody)
    }

    private fun linkDensity(element: Element) = element.select("a[href]").sumOf { it.text().length }.toDouble() /
        element.text().length.coerceAtLeast(1)
}
