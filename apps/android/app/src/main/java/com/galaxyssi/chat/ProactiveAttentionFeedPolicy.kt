package com.galaxyssi.chat

import org.jsoup.Jsoup
import org.jsoup.parser.Parser
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

data class AttentionFeedArticle(
    val key: String,
    val topicId: String,
    val title: String,
    val summary: String,
    val url: String,
    val publisher: String,
    val publishedAt: Long,
    val collectedAt: Long
)

/** Discovery is a source-attributed lead, not a model verdict or a full-text reading receipt. */
object ProactiveAttentionFeedPolicy {
    const val UNIT_PREFIX = "attention-feed:"
    const val MIN_INTERVAL = 30 * 60_000L
    const val MAX_INTERVAL = 4 * 60 * 60_000L

    fun endpoints(topic: AttentionTopic): List<String> {
        val query = if (ProactiveAttentionPolicy.group(topic.id) == AttentionTopicGroup.CUSTOM)
            topic.query.take(512) else topic.title
        val encoded = URLEncoder.encode(query, "UTF-8")
        return listOf(
            "https://www.bing.com/news/search?q=$encoded&format=rss&sortbydate=1",
            "https://news.google.com/rss/search?q=$encoded+when%3A7d&hl=zh-CN&gl=CN&ceid=CN%3Azh-Hans"
        )
    }

    fun parse(xml: String, topicId: String, now: Long): List<AttentionFeedArticle> {
        // Jsoup's XML parser does not resolve external entities or execute feed markup.
        val document = Jsoup.parse(xml, "", Parser.xmlParser())
        require(document.selectFirst("rss, RDF") != null) { "news_feed_invalid_document" }
        return document.select("item").mapNotNull { item ->
            val title = clean(item.selectFirst("title")?.text().orEmpty(), 240)
            val summary = clean(item.selectFirst("description")?.text().orEmpty(), 800)
            val link = item.selectFirst("link")?.text().orEmpty()
            val url = publicUrl(unwrap(link)) ?: return@mapNotNull null
            val published = date(item.selectFirst("pubDate")?.text().orEmpty())
            if (title.isBlank() || published < now - 7 * ProactiveAttentionNewsPolicy.DAY ||
                published > now + 5 * 60_000L) return@mapNotNull null
            val publisher = clean(item.selectFirst("source")?.text().orEmpty(), 120)
                .ifBlank { URI(url).host }
            AttentionFeedArticle(urlKey(url), topicId,
                title, summary, url, publisher, published, now)
        }.distinctBy { it.key }
    }

    fun date(value: String): Long = runCatching { Instant.parse(value).toEpochMilli() }.getOrNull()
        ?: runCatching { ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli() }.getOrNull()
        ?: runCatching { LocalDate.parse(value).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli() }.getOrDefault(0L)

    // Text-normalization keys erase URLs; article and feed identity must retain every URL byte.
    fun urlKey(url: String): String = java.security.MessageDigest.getInstance("SHA-256")
        .digest(url.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    fun publicUrl(value: String): String? {
        val uri = runCatching { URI(value.trim()) }.getOrNull() ?: return null
        val host = uri.host?.lowercase(Locale.ROOT) ?: return null
        if (uri.scheme != "https" || uri.rawUserInfo != null || uri.port !in listOf(-1, 443) ||
            !host.contains('.') || host.endsWith(".local") || host.endsWith(".localhost") ||
            host.contains(':') || host.all { it.isDigit() || it == '.' } || value.length > 4096) return null
        return GlobalEvidenceEvaluator.canonicalUri(uri.toString())
    }

    fun interval(previous: Long, newItems: Int, failed: Boolean): Long =
        if (newItems > 0) MIN_INTERVAL else (previous.coerceIn(MIN_INTERVAL, MAX_INTERVAL) +
            if (failed) previous.coerceIn(MIN_INTERVAL, MAX_INTERVAL) else MIN_INTERVAL).coerceAtMost(MAX_INTERVAL)

    fun markdownText(value: String): String = value.replace("\\", "\\\\").replace("[", "\\[")
        .replace("]", "\\]").replace("*", "\\*").replace("_", "\\_").replace("<", "&lt;").replace(">", "&gt;")

    private fun clean(value: String, limit: Int) = Jsoup.parse(value).text()
        .replace(Regex("\\s+"), " ").trim().take(limit)

    private fun unwrap(value: String): String {
        val uri = runCatching { URI(value) }.getOrNull() ?: return value
        if (uri.host?.lowercase(Locale.ROOT) !in setOf("www.bing.com", "bing.com")) return value
        val target = uri.rawQuery.orEmpty().split('&').firstOrNull { it.startsWith("url=") }
            ?.substringAfter('=') ?: return value
        return runCatching { URLDecoder.decode(target, "UTF-8") }.getOrDefault(value)
    }
}
