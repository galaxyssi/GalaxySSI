package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

enum class AttentionAlertMode { IMPORTANT, ALL, SILENT }
enum class AttentionFeedFilter { ALL, IMPORTANT, UNREAD, SAVED }
enum class AttentionTopicGroup { FINANCE, TECHNOLOGY, GALAXYSSI, RESEARCH, CUSTOM }

data class AttentionTopic(val id: String, val title: String, val query: String, val enabled: Boolean = true)
data class AttentionPreferences(
    val configured: Boolean = false,
    val enabled: Boolean = true,
    val alertMode: AttentionAlertMode = AttentionAlertMode.IMPORTANT,
    val topics: List<AttentionTopic> = emptyList(),
    val savedKeys: Set<String> = emptySet(),
    val allowPairedModel: Boolean = false,
    val allowCloudModel: Boolean = false
)

object ProactiveAttentionPolicy {
    const val TASK_PREFIX = "attention-research:"
    private val financeIds = listOf("macro", "rates", "stocks", "companies", "industry", "funds", "bonds",
        "fx", "commodities", "digital", "institutions", "events", "risks", "portfolio", "personal")
    private val technologyIds = listOf("ai_models", "agent_frontiers", "open_source", "dev_infrastructure",
        "multimodal_voice", "ar_wearables", "mobile_edge_ai")
    private val galaxyssiIds = listOf("galaxyssi_improvements", "agent_products", "user_needs", "dependency_risks", "product_experience")
    private val researchIds = listOf("research_papers", "protein_life_sciences", "cross_domain_innovation", "evaluation_science")
    val categoryIds = financeIds + technologyIds + galaxyssiIds + researchIds
    private val questions = listOf(
        "Macroeconomic data, fiscal and regulatory policy changes",
        "Central bank decisions, interest rates and changes in expectations",
        "Material changes in mainland China, Hong Kong and US equity markets",
        "Company filings, earnings, cash flow, debt and operating risks",
        "AI, semiconductor, robotics, energy and pharmaceutical industry fundamentals",
        "Fund and ETF fees, holdings, tracking error and product announcements",
        "Sovereign and corporate bond yields, credit and repayment risks",
        "Exchange rates, interest differentials and currency policy",
        "Gold, silver, oil and copper supply, demand and inventories",
        "Digital asset regulation, platform security and stablecoin risks",
        "Public institutional disclosures, buybacks and shareholder transactions; identify disclosure lag",
        "Dividends, mergers, reorganizations and index changes; treat opportunities as unverified leads",
        "Financial fraud warnings, corrected rumors, default and accounting risks",
        "Public guidance on portfolio concentration and diversification; no account access or assumed holdings",
        "Public deposit, loan, insurance and financial service fees; no assumed private accounts",
        "New AI models, measured capabilities, pricing, context, APIs, deprecations and alternatives",
        "Autonomous agents, collaboration, memory, proactivity and self-improvement methods with demonstrated cases",
        "Useful open-source projects, major releases, implementation, licenses and maintenance",
        "Developer tools, browser automation, MCP, Skills, databases, communication protocols and deployment",
        "Images, video, realtime voice, ASR, TTS, echo cancellation and on-device inference",
        "AR glasses and wearables, hands-on evidence, SDKs, third-party apps, sensors and interfaces",
        "Android, Wear OS, local models, NPU/QNN, power consumption, background execution and system changes",
        "External techniques relevant to GalaxySSI architecture, expected benefit, integration effort and verification methods",
        "Comparable Agent products, new features, interaction design, latency, reliability, pricing and user reviews",
        "Recurring user complaints, unmet needs and candidate priorities supported by public evidence",
        "Dependency vulnerabilities, API deprecations, service changes, licenses and potentially breaking updates",
        "Chat, collaboration, voice, floating interaction, notification and multi-device experience examples",
        "Relevant papers, methods, data, code, independent reproductions and limitations",
        "Protein design, structure prediction, function validation, experimental platforms, open data and tools",
        "Cross-domain method combinations, conflicting evidence, knowledge gaps and testable new hypotheses",
        "Benchmarks, datasets, controlled experiments, failure cases, evaluation contamination and reproducibility"
    )

    fun defaults(titles: List<String>, scopes: List<String> = questions): List<AttentionTopic> = categoryIds.mapIndexed { index, id ->
        AttentionTopic(id, titles.getOrElse(index) { id }, scopes.getOrElse(index) { questions[index] })
    }

