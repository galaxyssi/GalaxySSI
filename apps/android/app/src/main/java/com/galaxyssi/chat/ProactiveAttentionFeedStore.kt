package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID

class ProactiveAttentionFeedStore(context: Context) {
    private val context = context.applicationContext
    private val database = AgentEncryptedDatabase(this.context, "attention_feed_v1")
    private val repository = GlobalAgentRepository(this.context)

    private fun records(): List<JSONObject> = JSONArray(database.readString("articles", "[]")).let { array ->
        (0 until array.length()).mapNotNull(array::optJSONObject)
    }

    private fun save(records: List<JSONObject>) = database.writeString("articles",
        JSONArray(records.sortedByDescending { it.optLong("collected") }.take(500)).toString())

    fun ingest(article: AttentionFeedArticle, topic: AttentionTopic): Boolean = synchronized(LOCK) {
        if (!ProactiveAttentionPolicy.shouldCollect(ProactiveAttentionStore(context).preferences(), topic.id)) return false
        val all = records()
        val previous = all.firstOrNull { it.optString("key") == article.key }
        val record = previous ?: JSONObject().put("key", article.key).put("topic", article.topicId)
            .put("title", article.title).put("summary", article.summary).put("url", article.url)
            .put("publisher", article.publisher).put("published", article.publishedAt)
            .put("collected", article.collectedAt).put("review", "pending")
        if (previous == null) save(all + record)
        // Replays repair a crash between durable collection and inbox publication.
        if (previous == null || repository.proactiveMessages().none { it.id == messageId(record) })
            publish(record, topic.title)
        previous == null
    }

    private fun eventId(record: JSONObject) = "research:" + ProactiveAttentionPolicy.TASK_PREFIX +
        record.optString("topic") + ":feed:" + record.optString("key")
    private fun messageId(record: JSONObject) = "attention-feed:" + record.optString("key")

    private fun publish(record: JSONObject, topic: String) {
        val at = record.optLong("collected")
        val date = Instant.ofEpochMilli(record.optLong("published")).atZone(ZoneOffset.UTC).toLocalDate().toString()
        val content = "**" + ProactiveAttentionFeedPolicy.markdownText(record.optString("title")) + "**\n\n" +
            ProactiveAttentionFeedPolicy.markdownText(record.optString("summary")
                .ifBlank { context.getString(R.string.attention_headline_only) }) +
            "\n\n" + context.getString(R.string.attention_source_summary) + "\n" + date + "\n[" +
            ProactiveAttentionFeedPolicy.markdownText(record.optString("publisher")) + "](" + record.optString("url") + ")"
        val task = GlobalResearchTask(id = ProactiveAttentionPolicy.TASK_PREFIX + record.optString("topic"),
            sourceEventId = eventId(record), sourceConversationId = "", topic = topic, question = "",
            depth = GlobalResearchDepth.CONTINUOUS_MONITOR, preferredSources = emptyList(),
            updatedAtMillis = at, lastResultFingerprint = "feed:" + record.optString("key"),
            evidenceLedger = GlobalEvidenceLedger(sources = listOf(GlobalEvidenceSource(
                record.optString("url"), GlobalEvidenceSourceKind.UNKNOWN, 0.0, record.optString("publisher"),
                publishedAtMillis = record.optLong("published"), retrievedAtMillis = at))))
        ProactiveAttentionStore(context).saveEvidence(task, false)
        repository.appendProactiveMessage(GlobalProactiveMessage(
            id = messageId(record), sourceEventId = eventId(record), sourceConversationId = "",
            target = GlobalProactiveTarget.NEW_CONVERSATION, title = record.optString("title"),
            content = content, topic = topic, urgent = false, status = GlobalProactiveMessageStatus.DELIVERED,
            createdAtMillis = at, deliveredAtMillis = at))
    }

    fun nextPlan(task: GlobalResearchTask, now: Long): GlobalResearchPlan? = synchronized(LOCK) {
        val topic = task.id.removePrefix(ProactiveAttentionPolicy.TASK_PREFIX)
        val pending = records().filter { it.optString("topic") == topic &&
            (it.optString("review") == "pending" || it.optString("review") == "deferred" && it.optLong("retry_at") <= now) &&
            it.optLong("published") >= now - 7 * ProactiveAttentionNewsPolicy.DAY }
            .sortedByDescending { it.optLong("published") }.take(2)
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
                    "\nSOURCE: " + record.optString("url") + "\nPUBLISHED: " + record.optLong("published"),
                evidenceUris = listOf(record.optString("url"))) })
    }

    fun finish(task: GlobalResearchTask, reviewed: ProactiveAttentionNewsPolicy.Reviewed?, reason: String) = synchronized(LOCK) {
        val keys = task.researchPlan.units.filter { it.id.startsWith(ProactiveAttentionFeedPolicy.UNIT_PREFIX) }
            .map { it.id.removePrefix(ProactiveAttentionFeedPolicy.UNIT_PREFIX) }.toSet()
        if (keys.isEmpty()) return
        val all = records()
        all.filter { it.optString("key") in keys }.forEach { record ->
            val url = GlobalEvidenceEvaluator.canonicalUri(record.optString("url"))
            val item = reviewed?.items?.firstOrNull { result -> result.ledger.sources.any { it.uri == url } }
            val retryable = item == null && reason in setOf("attention_source_read_unavailable", "attention_review_failed",
                "attention_review_invalid")
            val state = if (item != null) "reviewed" else if (retryable) "deferred" else "unverified"
            val current = repository.proactiveMessages().firstOrNull { it.id == messageId(record) }
            if (current != null && current.status != GlobalProactiveMessageStatus.DISMISSED) {
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
        }
        save(all)
        GlobalProactiveDeliveryBus.signalReady()
    }

    fun topicState(topicId: String): JSONObject = synchronized(LOCK) {
        JSONObject(database.readString("topic:$topicId", "{}")).takeIf {
            it.optInt("source_revision") == SOURCE_REVISION
        } ?: JSONObject()
    }

    fun cachedFeed(url: String, now: Long): String? = synchronized(LOCK) {
        val cached = JSONObject(database.readString("feed:" + ProactiveAttentionFeedPolicy.urlKey(url), "{}"))
        cached.optString("xml").takeIf { it.isNotBlank() && cached.optLong("expires") > now }
    }

    fun cacheFeed(url: String, xml: String, now: Long) = synchronized(LOCK) {
        ProactiveAttentionFeedPolicy.parse(xml, "validation", now)
        database.writeString("feed:" + ProactiveAttentionFeedPolicy.urlKey(url),
            JSONObject().put("xml", xml).put("expires", now + 5 * 60_000L).toString())
    }

    fun recordPoll(topicId: String, count: Int, error: String, now: Long) = synchronized(LOCK) {
        val previous = topicState(topicId)
        val interval = ProactiveAttentionFeedPolicy.interval(previous.optLong("interval"), count, error.isNotBlank())
        database.writeString("topic:$topicId", JSONObject().put("at", now).put("next", now + interval)
            .put("source_revision", SOURCE_REVISION).put("interval", interval)
            .put("new_items", count).put("error", error.take(200)).toString())
    }

    companion object {
        private val LOCK = Any()
        // A new source adapter must not inherit a failed adapter's deferred wake-up.
        private const val SOURCE_REVISION = 2
        fun isFeed(task: GlobalResearchTask) = task.researchPlan.units.any { it.id.startsWith(ProactiveAttentionFeedPolicy.UNIT_PREFIX) }
    }
}
