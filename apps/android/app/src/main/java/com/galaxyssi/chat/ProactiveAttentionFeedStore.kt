package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject
import java.util.UUID

class ProactiveAttentionFeedStore(context: Context) {
    private val context = context.applicationContext
    private val database = AgentEncryptedDatabase(this.context, "attention_feed_v1")
    private val repository = GlobalAgentRepository(this.context)
    private val rows = ProactiveRecordRows(database, "article:", "articles", { it.getString("key") })

    fun ingest(article: AttentionFeedArticle, topic: AttentionTopic): Boolean = synchronized(LOCK) {
        if (!ProactiveAttentionPolicy.shouldCollect(ProactiveAttentionStore(context).preferences(), topic.id)) return false
        val previous = rows.get(article.key)
        val record = previous ?: JSONObject().put("key", article.key).put("topic", article.topicId)
            .put("title", article.title).put("summary", article.summary).put("url", article.url)
            .put("publisher", article.publisher).put("published", article.publishedAt)
            .put("discovered_via", article.discoveredVia)
            .put("discovery_date", article.discoveryDate)
            .put("collected", article.collectedAt).put("review", "pending")
        val topics = record.optJSONArray("topics") ?: org.json.JSONArray().put(record.optString("topic"))
        val addedTopic = (0 until topics.length()).none { topics.optString(it) == topic.id }
        if (addedTopic) topics.put(topic.id)
        record.put("topics", topics)
        if (previous == null || addedTopic) rows.put(article.key, record)
        AttentionArticleStore(context).enqueue(article, topic.title)
        previous == null
    }

    private fun eventId(record: JSONObject) = "research:" + ProactiveAttentionPolicy.TASK_PREFIX +
        record.optString("topic") + ":feed:" + record.optString("key")
    private fun messageId(record: JSONObject) = "attention-feed:" + record.optString("key")

    internal fun articleRecordsAfter(cursor: String, limit: Int): List<JSONObject> = synchronized(LOCK) {
        rows.migrate()
        database.readStrings(database.keysAfter("article:", cursor, limit)).values.map(::JSONObject)
            .sortedBy { it.getString("key") }
    }

    internal fun publishArticle(article: AttentionArticleJob): Boolean {
        require(article.state == "ready" && article.chineseTitle.isNotBlank() && article.preview.isNotBlank())
        val at = article.collected
        val event = "research:${ProactiveAttentionPolicy.TASK_PREFIX}${article.topic}:feed:${article.key}"
        val task = GlobalResearchTask(id = ProactiveAttentionPolicy.TASK_PREFIX + article.topic,
            sourceEventId = event, sourceConversationId = "", topic = article.topicTitle, question = "",
            depth = GlobalResearchDepth.CONTINUOUS_MONITOR, preferredSources = emptyList(),
            updatedAtMillis = at, lastResultFingerprint = "feed:" + article.key,
            evidenceLedger = GlobalEvidenceLedger(sources = listOf(GlobalEvidenceSource(
                article.url, GlobalEvidenceSourceKind.UNKNOWN, 0.0, AttentionFeedCollectionPlan.publisher(article.url, article.publisher),
                publishedAtMillis = article.published, retrievedAtMillis = System.currentTimeMillis()))))
        ProactiveAttentionStore(context).saveEvidence(task, false)
        return repository.publishNewsArticle(GlobalProactiveMessage(
            id = "attention-feed:" + article.key, sourceEventId = event, sourceConversationId = "",
            target = GlobalProactiveTarget.NEW_CONVERSATION, title = article.chineseTitle,
            content = article.preview, topic = article.topicTitle, urgent = false, status = GlobalProactiveMessageStatus.DELIVERED,
            createdAtMillis = at, deliveredAtMillis = at, newsArticleKey = article.key, newsTranslationProvider = article.provider))
    }

