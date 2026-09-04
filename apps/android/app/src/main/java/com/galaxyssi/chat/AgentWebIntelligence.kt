package com.galaxyssi.chat

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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorCompletionService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

const val AGENT_WEB_INTELLIGENCE_PROTOCOL = "galaxyssi.web-intelligence.v1"
private const val WEB_SOURCE_FAILURE_THRESHOLD = 3
private const val WEB_SOURCE_BASE_COOLDOWN_MILLIS = 60_000L
private const val WEB_SOURCE_MAX_COOLDOWN_MILLIS = 30 * 60_000L
private const val WEB_SOURCE_EWMA_ALPHA = 0.25

enum class AgentWebIntelligenceVertical(val wireValue: String) {
    GENERAL("general"),
    REGIONAL("regional"),
    NEWS("news"),
    KNOWLEDGE("knowledge"),
    PUBLISHING("publishing"),
    CODE("code"),
    DOCS("docs"),
    PACKAGES("packages"),
    QA("qa"),
    COMMUNITY("community"),
    SOCIAL("social"),
    ACADEMIC("academic"),
    RESEARCH_INDEX("research_index"),
    MEDICAL("medical"),
    HEALTHCARE("healthcare"),
    BIOLOGY("biology"),
    TECHNOLOGY("technology"),
    AGENTS("agents"),
    HARDWARE("hardware"),
    IMAGE("image"),
    VIDEO("video"),
    TRAVEL("travel"),
    LIFESTYLE("lifestyle"),
    GAMES("games"),
    SHOPPING("shopping"),
    FINANCE("finance"),
    BUSINESS("business"),
    SPORTS("sports"),
    WEATHER("weather"),
    MAPS_LOCAL("maps_local"),
    FOOD("food"),
    EDUCATION("education"),
    JOBS("jobs"),
    GOVERNMENT("government"),
    LEGAL("legal"),
    PATENTS("patents"),
    BOOKS("books"),
    AUDIO("audio"),
    ENTERTAINMENT("entertainment"),
    CYBERSECURITY("cybersecurity"),
    AI_MODELS("ai_models"),
    DATASETS("datasets"),
    AUTOMOTIVE("automotive"),
    REAL_ESTATE("real_estate"),
    EVENTS("events"),
    SMART_HOME("smart_home"),
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
    val enabledByDefault: Boolean = true,
    val requiresKey: String = "",
    val allowedHosts: Set<String> = emptySet(),
    val categoryTags: Set<String> = emptySet()
)

data class AgentWebIntelligenceLearnedSource(
    val sourceId: String,
    val host: String,
    val vertical: AgentWebIntelligenceVertical,
    val categoryTags: Set<String> = emptySet(),
    val status: String = "candidate",
    val observations: Int = 0,
    val queryFingerprints: Set<String> = emptySet(),
    val firstSeenAtMillis: Long = 0L,
    val lastSeenAtMillis: Long = 0L
) {
    fun toEngineSpec(index: Int): AgentWebIntelligenceEngineSpec {
        val scopedQuery = URLEncoder.encode("site:$host ", Charsets.UTF_8.name())
        val endpoint = if (index % 2 == 0) {
            "https://html.duckduckgo.com/html/?q=$scopedQuery{query}"
        } else {
            "https://www.bing.com/search?q=$scopedQuery{query}&count={limit}"
        }
        return AgentWebIntelligenceEngineSpec(
            id = sourceId,
            title = host,
            vertical = vertical,
            endpoint = endpoint,
            parser = "site_index",
            authority = confidence().coerceIn(0.55, 0.85),
            enabledByDefault = status == "verified",
            allowedHosts = setOf(host),
            categoryTags = categoryTags
        )
    }

    fun confidence(): Double {
        val evidence = (observations / 6.0).coerceAtMost(1.0)
        val diversity = (queryFingerprints.size / 4.0).coerceAtMost(1.0)
        return evidence * 0.6 + diversity * 0.4
    }

    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "source_id" to sourceId,
        "host" to host,
        "vertical" to vertical.wireValue,
        "category_tags" to categoryTags.sorted(),
        "status" to status,
        "observations" to observations,
        "distinct_queries" to queryFingerprints.size,
        "confidence" to confidence(),
        "first_seen_at_millis" to firstSeenAtMillis,
        "last_seen_at_millis" to lastSeenAtMillis
    )
}

data class AgentWebIntelligenceRawResult(
    val engineId: String,
    val rank: Int,
    val title: String,
    val url: String,
    val excerpt: String = "",
    val publishedAt: String = "",
    val vertical: AgentWebIntelligenceVertical = AgentWebIntelligenceVertical.GENERAL,
    val imageUrl: String = "",
    val thumbnailUrl: String = "",
    val imageWidth: Int = 0,
    val imageHeight: Int = 0
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
    val explicit: Boolean = false,
    val strategy: String = "broad_unscoped"
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
    var imageUrl: String = "",
    var thumbnailUrl: String = "",
    var imageWidth: Int = 0,
    var imageHeight: Int = 0,
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
        "image_url" to imageUrl.take(4_096),
        "thumbnail_url" to thumbnailUrl.take(4_096),
        "image_width" to imageWidth.coerceAtLeast(0),
        "image_height" to imageHeight.coerceAtLeast(0),
        "engines" to engineRanks.keys.sorted(),
        "rank" to rank,
        "score" to score.publicValue()
    )
}

object AgentWebIntelligenceEngineCatalog {
    private data class IndexedSource(
        val id: String,
        val title: String,
        val vertical: String,
        val host: String,
        val scope: String = host,
        val languages: Set<String> = setOf("*"),
        val authority: Double = 0.7
    )

