package com.galaxyssi.chat

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object ProactiveAttentionFeedScheduler {
    private const val WORK = "galaxyssi-attention-feed-v1"
    private const val TIMER = "galaxyssi-attention-feed-timer-v1"
    internal const val TIMER_INPUT = "feed_timer_only"
    internal fun buildRequest(delay: Long) = OneTimeWorkRequestBuilder<ProactiveAttentionFeedWorker>()
            .setInputData(workDataOf(TIMER_INPUT to (delay > 0)))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInitialDelay(delay.coerceAtLeast(0L), TimeUnit.MILLISECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build()
    fun request(context: Context, delay: Long = 0L) {
        val request = buildRequest(delay)
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            if (delay > 0) TIMER else WORK,
            if (delay > 0) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request)
    }
}

data class AttentionFeedCycle(val newItems: Int = 0, val nextAt: Long = 0L, val error: String = "",
    val scanned: Boolean = false)

class ProactiveAttentionFeedCollector(
    private val context: Context,
    private val fetch: (String) -> String = { url ->
        AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(url, maxBytes = AttentionFeedCollectionPlan.MAX_FEED_BYTES,
            timeoutMillis = 15_000)
            .body.toString(Charsets.UTF_8)
    }
) {
    fun collect(now: Long = System.currentTimeMillis(),
        interval: Long = ProactiveAttentionFeedPolicy.MIN_INTERVAL,
        continueBatch: () -> Boolean = { true }): AttentionFeedCycle {
        val preferences = ProactiveAttentionStore(context).preferences()
        if (!preferences.configured || !preferences.enabled)
            return AttentionFeedCycle()
        val topics = preferences.topics.filter { it.enabled }
        val store = ProactiveAttentionFeedStore(context)
        fun dueAt(topic: AttentionTopic) = store.topicDueAt(topic.id, interval)
        val topic = topics.minByOrNull(::dueAt) ?: return AttentionFeedCycle()
        val due = dueAt(topic)
        if (due > now) return AttentionFeedCycle(nextAt = due)
        val failures = mutableListOf<String>()
        var created = 0
        val originals = ProactiveAttentionFeedSources.originals(topic)
        val explicit = ProactiveAttentionWebSources.explicit(topic)
        val endpoints = AttentionFeedCollectionPlan.endpoints(topic)
        val searches = ProactiveAttentionFeedPolicy.endpoints(topic).toSet()
        val knowledge = AttentionKnowledgeSources.endpoints(topic.id).toSet()
        val articles = AttentionArticleStore(context)
        val learned = articles.dueLearnedFeed(topic.id, now)?.takeIf { url ->
            val retry = store.sourceRetryAt(url)
            if (retry > now) { articles.deferLearnedFeed(url, retry, now); false } else true
        }
        val cursor = store.topicState(topic.id).optInt("cursor").coerceIn(0, endpoints.lastIndex.coerceAtLeast(0))
        val base = AttentionFeedCollectionPlan.batch(endpoints, cursor).take(if (learned == null) 4 else 3)
        val batch = base + listOfNotNull(learned)
        fun load(url: String, allowPage: Boolean = false): String {
            store.cachedFeed(url, now)?.let { return it }
            check(store.sourceRetryAt(url) <= now) { "news_source_retry_deferred" }
            try {
                val text = fetch(url)
                val validFeed = runCatching { ProactiveAttentionFeedPolicy.parse(text, topic.id, now) }.isSuccess
                check(validFeed || allowPage) { "news_feed_invalid_document" }
                if (validFeed) store.cacheFeed(url, text, now)
                return text
            } catch (failure: Exception) {
                if (failure is java.util.concurrent.CancellationException) throw failure
                store.sourceFailed(url, failure.javaClass.simpleName, now)
                if (AttentionFeedFailurePolicy.affectsHost(failure, url in searches)) store.hostFailed(url, now)
                throw failure
            }
        }
        var scanned = 0
        for (endpoint in batch) {
            if (!continueBatch()) break
            scanned++
            if (store.sourceRetryAt(endpoint) > now) continue
            if (endpoint in knowledge && store.knowledgeRetryAt(topic.id, endpoint) > now) continue
            if (endpoint == learned) articles.deferLearnedFeed(endpoint, now + 5 * 60_000L, now)
            val items = try {
                val xml = load(endpoint, allowPage = endpoint in explicit || endpoint in knowledge)
                if (endpoint in knowledge) {
                    AttentionKnowledgeSources.discover(xml, endpoint, topic.id, now).also {
                        check(it.isNotEmpty()) { "knowledge_index_empty" }
                    }
                } else if (endpoint in explicit) {
                    runCatching { ProactiveAttentionFeedPolicy.parse(xml, topic.id, now) }.getOrElse {
                        val page = ProactiveAttentionWebSources.discover(xml, endpoint, topic.id, now)
                        if (page.articles.isNotEmpty()) page.articles
                        else {
                            val feedUrl = page.feeds.firstOrNull() ?: error("news_page_has_no_dated_articles_or_feed")
                            ProactiveAttentionFeedPolicy.parse(load(feedUrl), topic.id, now)
                        }
                    }
                } else ProactiveAttentionFeedPolicy.parse(xml, topic.id, now,
                    maxAgeDays = ProactiveAttentionSourceCatalog.maxAgeDays(topic.id)).filter {
                    endpoint !in originals || ProactiveAttentionSourceCatalog.dedicated(endpoint, topic.id) ||
                        ProactiveAttentionFeedSources.matches(it, topic)
                }
            } catch (failure: Exception) {
                if (failure is java.util.concurrent.CancellationException) throw failure
                val code = (failure as? AgentWebMediaException)?.code ?: failure.javaClass.simpleName
                if (endpoint in knowledge) store.sourceFailed(endpoint, code, now)
                failures += java.net.URI(endpoint).host + ":" + code
                android.util.Log.w("GalaxySSIAttention", "feed_source_failed host=" + java.net.URI(endpoint).host +
                    " code=" + code + " detail=" + failure.message.orEmpty().take(180))
                continue
            }
            if (endpoint == learned) {
                val memberships = articles.learnedFeedTopics(endpoint)
                items.map(articles::knownPublisherArticle).forEach { article -> topics.filter { it.id in memberships && ProactiveAttentionFeedSources.matches(article, it) }.forEach { scope ->
                    if (store.ingest(article.copy(topicId = scope.id), scope)) created++
                } }
                articles.deferLearnedFeed(endpoint, now + ProactiveAttentionFeedPolicy.MIN_INTERVAL, now)
            } else items.forEach { if (store.ingest(it, topic)) created++ }
            if (endpoint in knowledge && ProactiveAttentionPolicy.shouldCollect(
                    ProactiveAttentionStore(context).preferences(), topic.id)) store.knowledgeScanned(topic.id, endpoint, now)
        }
        val nextCursor = (cursor + scanned.coerceAtMost(base.size)).takeIf { it < endpoints.size } ?: 0
        val error = failures.joinToString("; ")
        val completed = scanned > 0 || batch.isEmpty()
        if (completed) store.recordBatch(topic.id, nextCursor, created, error, now)
        return AttentionFeedCycle(created, topics.minOf(::dueAt).coerceAtLeast(now + 1_000L), error, completed)
    }
}

class ProactiveAttentionFeedWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        if (inputData.getBoolean(ProactiveAttentionFeedScheduler.TIMER_INPUT, false)) {
            ProactiveAttentionFeedScheduler.request(applicationContext)
            return Result.success()
        }
        return execution.withLock { withContext(Dispatchers.IO) {
        val context = applicationContext
        val preferences = ProactiveAttentionStore(context).preferences()
        if (!preferences.configured || !preferences.enabled) return@withContext Result.success()
        val now = System.currentTimeMillis()
        val profile = AttentionNewsBudget.profile(context, now)
        val delay = maxOf(AttentionNewsBudget.feedDelay(context, now, profile), AttentionNewsBudget.pressure(context))
        if (delay > 0L) {
            ProactiveAttentionFeedScheduler.request(context, delay)
            return@withContext Result.success()
        }
        val coroutine = currentCoroutineContext()
        val collector = ProactiveAttentionFeedCollector(context) { url ->
            AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(url, maxBytes = AttentionFeedCollectionPlan.MAX_FEED_BYTES,
                timeoutMillis = 15_000,
                checkpoint = { coroutine.ensureActive() }).body.toString(Charsets.UTF_8)
        }
        val cycle = try { collector.collect(now, profile.feedInterval) {
            coroutine.ensureActive()
            AttentionNewsBudget.pressure(context) == 0L
        } } catch (failure: Exception) {
            if (failure is java.util.concurrent.CancellationException) throw failure
            return@withContext Result.retry()
        }
        if (cycle.scanned) AttentionNewsBudget.feedFinished(context, System.currentTimeMillis())
        ProactiveAttentionFeedDelivery.published(context, cycle.newItems)
        ProactiveAttentionPush.refresh()
        if (cycle.nextAt > 0L || cycle.newItems > 0)
            ProactiveAttentionFeedScheduler.request(context,
                (cycle.nextAt - System.currentTimeMillis()).coerceAtLeast(
                    maxOf(profile.feedSpacing, AttentionNewsBudget.pressure(context))))
        android.util.Log.i("GalaxySSIAttention", "feed_cycle new=" + cycle.newItems + " error=" + cycle.error)
        Result.success()
    } } }

    companion object { private val execution = Mutex() }
}

object ProactiveAttentionFeedDelivery {
    @Synchronized fun published(context: Context, newItems: Int) {
        // Empty polls and irrelevant push items must not scan the inbox or wake learning/UI work.
        if (newItems <= 0) return
        AttentionArticleScheduler.request(context)
        val runtime = GlobalSuperAgentRuntime.get(context)
        val candidate = runtime.notificationCandidateForDelivered(runtime.unnotifiedDeliveredMessages())
        if (candidate != null && AndroidCognitionNotificationCenter.notify(context, candidate))
            runtime.markNotified(candidate.messageIds)
        if (newItems > 0) {
            ProactiveAttentionTitleScheduler.request(context)
            GlobalProactiveDeliveryBus.signalReady()
            AndroidCognitionScheduler.requestAttention(context)
        }
    }
}
