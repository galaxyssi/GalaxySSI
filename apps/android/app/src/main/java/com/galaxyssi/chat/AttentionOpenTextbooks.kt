package com.galaxyssi.chat

import java.net.URI
import org.json.JSONObject
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

/** Parse the publisher's public table of contents as JSON, never execute page scripts. */
internal object AttentionOpenTextbooks {
    private val books = setOf("biology-2e", "microbiology", "anatomy-and-physiology-2e")
    val endpoints = books.map { "https://openstax.org/books/$it/pages/preface" }
    private const val PREFIX = "window.__PRELOADED_STATE__ = "

    fun accepts(endpoint: String, target: String): Boolean {
        if (endpoint !in endpoints) return false
        val url = runCatching { URI(target) }.getOrNull() ?: return false
        val prefix = URI(endpoint).path.substringBeforeLast('/') + "/"
        return url.scheme == "https" && url.host == "openstax.org" && url.userInfo == null &&
            url.port in listOf(-1, 443) && url.rawQuery == null && url.rawFragment == null &&
            url.path.startsWith(prefix) && url.path.removePrefix(prefix).matches(Regex("[0-9]+-[0-9]+-[a-z0-9-]+"))
    }

    fun isArticle(url: String) = endpoints.any { accepts(it, url) }

    private fun book(document: Document): JSONObject? = document.select("script:not([src])").asSequence()
        .map { it.data().trim() }.filter { it.startsWith(PREFIX) }.mapNotNull {
            runCatching { JSONObject(it.removePrefix(PREFIX).removeSuffix(";")).optJSONObject("content")?.optJSONObject("book") }.getOrNull()
        }.firstOrNull()

    fun discover(document: Document, endpoint: String): List<Pair<String, String>> {
        require(endpoint in endpoints)
        val book = requireNotNull(book(document)) { "knowledge_textbook_toc_missing" }
        require(book.optString("slug") == URI(endpoint).path.split('/')[2]) { "knowledge_textbook_mismatch" }
        val links = mutableListOf<Pair<String, String>>()
        var visited = 0
        fun visit(node: JSONObject, depth: Int) {
            require(depth <= 12 && ++visited <= 4000) { "knowledge_textbook_toc_too_large" }
            val slug = node.optString("slug")
            val url = endpoint.substringBeforeLast('/') + "/" + slug
            if (node.optString("toc_target_type") == "numbered-section" && accepts(endpoint, url))
                links += url to Jsoup.parseBodyFragment(node.optString("title")).text()
            val children = node.optJSONArray("contents") ?: return
            for (i in 0 until children.length()) children.optJSONObject(i)?.let { visit(it, depth + 1) }
        }
        visit(requireNotNull(book.optJSONObject("tree")), 0)
        return links.distinctBy { it.first }
    }

    fun attribution(url: String, document: Document): AttentionArticleBlock? {
        if (!isArticle(url)) return null
        val book = book(document) ?: return null
        val license = book.optJSONObject("license") ?: return null
        val licenseUrl = license.optString("url").replaceFirst("http://creativecommons.org/", "https://creativecommons.org/")
        if (runCatching { URI(licenseUrl).host }.getOrNull() != "creativecommons.org" || !licenseUrl.startsWith("https://")) return null
        val authors = book.optJSONArray("authors")
        val names = (0 until (authors?.length() ?: 0)).mapNotNull { index ->
            authors?.optJSONObject(index)?.optJSONObject("value")?.takeIf { it.optBoolean("display_at_top") }
                ?.optString("name")?.takeIf(String::isNotBlank)
        }
        return AttentionArticleBlock("attribution", (listOf("OpenStax", book.optString("title")) + names +
            license.optString("name")).filter(String::isNotBlank).joinToString(" · "), licenseUrl)
    }
}