    private val indexedSources = listOf(
        IndexedSource("reuters_news", "Reuters", "news", "reuters.com", authority = 0.9),
        IndexedSource("ap_news", "AP News", "news", "apnews.com", authority = 0.9),
        IndexedSource("bbc_news", "BBC News", "news", "bbc.com", "bbc.com/news", authority = 0.9),
        IndexedSource("xinhua_news", "Xinhua", "news", "news.cn", languages = setOf("zh"), authority = 0.85),
        IndexedSource("cna_news", "Channel News Asia", "news", "channelnewsasia.com", authority = 0.85),

        IndexedSource("britannica", "Britannica", "knowledge", "britannica.com", authority = 0.9),
        IndexedSource("wikidata", "Wikidata", "knowledge", "wikidata.org", authority = 0.9),
        IndexedSource("stanford_encyclopedia", "Stanford Encyclopedia of Philosophy", "knowledge", "plato.stanford.edu", authority = 0.95),
        IndexedSource("baidu_baike", "Baidu Baike", "knowledge", "baike.baidu.com", languages = setOf("zh"), authority = 0.75),

        IndexedSource("medium", "Medium", "publishing", "medium.com"),
        IndexedSource("substack", "Substack", "publishing", "substack.com"),
        IndexedSource("jianshu", "Jianshu", "publishing", "jianshu.com", languages = setOf("zh")),
        IndexedSource("toutiao", "Toutiao", "publishing", "toutiao.com", languages = setOf("zh")),
        IndexedSource("wordpress", "WordPress.com", "publishing", "wordpress.com"),

        IndexedSource("codeberg", "Codeberg", "code", "codeberg.org", authority = 0.8),
        IndexedSource("gitee", "Gitee", "code", "gitee.com", languages = setOf("zh"), authority = 0.8),
        IndexedSource("sourceforge", "SourceForge", "code", "sourceforge.net", authority = 0.75),

        IndexedSource("microsoft_learn", "Microsoft Learn", "docs", "learn.microsoft.com", authority = 0.95),
        IndexedSource("android_developers", "Android Developers", "docs", "developer.android.com", authority = 0.95),
        IndexedSource("apple_developer", "Apple Developer", "docs", "developer.apple.com", authority = 0.95),
        IndexedSource("python_docs", "Python Documentation", "docs", "docs.python.org", authority = 0.95),
        IndexedSource("rust_docs", "Rust Documentation", "docs", "doc.rust-lang.org", authority = 0.95),

        IndexedSource("maven_central", "Maven Central", "packages", "central.sonatype.com", authority = 0.9),
        IndexedSource("nuget", "NuGet", "packages", "nuget.org", authority = 0.9),
        IndexedSource("go_packages", "Go Packages", "packages", "pkg.go.dev", authority = 0.9),
        IndexedSource("packagist", "Packagist", "packages", "packagist.org", authority = 0.85),
        IndexedSource("rubygems", "RubyGems", "packages", "rubygems.org", authority = 0.85),

        IndexedSource("quora", "Quora", "qa", "quora.com"),
        IndexedSource("stackexchange", "Stack Exchange", "qa", "stackexchange.com", authority = 0.8),
        IndexedSource("superuser", "Super User", "qa", "superuser.com", authority = 0.8),
        IndexedSource("serverfault", "Server Fault", "qa", "serverfault.com", authority = 0.8),
        IndexedSource("askubuntu", "Ask Ubuntu", "qa", "askubuntu.com", authority = 0.8),

        IndexedSource("product_hunt", "Product Hunt", "community", "producthunt.com"),
        IndexedSource("slashdot", "Slashdot", "community", "slashdot.org"),
        IndexedSource("dev_community", "DEV Community", "community", "dev.to"),
        IndexedSource("hashnode", "Hashnode", "community", "hashnode.com"),

        IndexedSource("bluesky", "Bluesky", "social", "bsky.app"),
        IndexedSource("threads", "Threads", "social", "threads.net"),
        IndexedSource("weibo", "Weibo", "social", "weibo.com", languages = setOf("zh")),
        IndexedSource("douban", "Douban", "social", "douban.com", languages = setOf("zh")),

        IndexedSource("core_academic", "CORE", "academic", "core.ac.uk", authority = 0.9),
        IndexedSource("doaj", "Directory of Open Access Journals", "academic", "doaj.org", authority = 0.9),
        IndexedSource("ssrn", "SSRN", "academic", "ssrn.com", authority = 0.85),
        IndexedSource("biorxiv", "bioRxiv", "academic", "biorxiv.org", authority = 0.9),
        IndexedSource("medrxiv", "medRxiv", "academic", "medrxiv.org", authority = 0.85),

        IndexedSource("openalex", "OpenAlex", "research_index", "openalex.org", authority = 0.9),
        IndexedSource("datacite", "DataCite", "research_index", "datacite.org", authority = 0.9),
        IndexedSource("orcid", "ORCID", "research_index", "orcid.org", authority = 0.9),
        IndexedSource("researchgate", "ResearchGate", "research_index", "researchgate.net", authority = 0.75),
        IndexedSource("base_search", "BASE", "research_index", "base-search.net", authority = 0.85),

        IndexedSource("nih", "NIH", "medical", "nih.gov", authority = 0.95),
        IndexedSource("cochrane", "Cochrane", "medical", "cochrane.org", authority = 0.95),
        IndexedSource("clinical_trials", "ClinicalTrials.gov", "medical", "clinicaltrials.gov", authority = 0.95),
        IndexedSource("nejm", "New England Journal of Medicine", "medical", "nejm.org", authority = 0.95),
        IndexedSource("bmj", "BMJ", "medical", "bmj.com", authority = 0.95),
        IndexedSource("jama", "JAMA Network", "medical", "jamanetwork.com", authority = 0.95),

        IndexedSource("who_healthcare", "World Health Organization", "healthcare", "who.int", authority = 0.95),
        IndexedSource("cdc_healthcare", "CDC", "healthcare", "cdc.gov", authority = 0.95),
        IndexedSource("nhs", "NHS", "healthcare", "nhs.uk", authority = 0.95),
        IndexedSource("mayo_clinic", "Mayo Clinic", "healthcare", "mayoclinic.org", authority = 0.9),
        IndexedSource("cleveland_clinic", "Cleveland Clinic", "healthcare", "clevelandclinic.org", authority = 0.9),
        IndexedSource("medlineplus", "MedlinePlus", "healthcare", "medlineplus.gov", authority = 0.95),

        IndexedSource("ncbi", "NCBI", "biology", "ncbi.nlm.nih.gov", authority = 0.95),
        IndexedSource("uniprot", "UniProt", "biology", "uniprot.org", authority = 0.95),
        IndexedSource("ensembl", "Ensembl", "biology", "ensembl.org", authority = 0.95),
        IndexedSource("protein_data_bank", "RCSB Protein Data Bank", "biology", "rcsb.org", authority = 0.95),
        IndexedSource("kegg", "KEGG", "biology", "kegg.jp", authority = 0.9),
        IndexedSource("nature_biology", "Nature Biology", "biology", "nature.com", "nature.com/subjects/biological-sciences", authority = 0.9),

        IndexedSource("ars_technica", "Ars Technica", "technology", "arstechnica.com"),
        IndexedSource("techcrunch", "TechCrunch", "technology", "techcrunch.com"),
        IndexedSource("the_verge", "The Verge", "technology", "theverge.com"),
        IndexedSource("wired", "WIRED", "technology", "wired.com"),
        IndexedSource("zdnet", "ZDNET", "technology", "zdnet.com"),
        IndexedSource("thirty_six_kr", "36Kr", "technology", "36kr.com", languages = setOf("zh")),

        IndexedSource("openai_agents_sdk", "OpenAI Agents SDK", "agents", "openai.github.io", "openai.github.io/openai-agents-python", authority = 0.95),
        IndexedSource("anthropic_agents", "Anthropic Agent Guidance", "agents", "anthropic.com", "anthropic.com/research/building-effective-agents", authority = 0.95),
        IndexedSource("langchain_agents", "LangChain Agents", "agents", "docs.langchain.com", authority = 0.9),
        IndexedSource("autogen_agents", "Microsoft AutoGen", "agents", "microsoft.github.io", "microsoft.github.io/autogen", authority = 0.9),
        IndexedSource("crewai_agents", "CrewAI", "agents", "docs.crewai.com", authority = 0.85),
        IndexedSource("google_adk", "Google Agent Development Kit", "agents", "google.github.io", "google.github.io/adk-docs", authority = 0.9),

        IndexedSource("intel_ark", "Intel ARK", "hardware", "intel.com", "intel.com/content/www/us/en/ark", authority = 0.95),
        IndexedSource("amd_products", "AMD Products", "hardware", "amd.com", "amd.com/en/products", authority = 0.95),
        IndexedSource("nvidia_products", "NVIDIA Products", "hardware", "nvidia.com", "nvidia.com/en-us/products", authority = 0.95),
        IndexedSource("qualcomm_products", "Qualcomm Products", "hardware", "qualcomm.com", "qualcomm.com/products", authority = 0.95),
        IndexedSource("arm_developer", "Arm Developer", "hardware", "developer.arm.com", authority = 0.95),
        IndexedSource("toms_hardware", "Tom's Hardware", "hardware", "tomshardware.com", authority = 0.8),

        IndexedSource("wikimedia_commons", "Wikimedia Commons", "image", "commons.wikimedia.org", authority = 0.85),
        IndexedSource("unsplash", "Unsplash", "image", "unsplash.com"),
        IndexedSource("pexels", "Pexels", "image", "pexels.com"),
        IndexedSource("pixabay", "Pixabay", "image", "pixabay.com"),
        IndexedSource("openverse", "Openverse", "image", "openverse.org", authority = 0.8),

        IndexedSource("youtube", "YouTube", "video", "youtube.com"),
        IndexedSource("vimeo", "Vimeo", "video", "vimeo.com"),
        IndexedSource("bilibili", "Bilibili", "video", "bilibili.com", languages = setOf("zh")),
        IndexedSource("dailymotion", "Dailymotion", "video", "dailymotion.com"),
        IndexedSource("archive_video", "Internet Archive Video", "video", "archive.org", "archive.org/details/movies", authority = 0.8),
        IndexedSource("ted_video", "TED", "video", "ted.com", "ted.com/talks", authority = 0.85),

        IndexedSource("tripadvisor", "Tripadvisor", "travel", "tripadvisor.com"),
        IndexedSource("booking", "Booking.com", "travel", "booking.com"),
        IndexedSource("skyscanner", "Skyscanner", "travel", "skyscanner.com"),
        IndexedSource("trip_com", "Trip.com", "travel", "trip.com"),
        IndexedSource("lonely_planet", "Lonely Planet", "travel", "lonelyplanet.com"),
        IndexedSource("klook", "Klook", "travel", "klook.com"),

        IndexedSource("wikihow", "wikiHow", "lifestyle", "wikihow.com"),
        IndexedSource("lifehacker", "Lifehacker", "lifestyle", "lifehacker.com"),
        IndexedSource("the_spruce", "The Spruce", "lifestyle", "thespruce.com"),
        IndexedSource("good_housekeeping", "Good Housekeeping", "lifestyle", "goodhousekeeping.com"),
        IndexedSource("martha_stewart", "Martha Stewart", "lifestyle", "marthastewart.com"),
        IndexedSource("better_homes", "Better Homes & Gardens", "lifestyle", "bhg.com"),

        IndexedSource("steam", "Steam", "games", "store.steampowered.com"),
        IndexedSource("ign", "IGN", "games", "ign.com"),
        IndexedSource("gamespot", "GameSpot", "games", "gamespot.com"),
        IndexedSource("metacritic_games", "Metacritic Games", "games", "metacritic.com", "metacritic.com/game"),
        IndexedSource("pcgamingwiki", "PCGamingWiki", "games", "pcgamingwiki.com"),
        IndexedSource("taptap", "TapTap", "games", "taptap.cn", languages = setOf("zh")),

        IndexedSource("amazon", "Amazon", "shopping", "amazon.com"),
        IndexedSource("jd", "JD.com", "shopping", "jd.com", languages = setOf("zh")),
        IndexedSource("taobao", "Taobao", "shopping", "taobao.com", languages = setOf("zh")),
        IndexedSource("tmall", "Tmall", "shopping", "tmall.com", languages = setOf("zh")),
        IndexedSource("ebay", "eBay", "shopping", "ebay.com"),
        IndexedSource("aliexpress", "AliExpress", "shopping", "aliexpress.com"),

        IndexedSource("yahoo_finance", "Yahoo Finance", "finance", "finance.yahoo.com", authority = 0.85),
        IndexedSource("investing", "Investing.com", "finance", "investing.com"),
        IndexedSource("marketwatch", "MarketWatch", "finance", "marketwatch.com", authority = 0.8),
        IndexedSource("tradingview", "TradingView", "finance", "tradingview.com"),
        IndexedSource("eastmoney", "Eastmoney", "finance", "eastmoney.com", languages = setOf("zh")),
        IndexedSource("sina_finance", "Sina Finance", "finance", "finance.sina.com.cn", languages = setOf("zh")),

        IndexedSource("bloomberg", "Bloomberg", "business", "bloomberg.com", authority = 0.85),
        IndexedSource("financial_times", "Financial Times", "business", "ft.com", authority = 0.85),
        IndexedSource("forbes", "Forbes", "business", "forbes.com"),
        IndexedSource("fortune", "Fortune", "business", "fortune.com"),
        IndexedSource("cnbc", "CNBC", "business", "cnbc.com"),
        IndexedSource("caixin", "Caixin", "business", "caixin.com", languages = setOf("zh"), authority = 0.8),

        IndexedSource("espn", "ESPN", "sports", "espn.com"),
        IndexedSource("cbs_sports", "CBS Sports", "sports", "cbssports.com"),
        IndexedSource("sky_sports", "Sky Sports", "sports", "skysports.com"),
        IndexedSource("the_athletic", "The Athletic", "sports", "nytimes.com", "nytimes.com/athletic"),
        IndexedSource("hupu", "Hupu", "sports", "hupu.com", languages = setOf("zh")),
        IndexedSource("sina_sports", "Sina Sports", "sports", "sports.sina.com.cn", languages = setOf("zh")),

        IndexedSource("weather_com", "The Weather Channel", "weather", "weather.com", authority = 0.8),
        IndexedSource("accuweather", "AccuWeather", "weather", "accuweather.com", authority = 0.8),
        IndexedSource("meteoblue", "Meteoblue", "weather", "meteoblue.com", authority = 0.8),
        IndexedSource("windy", "Windy", "weather", "windy.com"),
        IndexedSource("noaa_weather", "NOAA Weather", "weather", "weather.gov", authority = 0.95),
        IndexedSource("china_weather", "China Weather", "weather", "weather.com.cn", languages = setOf("zh"), authority = 0.85),

        IndexedSource("openstreetmap", "OpenStreetMap", "maps_local", "openstreetmap.org", authority = 0.85),
        IndexedSource("google_maps", "Google Maps", "maps_local", "maps.google.com"),
        IndexedSource("bing_maps", "Bing Maps", "maps_local", "bing.com", "bing.com/maps"),
        IndexedSource("amap", "Amap", "maps_local", "amap.com", languages = setOf("zh")),
        IndexedSource("baidu_maps", "Baidu Maps", "maps_local", "map.baidu.com", languages = setOf("zh")),
        IndexedSource("mapquest", "MapQuest", "maps_local", "mapquest.com"),

        IndexedSource("allrecipes", "Allrecipes", "food", "allrecipes.com"),
        IndexedSource("serious_eats", "Serious Eats", "food", "seriouseats.com"),
        IndexedSource("epicurious", "Epicurious", "food", "epicurious.com"),
        IndexedSource("food_network", "Food Network", "food", "foodnetwork.com"),
        IndexedSource("dianping", "Dianping", "food", "dianping.com", languages = setOf("zh")),
        IndexedSource("xiachufang", "Xiachufang", "food", "xiachufang.com", languages = setOf("zh")),

        IndexedSource("khan_academy", "Khan Academy", "education", "khanacademy.org", authority = 0.85),
        IndexedSource("coursera", "Coursera", "education", "coursera.org"),
        IndexedSource("edx", "edX", "education", "edx.org"),
        IndexedSource("mit_ocw", "MIT OpenCourseWare", "education", "ocw.mit.edu", authority = 0.9),
        IndexedSource("openstax", "OpenStax", "education", "openstax.org", authority = 0.9),
        IndexedSource("xuetangx", "XuetangX", "education", "xuetangx.com", languages = setOf("zh")),

        IndexedSource("linkedin_jobs", "LinkedIn Jobs", "jobs", "linkedin.com", "linkedin.com/jobs"),
        IndexedSource("indeed", "Indeed", "jobs", "indeed.com"),
        IndexedSource("glassdoor", "Glassdoor", "jobs", "glassdoor.com"),
        IndexedSource("ziprecruiter", "ZipRecruiter", "jobs", "ziprecruiter.com"),
        IndexedSource("boss_zhipin", "BOSS Zhipin", "jobs", "zhipin.com", languages = setOf("zh")),
        IndexedSource("lagou", "Lagou", "jobs", "lagou.com", languages = setOf("zh")),

        IndexedSource("china_government", "China Government", "government", "gov.cn", languages = setOf("zh"), authority = 0.95),
        IndexedSource("usa_government", "USA.gov", "government", "usa.gov", authority = 0.95),
        IndexedSource("uk_government", "GOV.UK", "government", "gov.uk", authority = 0.95),
        IndexedSource("europa", "European Union", "government", "europa.eu", authority = 0.95),
        IndexedSource("united_nations", "United Nations", "government", "un.org", authority = 0.95),
        IndexedSource("oecd", "OECD", "government", "oecd.org", authority = 0.9),

        IndexedSource("cornell_law", "Cornell Legal Information Institute", "legal", "law.cornell.edu", authority = 0.95),
        IndexedSource("courtlistener", "CourtListener", "legal", "courtlistener.com", authority = 0.9),
        IndexedSource("justia", "Justia", "legal", "justia.com", authority = 0.8),
        IndexedSource("eur_lex", "EUR-Lex", "legal", "eur-lex.europa.eu", authority = 0.95),
        IndexedSource("china_laws", "China National Laws Database", "legal", "flk.npc.gov.cn", languages = setOf("zh"), authority = 0.95),
        IndexedSource("china_judgments", "China Judgments Online", "legal", "wenshu.court.gov.cn", languages = setOf("zh"), authority = 0.9),

        IndexedSource("google_patents", "Google Patents", "patents", "patents.google.com", authority = 0.9),
        IndexedSource("wipo_patents", "WIPO Patentscope", "patents", "patentscope.wipo.int", authority = 0.95),
        IndexedSource("uspto_patents", "USPTO Patent Search", "patents", "ppubs.uspto.gov", authority = 0.95),
        IndexedSource("espacenet", "Espacenet", "patents", "worldwide.espacenet.com", authority = 0.95),
        IndexedSource("lens_patents", "The Lens", "patents", "lens.org", authority = 0.9),
        IndexedSource("cnipa_patents", "CNIPA", "patents", "cnipa.gov.cn", languages = setOf("zh"), authority = 0.95),

        IndexedSource("google_books", "Google Books", "books", "books.google.com"),
        IndexedSource("open_library", "Open Library", "books", "openlibrary.org", authority = 0.85),
        IndexedSource("project_gutenberg", "Project Gutenberg", "books", "gutenberg.org", authority = 0.85),
        IndexedSource("worldcat", "WorldCat", "books", "worldcat.org", authority = 0.9),
        IndexedSource("archive_books", "Internet Archive Books", "books", "archive.org", "archive.org/details/texts", authority = 0.85),
        IndexedSource("douban_books", "Douban Books", "books", "book.douban.com", languages = setOf("zh")),

        IndexedSource("spotify", "Spotify", "audio", "open.spotify.com"),
        IndexedSource("apple_music", "Apple Music", "audio", "music.apple.com"),
        IndexedSource("soundcloud", "SoundCloud", "audio", "soundcloud.com"),
        IndexedSource("bandcamp", "Bandcamp", "audio", "bandcamp.com"),
        IndexedSource("podcast_index", "Podcast Index", "audio", "podcastindex.org"),
        IndexedSource("netease_music", "NetEase Cloud Music", "audio", "music.163.com", languages = setOf("zh")),

        IndexedSource("imdb", "IMDb", "entertainment", "imdb.com"),
        IndexedSource("tmdb", "The Movie Database", "entertainment", "themoviedb.org"),
        IndexedSource("rotten_tomatoes", "Rotten Tomatoes", "entertainment", "rottentomatoes.com"),
        IndexedSource("letterboxd", "Letterboxd", "entertainment", "letterboxd.com"),
        IndexedSource("douban_movies", "Douban Movies", "entertainment", "movie.douban.com", languages = setOf("zh")),
        IndexedSource("mtime", "Mtime", "entertainment", "mtime.com", languages = setOf("zh")),

        IndexedSource("nvd", "NVD", "cybersecurity", "nvd.nist.gov", authority = 0.95),
        IndexedSource("cve", "CVE", "cybersecurity", "cve.org", authority = 0.95),
        IndexedSource("mitre_attack", "MITRE ATT&CK", "cybersecurity", "attack.mitre.org", authority = 0.95),
        IndexedSource("cisa", "CISA", "cybersecurity", "cisa.gov", authority = 0.95),
        IndexedSource("exploit_db", "Exploit Database", "cybersecurity", "exploit-db.com", authority = 0.8),
        IndexedSource("snyk_vulnerability", "Snyk Vulnerability Database", "cybersecurity", "security.snyk.io", authority = 0.8),

        IndexedSource("huggingface_models", "Hugging Face Models", "ai_models", "huggingface.co", "huggingface.co/models"),
        IndexedSource("modelscope_models", "ModelScope Models", "ai_models", "modelscope.cn", "modelscope.cn/models", languages = setOf("zh")),
        IndexedSource("ollama_library", "Ollama Library", "ai_models", "ollama.com", "ollama.com/library"),
        IndexedSource("openai_models", "OpenAI Models", "ai_models", "platform.openai.com", "platform.openai.com/docs/models", authority = 0.9),
        IndexedSource("anthropic_models", "Anthropic Models", "ai_models", "docs.anthropic.com", authority = 0.9),
        IndexedSource("google_ai_models", "Google AI Models", "ai_models", "ai.google.dev", authority = 0.9),

        IndexedSource("kaggle_datasets", "Kaggle Datasets", "datasets", "kaggle.com", "kaggle.com/datasets"),
        IndexedSource("huggingface_datasets", "Hugging Face Datasets", "datasets", "huggingface.co", "huggingface.co/datasets"),
        IndexedSource("google_dataset_search", "Google Dataset Search", "datasets", "datasetsearch.research.google.com"),
        IndexedSource("data_gov", "Data.gov", "datasets", "data.gov", authority = 0.9),
        IndexedSource("zenodo", "Zenodo", "datasets", "zenodo.org", authority = 0.9),
        IndexedSource("uci_datasets", "UCI Machine Learning Repository", "datasets", "archive.ics.uci.edu", authority = 0.9),

        IndexedSource("edmunds", "Edmunds", "automotive", "edmunds.com"),
        IndexedSource("kbb", "Kelley Blue Book", "automotive", "kbb.com"),
        IndexedSource("car_and_driver", "Car and Driver", "automotive", "caranddriver.com"),
        IndexedSource("motortrend", "MotorTrend", "automotive", "motortrend.com"),
        IndexedSource("autohome", "Autohome", "automotive", "autohome.com.cn", languages = setOf("zh")),
        IndexedSource("dongchedi", "Dongchedi", "automotive", "dongchedi.com", languages = setOf("zh")),

        IndexedSource("zillow", "Zillow", "real_estate", "zillow.com"),
        IndexedSource("realtor", "Realtor.com", "real_estate", "realtor.com"),
        IndexedSource("redfin", "Redfin", "real_estate", "redfin.com"),
        IndexedSource("rightmove", "Rightmove", "real_estate", "rightmove.co.uk"),
        IndexedSource("fang", "Fang.com", "real_estate", "fang.com", languages = setOf("zh")),
        IndexedSource("lianjia", "Lianjia", "real_estate", "lianjia.com", languages = setOf("zh")),

        IndexedSource("eventbrite", "Eventbrite", "events", "eventbrite.com"),
        IndexedSource("meetup", "Meetup", "events", "meetup.com"),
        IndexedSource("ten_times", "10times", "events", "10times.com"),
        IndexedSource("ticketmaster", "Ticketmaster", "events", "ticketmaster.com"),
        IndexedSource("damai", "Damai", "events", "damai.cn", languages = setOf("zh")),
        IndexedSource("live_nation", "Live Nation", "events", "livenation.com"),

        IndexedSource("home_assistant", "Home Assistant", "smart_home", "home-assistant.io", authority = 0.9),
        IndexedSource("matter", "Matter", "smart_home", "csa-iot.org", authority = 0.9),
        IndexedSource("smartthings", "SmartThings", "smart_home", "smartthings.com"),
        IndexedSource("apple_home", "Apple Home", "smart_home", "support.apple.com", "support.apple.com/home"),
        IndexedSource("google_nest", "Google Nest", "smart_home", "support.google.com", "support.google.com/googlenest"),
        IndexedSource("openhab", "openHAB", "smart_home", "openhab.org", authority = 0.85)
    )

