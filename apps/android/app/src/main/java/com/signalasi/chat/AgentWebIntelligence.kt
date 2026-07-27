package com.signalasi.chat

import android.content.Context
import android.util.Xml
import org.json.JSONArray
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.StringReader
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.MessageDigest
import java.time.Instant
import java.time.OffsetDateTime
import java.util.Locale
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

const val AGENT_WEB_INTELLIGENCE_PROTOCOL = "signalasi.web-intelligence.v1"
private const val WEB_SOURCE_FAILURE_THRESHOLD = 3
private const val WEB_SOURCE_BASE_COOLDOWN_MILLIS = 60_000L
private const val WEB_SOURCE_MAX_COOLDOWN_MILLIS = 30 * 60_000L
private const val WEB_SOURCE_EWMA_ALPHA = 0.25

enum class AgentWebIntelligenceVertical(val wireValue: String) {
    GENERAL("general"),
    NEWS("news"),
    CODE("code"),
    DOCS("docs"),
    ACADEMIC("academic"),
    COMMUNITY("community"),
    KNOWLEDGE("knowledge"),
    IMAGE("image"),
    VIDEO("video"),
    LOCAL("local")
}

enum class AgentWebIntelligenceSearchProfile(
    val wireValue: String,
    val defaultFanout: Int,
    val defaultTimeoutMillis: Long
) {
    FAST("fast", 6, 6_000L),
    BALANCED("balanced", 18, 15_000L),
    DEEP("deep", 32, 35_000L);

    companion object {
        fun from(value: String): AgentWebIntelligenceSearchProfile =
            entries.firstOrNull { it.wireValue == value.lowercase(Locale.ROOT) }
                ?: throw IllegalArgumentException("Unsupported search profile: $value")
    }
}

data class AgentWebIntelligenceEngineSpec(
    val id: String,
    val title: String,
    val vertical: AgentWebIntelligenceVertical,
    val endpoint: String,
    val parser: String = "html",
    val languages: Set<String> = setOf("*"),
    val weight: Double = 1.0,
    val authority: Double = 0.5,
    val enabledByDefault: Boolean = true
)

data class AgentWebIntelligenceFetched(
    val url: String,
    val contentType: String,
    val body: ByteArray,
    val durationMillis: Long = 0L
)

fun interface AgentWebIntelligenceFetcher {
    fun fetch(
        url: String,
        maxBytes: Long,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched
}

class AgentBoundedWebIntelligenceFetcher(
    private val web: AgentBoundedWebService
) : AgentWebIntelligenceFetcher {
    override fun fetch(
        url: String,
        maxBytes: Long,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched {
        val started = System.currentTimeMillis()
        val resource = web.fetch(url, maxBytes, timeoutMillis, cancellationToken, checkpoint)
        return AgentWebIntelligenceFetched(
            url = resource.finalUrl,
            contentType = resource.contentType,
            body = resource.body,
            durationMillis = System.currentTimeMillis() - started
        )
    }
}

data class AgentWebIntelligenceRawResult(
    val engineId: String,
    val rank: Int,
    val title: String,
    val url: String,
    val excerpt: String = "",
    val publishedAt: String = "",
    val vertical: AgentWebIntelligenceVertical = AgentWebIntelligenceVertical.GENERAL
)

data class AgentWebIntelligenceReceipt(
    val sourceId: String,
    val status: String,
    val durationMillis: Long,
    val resultCount: Int,
    val errorCode: String = "",
    val errorMessage: String = "",
    val retryable: Boolean = false
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "source_id" to sourceId,
        "status" to status,
        "duration_millis" to durationMillis.coerceAtLeast(0L),
        "result_count" to resultCount.coerceAtLeast(0),
        "error_code" to errorCode,
        "error_message" to errorMessage.take(2_048),
        "retryable" to retryable
    )
}

data class AgentWebIntelligenceSourceHealth(
    val sourceId: String,
    val attempts: Int = 0,
    val successes: Int = 0,
    val emptyResponses: Int = 0,
    val failures: Int = 0,
    val consecutiveFailures: Int = 0,
    val ewmaLatencyMillis: Double = 0.0,
    val ewmaResultCount: Double = 0.0,
    val lastStatus: String = "",
    val lastAttemptAtMillis: Long = 0L,
    val lastSuccessAtMillis: Long = 0L,
    val circuitOpenUntilMillis: Long = 0L
) {
    fun circuitState(nowMillis: Long): String = when {
        circuitOpenUntilMillis > nowMillis -> "open"
        consecutiveFailures >= WEB_SOURCE_FAILURE_THRESHOLD -> "half_open"
        else -> "closed"
    }

    fun routingScore(): Double {
        val reliable = (successes + emptyResponses + 2.0) / (attempts + 4.0)
        val speed = if (ewmaLatencyMillis <= 0.0) 0.6 else 1.0 / (1.0 + ewmaLatencyMillis / 3_000.0)
        val useful = (ewmaResultCount / 8.0).coerceAtMost(1.0)
        val exploration = 1.0 / sqrt(attempts + 1.0)
        return reliable * 1.1 + speed * 0.5 + useful * 0.35 + exploration * 0.25
    }

    fun evolve(receipt: AgentWebIntelligenceReceipt, nowMillis: Long): AgentWebIntelligenceSourceHealth {
        if (receipt.status == "cancelled") {
            return copy(lastStatus = receipt.status, lastAttemptAtMillis = nowMillis)
        }
        val latency = receipt.durationMillis.coerceAtLeast(0L).toDouble()
        val resultCount = receipt.resultCount.coerceAtLeast(0).toDouble()
        val nextLatency = if (attempts == 0) latency else
            ewmaLatencyMillis * (1.0 - WEB_SOURCE_EWMA_ALPHA) + latency * WEB_SOURCE_EWMA_ALPHA
        val nextResults = if (attempts == 0) resultCount else
            ewmaResultCount * (1.0 - WEB_SOURCE_EWMA_ALPHA) + resultCount * WEB_SOURCE_EWMA_ALPHA
        val successful = receipt.status in setOf("completed", "empty")
        val nextFailures = if (successful) 0 else consecutiveFailures + 1
        val openUntil = if (!successful && nextFailures >= WEB_SOURCE_FAILURE_THRESHOLD) {
            val exponent = (nextFailures - WEB_SOURCE_FAILURE_THRESHOLD).coerceIn(0, 10)
            nowMillis + min(
                WEB_SOURCE_MAX_COOLDOWN_MILLIS,
                WEB_SOURCE_BASE_COOLDOWN_MILLIS * (1L shl exponent)
            )
        } else 0L
        return copy(
            attempts = attempts + 1,
            successes = successes + if (receipt.status == "completed") 1 else 0,
            emptyResponses = emptyResponses + if (receipt.status == "empty") 1 else 0,
            failures = failures + if (successful) 0 else 1,
            consecutiveFailures = nextFailures,
            ewmaLatencyMillis = nextLatency,
            ewmaResultCount = nextResults,
            lastStatus = receipt.status,
            lastAttemptAtMillis = nowMillis,
            lastSuccessAtMillis = if (successful) nowMillis else lastSuccessAtMillis,
            circuitOpenUntilMillis = openUntil
        )
    }

    fun publicValue(nowMillis: Long): AgentNativeJsonObject = linkedMapOf(
        "source_id" to sourceId,
        "attempts" to attempts,
        "successes" to successes,
        "empty_responses" to emptyResponses,
        "failures" to failures,
        "consecutive_failures" to consecutiveFailures,
        "ewma_latency_millis" to ewmaLatencyMillis,
        "ewma_result_count" to ewmaResultCount,
        "last_status" to lastStatus,
        "last_attempt_at_millis" to lastAttemptAtMillis,
        "last_success_at_millis" to lastSuccessAtMillis,
        "circuit_state" to circuitState(nowMillis),
        "circuit_open_until_millis" to circuitOpenUntilMillis,
        "routing_score" to routingScore()
    )
}

private data class AgentWebIntelligenceSourceSelection(
    val selected: List<String>,
    val skipped: List<AgentWebIntelligenceSourceHealth> = emptyList(),
    val explicit: Boolean = false
)

data class AgentWebIntelligenceScore(
    val final: Double,
    val reciprocalRank: Double,
    val lexical: Double,
    val consensus: Double,
    val authority: Double,
    val freshness: Double,
    val localModel: Double
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "final" to final.roundScore(),
        "reciprocal_rank" to reciprocalRank.roundScore(),
        "lexical" to lexical.roundScore(),
        "consensus" to consensus.roundScore(),
        "authority" to authority.roundScore(),
        "freshness" to freshness.roundScore(),
        "local_model" to localModel.roundScore()
    )
}

