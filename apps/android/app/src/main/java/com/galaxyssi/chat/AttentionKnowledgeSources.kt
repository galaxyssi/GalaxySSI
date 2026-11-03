package com.galaxyssi.chat

import java.net.URI
import org.jsoup.Jsoup

/** Only curated educational indexes may discover undated, evergreen material. */
internal object AttentionKnowledgeSources {
    const val REFRESH_MILLIS = 24 * 60 * 60_000L
    val endpoints = listOf(
        "https://pdb101.rcsb.org/motm/motm-by-date",
        "https://www.genome.gov/genetics-glossary",
        "https://www.ipd.uw.edu/what-is-protein-design/"
    ) + listOf("basics", "howgeneswork", "genomicresearch", "therapy", "precisionmedicine", "mutationsanddisorders",
        "inheritance", "traits", "consult", "testing", "dtcgenetictesting")
        .map { "https://medlineplus.gov/genetics/understanding/$it/" } + listOf(
        "https://www.genome.gov/about-genomics/fact-sheets",
        "https://www.cancer.gov/publications/fact-sheets",
        "https://www.cancer.gov/about-cancer/treatment/types"
    ) + AttentionOpenTextbooks.endpoints

    fun endpoints(topicId: String) = if (topicId == AttentionLifeScienceSources.TOPIC) endpoints else emptyList()
    fun accepts(endpoint: String, target: String): Boolean {
        if (endpoint !in endpoints) return false
        val source = URI(endpoint)
        val url = runCatching { URI(target) }.getOrNull() ?: return false
        if (url.scheme != "https" || url.host != source.host || url.rawQuery != null || url.rawFragment != null ||
            url.rawUserInfo != null || url.port !in listOf(-1, 443)) return false
        return when (source.host) {
            "pdb101.rcsb.org" -> url.path.matches(Regex("/motm/[0-9]+"))
            "www.genome.gov" -> if (source.path == "/genetics-glossary")
                url.path.matches(Regex("/genetics-glossary/[A-Za-z0-9-]+")) else
                url.path.matches(Regex("/about-genomics/fact-sheets/[A-Za-z0-9-]+"))
            "medlineplus.gov" -> url.path.startsWith(source.path) &&
                url.path.removePrefix(source.path).matches(Regex("[a-z0-9-]+/?"))
            "www.ipd.uw.edu" -> target.trimEnd('/') == endpoint.trimEnd('/')
            "www.cancer.gov" -> url.path.matches(Regex("/about-cancer/(treatment|diagnosis-staging|causes-prevention|screening|understanding)/[a-z0-9/-]+")) &&
                target.trimEnd('/') != endpoint.trimEnd('/')
            "openstax.org" -> AttentionOpenTextbooks.accepts(endpoint, target)
            else -> false
        }
    }

    fun discover(html: String, endpoint: String, topicId: String, now: Long): List<AttentionFeedArticle> {
        require(endpoint in endpoints && topicId == AttentionLifeScienceSources.TOPIC)
        val document = Jsoup.parse(html, endpoint)
        val textbookLinks = if (endpoint in AttentionOpenTextbooks.endpoints) AttentionOpenTextbooks.discover(document, endpoint) else null
        document.select("script,style,nav,footer,header,[role=navigation]").remove()
        val links = textbookLinks ?: if (endpoint.contains("ipd.uw.edu")) listOf(endpoint to
            (document.selectFirst("h1")?.text()?.takeIf(String::isNotBlank) ?: document.title())) else
            document.select("a[href]").map { it.absUrl("href") to it.text() }
        return links.mapNotNull { (raw, label) ->
            val url = ProactiveAttentionFeedPolicy.publicUrl(raw) ?: return@mapNotNull null
            if (!accepts(endpoint, url)) return@mapNotNull null
            // Glossary indexes label their links MORE; the entry heading lives in the article itself.
            val title = label.trim().takeIf { it.length >= 3 && !it.equals("more", true) }
                ?: URI(url).path.trimEnd('/').substringAfterLast('/').replace('-', ' ')
            AttentionFeedArticle(ProactiveAttentionFeedPolicy.urlKey(url), topicId, title.take(240), "", url,
                URI(url).host, 0, now, discoveryDate = true, discoveredVia = endpoint, knowledge = true)
        }.distinctBy { it.key }
    }
}