    fun nextPlan(task: GlobalResearchTask, now: Long): GlobalResearchPlan? = synchronized(LOCK) {
        val topic = task.id.removePrefix(ProactiveAttentionPolicy.TASK_PREFIX)
        val pending = rows.all().filter { (it.optString("topic") == topic ||
            it.optJSONArray("topics")?.let { values -> (0 until values.length()).any { values.optString(it) == topic } } == true) &&
            (it.optString("review") == "pending" || it.optString("review") == "deferred" && it.optLong("retry_at") <= now) &&
            it.optLong("published") >= now - 7 * ProactiveAttentionNewsPolicy.DAY }
            .sortedByDescending { it.optLong("published") }.take(2).toList()
        if (pending.isEmpty()) return null
        GlobalResearchPlan(id = UUID.randomUUID().toString(), depth = task.depth,
            phase = GlobalResearchPlanPhase.COLLECTING, createdAtMillis = now, updatedAtMillis = now,
            units = pending.map { record -> GlobalResearchUnit(
                id = ProactiveAttentionFeedPolicy.UNIT_PREFIX + record.optString("key"),
                purpose = GlobalResearchUnitPurpose.CHANGE_MONITOR, question = task.question,
                sourceFocus = "Source-attributed feed summary; not yet independently verified",
                status = GlobalResearchUnitStatus.COMPLETED, completedAtMillis = now,
                resourceId = "local-public-news-feed",
                result = "CLAIM: " + record.optString("title") + "\n" + record.optString("summary") +
                    "\nSOURCE: " + record.optString("url") +
                    (if (record.optBoolean("discovery_date")) "\nDISCOVERED (original publication date unknown): " else "\nPUBLISHED: ") + record.optLong("published"),
                evidenceUris = listOf(record.optString("url"))) })
    }

    fun finish(task: GlobalResearchTask, reviewed: ProactiveAttentionNewsPolicy.Reviewed?, reason: String) = synchronized(LOCK) {
        val keys = task.researchPlan.units.filter { it.id.startsWith(ProactiveAttentionFeedPolicy.UNIT_PREFIX) }
            .map { it.id.removePrefix(ProactiveAttentionFeedPolicy.UNIT_PREFIX) }.toSet()
        if (keys.isEmpty()) return
        keys.mapNotNull(rows::get).forEach { record ->
            val url = GlobalEvidenceEvaluator.canonicalUri(record.optString("url"))
            val item = reviewed?.items?.firstOrNull { result -> result.ledger.sources.any { it.uri == url } }
            item?.titleTranslations?.get(record.optString("title"))?.let { translated ->
                ProactiveAttentionTitleStore(context).save(record.optString("title"), translated)
            }
            val retryable = item == null && reason in setOf("attention_source_read_unavailable", "attention_review_failed",
                "attention_review_invalid")
            val state = if (item != null) "reviewed" else if (retryable) "deferred" else "unverified"
            val current = repository.proactiveMessage(messageId(record))
            if (current != null && current.status != GlobalProactiveMessageStatus.DISMISSED && current.newsArticleKey.isBlank()) {
                val text = if (item == null) current.content.replace(
                    context.getString(R.string.attention_source_summary),
                    context.getString(R.string.attention_not_verified)) else
                    ProactiveAttentionPolicy.visibleResult(item.text) + "\n\n" + context.getString(R.string.attention_reviewed)
                repository.reviseProactiveMessage(current.id, text, item?.important == true)
                if (current.deliveredConversationId.isNotBlank()) AgentTranscriptStore(context).upsert(
                    AgentTranscriptRole.ASSISTANT, text, "global-agent:" + current.id,
                    current.createdAtMillis, current.deliveredConversationId)
                if (item != null) {
                    ProactiveAttentionStore(context).saveEvidence(task.copy(
                        lastResultFingerprint = "feed:" + record.optString("key"), evidenceLedger = item.ledger), item.important)
                    repository.enqueue(GlobalConversationEvent(id = "attention-learning:" + record.optString("key"),
                        type = GlobalConversationEventType.TOOL_RESULT, conversationId = task.sourceConversationId,
                        messageId = current.id, actor = GlobalConversationActor.TOOL, content = text,
                        topicHints = setOf(task.topic), metadata = mapOf("source" to "reviewed_public_news",
                            "evidence_urls" to item.ledger.sources.joinToString(" ") { it.uri })))
                }
            }
            record.put("review", state).put("review_reason", reason).put("reviewed_at", System.currentTimeMillis())
            if (retryable) {
                val delay = (record.optLong("retry_delay").coerceAtLeast(ProactiveAttentionFeedPolicy.MIN_INTERVAL) * 2)
                    .coerceAtMost(ProactiveAttentionFeedPolicy.MAX_INTERVAL)
                record.put("retry_delay", delay).put("retry_at", System.currentTimeMillis() + delay)
            }
            rows.put(record.getString("key"), record)
        }
        GlobalProactiveDeliveryBus.signalReady()
    }

