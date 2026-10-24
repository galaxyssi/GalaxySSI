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

data class AttentionFeedCycle(val newItems: Int = 0, val nextAt: Long = 0L, val error: String = "")

class ProactiveAttentionFeedCollector(
    private val context: Context,
    private val fetch: (String) -> String = { url ->
        AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(url, maxBytes = AttentionFeedCollectionPlan.MAX_FEED_BYTES,
            timeoutMillis = 15_000)
            .body.toString(Charsets.UTF_8)
    }
) {
    fun collect(now: Long = System.currentTimeMillis()): AttentionFeedCycle {
        val preferences = ProactiveAttentionStore(context).preferences()
        if (!preferences.configured || !preferences.enabled)
            return AttentionFeedCycle()
        val topics = preferences.topics.filter { it.enabled }
        val store = ProactiveAttentionFeedStore(context)
        val topic = topics.minByOrNull { store.topicState(it.id).optLong("next") } ?: return AttentionFeedCycle()
        val due = store.topicState(topic.id).optLong("next")
        if (due > now) return AttentionFeedCycle(nextAt = due)
        val failures = mutableListOf<String>()
        var created = 0
        val originals = ProactiveAttentionFeedSources.originals(topic)
        val explicit = ProactiveAttentionWebSources.explicit(topic)
        val endpoints = AttentionFeedCollectionPlan.endpoints(topic)
        val cursor = store.topicState(topic.id).optInt("cursor").coerceIn(0, endpoints.lastIndex.coerceAtLeast(0))
        val batch = AttentionFeedCollectionPlan.batch(endpoints, cursor)
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
                throw failure
            }
        }
        for (endpoint in batch) {
            val items = try {
                val xml = load(endpoint, allowPage = endpoint in explicit)
                if (endpoint in explicit) {
                    runCatching { ProactiveAttentionFeedPolicy.parse(xml, topic.id, now) }.getOrElse {
                        val page = ProactiveAttentionWebSources.discover(xml, endpoint, topic.id, now)
                        if (page.articles.isNotEmpty()) page.articles
                        else {
                            val feedUrl = page.feeds.firstOrNull() ?: error("news_page_has_no_dated_articles_or_feed")
                            ProactiveAttentionFeedPolicy.parse(load(feedUrl), topic.id, now)
                        }
                    }
                } else ProactiveAttentionFeedPolicy.parse(xml, topic.id, now).filter {
                    endpoint !in originals || ProactiveAttentionFeedSources.matches(it, topic)
                }
            } catch (failure: Exception) {
                if (failure is java.util.concurrent.CancellationException) throw failure
                val code = (failure as? AgentWebMediaException)?.code ?: failure.javaClass.simpleName
                failures += java.net.URI(endpoint).host + ":" + code
                android.util.Log.w("GalaxySSIAttention", "feed_source_failed host=" + java.net.URI(endpoint).host +
                    " code=" + code + " detail=" + failure.message.orEmpty().take(180))
                continue
            }
            items.forEach { if (store.ingest(it, topic)) created++ }
        }
        val nextCursor = (cursor + batch.size).takeIf { it < endpoints.size } ?: 0
        val error = failures.joinToString("; ")
        store.recordBatch(topic.id, nextCursor, created, error, now)
        return AttentionFeedCycle(created, topics.minOf { store.topicState(it.id).optLong("next") }.coerceAtLeast(now + 1_000L),
            error)
    }
}

class ProactiveAttentionFeedWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        if (inputData.getBoolean(ProactiveAttentionFeedScheduler.TIMER_INPUT, false)) {
            ProactiveAttentionFeedScheduler.request(applicationContext)
            return Result.success()
        }
        return execution.withLock { withContext(Dispatchers.IO) {
        val coroutine = currentCoroutineContext()
        val collector = ProactiveAttentionFeedCollector(applicationContext) { url ->
            AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(url, maxBytes = AttentionFeedCollectionPlan.MAX_FEED_BYTES,
                timeoutMillis = 15_000,
                checkpoint = { coroutine.ensureActive() }).body.toString(Charsets.UTF_8)
        }
        val cycle = try { collector.collect() } catch (failure: Exception) {
            if (failure is java.util.concurrent.CancellationException) throw failure
            return@withContext Result.retry()
        }
        // Also repairs collection-to-scheduling interruption when a replay discovers no new IDs.
        AttentionArticleScheduler.request(applicationContext)
        ProactiveAttentionFeedDelivery.published(applicationContext, cycle.newItems)
        ProactiveAttentionPush.refresh()
        if (cycle.nextAt > 0L || cycle.newItems > 0)
            ProactiveAttentionFeedScheduler.request(applicationContext,
                (cycle.nextAt - System.currentTimeMillis()).coerceAtLeast(
                    BackgroundLearningLoadSampler.read(applicationContext).spacingMillis))
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