    val entries: List<AgentWebIntelligenceEngineSpec> = listOf(
        spec("bing", "Bing", "general", "https://www.bing.com/search?q={query}&count={limit}", weight = 1.05),
        spec("duckduckgo", "DuckDuckGo", "general", "https://html.duckduckgo.com/html/?q={query}", weight = 1.05),
        spec("baidu", "Baidu", "regional", "https://www.baidu.com/s?wd={query}&rn={limit}", languages = setOf("zh"), weight = 1.05),
        spec("brave", "Brave Search", "general", "https://search.brave.com/search?q={query}&source=web"),
        spec("mojeek", "Mojeek", "general", "https://www.mojeek.com/search?q={query}"),
        spec("qwant", "Qwant", "regional", "https://www.qwant.com/?q={query}&t=web"),
        spec("yahoo", "Yahoo", "general", "https://search.yahoo.com/search?p={query}"),
        spec("yandex", "Yandex", "regional", "https://yandex.com/search/?text={query}"),
        spec("ecosia", "Ecosia", "general", "https://www.ecosia.org/search?q={query}"),
        spec("startpage", "Startpage", "general", "https://www.startpage.com/sp/search?query={query}"),
        spec("sogou", "Sogou", "regional", "https://www.sogou.com/web?query={query}", languages = setOf("zh")),
        spec("naver", "Naver", "regional", "https://search.naver.com/search.naver?query={query}", languages = setOf("ko")),
        spec("google", "Google", "general", "https://www.google.com/search?q={query}&num={limit}", enabled = false),
        spec("bing_news", "Bing News", "news", "https://www.bing.com/news/search?q={query}&count={limit}", weight = 1.1),
        spec("brave_news", "Brave News", "news", "https://search.brave.com/news?q={query}"),
        spec(
            "brave_image",
            "Brave Image",
            "image",
            "https://api.search.brave.com/res/v1/images/search?q={query}&count={limit}&safesearch=moderate",
            parser = "brave_image",
            authority = 0.8,
            requiresKey = "brave_api_key"
        ),
        spec(
            "duckduckgo_image",
            "DuckDuckGo Image",
            "image",
            "https://duckduckgo.com/?q={query}&iax=images&ia=images",
            parser = "duckduckgo_image",
            authority = 0.75
        ),
        spec(
            "marginalia",
            "Marginalia",
            "general",
            "https://api2.marginalia-search.com/search?query={query}&count={limit}&dc=3",
            parser = "marginalia",
            authority = 0.7
        ),
        spec("wikipedia", "Wikipedia", "knowledge", "https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit={limit}&srsearch={query}", parser = "wikipedia", authority = 0.9),
        spec("wikipedia_zh", "Wikipedia Chinese", "knowledge", "https://zh.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit={limit}&srsearch={query}", parser = "wikipedia_zh", languages = setOf("zh"), authority = 0.9),
        spec("github", "GitHub", "code", "https://api.github.com/search/repositories?q={query}&per_page={limit}", parser = "github", authority = 0.85),
        spec("github_code", "GitHub Code Search", "code", "https://api.github.com/search/code?q={query}&per_page={limit}", parser = "github_code", authority = 0.9),
        spec("gitlab", "GitLab", "code", "https://gitlab.com/api/v4/projects?search={query}&per_page={limit}", parser = "gitlab", authority = 0.8),
        spec("stackoverflow", "Stack Overflow", "qa", "https://api.stackexchange.com/2.3/search/advanced?site=stackoverflow&pagesize={limit}&q={query}", parser = "stackoverflow", authority = 0.85),
        spec("hacker_news", "Hacker News", "community", "https://hn.algolia.com/api/v1/search?hitsPerPage={limit}&query={query}", parser = "hacker_news", authority = 0.7),
        spec("lobsters", "Lobsters", "community", "https://lobste.rs/search.json?q={query}", parser = "lobsters", authority = 0.7),
        spec("x_public", "X Public Posts", "social", "https://html.duckduckgo.com/html/?q=site%3Ax.com%2Fstatus+{query}", parser = "x_public", authority = 0.65),
        spec("wechat_public", "WeChat Public Articles", "publishing", "https://weixin.sogou.com/weixin?type=2&query={query}", parser = "wechat_public", languages = setOf("zh"), authority = 0.75),
        spec("zhihu_public", "Zhihu Public Content", "qa", "https://html.duckduckgo.com/html/?q=site%3Azhihu.com+{query}", parser = "zhihu_public", languages = setOf("zh"), authority = 0.7),
        spec("xiaohongshu_public", "Xiaohongshu Public Notes", "social", "https://html.duckduckgo.com/html/?q=site%3Axiaohongshu.com+{query}", parser = "xiaohongshu_public", languages = setOf("zh"), authority = 0.65),
        spec("reddit", "Reddit", "community", "https://www.reddit.com/search.json?q={query}&limit={limit}&raw_json=1", parser = "reddit", authority = 0.65),
        spec("crossref", "Crossref", "research_index", "https://api.crossref.org/works?rows={limit}&query={query}", parser = "crossref", authority = 0.9),
        spec("semantic_scholar", "Semantic Scholar", "academic", "https://api.semanticscholar.org/graph/v1/paper/search?limit={limit}&fields=title,url,abstract,year,authors&query={query}", parser = "semantic_scholar", authority = 0.9),
        spec("arxiv", "arXiv", "academic", "https://export.arxiv.org/api/query?max_results={limit}&search_query=all:{query}", parser = "atom", authority = 0.9),
        spec("pubmed", "PubMed", "medical", "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&retmax={limit}&term={query}", parser = "pubmed", authority = 0.95),
        spec("crates_io", "crates.io", "packages", "https://crates.io/api/v1/crates?q={query}&per_page={limit}", parser = "crates_io", authority = 0.8),
        spec("npm", "npm", "packages", "https://registry.npmjs.org/-/v1/search?size={limit}&text={query}", parser = "npm", authority = 0.8),
        spec("mdn", "MDN", "docs", "https://developer.mozilla.org/api/v1/search?q={query}&page_size={limit}", parser = "mdn", authority = 0.95),
        spec("devdocs", "DevDocs", "docs", "local://devdocs", parser = "devdocs", authority = 0.9),
        spec("pypi", "PyPI", "packages", "https://pypi.org/search/?q={query}", authority = 0.8)
    ) + indexedSources.mapIndexed(::indexedSpec)