    fun mergeTopics(defaults: List<AttentionTopic>, stored: List<AttentionTopic>): List<AttentionTopic> {
        val byId = stored.associateBy(AttentionTopic::id)
        val defaultIds = defaults.map(AttentionTopic::id).toSet()
        return defaults.map { byId[it.id] ?: it } + stored.filter { it.id !in defaultIds }.distinctBy(AttentionTopic::id)
    }

    fun group(topicId: String): AttentionTopicGroup = when (topicId) {
        in financeIds -> AttentionTopicGroup.FINANCE
        in technologyIds -> AttentionTopicGroup.TECHNOLOGY
        in galaxyssiIds -> AttentionTopicGroup.GALAXYSSI
        in researchIds -> AttentionTopicGroup.RESEARCH
        else -> AttentionTopicGroup.CUSTOM
    }

    fun preferredSources(topicId: String): List<String> = when (group(topicId)) {
        AttentionTopicGroup.FINANCE -> listOf("Official regulators, central banks, exchange filings and original company announcements")
        AttentionTopicGroup.TECHNOLOGY -> listOf("Official model and device documentation, release notes, pricing pages, repositories, licenses and independent measurements")
        AttentionTopicGroup.GALAXYSSI -> listOf("Public GalaxySSI documentation and release notes, upstream advisories, official competitor documentation and attributable public user reports")
        AttentionTopicGroup.RESEARCH -> listOf("Original papers and supplements, published datasets and code, independent reproductions, corrections and retractions")
        AttentionTopicGroup.CUSTOM -> listOf("Dated primary sources and independently verifiable evidence relevant to the requested topic")
    }

    fun researchQuestion(topic: AttentionTopic): String {
        val scope = when (group(topic.id)) {
            // Preserve existing finance requests and checkpoints when only the catalog expands.
            AttentionTopicGroup.FINANCE -> "Collect material public financial information, verify dated original sources, and summarize in Simplified Chinese. " +
                "Only research public information; do not access accounts or take financial actions. " +
                "Do not invent news or guarantee returns. Report source publication and retrieval times and uncertainty."
            AttentionTopicGroup.TECHNOLOGY -> "Collect material technology and product changes. Verify official availability, versions, regions, " +
                "licenses and dates; distinguish announcements, measured capabilities and marketing claims."
            AttentionTopicGroup.GALAXYSSI -> "Collect changes relevant to GalaxySSI. Verify the documented architecture before claiming compatibility " +
                "or exposure to a vulnerability. Explain concrete benefit, integration effort, limitations and a validation method; " +
                "if project details are unavailable, label relevance as a hypothesis. Do not treat anecdotes as representative demand."
            AttentionTopicGroup.RESEARCH -> "Collect research methods, results and limitations. Distinguish preprints, peer review, independent " +
                "replication, computational predictions and experimental validation. Label innovative combinations as hypotheses, " +
                "check prior work, and suggest falsifiable tests; do not claim novelty or validated function without evidence."
            AttentionTopicGroup.CUSTOM -> "Collect material changes relevant to this topic using dated primary evidence."
        }
        val common = if (group(topic.id) == AttentionTopicGroup.FINANCE) "" else
            " Only research public information, summarize in Simplified Chinese, retain publication/event/retrieval dates and source links, " +
                "and separate facts, inference and uncertainty. Do not change software, access private accounts or execute experiments."
        return "${topic.title}\n${topic.query}\n$scope$common"
    }

    fun isAttention(task: GlobalResearchTask): Boolean = task.id.startsWith(TASK_PREFIX)
    fun isAttention(message: GlobalProactiveMessage): Boolean = message.sourceEventId.startsWith("research:$TASK_PREFIX")
    fun shouldCollect(preferences: AttentionPreferences, topicId: String): Boolean =
        preferences.configured && preferences.enabled && preferences.topics.any { it.id == topicId && it.enabled }

    fun shouldAlert(mode: AttentionAlertMode, important: Boolean, active: Boolean): Boolean = active && when (mode) {
        AttentionAlertMode.IMPORTANT -> important
        AttentionAlertMode.ALL -> true
        AttentionAlertMode.SILENT -> false
    }

    fun matches(item: GlobalProactiveInboxItem, filter: AttentionFeedFilter, saved: Set<String>): Boolean = when (filter) {
        AttentionFeedFilter.ALL -> true
        AttentionFeedFilter.IMPORTANT -> item.urgent
        AttentionFeedFilter.UNREAD -> item.isNew
        AttentionFeedFilter.SAVED -> item.key in saved
    }

