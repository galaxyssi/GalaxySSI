package com.galaxyssi.chat

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

internal object AttentionArticleScheduler {
    fun request(context: Context, delay: Long = 0L) {
        val request = OneTimeWorkRequestBuilder<AttentionArticleWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInputData(workDataOf("timer" to (delay > 0)))
            .setInitialDelay(delay.coerceAtLeast(0L), TimeUnit.MILLISECONDS).build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
            if (delay > 0) "attention-article-timer-v1" else "attention-article-now-v1",
            if (delay > 0) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request)
    }
}

/** Independent from private cognition, chat routing, and Desktop availability. */
class AttentionArticleWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = execution.withLock { withContext(Dispatchers.IO) {
        val context = applicationContext
        if (inputData.getBoolean("timer", false)) {
            AttentionArticleScheduler.request(context)
            return@withContext Result.success()
        }
        val preferences = ProactiveAttentionStore(context).preferences()
        if (!preferences.configured || !preferences.enabled) return@withContext Result.success()
        val load = BackgroundLearningLoadSampler.read(context)
        if (load.deferMillis > 0) {
            AttentionArticleScheduler.request(context, load.deferMillis)
            return@withContext Result.success()
        }
        val store = AttentionArticleStore(context)
        val feed = ProactiveAttentionFeedStore(context)
        var migrating = false
        repeat(4) { currentCoroutineContext().ensureActive(); migrating = store.importLegacy(feed, preferences.topics) }
        val topics = preferences.topics.filter { it.enabled }.map { it.id }.toSet()
        val coroutine = currentCoroutineContext()
        val fetcher = AgentBoundedWebIntelligenceFetcher(AgentBoundedWebService(AgentPinnedOkHttpWebTransport(),
            policy = AgentWebPolicy(maxTimeoutMillis = 20_000L)))
        var published = 0
        AttentionArticleTranslator(context).use { translator ->
            repeat(3) {
                coroutine.ensureActive()
                val job = store.claim(topics, System.currentTimeMillis()) ?: return@repeat
                try {
                    if (job.state != "ready") {
                        val page = fetcher.fetch(job.url, 10 * 1024 * 1024L, 20_000L,
                            AgentDynamicArticleRequestPolicy.headers(job.url), AgentNativeToolCancellationToken.NONE,
                            { coroutine.ensureActive() })
                        val article = try { AttentionArticlePolicy.extract(page) } finally { page.body.fill(0) }
                        val translated = translator.translate(job.title.ifBlank { article.title }, article.content)
                        coroutine.ensureActive()
                        store.ready(job.key, translated)
                    }
                    val current = ProactiveAttentionStore(context).preferences()
                    if (ProactiveAttentionPolicy.shouldCollect(current, job.topic)) {
                        if (feed.publishArticle(checkNotNull(store.metadata(job.key)))) published++
                        store.published(job.key)
                    }
                } catch (timeout: TimeoutCancellationException) {
                    coroutine.ensureActive()
                    store.failed(job, "article_translation_timeout", System.currentTimeMillis())
                } catch (cancelled: CancellationException) { throw cancelled
                } catch (failure: Exception) {
                    val reason = if (failure is AgentWebMediaException) failure.code else
                        failure.message?.takeIf { it.startsWith("article_") } ?: failure.javaClass.simpleName
                    store.failed(job, reason, System.currentTimeMillis())
                    android.util.Log.w("GalaxySSIAttention", "article_deferred id=${job.key.take(12)} reason=$reason")
                }
            }
        }
        ProactiveAttentionFeedDelivery.published(context, published)
        val next = store.nextAt(topics)
        if (migrating || next != null) AttentionArticleScheduler.request(context,
            if (migrating) load.spacingMillis else ((next ?: 0) - System.currentTimeMillis()).coerceAtLeast(load.spacingMillis))
        android.util.Log.i("GalaxySSIAttention", "article_batch published=$published migrating=$migrating")
        Result.success()
    } }
    companion object { private val execution = Mutex() }
}
