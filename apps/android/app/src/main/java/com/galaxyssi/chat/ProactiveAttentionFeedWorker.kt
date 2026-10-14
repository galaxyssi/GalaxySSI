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
    fun request(context: Context, delay: Long = 0L) {
        val request = OneTimeWorkRequestBuilder<ProactiveAttentionFeedWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInitialDelay(delay.coerceAtLeast(0L), TimeUnit.MILLISECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            if (delay > 0) TIMER else WORK,
            if (delay > 0) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request)
    }
}

data class AttentionFeedCycle(val newItems: Int = 0, val nextAt: Long = 0L, val error: String = "")

class ProactiveAttentionFeedCollector(
    private val context: Context,
    private val fetch: (String) -> String = { url ->
        AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(url, maxBytes = 512 * 1024L)
            .body.toString(Charsets.UTF_8)
    }
) {
    fun collect(now: Long = System.currentTimeMillis()): AttentionFeedCycle {
        val preferences = ProactiveAttentionStore(context).preferences()
        if (!preferences.configured || !preferences.enabled || !GlobalAgentRepository(context).settings().enabled)
            return AttentionFeedCycle()
        val topics = preferences.topics.filter { it.enabled }
        val store = ProactiveAttentionFeedStore(context)
        val topic = topics.minByOrNull { store.topicState(it.id).optLong("next") } ?: return AttentionFeedCycle()
        val due = store.topicState(topic.id).optLong("next")
        if (due > now) return AttentionFeedCycle(nextAt = due)
        var error = ""
        val failures = mutableListOf<String>()
        var created = 0
        var fetched = false
        val originals = ProactiveAttentionFeedSources.originals(topic)
        for (endpoint in originals + ProactiveAttentionFeedPolicy.endpoints(topic)) {
            val items = try {
                val xml = (if (endpoint in originals) store.cachedFeed(endpoint, now) else null) ?: fetch(endpoint).also {
                    if (endpoint in originals) store.cacheFeed(endpoint, it, now)
                }
                ProactiveAttentionFeedPolicy.parse(xml, topic.id, now).filter {
                    endpoint !in originals || ProactiveAttentionFeedSources.matches(it, topic)
                }
            } catch (failure: Exception) {
                if (failure is java.util.concurrent.CancellationException) throw failure
                val code = (failure as? AgentWebMediaException)?.code ?: failure.javaClass.simpleName
                failures += java.net.URI(endpoint).host + ":" + code
                error = failures.joinToString("; ")
                android.util.Log.w("GalaxySSIAttention", "feed_source_failed host=" + java.net.URI(endpoint).host +
                    " code=" + code + " detail=" + failure.message.orEmpty().take(180))
                continue
            }
            fetched = true
            items.forEach { if (store.ingest(it, topic)) created++ }
            if (items.isNotEmpty()) break
        }
        store.recordPoll(topic.id, created, if (fetched) "" else error, now)
        GlobalProactiveDeliveryBus.signalReady()
        return AttentionFeedCycle(created, topics.minOf { store.topicState(it.id).optLong("next") }.coerceAtLeast(now + 1_000L),
            if (fetched) "" else error)
    }
}

class ProactiveAttentionFeedWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = execution.withLock { withContext(Dispatchers.IO) {
        val coroutine = currentCoroutineContext()
        val collector = ProactiveAttentionFeedCollector(applicationContext) { url ->
            AgentBoundedWebService(AgentPinnedOkHttpWebTransport()).fetch(url, maxBytes = 512 * 1024L,
                checkpoint = { coroutine.ensureActive() }).body.toString(Charsets.UTF_8)
        }
        val cycle = try { collector.collect() } catch (failure: Exception) {
            if (failure is java.util.concurrent.CancellationException) throw failure
            return@withContext Result.retry()
        }
        val runtime = GlobalSuperAgentRuntime.get(applicationContext)
        val candidate = runtime.notificationCandidateForDelivered(runtime.unnotifiedDeliveredMessages())
        if (candidate != null && AndroidCognitionNotificationCenter.notify(applicationContext, candidate))
            runtime.markNotified(candidate.messageIds)
        if (cycle.newItems > 0) AndroidCognitionScheduler.requestAttention(applicationContext)
        if (cycle.nextAt > 0L || cycle.newItems > 0)
            ProactiveAttentionFeedScheduler.request(applicationContext,
                (cycle.nextAt - System.currentTimeMillis()).coerceAtLeast(1_000L))
        android.util.Log.i("GalaxySSIAttention", "feed_cycle new=" + cycle.newItems + " error=" + cycle.error)
        Result.success()
    } }

    companion object { private val execution = Mutex() }
}
