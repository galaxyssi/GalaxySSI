package com.galaxyssi.chat

/** Public publisher feeds are usable without a model or a desktop-only network route. */
object ProactiveAttentionFeedSources {
    private const val TECHNOLOGY = "https://www.ithome.com/rss/"
    private const val FINANCE = "https://www.chinanews.com.cn/rss/finance.xml"
    private const val RESEARCH = "https://rss.arxiv.org/rss/cs.AI"

    fun originals(topic: AttentionTopic): List<String> = when (ProactiveAttentionPolicy.group(topic.id)) {
        AttentionTopicGroup.FINANCE -> listOf(FINANCE)
        AttentionTopicGroup.RESEARCH -> listOf(RESEARCH, TECHNOLOGY)
        AttentionTopicGroup.CUSTOM -> listOf(TECHNOLOGY, FINANCE)
        else -> listOf(TECHNOLOGY)
    }

    fun matches(article: AttentionFeedArticle, topic: AttentionTopic): Boolean {
        val words = (terms[topic.id]?.plus(english[topic.id].orEmpty())) ?: (topic.title + " " + topic.query)
            .split(Regex("[\\s,;]+")) .map(String::trim).filter { it.length >= 2 }
        val text = article.title + "\n" + article.summary
        return words.any { word ->
            if (word.any { it.code > 127 }) text.contains(word, ignoreCase = true)
            else Regex("\\b" + Regex.escape(word) + "\\b", RegexOption.IGNORE_CASE).containsMatchIn(text)
        }
    }

    private val english = mapOf(
        "macro" to listOf("inflation", "GDP", "fiscal"), "rates" to listOf("interest rate", "central bank"),
        "stocks" to listOf("stock market", "equities"), "companies" to listOf("earnings", "revenue"),
        "industry" to listOf("semiconductor", "robotics", "renewable energy"), "funds" to listOf("ETF", "mutual fund"),
        "bonds" to listOf("bond yield", "treasury"), "fx" to listOf("exchange rate", "forex"),
        "commodities" to listOf("crude oil", "gold price"), "digital" to listOf("bitcoin", "stablecoin", "crypto"),
        "institutions" to listOf("buyback", "shareholder"), "events" to listOf("merger", "dividend"),
        "risks" to listOf("fraud", "default risk"), "portfolio" to listOf("asset allocation"),
        "personal" to listOf("mortgage", "savings rate"),
        "ai_models" to listOf("OpenAI", "LLM", "language model", "Gemini"),
        "agent_frontiers" to listOf("multi-agent", "autonomous agent"),
        "open_source" to listOf("open source", "open-source"),
        "dev_infrastructure" to listOf("database", "compiler", "developer tool"),
        "multimodal_voice" to listOf("multimodal", "speech", "text-to-speech"),
        "ar_wearables" to listOf("smart glasses", "wearable"),
        "mobile_edge_ai" to listOf("on-device", "edge AI"),
        "galaxyssi_improvements" to listOf("agent memory", "tool calling"),
        "agent_products" to listOf("coding agent"), "user_needs" to listOf("user feedback", "usability"),
        "dependency_risks" to listOf("vulnerability", "CVE", "deprecation"),
        "product_experience" to listOf("user interface", "interaction design"),
        "research_papers" to listOf("preprint", "research paper", "arXiv"),
        "protein_life_sciences" to listOf("protein", "enzyme", "biology"),
        "cross_domain_innovation" to listOf("cross-domain", "novel method"),
        "evaluation_science" to listOf("reproducibility", "benchmark")
    )

