package com.galaxyssi.chat

import java.net.URI
import java.util.Locale
import org.jsoup.Jsoup

/** Public publisher-declared feeds only, never guessed paths, cross-site URLs, or model instructions. */
internal object AttentionLearnedFeedPolicy {
    fun host(url: String): String = runCatching { URI(url).host?.lowercase(Locale.ROOT)?.removePrefix("www.") }.getOrNull().orEmpty()
    private val builtIn by lazy {
        ProactiveAttentionPolicy.categoryIds.flatMap { id ->
            ProactiveAttentionFeedSources.originals(AttentionTopic(id, id, "")) + AttentionKnowledgeSources.endpoints(id)
        }.toSet()
    }
    private val excludedHosts by lazy { builtIn.map(::host).toSet() + setOf("arxiv.org", "github.com", "gitlab.com", "youtube.com", "youtu.be", "npmjs.com", "news.ycombinator.com") }
    fun needsProbe(url: String) = ProactiveAttentionFeedPolicy.publicUrl(url) != null && host(url).isNotBlank() && host(url) !in excludedHosts
    fun accepts(origin: String, url: String): Boolean = ProactiveAttentionFeedPolicy.publicUrl(url) != null &&
        host(origin).isNotBlank() && host(origin) == host(url) && URI(url).rawFragment == null && url !in builtIn && !discussionFeed(url)

    private val discussionTitle = Regex("\\b(?:comments?|replies)\\b|\u8bc4\u8bba|\u56de\u590d", RegexOption.IGNORE_CASE)
    fun discussionFeed(url: String): Boolean = runCatching {
        val uri = URI(url)
        uri.path.lowercase(Locale.ROOT).split('/').any {
            it in setOf("comment", "comments", "replies") || it.startsWith("comments.")
        } || uri.query.orEmpty().lowercase(Locale.ROOT).split('&').any {
            it.startsWith("feed=comments") || it == "withcomments=1"
        }
    }.getOrDefault(false)

    fun publisherAlias(url: String): String? = runCatching {
        if (ProactiveAttentionFeedPolicy.publicUrl(url) == null) return null
        val original = URI(url)
        if (original.rawFragment != null) return null
        val alternate = if (original.host.startsWith("www.")) original.host.removePrefix("www.") else "www." + original.host
        val candidate = URI(original.scheme, null, alternate, original.port, original.path, original.query, null)
        // Never conflate encoded separators or change a publisher's query semantics.
        candidate.toASCIIString().takeIf { candidate.rawPath == original.rawPath && candidate.rawQuery == original.rawQuery }
    }.getOrNull()

    fun discover(html: String, origin: String): List<String> = Jsoup.parse(html, origin).select("link[href]").asSequence()
        .filter { "alternate" in it.attr("rel").lowercase(Locale.ROOT).split(Regex("\\s+")) &&
            !discussionTitle.containsMatchIn(it.attr("title")) &&
            it.attr("type").substringBefore(';').trim().lowercase(Locale.ROOT) in
                setOf("application/rss+xml", "application/atom+xml", "application/rdf+xml") }
        .map { it.absUrl("href") }.filter { accepts(origin, it) }
        .mapNotNull { ProactiveAttentionFeedPolicy.publicUrl(it) }.distinct().take(2).toList()
}