data class AgentWebIntelligenceResult(
    var title: String,
    val url: String,
    var excerpt: String,
    var publishedAt: String,
    var vertical: AgentWebIntelligenceVertical,
    val engineRanks: MutableMap<String, Int> = linkedMapOf(),
    val engineWeights: MutableMap<String, Double> = linkedMapOf(),
    var authority: Double = 0.0,
    var score: AgentWebIntelligenceScore = AgentWebIntelligenceScore(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
) {
    fun publicValue(rank: Int): AgentNativeJsonObject = linkedMapOf(
        "citation_id" to AgentWebIntelligenceText.citationId(url, excerpt),
        "title" to title.take(2_048),
        "url" to url.take(4_096),
        "excerpt" to excerpt.take(16_384),
        "published_at" to publishedAt.take(64),
        "language" to AgentWebIntelligenceText.language("$title $excerpt"),
        "vertical" to vertical.wireValue,
        "engines" to engineRanks.keys.sorted(),
        "rank" to rank,
        "score" to score.publicValue()
    )
}

object AgentWebIntelligenceEngineCatalog {
    val entries: List<AgentWebIntelligenceEngineSpec> = listOf(
        spec("bing", "Bing", "general", "https://www.bing.com/search?q={query}&count={limit}", weight = 1.05),
        spec("duckduckgo", "DuckDuckGo", "general", "https://html.duckduckgo.com/html/?q={query}", weight = 1.05),
        spec("baidu", "Baidu", "general", "https://www.baidu.com/s?wd={query}&rn={limit}", languages = setOf("zh"), weight = 1.05),
        spec("brave", "Brave Search", "general", "https://search.brave.com/search?q={query}&source=web"),
        spec("mojeek", "Mojeek", "general", "https://www.mojeek.com/search?q={query}"),
        spec("qwant", "Qwant", "general", "https://www.qwant.com/?q={query}&t=web"),
        spec("yahoo", "Yahoo", "general", "https://search.yahoo.com/search?p={query}"),
        spec("yandex", "Yandex", "general", "https://yandex.com/search/?text={query}"),
        spec("ecosia", "Ecosia", "general", "https://www.ecosia.org/search?q={query}"),
        spec("startpage", "Startpage", "general", "https://www.startpage.com/sp/search?query={query}"),
        spec("sogou", "Sogou", "general", "https://www.sogou.com/web?query={query}", languages = setOf("zh")),
        spec("so360", "360 Search", "general", "https://www.so.com/s?q={query}", languages = setOf("zh")),
        spec("naver", "Naver", "general", "https://search.naver.com/search.naver?query={query}", languages = setOf("ko")),
        spec("google", "Google", "general", "https://www.google.com/search?q={query}&num={limit}", enabled = false),
        spec("bing_news", "Bing News", "news", "https://www.bing.com/news/search?q={query}&count={limit}", weight = 1.1),
        spec("brave_news", "Brave News", "news", "https://search.brave.com/news?q={query}"),
        spec("wikipedia", "Wikipedia", "knowledge", "https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit={limit}&srsearch={query}", parser = "wikipedia", authority = 0.9),
        spec("wikipedia_zh", "Wikipedia Chinese", "knowledge", "https://zh.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit={limit}&srsearch={query}", parser = "wikipedia_zh", languages = setOf("zh"), authority = 0.9),
        spec("github", "GitHub", "code", "https://api.github.com/search/repositories?q={query}&per_page={limit}", parser = "github", authority = 0.85),
        spec("gitlab", "GitLab", "code", "https://gitlab.com/api/v4/projects?search={query}&per_page={limit}", parser = "gitlab", authority = 0.8),
        spec("stackoverflow", "Stack Overflow", "community", "https://api.stackexchange.com/2.3/search/advanced?site=stackoverflow&pagesize={limit}&q={query}", parser = "stackoverflow", authority = 0.85),
        spec("hacker_news", "Hacker News", "community", "https://hn.algolia.com/api/v1/search?hitsPerPage={limit}&query={query}", parser = "hacker_news", authority = 0.7),
        spec("lobsters", "Lobsters", "community", "https://lobste.rs/search.json?q={query}", parser = "lobsters", authority = 0.7),
        spec("reddit", "Reddit", "community", "https://www.reddit.com/search.json?q={query}&limit={limit}&raw_json=1", parser = "reddit", authority = 0.65),
        spec("crossref", "Crossref", "academic", "https://api.crossref.org/works?rows={limit}&query={query}", parser = "crossref", authority = 0.9),
        spec("semantic_scholar", "Semantic Scholar", "academic", "https://api.semanticscholar.org/graph/v1/paper/search?limit={limit}&fields=title,url,abstract,year,authors&query={query}", parser = "semantic_scholar", authority = 0.9),
        spec("arxiv", "arXiv", "academic", "https://export.arxiv.org/api/query?max_results={limit}&search_query=all:{query}", parser = "atom", authority = 0.9),
        spec("pubmed", "PubMed", "academic", "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&retmax={limit}&term={query}", parser = "pubmed", authority = 0.95),
        spec("crates_io", "crates.io", "code", "https://crates.io/api/v1/crates?q={query}&per_page={limit}", parser = "crates_io", authority = 0.8),
        spec("npm", "npm", "code", "https://registry.npmjs.org/-/v1/search?size={limit}&text={query}", parser = "npm", authority = 0.8),
        spec("mdn", "MDN", "docs", "https://developer.mozilla.org/api/v1/search?q={query}&page_size={limit}", parser = "mdn", authority = 0.95),
        spec("pypi", "PyPI", "code", "https://pypi.org/search/?q={query}", authority = 0.8)
    )

    private fun spec(
        id: String,
        title: String,
        vertical: String,
        endpoint: String,
        parser: String = "html",
        languages: Set<String> = setOf("*"),
        weight: Double = 1.0,
        authority: Double = 0.5,
        enabled: Boolean = true
    ) = AgentWebIntelligenceEngineSpec(
        id = id,
        title = title,
        vertical = AgentWebIntelligenceVertical.entries.first { it.wireValue == vertical },
        endpoint = endpoint,
        parser = parser,
        languages = languages,
        weight = weight,
        authority = authority,
        enabledByDefault = enabled
    )
}

class AgentWebIntelligenceRanker(
    private val weights: DoubleArray = DEFAULT_WEIGHTS.copyOf()
) {
    init {
        require(weights.size == FEATURE_COUNT)
        require(weights.all(Double::isFinite))
    }

    fun score(features: DoubleArray): Double {
        require(features.size == FEATURE_COUNT - 1)
        var value = weights[0]
        features.indices.forEach { index -> value += weights[index + 1] * features[index] }
        return 1.0 / (1.0 + exp(-value.coerceIn(-30.0, 30.0)))
    }

    companion object {
        const val MODEL_ID = "signalasi-web-ranker-v1"
        private const val FEATURE_COUNT = 10
        private val DEFAULT_WEIGHTS = doubleArrayOf(-1.15, 2.35, 1.8, 1.25, 0.9, 0.55, 0.75, 1.1, 0.45, -1.4)

        fun fromAssets(context: Context): AgentWebIntelligenceRanker = runCatching {
            val raw = context.assets.open("web-intelligence/ranker-v1.json")
                .bufferedReader(Charsets.UTF_8).use { it.readText() }
            val values = JSONObject(raw).getJSONArray("weights")
            AgentWebIntelligenceRanker(DoubleArray(values.length()) { values.getDouble(it) })
        }.getOrElse { AgentWebIntelligenceRanker() }
    }
}

class AgentWebIntelligenceEmbedder(
    val dimensions: Int = 192
) {
    init {
        require(dimensions in 32..2_048)
    }

    val modelId: String = "signalasi-feature-hash-$dimensions-v1"

    fun embed(value: String): FloatArray {
        val normalized = AgentWebIntelligenceText.normalized(value)
        val features = AgentWebIntelligenceText.tokens(normalized).toMutableList()
        for (index in 0..(normalized.length - 3).coerceAtLeast(-1)) {
            val item = normalized.substring(index, index + 3)
            if (!item.any(Char::isWhitespace)) features += item
        }
        val counts = features.groupingBy { it }.eachCount()
        val vector = FloatArray(dimensions)
        counts.forEach { (feature, count) ->
            val digest = MessageDigest.getInstance("SHA-256").digest(feature.toByteArray(Charsets.UTF_8))
            val raw = digest.take(8).fold(0L) { accumulator, byte ->
                (accumulator shl 8) or (byte.toLong() and 0xff)
            }
            val index = ((raw and Long.MAX_VALUE) % dimensions).toInt()
            val sign = if (raw < 0L) -1f else 1f
            vector[index] += sign * (1.0 + ln(1.0 + count)).toFloat()
        }
        val norm = sqrt(vector.sumOf { it.toDouble() * it.toDouble() }).toFloat().takeIf { it > 0f } ?: 1f
        vector.indices.forEach { vector[it] /= norm }
        return vector
    }

    fun cosine(left: FloatArray, right: FloatArray): Double {
        if (left.size != right.size) return 0.0
        return left.indices.sumOf { left[it].toDouble() * right[it].toDouble() }.coerceIn(-1.0, 1.0)
    }
}

object AgentWebIntelligenceText {
    private val latinToken = Regex("[a-z0-9][a-z0-9_+.-]{1,}")
    private val cjkGroup = Regex("[\\u3400-\\u9fff]+")
    private val trackingKeys = setOf("gclid", "fbclid", "ref", "source", "campaign")

    fun normalized(value: String): String = java.text.Normalizer
        .normalize(value, java.text.Normalizer.Form.NFKC)
        .lowercase(Locale.ROOT)

    fun tokens(value: String): List<String> {
        val normalized = normalized(value)
        val values = latinToken.findAll(normalized).map { it.value }.toMutableList()
        cjkGroup.findAll(normalized).forEach { match ->
            val group = match.value
            if (group.length == 1) values += group
            else for (index in 0 until group.length - 1) values += group.substring(index, index + 2)
        }
        return values
    }

    fun language(value: String): String = when {
        Regex("[\\u3400-\\u9fff]").containsMatchIn(value) -> "zh"
        Regex("[\\u3040-\\u30ff]").containsMatchIn(value) -> "ja"
        Regex("[\\uac00-\\ud7af]").containsMatchIn(value) -> "ko"
        else -> "en"
    }

    fun canonicalUrl(value: String): String = runCatching {
        val parsed = URI(value.trim())
        val scheme = parsed.scheme?.lowercase(Locale.ROOT) ?: "https"
        val host = parsed.host?.lowercase(Locale.ROOT)?.removePrefix("www.") ?: return value.trim()
        val port = parsed.port.takeIf { it >= 0 && !((scheme == "https" && it == 443) || (scheme == "http" && it == 80)) }
        val authority = if (port != null) "$host:$port" else host
        val path = (parsed.path ?: "/").replace(Regex("/+"), "/").let { if (it != "/") it.trimEnd('/') else it }
        val query = parsed.rawQuery.orEmpty().split('&').mapNotNull { pair ->
            val key = pair.substringBefore('=')
            if (key.lowercase(Locale.ROOT).startsWith("utm_") || key.lowercase(Locale.ROOT) in trackingKeys) null else pair
        }.sorted().joinToString("&")
        URI(scheme, authority, path, query.ifBlank { null }, null).toString()
    }.getOrDefault(value.trim())

    fun citationId(url: String, excerpt: String): String = MessageDigest.getInstance("SHA-256")
        .digest("${canonicalUrl(url)}\n$excerpt".toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
        .take(24)

    fun clean(value: Any?, maxLength: Int): String = decodeHtml(
        value?.toString().orEmpty()
            .replace(Regex("<script[^>]*>[\\s\\S]*?</script>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<style[^>]*>[\\s\\S]*?</style>", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("<[^>]+>"), " ")
    ).replace(Regex("\\s+"), " ").trim().take(maxLength)

    fun decodeHtml(value: String): String {
        val named = value
            .replace("&nbsp;", " ", ignoreCase = true)
            .replace("&amp;", "&", ignoreCase = true)
            .replace("&lt;", "<", ignoreCase = true)
            .replace("&gt;", ">", ignoreCase = true)
            .replace("&quot;", "\"", ignoreCase = true)
            .replace("&#39;", "'", ignoreCase = true)
            .replace("&apos;", "'", ignoreCase = true)
        return Regex("&#(x[0-9a-f]+|[0-9]+);", RegexOption.IGNORE_CASE).replace(named) { match ->
            val raw = match.groupValues[1]
            val codePoint = runCatching {
                if (raw.startsWith("x", true)) raw.drop(1).toInt(16) else raw.toInt()
            }.getOrNull()
            codePoint?.takeIf(Character::isValidCodePoint)?.let(Character::toChars)?.concatToString()
                ?: match.value
        }
    }
}

class AgentWebIntelligenceSearchAdapter(
    private val spec: AgentWebIntelligenceEngineSpec,
    private val fetcher: AgentWebIntelligenceFetcher
) {
    fun search(
        query: String,
        limit: Int,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): List<AgentWebIntelligenceRawResult> {
        val encoded = URLEncoder.encode(query, Charsets.UTF_8.name())
        val url = spec.endpoint.replace("{query}", encoded).replace("{limit}", limit.toString())
        val fetched = fetcher.fetch(
            url = url,
            maxBytes = 1_048_576L,
            timeoutMillis = timeoutMillis,
            cancellationToken = cancellationToken,
            checkpoint = checkpoint
        )
        val text = fetched.body.toString(Charsets.UTF_8)
        return when (spec.parser) {
            "html" -> parseHtml(text, fetched.url, limit)
            "atom" -> parseAtom(text, limit)
            else -> parseJsonValue(text, limit)
        }
    }

    private fun parseHtml(source: String, baseUrl: String, limit: Int): List<AgentWebIntelligenceRawResult> {
        val anchorPattern = Regex(
            "<a\\b[^>]*?href\\s*=\\s*([\"'])(.*?)\\1[^>]*>([\\s\\S]*?)</a>",
            setOf(RegexOption.IGNORE_CASE)
        )
        val engineHost = runCatching { URI(baseUrl).host.orEmpty() }.getOrDefault("")
        val seen = linkedSetOf<String>()
        return buildList {
            anchorPattern.findAll(source).forEach { match ->
                val title = AgentWebIntelligenceText.clean(match.groupValues[3], 2_048)
                val unwrapped = unwrap(match.groupValues[2], baseUrl)
                val host = runCatching { URI(unwrapped).host.orEmpty() }.getOrDefault("")
                val canonical = AgentWebIntelligenceText.canonicalUrl(unwrapped)
                if (title.isBlank() || host.isBlank() || host.equals(engineHost, ignoreCase = true) || !seen.add(canonical)) {
                    return@forEach
                }
                add(raw(size + 1, title, canonical))
                if (size >= limit) return@buildList
            }
        }
    }

    private fun parseJson(root: JSONObject, limit: Int): List<AgentWebIntelligenceRawResult> = when (spec.parser) {
        "wikipedia" -> wikipedia(root, limit, "en")
        "wikipedia_zh" -> wikipedia(root, limit, "zh")
        "github" -> rows(root.optJSONArray("items"), limit, "full_name", "html_url", "description", "updated_at")
        "gitlab" -> rows(root.optJSONArray("_root"), limit, "path_with_namespace", "web_url", "description", "last_activity_at")
        "stackoverflow" -> rows(root.optJSONArray("items"), limit, "title", "link", "excerpt", "last_activity_date")
        "hacker_news" -> hackerNews(root, limit)
        "lobsters" -> rows(root.optJSONArray("_root"), limit, "title", "url", "description", "created_at")
        "reddit" -> reddit(root, limit)
        "crossref" -> crossref(root, limit)
        "semantic_scholar" -> rows(root.optJSONArray("data"), limit, "title", "url", "abstract", "year")
        "pubmed" -> pubmed(root, limit)
        "crates_io" -> crates(root, limit)
        "npm" -> npm(root, limit)
        "mdn" -> mdn(root, limit)
        else -> emptyList()
    }

    private fun parseJsonValue(source: String, limit: Int): List<AgentWebIntelligenceRawResult> {
        val trimmed = source.trim()
        return if (trimmed.startsWith("[")) {
            val wrapper = JSONObject().put("_root", JSONArray(trimmed))
            parseJson(wrapper, limit)
        } else parseJson(JSONObject(trimmed), limit)
    }

    private fun wikipedia(root: JSONObject, limit: Int, language: String) = buildList {
        val values = root.optJSONObject("query")?.optJSONArray("search") ?: JSONArray()
        for (index in 0 until min(values.length(), limit)) {
            val item = values.optJSONObject(index) ?: continue
            val pageId = item.optLong("pageid").takeIf { it > 0 } ?: continue
            result(
                rank = size + 1,
                title = item.optString("title"),
                url = "https://$language.wikipedia.org/?curid=$pageId",
                excerpt = item.optString("snippet")
            )?.let(::add)
        }
    }

    private fun hackerNews(root: JSONObject, limit: Int) = buildList {
        val values = root.optJSONArray("hits") ?: JSONArray()
        for (index in 0 until min(values.length(), limit)) {
            val item = values.optJSONObject(index) ?: continue
            result(
                size + 1,
                item.optString("title").ifBlank { item.optString("story_title") },
                item.optString("url").ifBlank {
                    item.optString("story_url").ifBlank {
                        "https://news.ycombinator.com/item?id=${item.optString("objectID")}"
                    }
                },
                item.optString("story_text").ifBlank { item.optString("comment_text") },
                item.optString("created_at")
            )?.let(::add)
        }
    }

    private fun reddit(root: JSONObject, limit: Int) = buildList {
        val values = root.optJSONObject("data")?.optJSONArray("children") ?: JSONArray()
        for (index in 0 until min(values.length(), limit)) {
            val item = values.optJSONObject(index)?.optJSONObject("data") ?: continue
            val url = item.optString("url_overridden_by_dest").ifBlank {
                item.optString("permalink").takeIf(String::isNotBlank)?.let { "https://www.reddit.com$it" }.orEmpty()
            }
            result(size + 1, item.optString("title"), url, item.optString("selftext"), item.optString("created_utc"))
                ?.let(::add)
        }
    }

    private fun crossref(root: JSONObject, limit: Int) = buildList {
        val values = root.optJSONObject("message")?.optJSONArray("items") ?: JSONArray()
        for (index in 0 until min(values.length(), limit)) {
            val item = values.optJSONObject(index) ?: continue
            val title = item.optJSONArray("title")?.optString(0).orEmpty()
            result(size + 1, title, item.optString("URL"), item.optString("abstract"), "")
                ?.let(::add)
        }
    }

    private fun pubmed(root: JSONObject, limit: Int) = buildList {
        val values = root.optJSONObject("esearchresult")?.optJSONArray("idlist") ?: JSONArray()
        for (index in 0 until min(values.length(), limit)) {
            val id = values.optString(index)
            result(size + 1, "PubMed record $id", "https://pubmed.ncbi.nlm.nih.gov/$id/", "", "")
                ?.let(::add)
        }
    }

    private fun crates(root: JSONObject, limit: Int) = buildList {
        val values = root.optJSONArray("crates") ?: JSONArray()
        for (index in 0 until min(values.length(), limit)) {
            val item = values.optJSONObject(index) ?: continue
            val name = item.optString("name").ifBlank { item.optString("id") }
            result(
                size + 1,
                name,
                item.optString("repository").ifBlank { "https://crates.io/crates/$name" },
                item.optString("description"),
                item.optString("updated_at")
            )?.let(::add)
        }
    }

    private fun npm(root: JSONObject, limit: Int) = buildList {
        val values = root.optJSONArray("objects") ?: JSONArray()
        for (index in 0 until min(values.length(), limit)) {
            val item = values.optJSONObject(index)?.optJSONObject("package") ?: continue
            val links = item.optJSONObject("links")
            result(
                size + 1,
                item.optString("name"),
                links?.optString("npm").orEmpty().ifBlank { links?.optString("repository").orEmpty() },
                item.optString("description"),
                item.optString("date")
            )?.let(::add)
        }
    }

    private fun mdn(root: JSONObject, limit: Int) = buildList {
        val values = root.optJSONArray("documents") ?: JSONArray()
        for (index in 0 until min(values.length(), limit)) {
            val item = values.optJSONObject(index) ?: continue
            val rawUrl = item.optString("mdn_url").ifBlank { item.optString("url") }
            result(
                size + 1,
                item.optString("title"),
                if (rawUrl.startsWith("/")) "https://developer.mozilla.org$rawUrl" else rawUrl,
                item.optString("summary"),
                ""
            )?.let(::add)
        }
    }

    private fun rows(
        values: JSONArray?,
        limit: Int,
        titleKey: String,
        urlKey: String,
        excerptKey: String,
        dateKey: String
    ) = buildList {
        val array = values ?: JSONArray()
        for (index in 0 until min(array.length(), limit)) {
            val item = array.optJSONObject(index) ?: continue
            result(
                size + 1,
                item.optString(titleKey),
                item.optString(urlKey),
                item.optString(excerptKey),
                item.optString(dateKey)
            )?.let(::add)
        }
    }

    private fun parseAtom(source: String, limit: Int): List<AgentWebIntelligenceRawResult> {
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        parser.setInput(StringReader(source))
        val values = mutableListOf<AgentWebIntelligenceRawResult>()
        var event = parser.eventType
        var currentTag = ""
        var title = ""
        var summary = ""
        var published = ""
        var url = ""
        var inEntry = false
        while (event != XmlPullParser.END_DOCUMENT && values.size < limit) {
            when (event) {
                XmlPullParser.START_TAG -> {
                    currentTag = parser.name.substringAfter(':')
                    if (currentTag == "entry") {
                        inEntry = true
                        title = ""
                        summary = ""
                        published = ""
                        url = ""
                    } else if (inEntry && currentTag == "link" && parser.getAttributeValue(null, "href") != null) {
                        val relation = parser.getAttributeValue(null, "rel").orEmpty()
                        if (relation.isBlank() || relation == "alternate") url = parser.getAttributeValue(null, "href")
                    }
                }
                XmlPullParser.TEXT -> if (inEntry) when (currentTag) {
                    "title" -> title += parser.text
                    "summary" -> summary += parser.text
                    "published" -> published += parser.text
                }
                XmlPullParser.END_TAG -> {
                    val tag = parser.name.substringAfter(':')
                    if (tag == "entry") {
                        result(values.size + 1, title, url, summary, published)?.let(values::add)
                        inEntry = false
                    }
                    currentTag = ""
                }
            }
            event = parser.next()
        }
        return values
    }

    private fun result(
        rank: Int,
        title: Any?,
        url: Any?,
        excerpt: Any? = "",
        publishedAt: Any? = ""
    ): AgentWebIntelligenceRawResult? {
        val cleanTitle = AgentWebIntelligenceText.clean(title, 2_048)
        val cleanUrl = url?.toString()?.trim().orEmpty()
        if (cleanTitle.isBlank() || !cleanUrl.startsWith("http://") && !cleanUrl.startsWith("https://")) return null
        return AgentWebIntelligenceRawResult(
            engineId = spec.id,
            rank = rank,
            title = cleanTitle,
            url = cleanUrl,
            excerpt = AgentWebIntelligenceText.clean(excerpt, 16_384),
            publishedAt = publishedAt?.toString().orEmpty().take(64),
            vertical = spec.vertical
        )
    }

    private fun raw(rank: Int, title: String, url: String) = AgentWebIntelligenceRawResult(
        engineId = spec.id,
        rank = rank,
        title = title,
        url = url,
        vertical = spec.vertical
    )

    private fun unwrap(raw: String, baseUrl: String): String = runCatching {
        val value = AgentWebIntelligenceText.decodeHtml(raw).trim()
        val absolute = when {
            value.startsWith("//") -> "https:$value"
            value.startsWith("/") -> URI(baseUrl).resolve(value).toString()
            else -> value
        }
        val parsed = URI(absolute)
        val query = parsed.rawQuery.orEmpty().split('&').associate { pair ->
            URLDecoder.decode(pair.substringBefore('='), Charsets.UTF_8.name()) to
                URLDecoder.decode(pair.substringAfter('=', ""), Charsets.UTF_8.name())
        }
        listOf("uddg", "url", "u", "target", "r")
            .firstNotNullOfOrNull { key -> query[key]?.takeIf { it.startsWith("http://") || it.startsWith("https://") } }
            ?: absolute
    }.getOrDefault(raw)

    companion object {
        fun parse(
            spec: AgentWebIntelligenceEngineSpec,
            fetched: AgentWebIntelligenceFetched,
            limit: Int
        ): List<AgentWebIntelligenceRawResult> {
            val adapter = AgentWebIntelligenceSearchAdapter(spec) { _, _, _, _, _ -> fetched }
            val source = fetched.body.toString(Charsets.UTF_8)
            return when {
                spec.parser == "html" -> adapter.parseHtml(source, fetched.url, limit)
                spec.parser == "atom" -> adapter.parseAtom(source, limit)
                source.trim().startsWith("[") -> adapter.parseJsonValue(source, limit)
                else -> adapter.parseJson(JSONObject(source), limit)
            }
        }
    }
}

class AgentWebIntelligenceFusion(
    private val ranker: AgentWebIntelligenceRanker = AgentWebIntelligenceRanker(),
    private val rrfK: Int = 60
) {
    private val specs = AgentWebIntelligenceEngineCatalog.entries.associateBy { it.id }

    fun fuse(
        query: String,
        groups: List<List<AgentWebIntelligenceRawResult>>,
        limit: Int
    ): List<AgentWebIntelligenceResult> {
        val merged = linkedMapOf<String, AgentWebIntelligenceResult>()
        groups.flatten().forEach { raw ->
            val canonical = AgentWebIntelligenceText.canonicalUrl(raw.url)
            if (canonical.isBlank()) return@forEach
            val spec = specs[raw.engineId]
            val current = merged.getOrPut(canonical) {
                AgentWebIntelligenceResult(
                    title = raw.title,
                    url = canonical,
                    excerpt = raw.excerpt,
                    publishedAt = raw.publishedAt,
                    vertical = raw.vertical,
                    authority = spec?.authority ?: 0.5
                )
            }
            if (raw.title.length > current.title.length) current.title = raw.title
            if (raw.excerpt.length > current.excerpt.length) current.excerpt = raw.excerpt
            if (current.publishedAt.isBlank() && raw.publishedAt.isNotBlank()) current.publishedAt = raw.publishedAt
            if (current.vertical == AgentWebIntelligenceVertical.GENERAL &&
                raw.vertical != AgentWebIntelligenceVertical.GENERAL) current.vertical = raw.vertical
            current.authority = max(current.authority, spec?.authority ?: 0.5)
            current.engineRanks[raw.engineId] = min(current.engineRanks[raw.engineId] ?: Int.MAX_VALUE, raw.rank)
            current.engineWeights[raw.engineId] = spec?.weight ?: 1.0
        }
        val engineCount = merged.values.flatMap { it.engineRanks.keys }.distinct().size.coerceAtLeast(1)
        val maxRrf = 1.0 / (rrfK + 1)
        merged.values.forEach { item ->
            val reciprocalRank = (
                item.engineRanks.entries.sumOf { (engine, rank) ->
                    (item.engineWeights[engine] ?: 1.0) / (rrfK + rank)
                } / maxRrf
            ).coerceIn(0.0, 1.0)
            val queryTokens = AgentWebIntelligenceText.tokens(query).toSet()
            val titleTokens = AgentWebIntelligenceText.tokens(item.title).toSet()
            val bodyTokens = AgentWebIntelligenceText.tokens(item.excerpt).toSet()
            val titleOverlap = if (queryTokens.isEmpty()) 0.0 else queryTokens.intersect(titleTokens).size.toDouble() / queryTokens.size
            val bodyOverlap = if (queryTokens.isEmpty()) 0.0 else queryTokens.intersect(bodyTokens).size.toDouble() / queryTokens.size
            val lexical = (0.7 * titleOverlap + 0.3 * bodyOverlap).coerceIn(0.0, 1.0)
            val exactness = if (AgentWebIntelligenceText.normalized(item.title)
                    .contains(AgentWebIntelligenceText.normalized(query))) 1.0 else titleOverlap
            val coverage = max(titleOverlap, bodyOverlap)
            val consensus = (item.engineRanks.size.toDouble() / min(5, engineCount)).coerceIn(0.0, 1.0)
            val freshness = freshness(item.publishedAt)
            val urlQuality = urlQuality(item.url)
            val duplicatePenalty = max(0.0, (item.engineRanks.size - 8) / 16.0)
            val localModel = ranker.score(doubleArrayOf(
                reciprocalRank,
                lexical,
                consensus,
                item.authority,
                freshness,
                exactness,
                coverage,
                urlQuality,
                duplicatePenalty
            ))
            val final = (
                0.28 * reciprocalRank +
                    0.21 * lexical +
                    0.14 * consensus +
                    0.10 * item.authority +
                    0.07 * freshness +
                    0.20 * localModel
                ).coerceIn(0.0, 1.0)
            item.score = AgentWebIntelligenceScore(
                final,
                reciprocalRank,
                lexical,
                consensus,
                item.authority,
                freshness,
                localModel
            )
        }
        return merged.values.sortedWith(
            compareByDescending<AgentWebIntelligenceResult> { it.score.final }
                .thenByDescending { it.engineRanks.size }
                .thenByDescending { it.authority }
        ).take(limit)
    }

    private fun freshness(value: String): Double {
        if (value.isBlank()) return 0.35
        val instant = runCatching {
            when {
                value.all(Char::isDigit) -> Instant.ofEpochSecond(
                    value.toLong().let { if (it > 10_000_000_000L) it / 1_000 else it }
                )
                else -> OffsetDateTime.parse(value).toInstant()
            }
        }.getOrNull()
        if (instant != null) {
            val days = ((System.currentTimeMillis() - instant.toEpochMilli()).coerceAtLeast(0L) / 86_400_000.0)
            return exp(-days / 365.0).coerceIn(0.05, 1.0)
        }
        val year = Regex("\\b(19|20)\\d{2}\\b").find(value)?.value?.toIntOrNull()
        return if (year != null) exp(-(java.time.Year.now().value - year).coerceAtLeast(0) / 4.0).coerceAtLeast(0.1) else 0.35
    }

    private fun urlQuality(value: String): Double = runCatching {
        val uri = URI(value)
        var score = 0.5
        if (uri.scheme == "https") score += 0.15
        if (uri.query.isNullOrBlank()) score += 0.1
        score += max(0.0, 0.2 - uri.path.orEmpty().split('/').count(String::isNotBlank) * 0.025)
        if (value.length > 250) score -= 0.2
        score.coerceIn(0.0, 1.0)
    }.getOrDefault(0.0)
}

data class AgentWebIntelligenceSearchResponse(
    val query: String,
    val status: String,
    val results: List<AgentWebIntelligenceResult>,
    val receipts: List<AgentWebIntelligenceReceipt>,
    val engineIds: List<String>,
    val elapsedMillis: Long,
    val profile: String = AgentWebIntelligenceSearchProfile.BALANCED.wireValue,
    val selectionStrategy: String = "adaptive_health_weighted",
    val sourceHealth: List<AgentWebIntelligenceSourceHealth> = emptyList(),
    val circuitsSkipped: List<AgentWebIntelligenceSourceHealth> = emptyList(),
    val timeoutMillis: Long = AgentWebIntelligenceSearchProfile.BALANCED.defaultTimeoutMillis,
    val completedAtMillis: Long = System.currentTimeMillis()
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "protocol" to AGENT_WEB_INTELLIGENCE_PROTOCOL,
        "operation" to "search",
        "status" to status,
        "query" to query,
        "results" to results.mapIndexed { index, result -> result.publicValue(index + 1) },
        "receipts" to receipts.sortedBy { it.sourceId }.map(AgentWebIntelligenceReceipt::publicValue),
        "metadata" to linkedMapOf(
            "engine_catalog_size" to AgentWebIntelligenceEngineCatalog.entries.size,
            "engines_requested" to engineIds,
            "engines_completed" to receipts.count { it.status == "completed" },
            "engine_failures" to receipts.count { it.status !in setOf("completed", "empty") },
            "profile" to profile,
            "engine_fanout" to engineIds.size,
            "timeout_millis" to timeoutMillis,
            "source_selection" to selectionStrategy,
            "source_health" to sourceHealth.map { it.publicValue(completedAtMillis) },
            "circuits_skipped" to circuitsSkipped.map { it.publicValue(completedAtMillis) },
            "fusion" to "weighted_rrf_plus_local_ranker",
            "ranker_model" to AgentWebIntelligenceRanker.MODEL_ID,
            "elapsed_millis" to elapsedMillis
        )
    )
}

class AgentWebIntelligenceSearchCoordinator(
    fetcher: AgentWebIntelligenceFetcher,
    private val fusion: AgentWebIntelligenceFusion = AgentWebIntelligenceFusion(),
    private val maxWorkers: Int = 8,
    private val clock: () -> Long = System::currentTimeMillis,
    private val healthProvider: () -> Map<String, AgentWebIntelligenceSourceHealth> = { emptyMap() },
    private val receiptObserver: (AgentWebIntelligenceReceipt) -> Unit = {}
) {
    private val specs = AgentWebIntelligenceEngineCatalog.entries.associateBy { it.id }
    private val adapters = specs.mapValues { AgentWebIntelligenceSearchAdapter(it.value, fetcher) }

    fun search(
        query: String,
        limit: Int = 10,
        engineFanout: Int = 18,
        requestedEngines: List<String> = emptyList(),
        verticals: Set<AgentWebIntelligenceVertical> = emptySet(),
        timeoutMillis: Long = 15_000L,
        cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE,
        checkpoint: () -> Unit = {},
        profile: String = AgentWebIntelligenceSearchProfile.BALANCED.wireValue
    ): AgentWebIntelligenceSearchResponse {
        require(query.isNotBlank() && query.length <= 4_096)
        require(limit in 1..100)
        require(engineFanout in 1..32)
        require(timeoutMillis in 1_000L..60_000L)
        val selection = selectEnginePlan(query, engineFanout, requestedEngines, verticals)
        val selected = selection.selected
        val started = clock()
        if (selected.isEmpty()) {
            return AgentWebIntelligenceSearchResponse(
                query = query,
                status = "failed",
                results = emptyList(),
                receipts = emptyList(),
                engineIds = emptyList(),
                elapsedMillis = 0L,
                profile = profile,
                selectionStrategy = "adaptive_health_weighted",
                circuitsSkipped = selection.skipped,
                timeoutMillis = timeoutMillis,
                completedAtMillis = started
            )
        }
        val deadline = started + timeoutMillis
        val executor = Executors.newFixedThreadPool(min(maxWorkers.coerceIn(1, 16), selected.size))
        try {
            val completion = ExecutorCompletionService<
                Triple<String, List<AgentWebIntelligenceRawResult>, AgentWebIntelligenceReceipt>
                >(executor)
            val pending = selected.toMutableSet()
            selected.forEach { id ->
                completion.submit(Callable {
                    val attemptStarted = clock()
                    try {
                        checkpoint()
                        if (cancellationToken.isCancellationRequested) throw AgentNativeToolCancelledException()
                        val remaining = (deadline - clock()).coerceAtLeast(1_000L)
                        val results = adapters.getValue(id).search(
                            query,
                            max(limit, 8).coerceAtMost(20),
                            min(8_000L, remaining),
                            cancellationToken,
                            checkpoint
                        )
                        Triple(
                            id,
                            results,
                            AgentWebIntelligenceReceipt(
                                id,
                                if (results.isEmpty()) "empty" else "completed",
                                clock() - attemptStarted,
                                results.size
                            )
                        )
                    } catch (error: Throwable) {
                        val code = when (error) {
                            is AgentWebMediaException -> error.code
                            is AgentNativeToolCancelledException -> "cancelled"
                            else -> "engine_failed"
                        }
                        Triple(
                            id,
                            emptyList(),
                            AgentWebIntelligenceReceipt(
                                id,
                                when {
                                    code == "cancelled" -> "cancelled"
                                    code.contains("timeout") -> "timeout"
                                    code.contains("private") -> "blocked"
                                    else -> "failed"
                                },
                                clock() - attemptStarted,
                                0,
                                code,
                                error.message.orEmpty(),
                                error is AgentWebMediaException && error.retryable
                            )
                        )
                    }
                })
            }
            val groups = mutableListOf<List<AgentWebIntelligenceRawResult>>()
            val receipts = mutableListOf<AgentWebIntelligenceReceipt>()
            while (pending.isNotEmpty()) {
                checkpoint()
                val remaining = deadline - clock()
                if (remaining <= 0L) break
                val completed = completion.poll(remaining, TimeUnit.MILLISECONDS) ?: break
                val (engine, results, receipt) = completed.get()
                pending.remove(engine)
                groups += results
                receipts += receipt
            }
            pending.forEach { engine ->
                receipts += AgentWebIntelligenceReceipt(
                    engine, "timeout", timeoutMillis, 0, "engine_timeout",
                    "Search source exceeded the shared request deadline", true
                )
            }
            receipts.forEach(receiptObserver)
            val results = fusion.fuse(query, groups, limit)
            val status = when {
                results.isEmpty() -> "failed"
                receipts.all { it.status in setOf("completed", "empty") } -> "completed"
                else -> "partial"
            }
            val completedAt = clock()
            val health = healthProvider()
            return AgentWebIntelligenceSearchResponse(
                query = query,
                status = status,
                results = results,
                receipts = receipts,
                engineIds = selected,
                elapsedMillis = completedAt - started,
                profile = profile,
                selectionStrategy = if (selection.explicit) {
                    "explicit_sources"
                } else {
                    "adaptive_health_weighted"
                },
                sourceHealth = selected.map { health[it] ?: AgentWebIntelligenceSourceHealth(it) },
                circuitsSkipped = selection.skipped,
                timeoutMillis = timeoutMillis,
                completedAtMillis = completedAt
            )
        } finally {
            executor.shutdownNow()
        }
    }

    fun selectEngines(
        query: String,
        fanout: Int,
        requested: List<String>,
        verticals: Set<AgentWebIntelligenceVertical>
    ): List<String> = selectEnginePlan(query, fanout, requested, verticals).selected

    private fun selectEnginePlan(
        query: String,
        fanout: Int,
        requested: List<String>,
        verticals: Set<AgentWebIntelligenceVertical>
    ): AgentWebIntelligenceSourceSelection {
        if (requested.isNotEmpty()) {
            val unknown = requested.filterNot(specs::containsKey)
            require(unknown.isEmpty()) { "Unknown web intelligence engines: ${unknown.joinToString()}" }
            return AgentWebIntelligenceSourceSelection(
                selected = requested.distinct().take(fanout),
                explicit = true
            )
        }
        val language = AgentWebIntelligenceText.language(query)
        val desired = verticals.ifEmpty { inferVerticals(query) }
        val nowMillis = clock()
        val health = healthProvider()
        val skipped = mutableListOf<AgentWebIntelligenceSourceHealth>()
        val ranked = AgentWebIntelligenceEngineCatalog.entries
            .filter(AgentWebIntelligenceEngineSpec::enabledByDefault)
            .mapIndexedNotNull { index, spec ->
                val sourceHealth = health[spec.id] ?: AgentWebIntelligenceSourceHealth(spec.id)
                if (sourceHealth.circuitState(nowMillis) == "open") {
                    skipped += sourceHealth
                    return@mapIndexedNotNull null
                }
                val score = spec.weight +
                    if (spec.vertical in desired) 2.5 else 0.0 +
                    if (spec.vertical == AgentWebIntelligenceVertical.GENERAL) 1.0 else 0.0 +
                    if ("*" in spec.languages || language in spec.languages) 0.8 else -1.5 +
                    spec.authority * 0.5 +
                    sourceHealth.routingScore()
                Triple(score, -index, spec.id)
            }
            .sortedWith(compareByDescending<Triple<Double, Int, String>> { it.first }.thenByDescending { it.second })
        val selected = mutableListOf<String>()
        desired.sortedBy(AgentWebIntelligenceVertical::wireValue).forEach { vertical ->
            ranked.firstOrNull { specs.getValue(it.third).vertical == vertical && it.third !in selected }
                ?.third
                ?.let(selected::add)
        }
        ranked.forEach { item ->
            if (selected.size < fanout && item.third !in selected) selected += item.third
        }
        return AgentWebIntelligenceSourceSelection(
            selected = selected.take(fanout),
            skipped = skipped.sortedBy(AgentWebIntelligenceSourceHealth::circuitOpenUntilMillis)
        )
    }

    private fun inferVerticals(query: String): Set<AgentWebIntelligenceVertical> {
        val lower = query.lowercase(Locale.ROOT)
        return buildSet {
            add(AgentWebIntelligenceVertical.GENERAL)
            add(AgentWebIntelligenceVertical.KNOWLEDGE)
            if (Regex(
                    "\\b(today|latest|breaking|news|current)\\b|" +
                        "\u4eca\u5929|\u6700\u65b0|\u65b0\u95fb|\u5b9e\u65f6"
                ).containsMatchIn(lower)
            ) {
                add(AgentWebIntelligenceVertical.NEWS)
            }
            if (Regex(
                    "\\b(code|api|sdk|library|package|bug|github|python|javascript|rust|java)\\b|" +
                        "\u4ee3\u7801|\u7f16\u7a0b|\u63a5\u53e3|\u5f00\u53d1"
                ).containsMatchIn(lower)
            ) {
                add(AgentWebIntelligenceVertical.CODE)
                add(AgentWebIntelligenceVertical.DOCS)
                add(AgentWebIntelligenceVertical.COMMUNITY)
            }
            if (Regex(
                    "\\b(paper|study|research|doi|journal|citation)\\b|" +
                        "\u8bba\u6587|\u7814\u7a76|\u6587\u732e|\u5b66\u672f"
                ).containsMatchIn(lower)
            ) {
                add(AgentWebIntelligenceVertical.ACADEMIC)
            }
        }
    }
}

private fun Double.roundScore(): Double = kotlin.math.round(this.coerceIn(0.0, 1.0) * 1_000_000.0) / 1_000_000.0
