package com.galaxyssi.chat

import org.jsoup.Jsoup
import java.net.URI
import java.net.URLDecoder
import java.util.Base64

/** Parse result cards, not every link in the search page (navigation is not evidence). */
internal object AgentPublicWebSearchParser {
    data class Hit(val title: String, val url: String, val excerpt: String)

    fun parse(source: String, baseUrl: String, limit: Int): List<Hit> {
        val document = Jsoup.parse(source, baseUrl)
        val responseUri = runCatching { URI(baseUrl) }.getOrNull()
        val responseHost = responseUri?.host.orEmpty().lowercase()
        if ((responseHost == "wappass.baidu.com" && responseUri?.path.orEmpty().contains("/captcha/")) ||
            (responseHost in setOf("baidu.com", "www.baidu.com") && document.title() == "\u767e\u5ea6\u5b89\u5168\u9a8c\u8bc1")) {
            throw AgentWebMediaException("source_verification_required", "Search source requires verification", retryable = false)
        }
        document.select("script, style, nav, footer, header, .b_ad, .ads, [data-text-ad]").remove()
        val selector = "h2 a[href], h3 a[href], a[href]:has(h2), a[href]:has(h3), " +
            "a.result__a[href], a.result-link[href], a.heading-serpresult[href]"
        val titles = document.select(selector)
        // Small bare-link responses remain useful for simple HTML indexes and adapters.
        val anchors = if (titles.isEmpty() && document.body().children().all { it.tagName() == "a" }) {
            document.select("a[href]")
        } else titles
        val seen = hashSetOf<String>()
        val engineHost = runCatching { URI(baseUrl).host?.lowercase()?.removePrefix("www.") }.getOrNull().orEmpty()
        return anchors.mapNotNull { anchor ->
            val title = anchor.text().trim().take(2_048)
            val card = anchor.closest(".b_algo, .result, .results_links, .vrResult, .vrwrap, .rb, " +
                ".sa-spacing-text-heading, .c-container, .snippet") ?: anchor.parent()
            // Baidu's ordinary result cards expose the destination without following an opaque redirect.
            val cardUrl = card?.takeIf { engineHost == "baidu.com" && it.hasClass("c-container") &&
                it.selectFirst("h3 a[href]") == anchor }?.attr("mu").orEmpty()
            val directCardUrl = cardUrl.takeIf { it.startsWith("https://") || it.startsWith("http://") }
                ?.let { destination(it, baseUrl) }.orEmpty()
            val url = directCardUrl.ifBlank { destination(anchor.attr("href"), baseUrl) }
            val host = runCatching { URI(url).host?.removePrefix("www.") }.getOrNull().orEmpty()
            if (title.isBlank() || host.isBlank() || host.equals(engineHost, true) || !seen.add(url)) {
                return@mapNotNull null
            }
            val excerpt = card?.select(".b_caption p, .result__snippet, .click-sugg-content, " +
                "[class*=introduceWrap], [data-module=abstract], .c-abstract, .c-span-last, .content, .snippet-description, p")
                ?.map { it.text().trim() }?.filter { it.isNotBlank() && it != title }
                ?.distinct()?.joinToString(" ")?.take(1_600).orEmpty()
            Hit(title, url, excerpt)
        }.take(limit)
    }

    internal fun destination(raw: String, baseUrl: String): String = runCatching {
        val absolute = URI(baseUrl).resolve(raw.trim())
        val query = absolute.rawQuery.orEmpty().split('&').associate { pair ->
            decode(pair.substringBefore('=')) to decode(pair.substringAfter('=', ""))
        }
        val host = absolute.host.orEmpty().lowercase()
        val redirected = if (host == URI(baseUrl).host.orEmpty().lowercase()) {
            val encodedBing = query["u"].orEmpty()
            if ((host == "bing.com" || host.endsWith(".bing.com")) && encodedBing.startsWith("a1")) {
                runCatching { String(Base64.getUrlDecoder().decode(encodedBing.drop(2)), Charsets.UTF_8) }.getOrNull()
                    ?: return@runCatching ""
            } else listOf("uddg", "url", "target", "u", "r").firstNotNullOfOrNull { key ->
                query[key]?.takeIf { it.startsWith("https://") || it.startsWith("http://") }
            }
        } else null
        val uri = URI(redirected ?: absolute.toString())
        if (uri.scheme !in setOf("https", "http") || uri.host.isNullOrBlank() || uri.userInfo != null) ""
        else AgentWebIntelligenceText.canonicalUrl(uri.toString())
    }.getOrDefault("")

    private fun decode(value: String): String = URLDecoder.decode(value, Charsets.UTF_8.name())
}
