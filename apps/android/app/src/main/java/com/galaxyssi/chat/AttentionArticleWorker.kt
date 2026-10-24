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
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

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
        var attempted = 0
        val started = android.os.SystemClock.elapsedRealtime()
        val parallelism = if (load.spacingMillis > 1_000L) 1 else 2
        val extraction = Mutex()
        AttentionArticleTranslator(context).use { translator ->
            while (attempted < 24 && android.os.SystemClock.elapsedRealtime() - started < 120_000L) {
                coroutine.ensureActive()
                if (BackgroundLearningLoadSampler.read(context).deferMillis > 0) break
                val jobs = (0 until parallelism).mapNotNull { store.claim(topics, System.currentTimeMillis()) }
                if (jobs.isEmpty()) break
                attempted += jobs.size
                // Only downloads overlap. DOM extraction and the reused translator stay bounded.
                val prepared = coroutineScope { jobs.map { job -> async(Dispatchers.IO) {
                    try {
                        val article = if (job.state == "ready") null else {
                            val page = fetcher.fetch(job.url, 10 * 1024 * 1024L, 20_000L,
                                AgentDynamicArticleRequestPolicy.headers(job.url), AgentNativeToolCancellationToken.NONE,
                                { coroutine.ensureActive() })
                            try { extraction.withLock { AttentionArticlePolicy.extractStructured(page) } } finally { page.body.fill(0) }
                        }
                        kotlin.Result.success(article)
                    } catch (cancelled: CancellationException) { throw cancelled
                    } catch (failure: Exception) { kotlin.Result.failure<AttentionArticleSource?>(failure) }
                } }.awaitAll() }
                for ((index, job) in jobs.withIndex()) {
                    try {
                        val article = prepared[index].getOrThrow()
                        if (article != null) {
                            val translated = translator.translate(job.title.ifBlank { article.article.title }, article)
                            coroutine.ensureActive()
                            store.ready(job.key, translated)
                        }
                        val current = ProactiveAttentionStore(context).preferences()
                        if (job.state != "published" && ProactiveAttentionPolicy.shouldCollect(current, job.topic)) {
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
        }
        ProactiveAttentionFeedDelivery.published(context, published)
        val next = store.nextAt(topics)
        if (migrating || next != null) AttentionArticleScheduler.request(context,
            if (migrating) load.spacingMillis else ((next ?: 0) - System.currentTimeMillis()).coerceAtLeast(load.spacingMillis))
        GlobalProactiveDeliveryBus.signalReady()
        android.util.Log.i("GalaxySSIAttention", "article_batch attempted=$attempted published=$published migrating=$migrating " +
            "elapsed_ms=${android.os.SystemClock.elapsedRealtime() - started}")
        Result.success()
    } }
    companion object { private val execution = Mutex() }
}
