package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import org.jsoup.Jsoup

data class AttentionWebSources(val feeds: List<String>, val articles: List<AttentionFeedArticle>)

object ProactiveAttentionWebSources {
    fun explicit(topic: AttentionTopic): List<String> = Regex("https://[^\\s<>\"']+")
        .findAll(topic.query).mapNotNull { ProactiveAttentionFeedPolicy.publicUrl(it.value.trimEnd(',', ';', ')')) }
        .distinct().toList()

    fun discover(html: String, baseUrl: String, topicId: String, now: Long): AttentionWebSources {
        require(ProactiveAttentionFeedPolicy.publicUrl(baseUrl) != null)
        val document = Jsoup.parse(html, baseUrl)
        val feeds = document.select("link[rel=alternate]").filter {
            it.attr("type").lowercase() in setOf("application/rss+xml", "application/atom+xml")
        }.mapNotNull { ProactiveAttentionFeedPolicy.publicUrl(it.absUrl("href")) }.distinct()
        val articles = mutableListOf<AttentionFeedArticle>()
        fun visit(value: Any?, depth: Int = 0) {
            if (depth > 8) return
            when (value) {
                is JSONArray -> (0 until value.length()).forEach { visit(value.opt(it), depth + 1) }
                is JSONObject -> {
                    visit(value.opt("@graph"), depth + 1)
                    val types = value.opt("@type")
                    val article = types == "NewsArticle" || types == "Article" || types == "BlogPosting" ||
                        types is JSONArray && (0 until types.length()).any { types.optString(it) in setOf("NewsArticle", "Article", "BlogPosting") }
                    if (!article) return
                    val date = ProactiveAttentionFeedPolicy.date(value.optString("datePublished"))
                    if (date < now - 7 * ProactiveAttentionNewsPolicy.DAY || date > now + 300_000L) return
                    val declared = value.optString("url").ifBlank {
                        value.optJSONObject("mainEntityOfPage")?.optString("@id").orEmpty()
                    }.ifBlank { baseUrl }
                    val resolved = runCatching { java.net.URI(document.baseUri()).resolve(declared).toString() }.getOrNull() ?: return
                    val url = ProactiveAttentionFeedPolicy.publicUrl(resolved) ?: return
                    val title = Jsoup.parse(value.optString("headline")).text().take(240)
                    if (title.isBlank()) return
                    val publisher = value.optJSONObject("publisher")?.optString("name").orEmpty()
                        .ifBlank { java.net.URI(url).host }
                    articles += AttentionFeedArticle(ProactiveAttentionFeedPolicy.urlKey(url), topicId, title,
                        Jsoup.parse(value.optString("description")).text().take(800), url, publisher.take(120), date, now)
                }
            }
        }
        document.select("script[type=application/ld+json]").forEach { script ->
            runCatching { visit(JSONTokener(script.data()).nextValue()) }
        }
        return AttentionWebSources(feeds, articles.distinctBy { it.key })
    }
}
