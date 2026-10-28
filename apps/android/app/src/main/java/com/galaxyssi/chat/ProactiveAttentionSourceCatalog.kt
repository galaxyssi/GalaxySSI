package com.galaxyssi.chat

/** Topic-specific publisher entry points; discovery is never treated as a verified full article. */
internal object ProactiveAttentionSourceCatalog {
    private const val OPENAI = "https://openai.com/news/rss.xml"
    private const val LANGCHAIN = "https://www.langchain.com/blog/rss.xml"
    private const val MIT_AI = "https://news.mit.edu/rss/topic/artificial-intelligence2"
    private const val ELIFE = "https://elifesciences.org/rss/recent.xml"
    private const val PLOS = "https://journals.plos.org/plosbiology/feed/atom"
    private const val NATURE_BIOTECH = "https://www.nature.com/nbt.rss"
    private const val SCIENCE = "https://www.sciencedaily.com/rss/top/science.xml"

    fun specialized(topicId: String): List<String> = when (topicId) {
        "ai_models" -> listOf(OPENAI, MIT_AI)
        "agent_frontiers", "agent_products", "galaxyssi_improvements" -> listOf(LANGCHAIN, OPENAI, MIT_AI)
        "open_source", "dev_infrastructure", "product_experience", "user_needs" -> listOf(LANGCHAIN)
        "multimodal_voice", "mobile_edge_ai", "dependency_risks" -> listOf(OPENAI)
        "protein_life_sciences" -> listOf(PLOS, ELIFE, NATURE_BIOTECH)
        "research_papers", "cross_domain_innovation", "evaluation_science" -> listOf(PLOS, ELIFE, MIT_AI, SCIENCE)
        "industry" -> listOf(NATURE_BIOTECH, OPENAI)
        else -> emptyList()
    }

    fun dedicated(url: String, topicId: String): Boolean = when (topicId) {
        "protein_life_sciences" -> url in specialized(topicId) ||
            url == "https://news.mit.edu/rss/topic/biology-and-genetics" || url.startsWith("https://rss.arxiv.org/rss/q-bio")
        "agent_frontiers", "agent_products", "galaxyssi_improvements" -> url == LANGCHAIN
        else -> false
    }

    // Research publishers are slower than breaking news. Keep the real publication date visible.
    fun maxAgeDays(topicId: String): Int = if (ProactiveAttentionPolicy.group(topicId) == AttentionTopicGroup.RESEARCH) 30 else 7

    fun searchQuery(topic: AttentionTopic): String = searches[topic.id] ?: topic.query.take(512).ifBlank { topic.title }

    private val searches = mapOf(
        "macro" to "macroeconomics inflation fiscal policy", "rates" to "central bank interest rates",
        "stocks" to "stock market equities", "companies" to "company earnings financial results",
        "industry" to "semiconductor robotics biotechnology", "funds" to "ETF fund fees holdings",
        "bonds" to "bond yields credit risk", "fx" to "foreign exchange currency policy",
        "commodities" to "gold oil copper supply demand", "digital" to "crypto stablecoin regulation",
        "institutions" to "institutional investors share buyback", "events" to "merger acquisition dividend",
        "risks" to "financial fraud risk warning", "portfolio" to "portfolio diversification research",
        "personal" to "savings mortgage insurance fees", "ai_models" to "AI model LLM release",
        "agent_frontiers" to "AI agents multi-agent memory", "open_source" to "open source software release",
        "dev_infrastructure" to "developer tools MCP database", "multimodal_voice" to "multimodal speech recognition synthesis",
        "ar_wearables" to "AR smart glasses wearable", "mobile_edge_ai" to "on-device AI Android NPU",
        "galaxyssi_improvements" to "agent memory tool calling evaluation", "agent_products" to "coding agents product release",
        "user_needs" to "AI usability user feedback", "dependency_risks" to "software vulnerability API deprecation",
        "product_experience" to "AI interaction design accessibility", "research_papers" to "AI research paper methods",
        "protein_life_sciences" to "protein design structure biotechnology", "cross_domain_innovation" to "interdisciplinary research innovation",
        "evaluation_science" to "AI benchmark reproducibility evaluation"
    )
}