    fun topicState(topicId: String): JSONObject = synchronized(LOCK) {
        JSONObject(database.readString("topic:$topicId", "{}")).takeIf {
            it.optInt("source_revision") == SOURCE_REVISION
        } ?: JSONObject()
    }

    fun cachedFeed(url: String, now: Long): String? = synchronized(LOCK) {
        val key = "feed:" + ProactiveAttentionFeedPolicy.urlKey(url)
        val cached = runCatching { JSONObject(database.readString(key, "{}")) }.getOrElse {
            // A disposable cache must never permanently block its source or erase discoveries.
            database.remove(key)
            return@synchronized null
        }
        cached.optString("xml").takeIf { it.isNotBlank() && cached.optLong("expires") > now }
    }

    fun cacheFeed(url: String, xml: String, now: Long) = synchronized(LOCK) {
        ProactiveAttentionFeedPolicy.parse(xml, "validation", now)
        database.writeString("feed:" + ProactiveAttentionFeedPolicy.urlKey(url),
            JSONObject().put("xml", xml).put("expires", now + AttentionFeedCollectionPlan.CACHE_MILLIS).toString())
        database.writeString("source:" + ProactiveAttentionFeedPolicy.urlKey(url), "{}")
    }

    fun sourceRetryAt(url: String): Long = synchronized(LOCK) {
        maxOf(JSONObject(database.readString("source:" + ProactiveAttentionFeedPolicy.urlKey(url), "{}")).optLong("next"),
            database.readString(AttentionFeedFailurePolicy.hostKey(url), "0").toLongOrNull() ?: 0L)
    }

    fun hostFailed(url: String, now: Long) = synchronized(LOCK) {
        database.writeString(AttentionFeedFailurePolicy.hostKey(url), (now + AttentionFeedFailurePolicy.HOST_BACKOFF).toString())
    }

    fun sourceFailed(url: String, code: String, now: Long) = synchronized(LOCK) {
        val key = "source:" + ProactiveAttentionFeedPolicy.urlKey(url)
        val previous = JSONObject(database.readString(key, "{}"))
        if (previous.optLong("next") <= now) {
            val delay = ProactiveAttentionFeedPolicy.interval(previous.optLong("delay"), 0, true)
            database.writeString(key, JSONObject().put("next", now + delay).put("delay", delay)
                .put("error", code.take(120)).toString())
        }
    }

    fun recordBatch(topicId: String, cursor: Int, count: Int, error: String, now: Long) = synchronized(LOCK) {
        val previous = topicState(topicId)
        val total = previous.optInt("cycle_new") + count
        val errors = listOf(previous.optString("cycle_errors"), error).filter(String::isNotBlank).joinToString("; ").take(1000)
        if (cursor == 0) {
            recordPoll(topicId, total, errors, now)
        } else {
            database.writeString("topic:$topicId", previous.put("source_revision", SOURCE_REVISION)
                .put("cursor", cursor).put("cycle_new", total).put("cycle_errors", errors)
                .put("next", now + 1_000L).toString())
        }
    }

    fun recordPoll(topicId: String, count: Int, error: String, now: Long) = synchronized(LOCK) {
        // Retry/backoff belongs to individual sources. One failing search must not defer healthy feeds.
        val interval = ProactiveAttentionFeedPolicy.MIN_INTERVAL
        database.writeString("topic:$topicId", JSONObject().put("at", now).put("next", now + interval)
            .put("source_revision", SOURCE_REVISION).put("interval", interval)
            .put("new_items", count).put("error", error.take(200)).toString())
    }

    companion object {
        private val LOCK = Any()
        // A new source adapter must not inherit a failed adapter's deferred wake-up.
        private const val SOURCE_REVISION = 5
        fun isFeed(task: GlobalResearchTask) = task.researchPlan.units.any { it.id.startsWith(ProactiveAttentionFeedPolicy.UNIT_PREFIX) }
    }
}