    private val terms = mapOf(
        "macro" to listOf("\u7ecf\u6d4e", "GDP", "CPI", "\u901a\u80c0", "\u8d22\u653f", "\u653f\u7b56"),
        "rates" to listOf("\u592e\u884c", "\u5229\u7387", "\u964d\u606f", "\u52a0\u606f", "\u7f8e\u8054\u50a8"),
        "stocks" to listOf("\u80a1\u5e02", "\u80a1\u6307", "A\u80a1", "\u6e2f\u80a1", "\u7f8e\u80a1", "\u80a1\u7968"),
        "companies" to listOf("\u8d22\u62a5", "\u8425\u6536", "\u51c0\u5229\u6da6", "\u73b0\u91d1\u6d41", "\u503a\u52a1", "\u4e1a\u7ee9"),
        "industry" to listOf("AI", "\u82af\u7247", "\u534a\u5bfc\u4f53", "\u673a\u5668\u4eba", "\u533b\u836f", "\u65b0\u80fd\u6e90"),
        "funds" to listOf("\u57fa\u91d1", "ETF", "\u8d39\u7387"),
        "bonds" to listOf("\u503a\u5238", "\u56fd\u503a", "\u4fe1\u7528\u503a", "\u8fdd\u7ea6"),
        "fx" to listOf("\u6c47\u7387", "\u4eba\u6c11\u5e01", "\u7f8e\u5143", "\u5916\u6c47"),
        "commodities" to listOf("\u9ec4\u91d1", "\u767d\u94f6", "\u539f\u6cb9", "\u94dc", "\u671f\u8d27"),
        "digital" to listOf("\u52a0\u5bc6", "\u6570\u5b57\u8d44\u4ea7", "\u7a33\u5b9a\u5e01", "\u6bd4\u7279\u5e01"),
        "institutions" to listOf("\u56de\u8d2d", "\u6301\u80a1", "\u51cf\u6301", "\u589e\u6301", "\u673a\u6784"),
        "events" to listOf("\u5206\u7ea2", "\u5e76\u8d2d", "\u91cd\u7ec4", "\u6307\u6570"),
        "risks" to listOf("\u8bc8\u9a97", "\u98ce\u9669", "\u9020\u5047", "\u8fdd\u7ea6", "\u8c23\u8a00"),
        "portfolio" to listOf("\u6295\u8d44\u7ec4\u5408", "\u8d44\u4ea7\u914d\u7f6e", "\u5206\u6563\u6295\u8d44"),
        "personal" to listOf("\u5b58\u6b3e", "\u8d37\u6b3e", "\u4fdd\u9669", "\u7406\u8d22", "\u624b\u7eed\u8d39"),
        "ai_models" to listOf("AI", "\u6a21\u578b", "GPT", "Claude", "DeepSeek", "\u4eba\u5de5\u667a\u80fd"),
        "agent_frontiers" to listOf("\u667a\u80fd\u4f53", "Agent", "\u8bb0\u5fc6", "\u81ea\u4e3b"),
        "open_source" to listOf("\u5f00\u6e90", "GitHub", "\u8bb8\u53ef\u8bc1"),
        "dev_infrastructure" to listOf("\u5f00\u53d1", "MCP", "\u6570\u636e\u5e93", "\u6d4f\u89c8\u5668", "\u534f\u8bae", "\u5de5\u5177"),
        "multimodal_voice" to listOf("\u89c6\u9891", "\u56fe\u50cf", "\u591a\u6a21\u6001", "\u8bed\u97f3", "ASR", "TTS"),
        "ar_wearables" to listOf("\u773c\u955c", "\u7a7f\u6234", "AR", "\u624b\u8868"),
        "mobile_edge_ai" to listOf("Android", "\u5b89\u5353", "\u624b\u673a", "\u7aef\u4fa7", "NPU", "QNN", "Wear OS"),
        "galaxyssi_improvements" to listOf("\u667a\u80fd\u4f53", "Agent", "MCP", "\u7aef\u4fa7", "\u8bb0\u5fc6"),
        "agent_products" to listOf("\u667a\u80fd\u4f53", "Agent", "Codex", "Claude", "\u8c46\u5305"),
        "user_needs" to listOf("\u7528\u6237", "\u4f53\u9a8c", "\u53cd\u9988", "\u75db\u70b9"),
        "dependency_risks" to listOf("\u6f0f\u6d1e", "\u5f03\u7528", "\u8bb8\u53ef\u8bc1", "\u505c\u6b62\u670d\u52a1", "\u5b89\u5168"),
        "product_experience" to listOf("\u4ea4\u4e92", "\u8bbe\u8ba1", "\u901a\u77e5", "\u8bed\u97f3", "\u591a\u8bbe\u5907"),
        "research_papers" to listOf("\u8bba\u6587", "\u7814\u7a76", "\u5b9e\u9a8c", "arXiv"),
        "protein_life_sciences" to listOf("\u86cb\u767d", "\u751f\u7269", "\u751f\u547d\u79d1\u5b66", "\u6298\u53e0", "\u9176"),
        "cross_domain_innovation" to listOf("\u521b\u65b0", "\u8de8\u9886\u57df", "\u7814\u7a76", "\u65b0\u65b9\u6cd5"),
        "evaluation_science" to listOf("\u8bc4\u6d4b", "\u57fa\u51c6", "\u590d\u73b0", "\u5b9e\u9a8c", "benchmark")
    )
}