    fun important(result: String, ledger: GlobalEvidenceLedger): Boolean =
        result.lineSequence().any { it.trim() == "ATTENTION_IMPORTANCE: important" } &&
            ledger.verified && ledger.primarySourceCount > 0 && ledger.freshSourceCount > 0 &&
            ledger.contestedClaimCount == 0

    fun visibleResult(result: String): String = result.lineSequence()
        .filterNot { it.trim().startsWith("ATTENTION_IMPORTANCE:") || it.trim().startsWith("ATTENTION_RECHECK_HOURS:") }
        .joinToString("\n").trim()

    fun nextInterval(result: String, changed: Boolean, previous: Long): Long {
        val proposed = result.lineSequence().firstOrNull { it.trim().startsWith("ATTENTION_RECHECK_HOURS:") }
            ?.substringAfter(':')?.trim()?.toDoubleOrNull()?.takeIf { it.isFinite() && it > 0 }
        val duration = proposed?.coerceIn(1.0, 168.0)?.times(3_600_000)?.toLong()
            ?: if (changed) previous else previous.coerceAtMost(3L * 86_400_000) * 2
        return GlobalResearchTaskPolicy.monitorIntervalMillis(duration)
    }

    const val SYNTHESIS_INSTRUCTIONS = "\nFor this proactive attention report, follow the requested topic and write concise Simplified Chinese. " +
        "Separate facts, inference and uncertainty; cite original dated sources and distinguish publication, event " +
        "and retrieval times. Distinguish announced from measured capabilities, predictions from experiments, " +
        "and proposed ideas from verified discoveries. Do not invent holdings, guarantee profits or execute actions. " +
        "End with a separate line ATTENTION_IMPORTANCE: important only for a material, time-sensitive change " +
        "with a concrete consequence supported by current primary evidence; otherwise ATTENTION_IMPORTANCE: normal. " +
        "Also suggest ATTENTION_RECHECK_HOURS: <hours> from expected source changes/deadlines, not a notification schedule."
}

class ProactiveAttentionStore(context: Context) {
    private val appContext = context.applicationContext
    private val database = AgentEncryptedDatabase(appContext, GlobalAgentRepository.DATABASE_NAME)

    fun preferences(): AttentionPreferences = synchronized(LOCK) {
        val root = runCatching { JSONObject(database.readString(KEY, "{}")) }.getOrDefault(JSONObject())
        val defaults = ProactiveAttentionPolicy.defaults(appContext.resources.getStringArray(R.array.attention_categories).toList(),
            appContext.resources.getStringArray(R.array.attention_scopes).toList())
        val stored = root.optJSONArray("topics") ?: JSONArray()
        val topics = (0 until stored.length()).mapNotNull { index ->
            stored.optJSONObject(index)?.let { value ->
                val id = value.optString("id")
                if (id.isBlank()) null else AttentionTopic(id, value.optString("title"), value.optString("query"), value.optBoolean("enabled", true))
            }
        }
        AttentionPreferences(root.optBoolean("configured"), root.optBoolean("enabled", true),
            runCatching { AttentionAlertMode.valueOf(root.optString("mode")) }.getOrDefault(AttentionAlertMode.IMPORTANT),
            ProactiveAttentionPolicy.mergeTopics(defaults, topics),
            root.optJSONArray("saved").strings(), root.optBoolean("paired"), root.optBoolean("cloud"))
    }

    fun update(transform: (AttentionPreferences) -> AttentionPreferences): AttentionPreferences = synchronized(LOCK) {
        val next = transform(preferences())
        database.writeString(KEY, JSONObject().put("configured", next.configured).put("enabled", next.enabled)
            .put("paired", next.allowPairedModel).put("cloud", next.allowCloudModel)
            .put("mode", next.alertMode.name).put("saved", JSONArray(next.savedKeys.toList()))
            .put("topics", JSONArray().apply { next.topics.forEach { topic -> put(JSONObject()
                .put("id", topic.id).put("title", topic.title).put("query", topic.query).put("enabled", topic.enabled)) } }).toString())
        next
    }