    private fun spec(
        id: String,
        title: String,
        vertical: String,
        endpoint: String,
        parser: String = "html",
        languages: Set<String> = setOf("*"),
        weight: Double = 1.0,
        authority: Double = 0.5,
        enabled: Boolean = true,
        requiresKey: String = "",
        allowedHosts: Set<String> = emptySet(),
        categoryTags: Set<String> = emptySet()
    ) = AgentWebIntelligenceEngineSpec(
        id = id,
        title = title,
        vertical = AgentWebIntelligenceVertical.entries.first { it.wireValue == vertical },
        endpoint = endpoint,
        parser = parser,
        languages = languages,
        weight = weight,
        authority = authority,
        enabledByDefault = enabled,
        requiresKey = requiresKey,
        allowedHosts = allowedHosts,
        categoryTags = categoryTags
    )

    private fun indexedSpec(
        index: Int,
        source: IndexedSource
    ): AgentWebIntelligenceEngineSpec {
        val scopedQuery = URLEncoder.encode("site:${source.scope} ", Charsets.UTF_8.name())
        val endpoint = if (index % 2 == 0) {
            "https://html.duckduckgo.com/html/?q=$scopedQuery{query}"
        } else {
            "https://www.bing.com/search?q=$scopedQuery{query}&count={limit}"
        }
        return spec(
            id = source.id,
            title = source.title,
            vertical = source.vertical,
            endpoint = endpoint,
            parser = "site_index",
            languages = source.languages,
            authority = source.authority,
            allowedHosts = setOf(source.host),
            categoryTags = setOf(source.vertical)
        )
    }
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
        const val MODEL_ID = "galaxyssi-web-ranker-v1"
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