    fun saveEvidence(task: GlobalResearchTask, important: Boolean) = synchronized(LOCK) {
        val records = runCatching { JSONObject(database.readString(EVIDENCE, "{}")) }.getOrDefault(JSONObject())
        records.put(eventId(task), JSONObject().put("topic_id", task.id.removePrefix(ProactiveAttentionPolicy.TASK_PREFIX))
            .put("important", important).put("at", task.updatedAtMillis)
            .put("sources", JSONArray().apply { task.evidenceLedger.sources.forEach { source -> put(JSONObject()
                .put("url", source.uri).put("title", source.authority.ifBlank { source.uri })
                .put("published", source.publishedAtMillis).put("retrieved", source.retrievedAtMillis)) } }))
        // Match the bounded inbox retention without deleting research evidence from its original store.
        val keys = records.keys().asSequence().toList().sortedByDescending { records.optJSONObject(it)?.optLong("at") ?: 0L }
        keys.drop(500).forEach(records::remove)
        database.writeString(EVIDENCE, records.toString())
    }

    fun allows(message: GlobalProactiveMessage): Boolean {
        if (!ProactiveAttentionPolicy.isAttention(message)) return true
        val topicId = message.sourceEventId.removePrefix("research:${ProactiveAttentionPolicy.TASK_PREFIX}").substringBefore(':')
        return ProactiveAttentionPolicy.shouldCollect(preferences(), topicId)
    }

    fun allowsNotification(message: GlobalProactiveMessage): Boolean {
        if (!ProactiveAttentionPolicy.isAttention(message)) return true
        val preferences = preferences()
        return ProactiveAttentionPolicy.shouldAlert(preferences.alertMode, message.urgent, allows(message))
    }

    fun evidence(eventId: String): JSONObject? = synchronized(LOCK) {
        runCatching { JSONObject(database.readString(EVIDENCE, "{}")).optJSONObject(eventId) }.getOrNull()
    }

    companion object {
        private val LOCK = Any()
        private const val KEY = "proactive_attention_v1"
        private const val EVIDENCE = "proactive_attention_evidence_v1"
        fun eventId(task: GlobalResearchTask) = "research:${task.id}:${task.lastResultFingerprint}"
    }
}

private fun JSONArray?.strings(): Set<String> = if (this == null) emptySet() else
    (0 until length()).map { optString(it) }.filter(String::isNotBlank).toSet()

class ProactiveAttentionCoordinator(context: Context) {
    private val appContext = context.applicationContext
    private val store = ProactiveAttentionStore(appContext)
    private val repository = GlobalAgentRepository(appContext)

    fun reconcile() = synchronized(LOCK) {
        val preferences = store.preferences()
        if (!preferences.configured) return@synchronized
        val existing = repository.researchTasks().associateBy(GlobalResearchTask::id)
        val inactiveMessages = repository.proactiveMessages().filter {
            ProactiveAttentionPolicy.isAttention(it) && !store.allows(it) &&
                it.status == GlobalProactiveMessageStatus.PENDING
        }.map(GlobalProactiveMessage::id).toSet()
        if (inactiveMessages.isNotEmpty()) repository.dismissProactiveMessages(inactiveMessages, "Attention topic disabled")
        preferences.topics.forEach { topic ->
            val id = ProactiveAttentionPolicy.TASK_PREFIX + topic.id
            val current = existing[id]
            val active = preferences.enabled && topic.enabled
            if (!active) {
                if (current != null && current.status != GlobalResearchTaskStatus.PAUSED) {
                    repository.updateResearchTask(id) { it.copy(status = GlobalResearchTaskStatus.PAUSED, leaseExpiresAtMillis = 0L) }
                }
                return@forEach
            }
            val question = ProactiveAttentionPolicy.researchQuestion(topic)
            if (current == null) {
                repository.upsertResearchTask(GlobalResearchTask(id = id, sourceEventId = id,
                    sourceConversationId = id, topic = topic.title, question = question,
                    depth = GlobalResearchDepth.CONTINUOUS_MONITOR,
                    preferredSources = ProactiveAttentionPolicy.preferredSources(topic.id),
                    monitorIntervalMillis = repository.settings().monitorIntervalMillis))
            } else if (current.question != question || current.status == GlobalResearchTaskStatus.PAUSED) {
                repository.updateResearchTask(id) { it.copy(question = question, topic = topic.title,
                    preferredSources = ProactiveAttentionPolicy.preferredSources(topic.id),
                    status = GlobalResearchTaskStatus.QUEUED, nextAttemptAtMillis = 0L, leaseExpiresAtMillis = 0L,
                    sourceMessageId = 0L, researchPlan = GlobalResearchPlan(), attemptedResourceIds = emptyList()) }
            }
        }
    }

    companion object { private val LOCK = Any() }
}