    val modelId: String = "galaxyssi-feature-hash-$dimensions-v1"

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

private object AgentWebIntelligenceQueryRouting {
    private val documentationHint = Regex(
        "\\b(?:documentation|docs|reference|manual|official\\s+(?:docs?|documentation)|developer\\s+guide)\\b|" +
            "官方文档|开发文档|参考文档|开发手册|技术手册",
        RegexOption.IGNORE_CASE
    )
    private val genericSourceTokens = setOf(
        "app", "application", "developer", "developers", "documentation", "docs", "official",
        "reference", "manual", "guide", "process", "source", "sources"
    )

    fun inferredVerticals(query: String): Set<AgentWebIntelligenceVertical> = buildSet {
        if (documentationHint.containsMatchIn(query)) add(AgentWebIntelligenceVertical.DOCS)
    }

    fun sourceAffinity(query: String, spec: AgentWebIntelligenceEngineSpec): Double {
        val queryTokens = AgentWebIntelligenceText.tokens(query)
            .asSequence()
            .filter { it.length >= 3 && it !in genericSourceTokens }
            .toSet()
        if (queryTokens.isEmpty()) return 0.0
        val sourceTokens = AgentWebIntelligenceText.tokens(buildString {
            append(spec.id.replace('_', ' ')).append(' ')
            append(spec.title).append(' ')
            append(spec.allowedHosts.joinToString(" "))
        }).toSet()
        return when ((queryTokens intersect sourceTokens).size) {
            0 -> 0.0
            1 -> 3.5
            else -> 5.0
        }
    }
}

class AgentWebIntelligenceSearchAdapter(
    private val spec: AgentWebIntelligenceEngineSpec,
    private val fetcher: AgentWebIntelligenceFetcher,
    private val credentialProvider: AgentWebIntelligenceCredentialProvider =
        AgentWebIntelligenceCredentialProvider.NONE
) {
    fun search(
        query: String,
        limit: Int,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): List<AgentWebIntelligenceRawResult> {
        if (spec.parser == "devdocs") return devDocs(query, limit)
        if (spec.requiresKey.isNotBlank() && credentialProvider.credential(spec.requiresKey).isBlank()) {
            throw AgentWebMediaException(
                "credential_unavailable",
                "${spec.title} requires a configured credential"
            )
        }
        val encoded = URLEncoder.encode(query, Charsets.UTF_8.name())
        val url = spec.endpoint.replace("{query}", encoded).replace("{limit}", limit.toString())
        if (spec.parser == "duckduckgo_image") {
            return duckDuckGoImages(query, encoded, url, limit, timeoutMillis, cancellationToken, checkpoint)
        }
        val fetched = fetch(
            url,
            timeoutMillis,
            requestHeaders(),
            cancellationToken,
            checkpoint
        )
        val text = fetched.body.toString(Charsets.UTF_8)
        return when (spec.parser) {
            "html" -> parseHtml(text, fetched.url, limit)
            "site_index" -> parseSiteIndex(text, fetched.url, limit)
            "x_public" -> parseXPublic(text, fetched.url, limit)
            "wechat_public" -> parseWeChatPublic(text, fetched.url, limit)
            "zhihu_public", "xiaohongshu_public" -> parseIndexedSocial(text, fetched.url, limit)
            "atom" -> parseAtom(text, limit)
            else -> parseJsonValue(text, limit)
        }
    }

    private fun parseXPublic(
        source: String,
        baseUrl: String,
        limit: Int
    ): List<AgentWebIntelligenceRawResult> = parseHtml(source, baseUrl, limit * 4)
        .filter { result ->
            runCatching {
                val uri = URI(result.url)
                uri.host.orEmpty().removePrefix("www.").lowercase(Locale.ROOT) in
                    setOf("x.com", "twitter.com") &&
                    "/status/" in uri.path.orEmpty()
            }.getOrDefault(false)
        }
        .take(limit)

    private fun parseSiteIndex(
        source: String,
        baseUrl: String,
        limit: Int
    ): List<AgentWebIntelligenceRawResult> = parseHtml(source, baseUrl, limit * 4)
        .filter { result ->
            runCatching {
                val host = URI(result.url).host.orEmpty()
                    .removePrefix("www.")
                    .lowercase(Locale.ROOT)
                spec.allowedHosts.any { allowed ->
                    val normalized = allowed.removePrefix("www.").lowercase(Locale.ROOT)
                    host == normalized || host.endsWith(".$normalized")
                }
            }.getOrDefault(false)
        }
        .take(limit)

    private fun parseWeChatPublic(
        source: String,
        baseUrl: String,
        limit: Int
    ): List<AgentWebIntelligenceRawResult> {
        val anchorPattern = Regex(
            "<a\\b[^>]*?href\\s*=\\s*([\"'])(.*?)\\1[^>]*>([\\s\\S]*?)</a>",
            setOf(RegexOption.IGNORE_CASE)
        )
        val seen = linkedSetOf<String>()
        return buildList {
            anchorPattern.findAll(source).forEach { match ->
                val title = AgentWebIntelligenceText.clean(match.groupValues[3], 2_048)
                val url = unwrap(match.groupValues[2], baseUrl)
                val accepted = runCatching {
                    val uri = URI(url)
                    val host = uri.host.orEmpty().removePrefix("www.").lowercase(Locale.ROOT)
                    host == "mp.weixin.qq.com" ||
                        (host == "weixin.sogou.com" && uri.path.orEmpty().startsWith("/link"))
                }.getOrDefault(false)
                val canonical = AgentWebIntelligenceText.canonicalUrl(url)
                if (accepted && title.isNotBlank() && seen.add(canonical)) {
                    add(raw(size + 1, title, canonical))
                }
                if (size >= limit) return@buildList
            }
        }
    }

    private fun parseIndexedSocial(
        source: String,
        baseUrl: String,
        limit: Int
    ): List<AgentWebIntelligenceRawResult> = parseHtml(source, baseUrl, limit * 4)
        .filter { result ->
            runCatching {
                val uri = URI(result.url)
                val host = uri.host.orEmpty().removePrefix("www.").lowercase(Locale.ROOT)
                val path = uri.path.orEmpty()
                when (spec.parser) {
                    "zhihu_public" ->
                        host == "zhihu.com" || host == "zhuanlan.zhihu.com"
                    "xiaohongshu_public" ->
                        host == "xiaohongshu.com" &&
                            (path.startsWith("/explore/") || path.startsWith("/discovery/item/"))
                    else -> false
                }
            }.getOrDefault(false)
        }
        .take(limit)

    private fun fetch(
        url: String,
        timeoutMillis: Long,
        headers: Map<String, String>,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): AgentWebIntelligenceFetched {
        val requestFetcher = fetcher as? AgentWebIntelligenceRequestFetcher
        return if (requestFetcher != null) {
            requestFetcher.fetch(url, AGENT_WEB_MAX_FETCH_BYTES, timeoutMillis, headers, cancellationToken, checkpoint)
        } else {
            fetcher.fetch(url, AGENT_WEB_MAX_FETCH_BYTES, timeoutMillis, cancellationToken, checkpoint)
        }
    }

    private fun requestHeaders(): Map<String, String> = buildMap {
        when (spec.parser) {
            "brave_image" -> {
                put("Accept", "application/json")
                put("X-Subscription-Token", credentialProvider.credential("brave_api_key"))
            }
            "marginalia" -> {
                put("Accept", "application/json")
                put("API-Key", "public")
            }
            "github", "github_code" -> {
                put("Accept", "application/vnd.github+json")
                put("X-GitHub-Api-Version", "2022-11-28")
                credentialProvider.credential("github_token").takeIf(String::isNotBlank)
                    ?.let { put("Authorization", "Bearer $it") }
            }
        }
    }

    private fun duckDuckGoImages(
        query: String,
        encoded: String,
        landingUrl: String,
        limit: Int,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        checkpoint: () -> Unit
    ): List<AgentWebIntelligenceRawResult> {
        val commonHeaders = mapOf(
            "Accept" to "text/html,application/xhtml+xml",
            "User-Agent" to SEARCH_USER_AGENT
        )
        val landing = fetch(landingUrl, timeoutMillis, commonHeaders, cancellationToken, checkpoint)
        val token = Regex("""vqd\s*=\s*['"]([^'"]+)['"]""")
            .find(landing.body.toString(Charsets.UTF_8))
            ?.groupValues
            ?.getOrNull(1)
            ?.trim()
            .orEmpty()
        if (token.isBlank()) {
            throw AgentWebMediaException(
                "invalid_engine_response",
                "DuckDuckGo Image did not return a search token",
                retryable = true
            )
        }
        val endpoint = "https://duckduckgo.com/i.js?l=wt-wt&o=json&q=$encoded&vqd=" +
            URLEncoder.encode(token, Charsets.UTF_8.name()) + "&f=,,,,,&p=1"
        val response = fetch(
            endpoint,
            timeoutMillis,
            mapOf(
                "Accept" to "application/json",
                "Referer" to landingUrl,
                "User-Agent" to SEARCH_USER_AGENT
            ),
            cancellationToken,
            checkpoint
        )
        return parseJson(JSONObject(response.body.toString(Charsets.UTF_8)), limit)
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
        "github_code" -> githubCode(root, limit)
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
        "marginalia" -> rows(root.optJSONArray("results"), limit, "title", "url", "description", "")
        "brave_image" -> imageRows(root.optJSONArray("results"), limit, brave = true)
        "duckduckgo_image" -> imageRows(root.optJSONArray("results"), limit, brave = false)
        else -> emptyList()
    }

    private fun githubCode(root: JSONObject, limit: Int) = buildList {
        val values = root.optJSONArray("items") ?: JSONArray()
        for (index in 0 until min(values.length(), limit)) {
            val item = values.optJSONObject(index) ?: continue
            val repository = item.optJSONObject("repository")
            val path = item.optString("path").ifBlank { item.optString("name") }
            val repo = repository?.optString("full_name").orEmpty()
            result(
                size + 1,
                listOf(repo, path).filter(String::isNotBlank).joinToString(" · "),
                item.optString("html_url"),
                repository?.optString("description").orEmpty().ifBlank { path },
                repository?.optString("updated_at").orEmpty()
            )?.let(::add)
        }
    }

    private fun imageRows(values: JSONArray?, limit: Int, brave: Boolean) = buildList {
        val array = values ?: JSONArray()
        for (index in 0 until min(array.length(), limit)) {
            val item = array.optJSONObject(index) ?: continue
            val properties = item.optJSONObject("properties")
            val thumbnail = item.optJSONObject("thumbnail")
            val imageUrl = if (brave) properties?.optString("url").orEmpty() else item.optString("image")
            val thumbnailUrl = if (brave) thumbnail?.optString("src").orEmpty() else item.optString("thumbnail")
            val sourceUrl = item.optString("url").ifBlank { imageUrl }
            imageResult(
                size + 1,
                item.optString("title").ifBlank { runCatching { URI(sourceUrl).host }.getOrDefault("") },
                sourceUrl,
                item.optString("source").ifBlank { item.optString("provider") },
                imageUrl,
                thumbnailUrl,
                if (brave) properties?.optInt("width") ?: 0 else item.optInt("width"),
                if (brave) properties?.optInt("height") ?: 0 else item.optInt("height")
            )?.let(::add)
        }
    }

    private fun devDocs(query: String, limit: Int): List<AgentWebIntelligenceRawResult> {
        val normalized = AgentWebIntelligenceText.normalized(query)
        val matches = DEV_DOCS.filter { entry ->
            entry.aliases.any { alias ->
                Regex("(^|[^a-z0-9])${Regex.escape(alias)}([^a-z0-9]|$)").containsMatchIn(normalized)
            }
        }.ifEmpty {
            DEV_DOCS.filter { entry ->
                AgentWebIntelligenceText.tokens(normalized).any { token ->
                    token.length >= 3 && (
                        entry.title.lowercase(Locale.ROOT).contains(token) ||
                            entry.slug.contains(token)
                        )
                }
            }
        }
        return matches.take(limit).mapIndexed { index, entry ->
            AgentWebIntelligenceRawResult(
                engineId = spec.id,
                rank = index + 1,
                title = "${entry.title} documentation",
                url = "https://devdocs.io/${entry.slug}",
                excerpt = "Offline DevDocs index match for ${entry.title}.",
                vertical = spec.vertical
            )
        }
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

    private fun imageResult(
        rank: Int,
        title: Any?,
        url: Any?,
        excerpt: Any?,
        imageUrl: Any?,
        thumbnailUrl: Any?,
        width: Int,
        height: Int
    ): AgentWebIntelligenceRawResult? {
        val base = result(rank, title, url, excerpt) ?: return null
        val cleanImage = imageUrl?.toString()?.trim().orEmpty()
        if (!cleanImage.startsWith("http://") && !cleanImage.startsWith("https://")) return null
        val cleanThumbnail = thumbnailUrl?.toString()?.trim().orEmpty()
        return base.copy(
            imageUrl = cleanImage,
            thumbnailUrl = cleanThumbnail.takeIf {
                it.startsWith("http://") || it.startsWith("https://")
            }.orEmpty(),
            imageWidth = width.coerceAtLeast(0),
            imageHeight = height.coerceAtLeast(0)
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
        private const val SEARCH_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36"

        private data class DevDocsEntry(
            val title: String,
            val slug: String,
            val aliases: Set<String>
        )

        private val DEV_DOCS = listOf(
            DevDocsEntry("React", "react", setOf("react", "reactjs")),
            DevDocsEntry("Vue", "vue~3", setOf("vue", "vuejs")),
            DevDocsEntry("Angular", "angular", setOf("angular")),
            DevDocsEntry("Svelte", "svelte", setOf("svelte")),
            DevDocsEntry("TypeScript", "typescript", setOf("typescript", "ts")),
            DevDocsEntry("JavaScript", "javascript", setOf("javascript", "js", "ecmascript")),
            DevDocsEntry("Node.js", "node", setOf("node", "nodejs", "node.js")),
            DevDocsEntry("Python", "python~3.13", setOf("python", "python3")),
            DevDocsEntry("Go", "go", setOf("golang")),
            DevDocsEntry("Rust", "rust", setOf("rust")),
            DevDocsEntry("CSS", "css", setOf("css")),
            DevDocsEntry("HTML", "html", setOf("html")),
            DevDocsEntry("HTTP", "http", setOf("http")),
            DevDocsEntry("PostgreSQL", "postgresql~17", setOf("postgresql", "postgres")),
            DevDocsEntry("SQLite", "sqlite", setOf("sqlite")),
            DevDocsEntry("Redis", "redis", setOf("redis")),
            DevDocsEntry("Docker", "docker", setOf("docker")),
            DevDocsEntry("Git", "git", setOf("git")),
            DevDocsEntry("Bash", "bash", setOf("bash", "shell")),
            DevDocsEntry("nginx", "nginx", setOf("nginx")),
            DevDocsEntry("webpack", "webpack~5", setOf("webpack")),
            DevDocsEntry("Tailwind CSS", "tailwindcss", setOf("tailwind", "tailwindcss"))
        )

        fun parse(
            spec: AgentWebIntelligenceEngineSpec,
            fetched: AgentWebIntelligenceFetched,
            limit: Int
        ): List<AgentWebIntelligenceRawResult> {
            val adapter = AgentWebIntelligenceSearchAdapter(
                spec = spec,
                fetcher = AgentWebIntelligenceFetcher { _, _, _, _, _ -> fetched }
            )
            val source = fetched.body.toString(Charsets.UTF_8)
            return when {
                spec.parser == "html" -> adapter.parseHtml(source, fetched.url, limit)
                spec.parser == "site_index" -> adapter.parseSiteIndex(source, fetched.url, limit)
                spec.parser == "x_public" -> adapter.parseXPublic(source, fetched.url, limit)
                spec.parser == "wechat_public" -> adapter.parseWeChatPublic(source, fetched.url, limit)
                spec.parser in setOf("zhihu_public", "xiaohongshu_public") ->
                    adapter.parseIndexedSocial(source, fetched.url, limit)
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
            val mergeKey = if (raw.vertical == AgentWebIntelligenceVertical.IMAGE && raw.imageUrl.isNotBlank()) {
                AgentWebIntelligenceText.canonicalUrl(raw.imageUrl)
            } else {
                canonical
            }
            val spec = specs[raw.engineId]
            val current = merged.getOrPut(mergeKey) {
                AgentWebIntelligenceResult(
                    title = raw.title,
                    url = canonical,
                    excerpt = raw.excerpt,
                    publishedAt = raw.publishedAt,
                    vertical = raw.vertical,
                    imageUrl = raw.imageUrl,
                    thumbnailUrl = raw.thumbnailUrl,
                    imageWidth = raw.imageWidth,
                    imageHeight = raw.imageHeight,
                    authority = spec?.authority ?: 0.5
                )
            }
            if (raw.title.length > current.title.length) current.title = raw.title
            if (raw.excerpt.length > current.excerpt.length) current.excerpt = raw.excerpt
            if (current.publishedAt.isBlank() && raw.publishedAt.isNotBlank()) current.publishedAt = raw.publishedAt
            if (current.imageUrl.isBlank() && raw.imageUrl.isNotBlank()) current.imageUrl = raw.imageUrl
            if (current.thumbnailUrl.isBlank() && raw.thumbnailUrl.isNotBlank()) current.thumbnailUrl = raw.thumbnailUrl
            if (current.imageWidth <= 0 && raw.imageWidth > 0) current.imageWidth = raw.imageWidth
            if (current.imageHeight <= 0 && raw.imageHeight > 0) current.imageHeight = raw.imageHeight
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
    val engineCatalogSize: Int = AgentWebIntelligenceEngineCatalog.entries.size,
    val completedAtMillis: Long = System.currentTimeMillis(),
    val earlyCompleted: Boolean = false,
    val completionReason: String = ""
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "protocol" to AGENT_WEB_INTELLIGENCE_PROTOCOL,
        "operation" to "search",
        "status" to status,
        "query" to query,
        "results" to results.mapIndexed { index, result -> result.publicValue(index + 1) },
        "receipts" to receipts.sortedBy { it.sourceId }.map(AgentWebIntelligenceReceipt::publicValue),
        "metadata" to linkedMapOf(
            "engine_catalog_size" to engineCatalogSize,
            "engines_requested" to engineIds,
            "engines_completed" to receipts.count { it.status == "completed" },
            "engines_cancelled" to receipts.count { it.status == "cancelled" },
            "engine_failures" to receipts.count {
                it.status !in setOf("completed", "empty", "cancelled")
            },
            "profile" to profile,
            "engine_fanout" to engineIds.size,
            "timeout_millis" to timeoutMillis,
            "source_selection" to selectionStrategy,
            "source_health" to sourceHealth.map { it.publicValue(completedAtMillis) },
            "circuits_skipped" to circuitsSkipped.map { it.publicValue(completedAtMillis) },
            "fusion" to "weighted_rrf_plus_local_ranker",
            "ranker_model" to AgentWebIntelligenceRanker.MODEL_ID,
            "early_completed" to earlyCompleted,
            "completion_reason" to completionReason,
            "elapsed_millis" to elapsedMillis
        )
    )
}

internal object AgentWebSearchCompletionPolicy {
    fun hasSufficientEvidence(
        profile: String,
        explicitSources: Boolean,
        groups: List<List<AgentWebIntelligenceRawResult>>,
        limit: Int
    ): Boolean {
        if (explicitSources || profile == AgentWebIntelligenceSearchProfile.DEEP.wireValue) return false
        val successfulGroups = groups.filter { it.isNotEmpty() }
        val uniqueUrls = successfulGroups.flatten()
            .map { AgentWebIntelligenceText.canonicalUrl(it.url) }
            .filter(String::isNotBlank)
            .toSet()
        val uniqueDomains = uniqueUrls.mapNotNull { url ->
            runCatching { URI(url).host?.removePrefix("www.")?.lowercase() }.getOrNull()
        }.filter(String::isNotBlank).toSet()
        val fast = profile == AgentWebIntelligenceSearchProfile.FAST.wireValue
        val requiredSources = if (fast) 2 else 4
        val requiredResults = if (fast) max(limit, 6) else max(limit * 2, 12)
        val requiredDomains = if (fast) 3 else 5
        return successfulGroups.size >= requiredSources &&
            uniqueUrls.size >= requiredResults &&
            uniqueDomains.size >= requiredDomains
    }
}

class AgentWebIntelligenceSearchCoordinator(
    private val fetcher: AgentWebIntelligenceFetcher,
    private val credentialProvider: AgentWebIntelligenceCredentialProvider =
        AgentWebIntelligenceCredentialProvider.NONE,
    private val fusion: AgentWebIntelligenceFusion = AgentWebIntelligenceFusion(),
    private val maxWorkers: Int = 8,
    private val clock: () -> Long = System::currentTimeMillis,
    private val healthProvider: () -> Map<String, AgentWebIntelligenceSourceHealth> = { emptyMap() },
    private val receiptObserver: (AgentWebIntelligenceReceipt) -> Unit = {},
    private val learnedSourceProvider: () -> List<AgentWebIntelligenceLearnedSource> = { emptyList() }
) {
    private val baseSourceIds = AgentWebIntelligenceEngineCatalog.entries.map { it.id }.toSet()
    private val specs = ConcurrentHashMap(
        AgentWebIntelligenceEngineCatalog.entries.associateBy { it.id }
    )
    private val adapters = ConcurrentHashMap(
        specs.mapValues {
            AgentWebIntelligenceSearchAdapter(it.value, fetcher, credentialProvider)
        }
    )

    fun search(
        query: String,
        limit: Int = 10,
        engineFanout: Int = 18,
        requestedEngines: List<String> = emptyList(),
        verticals: Set<AgentWebIntelligenceVertical> = emptySet(),
        categoryTags: Set<String> = emptySet(),
        timeoutMillis: Long = 15_000L,
        cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE,
        checkpoint: () -> Unit = {},
        profile: String = AgentWebIntelligenceSearchProfile.BALANCED.wireValue
    ): AgentWebIntelligenceSearchResponse {
        require(query.isNotBlank() && query.length <= 4_096)
        require(limit in 1..100)
        require(engineFanout in 1..32)
        require(timeoutMillis in 1_000L..60_000L)
        refreshLearnedSources()
        val selection = selectEnginePlan(
            query,
            engineFanout,
            requestedEngines,
            verticals,
            categoryTags
        )
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
                selectionStrategy = selection.strategy,
                circuitsSkipped = selection.skipped,
                timeoutMillis = timeoutMillis,
                engineCatalogSize = specs.size,
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
            var earlyCompleted = false
            while (pending.isNotEmpty()) {
                checkpoint()
                val remaining = deadline - clock()
                if (remaining <= 0L) break
                val completed = completion.poll(remaining, TimeUnit.MILLISECONDS) ?: break
                val (engine, results, receipt) = completed.get()
                pending.remove(engine)
                groups += results
                receipts += receipt
                if (AgentWebSearchCompletionPolicy.hasSufficientEvidence(
                        profile = profile,
                        explicitSources = selection.explicit,
                        groups = groups,
                        limit = limit
                    )
                ) {
                    earlyCompleted = true
                    break
                }
            }
            pending.forEach { engine ->
                receipts += AgentWebIntelligenceReceipt(
                    sourceId = engine,
                    status = if (earlyCompleted) "cancelled" else "timeout",
                    durationMillis = if (earlyCompleted) clock() - started else timeoutMillis,
                    resultCount = 0,
                    errorCode = if (earlyCompleted) "sufficient_evidence" else "engine_timeout",
                    errorMessage = if (earlyCompleted) {
                        "Search stopped after collecting sufficient diverse evidence"
                    } else {
                        "Search source exceeded the shared request deadline"
                    },
                    retryable = !earlyCompleted
                )
            }
            receipts.forEach(receiptObserver)
            val results = fusion.fuse(query, groups, limit)
            val status = when {
                results.isEmpty() -> "failed"
                earlyCompleted -> "completed"
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
                selectionStrategy = selection.strategy,
                sourceHealth = selected.map { health[it] ?: AgentWebIntelligenceSourceHealth(it) },
                circuitsSkipped = selection.skipped,
                timeoutMillis = timeoutMillis,
                engineCatalogSize = specs.size,
                completedAtMillis = completedAt,
                earlyCompleted = earlyCompleted,
                completionReason = if (earlyCompleted) "sufficient_diverse_evidence" else ""
            )
        } finally {
            executor.shutdownNow()
        }
    }

    fun selectEngines(
        query: String,
        fanout: Int,
        requested: List<String>,
        verticals: Set<AgentWebIntelligenceVertical>,
        categoryTags: Set<String> = emptySet()
    ): List<String> {
        refreshLearnedSources()
        return selectEnginePlan(query, fanout, requested, verticals, categoryTags).selected
    }

    private fun selectEnginePlan(
        query: String,
        fanout: Int,
        requested: List<String>,
        verticals: Set<AgentWebIntelligenceVertical>,
        categoryTags: Set<String>
    ): AgentWebIntelligenceSourceSelection {
        if (requested.isNotEmpty()) {
            val unknown = requested.filterNot(specs::containsKey)
            require(unknown.isEmpty()) { "Unknown web intelligence engines: ${unknown.joinToString()}" }
            return AgentWebIntelligenceSourceSelection(
                selected = requested.distinct().take(fanout),
                explicit = true,
                strategy = "explicit_sources"
            )
        }
        val language = AgentWebIntelligenceText.language(query)
        val inferredVerticals = if (verticals.isEmpty()) {
            AgentWebIntelligenceQueryRouting.inferredVerticals(query)
        } else {
            emptySet()
        }
        val desired = verticals.ifEmpty { inferredVerticals }
        val desiredTags = categoryTags.mapNotNull(::normalizeAgentWebCategoryTag).toSet()
        val nowMillis = clock()
        val health = healthProvider()
        val skipped = mutableListOf<AgentWebIntelligenceSourceHealth>()
        val orderedSpecs = AgentWebIntelligenceEngineCatalog.entries +
            specs.values.filter { it.id !in baseSourceIds }.sortedBy(AgentWebIntelligenceEngineSpec::id)
        val ranked = orderedSpecs
            .filter(AgentWebIntelligenceEngineSpec::enabledByDefault)
            .filter { spec ->
                spec.requiresKey.isBlank() || credentialProvider.credential(spec.requiresKey).isNotBlank()
            }
            .mapIndexedNotNull { index, spec ->
                val sourceHealth = health[spec.id] ?: AgentWebIntelligenceSourceHealth(spec.id)
                if (sourceHealth.circuitState(nowMillis) == "open") {
                    skipped += sourceHealth
                    return@mapIndexedNotNull null
                }
                val score = spec.weight +
                    (if (spec.vertical in desired) 2.5 else 0.0) +
                    (if (spec.categoryTags.any(desiredTags::contains)) 2.0 else 0.0) +
                    (if (spec.vertical == AgentWebIntelligenceVertical.GENERAL) 1.0 else 0.0) +
                    (if ("*" in spec.languages || language in spec.languages) 0.8 else -1.5) +
                    spec.authority * 0.5 +
                    AgentWebIntelligenceQueryRouting.sourceAffinity(query, spec) +
                    sourceHealth.routingScore()
                Triple(score, -index, spec.id)
            }
            .sortedWith(compareByDescending<Triple<Double, Int, String>> { it.first }.thenByDescending { it.second })
        val selected = mutableListOf<String>()
        for (category in desiredTags.sorted()) {
            if (selected.size >= fanout) break
            ranked.firstOrNull {
                category in specs.getValue(it.third).categoryTags && it.third !in selected
            }?.third?.let(selected::add)
        }
        for (vertical in desired.sortedBy(AgentWebIntelligenceVertical::wireValue)) {
            if (selected.size >= fanout) break
            ranked.firstOrNull { specs.getValue(it.third).vertical == vertical && it.third !in selected }
                ?.third
                ?.let(selected::add)
        }
        ranked.forEach { item ->
            if (selected.size < fanout && item.third !in selected) selected += item.third
        }
        return AgentWebIntelligenceSourceSelection(
            selected = selected.take(fanout),
            skipped = skipped.sortedBy(AgentWebIntelligenceSourceHealth::circuitOpenUntilMillis),
            strategy = if (inferredVerticals.isNotEmpty()) {
                "semantic_query_topics"
            } else if (desired.isNotEmpty() || desiredTags.isNotEmpty()) {
                "model_selected_topics"
            } else {
                "broad_unscoped"
            }
        )
    }

    @Synchronized
    private fun refreshLearnedSources() {
        learnedSourceProvider()
            .filter { it.status == "verified" }
            .sortedBy(AgentWebIntelligenceLearnedSource::sourceId)
            .forEachIndexed { index, learned ->
                if (specs.containsKey(learned.sourceId)) return@forEachIndexed
                val spec = learned.toEngineSpec(index + baseSourceIds.size)
                specs[spec.id] = spec
                adapters[spec.id] = AgentWebIntelligenceSearchAdapter(
                    spec,
                    fetcher,
                    credentialProvider
                )
            }
    }

}

private fun Double.roundScore(): Double = kotlin.math.round(this.coerceIn(0.0, 1.0) * 1_000_000.0) / 1_000_000.0
